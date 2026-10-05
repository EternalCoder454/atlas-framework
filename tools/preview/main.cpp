// atlas-preview: loads a page or component of an Atlas app offscreen in the
// visual-test matrix (light, dark, accent, opaque, rtl, text200, compact,
// contrast) and writes one PNG per variant plus the QML warnings. See
// tools/README.md.
//
//   atlas-preview <file.qml> --out <dir> [--size WxH] [-I <import path>]...
//
// Exit 0: pictures written, no warnings. 1: pictures written, QML warnings
// (listed on stderr and in <dir>/<name>-warnings.txt). 2: bad usage or a file
// that would not load.
//
// Every variant needs its own process: the colour scheme, the font and the
// platform theme are read once at start. The first process (the parent) starts
// itself once per variant with the hidden option --internal-render; the
// contrast variant runs inside a private session bus with a settings portal
// stand-in (--internal-contrast-host and --internal-portal).
#include "fakeportal.h"
#include "variant.h"

#include <QApplication>
#include <QCommandLineParser>
#include <QCoreApplication>
#include <QDir>
#include <QElapsedTimer>
#include <QEventLoop>
#include <QFile>
#include <QFileInfo>
#include <QImage>
#include <QMap>
#include <QMutex>
#include <QProcess>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QQuickItem>
#include <QQuickWindow>
#include <QRegularExpression>
#include <QSaveFile>
#include <QSocketNotifier>
#include <QSize>
#include <QStandardPaths>
#include <QTemporaryDir>
#include <QThread>
#include <QTimer>
#include <QUrl>
#include <QUuid>
#include <QLibraryInfo>

#include <fcntl.h>
#include <signal.h>
#include <sys/prctl.h>
#include <unistd.h>

#include <cstdio>
#include <cstdlib>
#include <functional>
#include <memory>

using AtlasVariant::names;

namespace {

constexpr int kExitWarnings = 1;
constexpr int kExitError = 2;
// A render that takes longer is stuck. The contrast host and the parent wait
// a little longer each, so the innermost one reports.
constexpr int kRenderSeconds = 60;
constexpr int kHostSeconds = 90;
constexpr int kParentSeconds = 120;
constexpr int kLargestSide = 4096;
// The fake portal gives up after this, whatever happens to its parents.
constexpr int kPortalSeconds = 100;
// terminate(), then kill() after this long.
constexpr int kGraceMs = 3000;
// The parent puts a random value in this variable for the processes it starts:
// the hidden --internal-* modes refuse to run without it.
const char kTokenVariable[] = "ATLAS_PREVIEW_PRIVATE";
const char kScratchVariable[] = "ATLAS_PREVIEW_SCRATCH";

// Control characters other than a tab become '?': a message from QML or a
// file name must not move the cursor or forge a CI log command.
QString clean(QString text)
{
    for (QChar &c : text) {
        if ((c.unicode() < 0x20 && c != QLatin1Char('\t') && c != QLatin1Char('\n')) || c.unicode() == 0x7f) {
            c = QLatin1Char('?');
        }
    }
    return text;
}

void say(const QString &text)
{
    std::fprintf(stderr, "%s\n", qUtf8Printable(clean(text)));
}

// A file the tool writes must not be a symbolic link: QSaveFile would write
// through it to wherever it points.
bool refuseLink(const QString &path)
{
    if (QFileInfo(path).isSymLink()) {
        say(QStringLiteral("error: %1 is a symbolic link; not writing through it").arg(path));
        return true;
    }
    return false;
}

// A child ends with its parent: SIGTERM when the parent dies (Linux).
void hardenChild(QProcess &process)
{
    process.setChildProcessModifier([] { ::prctl(PR_SET_PDEATHSIG, SIGTERM); });
}

// terminate(), and kill() when it has not ended after the grace period.
void stopProcess(QProcess &process)
{
    if (process.state() == QProcess::NotRunning) {
        return;
    }
    process.terminate();
    if (!process.waitForFinished(kGraceMs)) {
        process.kill();
        process.waitForFinished(2000);
    }
}

bool privateModeAllowed()
{
    return qEnvironmentVariable(kTokenVariable).size() >= 16;
}

// "WxH" with both sides between 1 and kLargestSide.
bool parseSize(const QString &text, QSize *size)
{
    static const QRegularExpression re(QStringLiteral("^([0-9]{1,5})x([0-9]{1,5})$"));
    const auto m = re.match(text);
    if (!m.hasMatch()) {
        return false;
    }
    const int w = m.captured(1).toInt();
    const int h = m.captured(2).toInt();
    if (w < 1 || h < 1 || w > kLargestSide || h > kLargestSide) {
        return false;
    }
    *size = QSize(w, h);
    return true;
}

// ---- the render process: one variant, one picture --------------------------

// What the previewed page is put in. A string, not a resource: a resource with
// QML in it makes CMake try to link the QML plugins it imports statically.
const char kHostQml[] = R"QML(
import QtQuick
import QtQuick.Controls
import org.kde.kirigami as Kirigami
import Atlas.Ui

// What atlas-preview puts the previewed page in: the stage the visual tests
// use (the theme's background), mirrored for the rtl variant, with the
// density of the compact variant. A previewed window gets the same through
// mirrorWindow().
Rectangle {
    id: stage

    property bool rtl: false
    property bool compact: false
    readonly property bool highContrast: AtlasStyle.highContrast

    color: Kirigami.Theme.backgroundColor
    LayoutMirroring.enabled: rtl
    LayoutMirroring.childrenInherit: true

    Component.onCompleted: AtlasStyle.density = compact ? AtlasStyle.Compact : AtlasStyle.Normal

    // An RTL app mirrors its windows' content and overlay (Qt does not do it).
    function mirrorWindow(w: Window) {
        if (!rtl) {
            return;
        }
        w.contentItem.LayoutMirroring.enabled = true;
        w.contentItem.LayoutMirroring.childrenInherit = true;
        if (w.Overlay.overlay) {
            w.Overlay.overlay.LayoutMirroring.enabled = true;
            w.Overlay.overlay.LayoutMirroring.childrenInherit = true;
        }
    }
}
)QML";


