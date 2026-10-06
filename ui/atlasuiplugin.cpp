// The Atlas.Ui plugin class. Qt would generate it; this one also tells each
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

extern void qml_register_types_Atlas_Ui();
bool atlasUiInstallTranslations();
bool atlasUiTranslationsDone();

namespace {
Q_LOGGING_CATEGORY(lcRenderer, "atlas.ui.renderer", QtInfoMsg)

// Atlas apps draw on the CPU (Qt Quick's software backend) to save the GPU
// stack's memory and start-up time. On Wayland at a fractional scale that
// path leaves the last device pixel row and column of a window unpainted, so
// old frames show there: a black or grey line along a window's edge, a stray
// line beside the Updater, Notepad's border left behind while it is dragged
// on a 4K screen at 1.7x. Qt reports such a screen with the integer ceiling
// of its scale (2 for 1.7; only a window knows 1.7), so the rule is: with any
// screen above 1, an app that asked for the CPU draws on the GPU instead.
// Runs once, as the first engine loads the module: before any window, so
// before Qt Quick's render loop reads the graphics API. An explicit choice
// wins: QT_QUICK_BACKEND (then the app never asked for Software here), and
// ATLAS_SOFTWARE_RENDERING=1 keeps the CPU.
void pickRenderer()
{
    static bool done = false;
    if (done) {
        return;
    }
    done = true;
    if (QQuickWindow::graphicsApi() != QSGRendererInterface::Software) {
        return;
    }
    if (qEnvironmentVariable("ATLAS_SOFTWARE_RENDERING") == QLatin1String("1")) {
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
    QQuickWindow::setGraphicsApi(QSGRendererInterface::OpenGL);
    qCInfo(lcRenderer) << "drawing on the GPU: a screen is scaled" << highest
                       << "and the CPU renderer leaves stale edge pixels at fractional scales"
                       << "(ATLAS_SOFTWARE_RENDERING=1 keeps the CPU)";
}

// Retranslates `engine` once the translator is in place, looking every 10 ms
// for up to 5 s. Runs on the engine's thread, and the timers die with the
// engine, so nothing touches it from another thread or after it is gone.
void retranslateWhenDone(QQmlEngine *engine, int triesLeft = 500)
{
    if (atlasUiTranslationsDone()) {
        engine->retranslate();
    } else if (triesLeft > 0) {
        QTimer::singleShot(10, engine, [engine, triesLeft] { retranslateWhenDone(engine, triesLeft - 1); });
    }
}
}

class AtlasUiPlugin : public QQmlEngineExtensionPlugin
{
    Q_OBJECT
    Q_PLUGIN_METADATA(IID QQmlEngineExtensionInterface_iid)

public:
    AtlasUiPlugin(QObject *parent = nullptr)
        : QQmlEngineExtensionPlugin(parent)
    {
        // Keeps the type registration linked in.
        volatile auto registration = &qml_register_types_Atlas_Ui;
        Q_UNUSED(registration);
    }

    void initializeEngine(QQmlEngine *engine, const char *) override
    {
        if (!engine) {
            return;
        }
        pickRenderer();
        // The violet and the UI font, before any item reads them.
        atlasUiApplyBrand();
        // Before the engine evaluates any qsTr(), then once more so that an
        // engine that cached translations earlier looks again.
        if (atlasUiInstallTranslations()) {
            engine->retranslate();
            return;
        }
        // The install runs later on the application's thread: retranslate
        // after it, on the engine's own thread.
        retranslateWhenDone(engine);
    }
};

#include "atlasuiplugin.moc"
