// The C++ half of atlas-framework-ui: see include/atlas/app.h.
#include "atlas/app.h"

#include <KDBusService>
#include <KWindowSystem>

#include <QApplication>
#include <QIcon>
#include <QElapsedTimer>
#include <QEventLoop>
#include <QLoggingCategory>
#include <QQmlApplicationEngine>
#include <QQmlComponent>
#include <QQuickStyle>
#include <QQuickWindow>

#include <algorithm>
#include <cstdio>
#include <memory>
#include <optional>
#include <vector>

// Rust, see src/lib.rs.
extern "C" {
void atlas_framework_ui_start();
void atlas_framework_ui_fatal(const char *msg);
const char *atlas_framework_ui_field(int field);
}

namespace
{
enum Field { Name = 0, Id = 1, Version = 2, Repo = 3, RequiredUi = 4 };

Q_LOGGING_CATEGORY(lcUi, "atlas.ui", QtWarningMsg)

// What atlas_app_require_ui set; empty means ask the app's app! (field 4).
QByteArray s_requiredUi;

QString field(Field f)
{
    return QString::fromUtf8(atlas_framework_ui_field(f));
}

QtMessageHandler s_previousHandler = nullptr;

void messageHandler(QtMsgType type, const QMessageLogContext &context, const QString &msg)
{
    if (type == QtFatalMsg) {
        // Save a crash report (Rust checks the user turned them on) before
        // the previous handler aborts.
        atlas_framework_ui_fatal(msg.toUtf8().constData());
    }
    // Qt 6 hands back its default handler (journal or stderr) when none was
    // installed, so this is normally that.
    if (s_previousHandler) {
        s_previousHandler(type, context, msg);
    } else {
        fprintf(stderr, "%s\n", qPrintable(qFormatLogMessage(type, context, msg)));
        fflush(stderr);
    }
}

// "1.3.0" as {1, 3, 0}: dot-separated numbers, then anything (a "-dev" tail).
// nullopt if it doesn't start with a number.
std::optional<std::vector<int>> parseVersion(const QString &text)
{
    std::vector<int> parts;
    for (const QString &piece : text.trimmed().split(QLatin1Char('.'))) {
        qsizetype digits = 0;
        while (digits < piece.size() && piece[digits].isDigit() && digits < 9) {
            ++digits;
        }
        if (digits == 0) {
            break;
        }
        parts.push_back(piece.left(digits).toInt());
        if (digits != piece.size()) {
            break;
        }
    }
    if (parts.empty()) {
        return std::nullopt;
    }
    return parts;
}

// Numeric, missing parts are 0: 1.3 equals 1.3.0, and 1.10 is above 1.9.
bool atLeast(std::vector<int> have, std::vector<int> need)
{
    const size_t n = std::max(have.size(), need.size());
    have.resize(n);
    need.resize(n);
    return !std::lexicographical_compare(have.begin(), have.end(), need.begin(), need.end());
}

// Reads the installed Atlas.Ui's version the way an app's QML would: a
// failed import is "not installed", a missing uiVersion (Atlas.Ui before
// 1.3.0) comes back as an empty string.
std::optional<QString> installedUi()
{
    QQmlEngine engine;
    QQmlComponent probe(&engine);
    probe.setData(QByteArrayLiteral("import QtQml\nimport Atlas.Ui\n"
                                    "QtObject { property string v: typeof AtlasApp.uiVersion === \"string\" ? AtlasApp.uiVersion : \"\" }\n"),
                  QUrl());
    if (probe.isError()) {
        qCWarning(lcUi) << "Atlas.Ui cannot be imported:" << probe.errorString();
        return std::nullopt;
    }
    std::unique_ptr<QObject> object(probe.create());
    if (!object) {
        qCWarning(lcUi) << "Atlas.Ui cannot be used:" << probe.errorString();
        return std::nullopt;
    }
    return object->property("v").toString();
}

// A plain window, with no Atlas.Ui in it (that is what may be missing), until
// the user closes it.
void showUiError(const QString &title, const QString &text)
{
    const QString platform = QGuiApplication::platformName();
    if (platform == QLatin1String("offscreen") || platform == QLatin1String("minimal")) {
        return; // nobody to read it or close it
    }
    QQmlEngine engine;
    QQmlComponent component(&engine);
    component.setData(QByteArrayLiteral("import QtQuick\nimport QtQuick.Controls.Basic\nimport QtQuick.Layouts\n"
                                        "ApplicationWindow {\n"
                                        "  id: win\n"
                                        "  property string message\n"
                                        "  width: 560; height: 260; minimumWidth: 360; minimumHeight: 200\n"
                                        "  visible: true\n"
                                        "  ColumnLayout {\n"
                                        "    anchors.fill: parent; anchors.margins: 24; spacing: 16\n"
                                        "    Label { Layout.fillWidth: true; Layout.fillHeight: true; text: win.message\n"
                                        "            textFormat: Text.PlainText; wrapMode: Text.Wrap; font.pixelSize: 15 }\n"
                                        "    Button { Layout.alignment: Qt.AlignRight; text: \"Close\"; onClicked: win.close() }\n"
                                        "  }\n"
                                        "}\n"),
                      QUrl());
    std::unique_ptr<QObject> object(component.createWithInitialProperties({{QStringLiteral("title"), title}, {QStringLiteral("message"), text}}));
    auto *window = qobject_cast<QQuickWindow *>(object.get());
    if (!window) {
        qCritical("Cannot show the Atlas.Ui error window: %s", qPrintable(component.errorString()));
        return;
    }
    QEventLoop loop;
    QObject::connect(window, &QWindow::visibleChanged, &loop, [&loop, window] {
        if (!window->isVisible()) {
            loop.quit();
        }
    });
    loop.exec();
}

// Exits with 1 when the installed Atlas.Ui is older than the app needs. Costs
// nothing for an app that names no version.
void requireUi()
{
    const QString need = s_requiredUi.isEmpty() ? field(RequiredUi) : QString::fromUtf8(s_requiredUi);
    if (need.isEmpty()) {
        return;
    }
    const auto needParts = parseVersion(need);
    if (!needParts) {
        qCWarning(lcUi) << "Ignoring the Atlas.Ui version this app asks for, which is not a version:" << need;
        return;
    }
    QElapsedTimer timer;
    timer.start();
    const std::optional<QString> have = installedUi();
    const auto haveParts = have ? parseVersion(*have) : std::nullopt;
    qCDebug(lcUi) << "Atlas.Ui check took" << timer.nsecsElapsed() / 1e6 << "ms";
    if (haveParts && atLeast(*haveParts, *needParts)) {
        return;
    }

    const QString app = field(Name);
    const QString fix = QStringLiteral("Update AtlasOS, or install atlas-ui %1 or newer.").arg(need);
    QString problem;
    if (!have) {
        problem = QStringLiteral("%1 needs Atlas.Ui %2 or newer, and Atlas.Ui is not installed.").arg(app, need);
    } else if (have->isEmpty()) {
        problem = QStringLiteral("%1 needs Atlas.Ui %2 or newer, and this system has an older Atlas.Ui than 1.3.0.").arg(app, need);
    } else {
        problem = QStringLiteral("%1 needs Atlas.Ui %2 or newer, and this system has Atlas.Ui %3.").arg(app, need, *have);
    }
    qCritical("%s %s", qPrintable(problem), qPrintable(fix));
    showUiError(QStringLiteral("%1 cannot start").arg(app), problem + QStringLiteral("\n\n") + fix);
    std::exit(1);
}

void raise(QQmlApplicationEngine &engine)
{
    for (QObject *root : engine.rootObjects()) {
        if (auto *window = qobject_cast<QQuickWindow *>(root)) {
            // Un-minimise, keeping maximised or full-screen.
            window->setWindowStates(window->windowStates() & ~Qt::WindowMinimized);
            window->show();
            window->raise();
            // KDBusService put the launcher's activation token in the
            // environment: use it, or Wayland won't let the window come up.
            KWindowSystem::updateStartupId(window);
            KWindowSystem::activateWindow(window);
        }
    }
}
}