QMutex g_warningsMutex;
QStringList g_warnings;

// QML's own warnings: the engine's (category qml), console.warn (js), Qt
// Quick's, and any warning that names a .qml or .js file. The platform's and
// the fonts' noise is dropped: it is not the app's.
void messageHandler(QtMsgType type, const QMessageLogContext &context, const QString &message)
{
    if (type == QtFatalMsg) {
        std::fprintf(stderr, "fatal: %s\n", qUtf8Printable(message));
        std::abort();
    }
    if (type != QtWarningMsg && type != QtCriticalMsg) {
        return;
    }
    const QString category = QString::fromUtf8(context.category);
    const QString file = QString::fromUtf8(context.file);
    const bool qml = category.startsWith(QLatin1String("qml")) || category.startsWith(QLatin1String("js"))
        || category.startsWith(QLatin1String("qt.qml")) || category.startsWith(QLatin1String("qt.quick"))
        || file.endsWith(QLatin1String(".qml")) || file.endsWith(QLatin1String(".js")) || message.contains(QLatin1String(".qml:"));
    if (!qml) {
        return;
    }
    QString line = message;
    line.replace(QLatin1Char('\n'), QLatin1Char(' '));
    line.replace(QLatin1Char('\r'), QLatin1Char(' '));
    const QMutexLocker lock(&g_warningsMutex);
    g_warnings << clean(line).trimmed();
}

bool savePng(const QImage &image, const QString &path)
{
    if (refuseLink(path)) {
        return false;
    }
    QSaveFile file(path);
    return file.open(QIODevice::WriteOnly) && image.save(&file, "PNG") && file.commit();
}

// Lets the event loop run for `ms`.
void settle(int ms)
{
    QEventLoop loop;
    QTimer::singleShot(ms, &loop, &QEventLoop::quit);
    loop.exec();
}

