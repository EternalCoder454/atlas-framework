// The C++ half of atlas-framework-ui: see include/atlas/app.h.
#include "atlas/app.h"

#include <KDBusService>
#include <KWindowSystem>

#include <QApplication>
#include <QIcon>
#include <QQmlApplicationEngine>
#include <QQuickStyle>
#include <QQuickWindow>

#include <algorithm>
#include <cstdio>
#include <memory>

// Rust, see src/lib.rs.
extern "C" {
void atlas_framework_ui_start();
void atlas_framework_ui_fatal(const char *msg);
const char *atlas_framework_ui_field(int field);
}

namespace
{
enum Field { Name = 0, Id = 1, Version = 2, Repo = 3 };

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

void raise(QQmlApplicationEngine &engine)
{
    for (QObject *root : engine.rootObjects()) {
        if (auto *window = qobject_cast<QQuickWindow *>(root)) {
            if (window->visibility() == QWindow::Minimized) {
                window->showNormal();
            } else {
                window->show();
            }
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
