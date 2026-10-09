// The Telamon.Ui plugin class. Qt would generate it; this one also tells each
// QML engine that loads the module to re-evaluate its translated strings,
// installs the module's translator as the module loads (translations.cpp),
// and moves an app that asked for the CPU renderer onto the GPU on a HiDPI
// screen (pickRenderer below).
#include <algorithm>

#include <QtCore/qloggingcategory.h>
#include <QtCore/qplugin.h>
#include <QtCore/qtimer.h>
#include <QtGui/qguiapplication.h>
#include <QtGui/qscreen.h>
#include <QtQml/qqmlengine.h>
#include <QtQml/qqmlextensionplugin.h>
#include <QtQuick/qquickwindow.h>

#include "appearance.h"
#include "legacyconfig.h"
#include "telamonnetwork.h"

extern void qml_register_types_Telamon_Ui();
bool telamonUiInstallTranslations();
bool telamonUiTranslationsDone();

namespace {
Q_LOGGING_CATEGORY(lcRenderer, "telamon.ui.renderer", QtInfoMsg)

// Telamon apps draw on the CPU (Qt Quick's software backend) to save the GPU
// stack's memory and start-up time. On Wayland at a fractional scale that
// path leaves the last device pixel row and column of a window unpainted, so
// old frames show there: a black or grey line along a window's edge, a stray
// line beside the Updater, Notepad's border left behind while it is dragged
// on a 4K screen at 1.7x. Qt reports such a screen with the integer ceiling
// of its scale (2 for 1.7; only a window knows 1.7), so the rule is: with any
// screen above 1, an app that asked for the CPU draws on the GPU instead.
// Runs as each engine loads the module, before that engine makes a window, so
// before Qt Quick's render loop reads the graphics API. Not only for the first
// engine: the framework's start-up version check loads the module in an
// engine of its own before the app has asked for the software renderer, so
// the first look found nothing to change (1.6.0 never switched an app). Once
// switched, the backend is no longer "software" and later engines change
// nothing. setGraphicsApi(Software) picks the "software" scene graph backend;
// graphicsApi() keeps reporting the RHI API (OpenGL), so the backend is what
// is read, and cleared. An explicit choice wins: QT_QUICK_BACKEND (then the
// app never asked for Software here), and TELAMON_SOFTWARE_RENDERING=1 keeps
// the CPU (ATLAS_SOFTWARE_RENDERING, its name before 2.0.0, does too).
void pickRenderer()
{
    if (QQuickWindow::sceneGraphBackend() != QLatin1String("software")) {
        return;
    }
    if (LegacyConfig::env("TELAMON_SOFTWARE_RENDERING", "ATLAS_SOFTWARE_RENDERING") == "1") {
        return;
    }
    if (!QGuiApplication::platformName().startsWith(QLatin1String("wayland"))) {
        return;
    }
    qreal highest = 1;
    const auto screens = QGuiApplication::screens();
    for (const QScreen *screen : screens) {
        highest = std::max(highest, screen->devicePixelRatio());
    }
    if (highest <= 1) {
        return;
    }
    QQuickWindow::setSceneGraphBackend(QString());
    QQuickWindow::setGraphicsApi(QSGRendererInterface::OpenGL);
    qCInfo(lcRenderer) << "drawing on the GPU: a screen is scaled" << highest
                       << "and the CPU renderer leaves stale edge pixels at fractional scales"
                       << "(TELAMON_SOFTWARE_RENDERING=1 keeps the CPU)";
}

// Retranslates `engine` once the translator is in place, looking every 10 ms
// for up to 5 s. Runs on the engine's thread, and the timers die with the
// engine, so nothing touches it from another thread or after it is gone.
void retranslateWhenDone(QQmlEngine *engine, int triesLeft = 500)
{
    if (telamonUiTranslationsDone()) {
        engine->retranslate();
    } else if (triesLeft > 0) {
        QTimer::singleShot(10, engine, [engine, triesLeft] { retranslateWhenDone(engine, triesLeft - 1); });
    }
}
}

class TelamonUiPlugin : public QQmlEngineExtensionPlugin
{
    Q_OBJECT
    Q_PLUGIN_METADATA(IID QQmlEngineExtensionInterface_iid)

public:
    TelamonUiPlugin(QObject *parent = nullptr)
        : QQmlEngineExtensionPlugin(parent)
    {
        // Keeps the type registration linked in.
        volatile auto registration = &qml_register_types_Telamon_Ui;
        Q_UNUSED(registration);
    }

    void initializeEngine(QQmlEngine *engine, const char *) override
    {
        if (!engine) {
            return;
        }
        // Before any item fetches: no cleartext address of another computer.
        TelamonNetwork::install(engine);
        pickRenderer();
        // The violet and the UI font, before any item reads them.
        telamonUiApplyBrand();
        // Before the engine evaluates any qsTr(), then once more so that an
        // engine that cached translations earlier looks again.
        if (telamonUiInstallTranslations()) {
            engine->retranslate();
            return;
        }
        // The install runs later on the application's thread: retranslate
        // after it, on the engine's own thread.
        retranslateWhenDone(engine);
    }
};

#include "telamonuiplugin.moc"