// Prints the warnings (one "W <text>" line each) for the parent, and ends the
// process without tearing the engine down: nothing is left to save, and a
// page's destructors are not the preview's to debug.
[[noreturn]] void finish(int code)
{
    {
        const QMutexLocker lock(&g_warningsMutex);
        for (const QString &w : std::as_const(g_warnings)) {
            std::fprintf(stdout, "W %s\n", qUtf8Printable(w));
        }
    }
    std::fflush(stdout);
    std::fflush(stderr);
    std::_Exit(code);
}

int renderVariant(int argc, char **argv, const QString &variant, const QString &file, const QString &png, const QSize &size,
                  const QStringList &importPaths)
{
    QApplication app(argc, argv);
    AtlasVariant::applyToApplication(variant);
    qInstallMessageHandler(messageHandler);

    // A stuck page must not hang CI.
    QTimer::singleShot(kRenderSeconds * 1000, &app, [] {
        say(QStringLiteral("error: still rendering after %1 s").arg(kRenderSeconds));
        finish(kExitError);
    });

    QQmlEngine engine;
    for (const QString &path : importPaths) {
        engine.addImportPath(path);
    }

    QQmlComponent hostComponent(&engine);
    hostComponent.setData(QByteArray(kHostQml), QUrl::fromLocalFile(QCoreApplication::applicationDirPath() + QStringLiteral("/atlas-preview-host.qml")));
    std::unique_ptr<QObject> hostObject(hostComponent.createWithInitialProperties(
        {{QStringLiteral("rtl"), variant == QLatin1String("rtl")}, {QStringLiteral("compact"), variant == QLatin1String("compact")}}));
    auto *host = qobject_cast<QQuickItem *>(hostObject.get());
    if (!host) {
        say(QStringLiteral("error: cannot load Atlas.Ui (is it installed, or on the import path with -I or QML_IMPORT_PATH?) [status %1]: %2")
                .arg(int(hostComponent.status()))
                .arg(hostComponent.errorString().trimmed()));
        finish(kExitError);
    }
    if (variant == QLatin1String("contrast") && !host->property("highContrast").toBool()) {
        say(QStringLiteral("error: the contrast variant did not turn high contrast on (no settings portal stand-in on the session bus?)"));
        finish(kExitError);
    }

    QQmlComponent component(&engine, QUrl::fromLocalFile(file));
    if (component.status() == QQmlComponent::Loading) {
        settle(100);
    }
    std::unique_ptr<QObject> root(component.status() == QQmlComponent::Ready ? component.create() : nullptr);
    if (!root) {
        say(QStringLiteral("error: %1").arg(component.errorString().trimmed()));
        finish(kExitError);
    }

    std::unique_ptr<QQuickWindow> ownWindow;
    QQuickWindow *window = qobject_cast<QQuickWindow *>(root.get());
    if (window) {
        if (size.isValid()) {
            window->resize(size);
        }
        QMetaObject::invokeMethod(host, "mirrorWindow", Q_ARG(QVariant, QVariant::fromValue(static_cast<QObject *>(window))));
    } else if (auto *item = qobject_cast<QQuickItem *>(root.get())) {
        const QSize used = size.isValid() ? size : QSize(900, 700);
        ownWindow = std::make_unique<QQuickWindow>();
        window = ownWindow.get();
        window->resize(used);
        host->setParentItem(window->contentItem());
        host->setSize(QSizeF(used));
        item->setParentItem(host);
        item->setSize(QSizeF(used));
    } else {
        say(QStringLiteral("error: the root of %1 is %2, not an Item or a Window").arg(file, QString::fromUtf8(root->metaObject()->className())));
        finish(kExitError);
    }

    window->show();
    QElapsedTimer waited;
    waited.start();
    while (!window->isExposed() && waited.elapsed() < 10000) {
        settle(20);
    }
    // Popups open and transitions end (the goldens wait the same 600 ms).
    settle(700);
    const QImage image = window->grabWindow();
    if (image.isNull()) {
        say(QStringLiteral("error: could not grab the picture of the %1 variant").arg(variant));
        finish(kExitError);
    }
    if (!savePng(image.convertToFormat(QImage::Format_RGB32), png)) {
        say(QStringLiteral("error: could not write %1").arg(png));
        finish(kExitError);
    }
    finish(0);
}

// ---- helper processes of the contrast variant ------------------------------