extern "C" void atlas_app_init()
{
    atlas_framework_ui_start();
    // Before QApplication, so a fatal while it starts (no display, no
    // platform plugin) is saved too.
    s_previousHandler = qInstallMessageHandler(messageHandler);
    // KDBusService registers <reversed organization domain>.<application
    // name>: split the app ID so that is the app ID itself.
    const QString id = field(Id);
    const qsizetype dot = id.lastIndexOf(QLatin1Char('.'));
    QStringList domain = id.left(std::max<qsizetype>(dot, 0)).split(QLatin1Char('.'), Qt::SkipEmptyParts);
    std::reverse(domain.begin(), domain.end());
    QCoreApplication::setOrganizationDomain(domain.join(QLatin1Char('.')));
    QCoreApplication::setApplicationName(id.mid(dot + 1));
    QCoreApplication::setApplicationVersion(field(Version));
    QGuiApplication::setDesktopFileName(id);
    if (qEnvironmentVariableIsEmpty("QT_QUICK_CONTROLS_STYLE")) {
        QQuickStyle::setStyle(QStringLiteral("org.kde.desktop"));
    }
}

extern "C" void atlas_app_ready()
{
    QGuiApplication::setApplicationDisplayName(field(Name));
    QGuiApplication::setWindowIcon(QIcon::fromTheme(field(Id)));
    // Atlas.Ui's AtlasApp reads it for the About page's links.
    qApp->setProperty("atlasRepo", field(Repo));
    // Last, before any of the app's QML.
    requireUi();
}

extern "C" void atlas_app_require_ui(const char *minVersion)
{
    s_requiredUi = minVersion ? QByteArray(minVersion) : QByteArray();
}

extern "C" int atlas_app_run(int argc, char *argv[], const char *qmlModule, const char *qmlType, void *(*makeBackend)())
{
    atlas_app_init();
    QApplication app(argc, argv);
    atlas_app_ready();

    // A second launch asks this one to raise its window, then exits here.
    // Without a session bus (ssh, a bare container) there is nobody to ask:
    // run anyway, as one more instance.
    KDBusService service(KDBusService::Unique | KDBusService::NoExitOnFailure);
    if (!service.isRegistered()) {
        qWarning("No single-instance service, running as a separate instance: %s", qPrintable(service.errorMessage()));
    }

    // Deleted after the engine, which must never own it.
    std::unique_ptr<QObject> backend(makeBackend ? static_cast<QObject *>(makeBackend()) : nullptr);
    if (backend) {
        QQmlEngine::setObjectOwnership(backend.get(), QQmlEngine::CppOwnership);
    }
    QQmlApplicationEngine engine;
    if (backend) {
        engine.setInitialProperties({{QStringLiteral("backend"), QVariant::fromValue(backend.get())}});
    }
    QObject::connect(
        &engine,
        &QQmlApplicationEngine::objectCreationFailed,
        &app,
        [] {
            QCoreApplication::exit(1);
        },
        Qt::QueuedConnection);
    engine.loadFromModule(QString::fromUtf8(qmlModule), QString::fromUtf8(qmlType));
    QObject::connect(&service, &KDBusService::activateRequested, &engine, [&engine](const QStringList &, const QString &) {
        raise(engine);
    });
    return app.exec();
}