int runPortal(int argc, char **argv, const QString &readyFile)
{
    QCoreApplication app(argc, argv);
    return AtlasVariant::runFakePortal(readyFile, kPortalSeconds);
}

// Inside a private session bus: starts the portal stand-in, waits for it, runs
// the render process (its output goes straight through), stops the portal.
int runContrastHost(int argc, char **argv, const QStringList &renderArgs)
{
    QCoreApplication app(argc, argv);
    // The parent's scratch directory for this variant: it removes it.
    const QString ready = qEnvironmentVariable(kScratchVariable) + QStringLiteral("/portal-ready");
    if (qEnvironmentVariable(kScratchVariable).isEmpty()) {
        say(QStringLiteral("error: no scratch directory"));
        return kExitError;
    }
    QProcess portal;
    hardenChild(portal);
    portal.setProcessChannelMode(QProcess::ForwardedErrorChannel);
    portal.start(QCoreApplication::applicationFilePath(), {QStringLiteral("--internal-portal"), ready});
    QElapsedTimer waited;
    waited.start();
    while (!QFile::exists(ready) && portal.state() != QProcess::NotRunning && waited.elapsed() < 10000) {
        settle(50);
    }
    if (!QFile::exists(ready)) {
        say(QStringLiteral("error: the settings portal stand-in did not start"));
        stopProcess(portal);
        return kExitError;
    }

    QProcess render;
    hardenChild(render);
    render.setProcessChannelMode(QProcess::ForwardedChannels);
    render.start(QCoreApplication::applicationFilePath(), renderArgs);
    int code = kExitError;
    if (render.waitForFinished(kHostSeconds * 1000)) {
        code = render.exitStatus() == QProcess::NormalExit ? render.exitCode() : kExitError;
    } else {
        say(QStringLiteral("error: the contrast variant did not finish in %1 s").arg(kHostSeconds));
        stopProcess(render);
    }
    stopProcess(portal);
    return code;
}

// ---- the parent -----------------------------------------------------------

// SIGINT and SIGTERM reach the event loop through a pipe, so the parent can stop its
// children and remove its temporary directory.
int g_signalPipe[2] = {-1, -1};

void onSignal(int)
{
    const char byte = 1;
    const ssize_t ignored = ::write(g_signalPipe[1], &byte, 1);
    (void)ignored;
}

bool catchSignals(QObject *parent, const std::function<void()> &handler)
{
    if (::pipe2(g_signalPipe, O_CLOEXEC | O_NONBLOCK) != 0) {
        return false;
    }
    auto *notifier = new QSocketNotifier(g_signalPipe[0], QSocketNotifier::Read, parent);
    QObject::connect(notifier, &QSocketNotifier::activated, parent, [handler] {
        char buffer[16];
        const ssize_t ignored = ::read(g_signalPipe[0], buffer, sizeof buffer);
        (void)ignored;
        handler();
    });
    struct sigaction action = {};
    action.sa_handler = onSignal;
    sigemptyset(&action.sa_mask);
    return ::sigaction(SIGINT, &action, nullptr) == 0 && ::sigaction(SIGTERM, &action, nullptr) == 0;
}

// The org.kde.desktop style (kf6-qqc2-desktop-style) is the one the pictures are
// made in; without it Qt would fall back to another and say nothing.
bool desktopStyleInstalled()
{
    QStringList roots{QLibraryInfo::path(QLibraryInfo::QmlImportsPath)};
    for (const char *name : {"QML_IMPORT_PATH", "QML2_IMPORT_PATH"}) {
        roots << qEnvironmentVariable(name).split(QDir::listSeparator(), Qt::SkipEmptyParts);
    }
    for (const QString &root : std::as_const(roots)) {
        if (QFile::exists(root + QStringLiteral("/org/kde/desktop/qmldir"))) {
            return true;
        }
    }
    return false;
}

struct Job
{
    QString variant;
    std::unique_ptr<QProcess> process;
    QByteArray out;
    QByteArray err;
    int code = -1;
    bool done = false;
};

bool writeFile(const QString &path, const QByteArray &data)
{
    if (refuseLink(path)) {
        return false;
    }
    QSaveFile f(path);
    return f.open(QIODevice::WriteOnly) && f.write(data) == data.size() && f.commit();
}

// A private environment for one variant, the way tests/visual/run-variant.sh
// makes it: its own XDG directories and colour scheme, the software renderer,
// scale 1, the org.kde.desktop style.
bool prepare(Job &job, const QString &root, const QStringList &renderArgs, QProcessEnvironment env, QString *problem)
{
    const QString base = QDir(root).filePath(job.variant);
    const QString config = base + QStringLiteral("/config");
    if (!QDir().mkpath(config) || !QDir().mkpath(base + QStringLiteral("/data")) || !QDir().mkpath(base + QStringLiteral("/cache"))) {
        *problem = QStringLiteral("cannot make %1").arg(base);
        return false;
    }
    const QByteArray scheme = AtlasVariant::kdeglobals(job.variant);
    if (scheme.isEmpty() || !writeFile(config + QStringLiteral("/kdeglobals"), scheme)) {
        *problem = QStringLiteral("cannot write the colour scheme of the %1 variant").arg(job.variant);
        return false;
    }
    if (AtlasVariant::transparencyOff(job.variant)
        && !writeFile(config + QStringLiteral("/atlasrc"), "[Appearance]\nTransparency=false\n")) {
        *problem = QStringLiteral("cannot write atlasrc");
        return false;
    }
    env.insert(QStringLiteral("XDG_CONFIG_HOME"), config);
    env.insert(QStringLiteral("XDG_DATA_HOME"), base + QStringLiteral("/data"));
    env.insert(QStringLiteral("XDG_CACHE_HOME"), base + QStringLiteral("/cache"));
    env.insert(QStringLiteral("QT_QUICK_BACKEND"), QStringLiteral("software"));
    env.insert(QStringLiteral("QT_SCALE_FACTOR"), QStringLiteral("1"));
    env.insert(QStringLiteral("QT_FONT_DPI"), QStringLiteral("96"));
    env.insert(QStringLiteral("QT_QUICK_CONTROLS_STYLE"), QStringLiteral("org.kde.desktop"));
    env.insert(QStringLiteral("QT_LOGGING_RULES"), QStringLiteral("qt.qpa.fonts=false"));
    // Offscreen unless the caller chose a platform (CI runs it under xvfb-run
    // with QT_QPA_PLATFORM=xcb or leaves it): nothing may reach a real desktop.
    if (!env.contains(QStringLiteral("QT_QPA_PLATFORM"))) {
        env.insert(QStringLiteral("QT_QPA_PLATFORM"), QStringLiteral("offscreen"));
    }
    // Qt learns "high contrast" only from the settings portal.
    env.insert(QStringLiteral("QT_QPA_PLATFORMTHEME"), job.variant == QLatin1String("contrast") ? QStringLiteral("xdgdesktopportal") : QString());
    env.remove(QStringLiteral("WAYLAND_DISPLAY"));
    env.remove(QStringLiteral("KDE_FULL_SESSION"));
    env.remove(QStringLiteral("XDG_CURRENT_DESKTOP"));

    // Every variant runs on a session bus of its own: no service can be
    // started on it (no service directories), and nothing on the user's bus is
    // reachable, whether a notification, a global shortcut or the real
    // portal's colour scheme.
    const QString runner = QStandardPaths::findExecutable(QStringLiteral("dbus-run-session"));
    if (runner.isEmpty()) {
        *problem = QStringLiteral("atlas-preview needs dbus-run-session (package dbus-daemon)");
        return false;
    }
    const QString busConfig = base + QStringLiteral("/bus.conf");
    const QByteArray busXml = QByteArrayLiteral(
                                  "<!DOCTYPE busconfig PUBLIC \"-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN\" "
                                  "\"http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd\">\n"
                                  "<busconfig>\n  <type>session</type>\n  <listen>unix:dir=")
        + base.toHtmlEscaped().toUtf8()
        + QByteArrayLiteral("</listen>\n  <auth>EXTERNAL</auth>\n  <policy context=\"default\">\n"
                            "    <allow send_destination=\"*\" eavesdrop=\"true\"/>\n    <allow eavesdrop=\"true\"/>\n"
                            "    <allow own=\"*\"/>\n  </policy>\n</busconfig>\n");
    if (!writeFile(busConfig, busXml)) {
        *problem = QStringLiteral("cannot write %1").arg(busConfig);
        return false;
    }
    env.insert(QString::fromLatin1(kScratchVariable), base);

    job.process = std::make_unique<QProcess>();
    hardenChild(*job.process);
    job.process->setProcessEnvironment(env);
    const QString self = QCoreApplication::applicationFilePath();
    job.process->setProgram(runner);
    QStringList args{QStringLiteral("--config-file=%1").arg(busConfig), QStringLiteral("--"), self};
    if (job.variant == QLatin1String("contrast")) {
        args << QStringLiteral("--internal-contrast-host");
    }
    job.process->setArguments(args + renderArgs);
    return true;
}

int runParent(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    QCoreApplication::setApplicationName(QStringLiteral("atlas-preview"));
    QCommandLineParser parser;
    parser.setApplicationDescription(QStringLiteral("Loads a QML page offscreen in Atlas.Ui's visual-test matrix (%1) and writes one PNG per variant.")
                                         .arg(names().join(QStringLiteral(", "))));
    parser.addHelpOption();
    parser.addPositionalArgument(QStringLiteral("file.qml"), QStringLiteral("The page or component to load."));
    const QCommandLineOption outOption({QStringLiteral("o"), QStringLiteral("out")}, QStringLiteral("Where the PNGs and warnings go (created)."), QStringLiteral("dir"));
    const QCommandLineOption sizeOption(QStringLiteral("size"), QStringLiteral("Size of the picture (default: 900x700; a window keeps its own)."), QStringLiteral("WxH"));
    const QCommandLineOption importOption({QStringLiteral("I"), QStringLiteral("import-path")}, QStringLiteral("An extra QML import path (repeatable)."), QStringLiteral("path"));
    parser.addOption(outOption);
    parser.addOption(sizeOption);
    parser.addOption(importOption);
    if (!parser.parse(QCoreApplication::arguments())) {
        say(QStringLiteral("atlas-preview: %1").arg(parser.errorText()));
        return kExitError;
    }
    if (parser.isSet(QStringLiteral("help"))) {
        std::fprintf(stdout, "%s\n", qUtf8Printable(parser.helpText()));
        return 0;
    }
    if (parser.positionalArguments().size() != 1 || !parser.isSet(outOption)) {
        say(QStringLiteral("usage: atlas-preview <file.qml> --out <dir> [--size WxH] [-I <import path>]..."));
        return kExitError;
    }
    const QFileInfo info(parser.positionalArguments().first());
    if (!info.isFile() || !info.isReadable() || info.suffix().compare(QLatin1String("qml"), Qt::CaseInsensitive) != 0) {
        say(QStringLiteral("atlas-preview: %1 is not a readable .qml file").arg(info.filePath()));
        return kExitError;
    }
    QSize size;
    if (parser.isSet(sizeOption) && !parseSize(parser.value(sizeOption), &size)) {
        say(QStringLiteral("atlas-preview: --size is WIDTHxHEIGHT, each 1 to %1: %2").arg(kLargestSide).arg(parser.value(sizeOption)));
        return kExitError;
    }
    QStringList importPaths;
    for (const QString &p : parser.values(importOption)) {
        importPaths << QDir(p).absolutePath();
    }
    if (!desktopStyleInstalled()) {
        say(QStringLiteral("atlas-preview: the org.kde.desktop style is not installed (package kf6-qqc2-desktop-style); the pictures would be made in another style"));
        return kExitError;
    }
    const QString outDir = QDir(parser.value(outOption)).absolutePath();
    const bool outExisted = QFileInfo::exists(outDir);
    if (!QDir().mkpath(outDir)) {
        say(QStringLiteral("atlas-preview: cannot create %1").arg(outDir));
        return kExitError;
    }
    if (!outExisted) {
        QFile::setPermissions(outDir, QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ExeOwner);
    }
    const QString file = info.canonicalFilePath();
    const QString stem = info.completeBaseName();

    QTemporaryDir scratch(QDir::tempPath() + QStringLiteral("/atlas-preview-XXXXXX"));
    if (!scratch.isValid()) {
        say(QStringLiteral("atlas-preview: cannot make a temporary directory"));
        return kExitError;
    }

    // The hidden modes run only for a parent that holds this random value.
    qputenv(kTokenVariable, QUuid::createUuid().toString(QUuid::Id128).toLatin1());
    QList<std::shared_ptr<Job>> jobs;
    const QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
    for (const QString &variant : names()) {
        auto job = std::make_shared<Job>();
        job->variant = variant;
        QStringList args{QStringLiteral("--internal-render"), variant, QStringLiteral("--internal-file"), file, QStringLiteral("--internal-png"),
                         QDir(outDir).filePath(stem + QLatin1Char('-') + variant + QStringLiteral(".png"))};
        if (size.isValid()) {
            args << QStringLiteral("--internal-size") << QStringLiteral("%1x%2").arg(size.width()).arg(size.height());
        }
        for (const QString &p : std::as_const(importPaths)) {
            args << QStringLiteral("--internal-import") << p;
        }
        QString problem;
        if (!prepare(*job, scratch.path(), args, env, &problem)) {
            say(QStringLiteral("atlas-preview: %1").arg(problem));
            return kExitError;
        }
        jobs << job;
    }

    // A few at a time: each render is a Qt Quick process of its own.
    const int parallel = qBound(1, QThread::idealThreadCount() / 2, 4);
    int next = 0;
    int running = 0;
    QEventLoop loop;
    bool interrupted = false;
    std::function<void()> startMore = [&] {
        while (!interrupted && running < parallel && next < jobs.size()) {
            const std::shared_ptr<Job> job = jobs.at(next++);
            QProcess *p = job->process.get();
            ++running;
            QObject::connect(p, &QProcess::readyReadStandardOutput, p, [job, p] { job->out += p->readAllStandardOutput(); });
            QObject::connect(p, &QProcess::readyReadStandardError, p, [job, p] { job->err += p->readAllStandardError(); });
            auto finished = [&, job](int code, QProcess::ExitStatus status) {
                if (job->done) {
                    return;
                }
                job->done = true;
                job->out += job->process->readAllStandardOutput();
                job->err += job->process->readAllStandardError();
                job->code = status == QProcess::NormalExit ? code : kExitError;
                --running;
                startMore();
                if (running == 0 && (interrupted || next >= jobs.size())) {
                    loop.quit();
                }
            };
            QObject::connect(p, &QProcess::finished, p, finished);
            QObject::connect(p, &QProcess::errorOccurred, p, [job, finished](QProcess::ProcessError error) {
                if (error == QProcess::FailedToStart) {
                    job->err += "cannot start the render process\n";
                    finished(kExitError, QProcess::NormalExit);
                }
            });
            QTimer::singleShot(kParentSeconds * 1000, p, [job, p] {
                if (!job->done) {
                    job->err += QByteArray("error: not finished in ") + QByteArray::number(kParentSeconds) + " s\n";
                    p->terminate();
                    QTimer::singleShot(kGraceMs, p, [job, p] {
                        if (!job->done) {
                            p->kill();
                        }
                    });
                }
            });
            p->start();
        }
    };
    catchSignals(&app, [&] {
        interrupted = true;
        for (const auto &job : std::as_const(jobs)) {
            QProcess *p = job->process.get();
            if (p && !job->done && p->state() != QProcess::NotRunning) {
                p->terminate();
                QTimer::singleShot(kGraceMs, p, [job, p] {
                    if (!job->done) {
                        p->kill();
                    }
                });
            }
        }
        if (running == 0) {
            loop.quit();
        }
    });
    startMore();
    if (running > 0) {
        loop.exec();
    }

    if (interrupted) {
        say(QStringLiteral("atlas-preview: interrupted"));
        return kExitError;
    }
    // Report in matrix order: errors first, then the warnings, each message once
    // with the variants that raised it.
    bool failed = false;
    QStringList order;
    QMap<QString, QStringList> warned;
    int pictures = 0;
    for (const auto &job : std::as_const(jobs)) {
        const QString err = QString::fromUtf8(job->err).trimmed();
        if (job->code == kExitError || (job->code != 0 && job->code != kExitWarnings)) {
            failed = true;
            say(QStringLiteral("atlas-preview: %1: %2").arg(job->variant, err.isEmpty() ? QStringLiteral("failed (exit %1)").arg(job->code) : err));
        } else {
            ++pictures;
        }
        for (const QString &line : QString::fromUtf8(job->out).split(QLatin1Char('\n'), Qt::SkipEmptyParts)) {
            if (!line.startsWith(QLatin1String("W "))) {
                continue;
            }
            const QString message = line.mid(2);
            if (!warned.contains(message)) {
                order << message;
            }
            if (!warned[message].contains(job->variant)) {
                warned[message] << job->variant;
            }
        }
    }
    QStringList report;
    for (const QString &message : std::as_const(order)) {
        const QStringList in = warned.value(message);
        report << (in.size() == names().size() ? message : QStringLiteral("%1  [%2]").arg(message, in.join(QStringLiteral(", "))));
    }
    const QString warningsPath = QDir(outDir).filePath(stem + QStringLiteral("-warnings.txt"));
    if (report.isEmpty()) {
        QFile::remove(warningsPath);
    } else {
        for (const QString &r : std::as_const(report)) {
            say(QStringLiteral("warning: %1").arg(r));
        }
        if (!writeFile(warningsPath, (report.join(QLatin1Char('\n')) + QLatin1Char('\n')).toUtf8())) {
            say(QStringLiteral("atlas-preview: cannot write %1").arg(warningsPath));
            failed = true;
        }
    }
    std::fprintf(stdout, "atlas-preview: %d of %lld pictures in %s, %lld warning(s)\n", pictures, static_cast<long long>(names().size()), qUtf8Printable(outDir),
                 static_cast<long long>(report.size()));
    if (failed) {
        return kExitError;
    }
    return report.isEmpty() ? 0 : kExitWarnings;
}

} // namespace

int main(int argc, char **argv)
{
    // The hidden modes are read by hand: QApplication must not exist yet in the parent.
    const QStringList args = [&] {
        QStringList a;
        for (int i = 1; i < argc; ++i) {
            a << QString::fromLocal8Bit(argv[i]);
        }
        return a;
    }();
    if (!args.isEmpty() && args.at(0).startsWith(QLatin1String("--internal-")) && !privateModeAllowed()) {
        say(QStringLiteral("atlas-preview: the --internal-* options are for atlas-preview itself"));
        return kExitError;
    }
    if (args.size() == 2 && args.at(0) == QLatin1String("--internal-portal")) {
        return runPortal(argc, argv, args.at(1));
    }
    const bool host = !args.isEmpty() && args.at(0) == QLatin1String("--internal-contrast-host");
    const QStringList render = host ? args.mid(1) : args;
    if (render.size() >= 2 && render.at(0) == QLatin1String("--internal-render")) {
        if (host) {
            return runContrastHost(argc, argv, render);
        }
        // --internal-render <variant> then key/value pairs; the parent wrote them.
        const QString variant = render.at(1);
        QString file, png;
        QSize size;
        QStringList importPaths;
        for (qsizetype i = 2; i + 1 < render.size(); i += 2) {
            const QString &key = render.at(i);
            const QString &value = render.at(i + 1);
            if (key == QLatin1String("--internal-file")) {
                file = value;
            } else if (key == QLatin1String("--internal-png")) {
                png = value;
            } else if (key == QLatin1String("--internal-size")) {
                parseSize(value, &size);
            } else if (key == QLatin1String("--internal-import")) {
                importPaths << value;
            }
        }
        if (!AtlasVariant::isValid(variant) || file.isEmpty() || png.isEmpty()) {
            say(QStringLiteral("atlas-preview: an internal option is for atlas-preview itself"));
            return kExitError;
        }
        return renderVariant(argc, argv, variant, file, png, size, importPaths);
    }
    return runParent(argc, argv);
}
