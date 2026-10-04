// The Atlas.Ui plugin class. Qt would generate it; this one also tells each
// QML engine that loads the module to re-evaluate its translated strings,
// and installs the module's translator as the module loads (translations.cpp).
#include <QtCore/qplugin.h>
#include <QtCore/qtimer.h>
#include <QtQml/qqmlengine.h>
#include <QtQml/qqmlextensionplugin.h>

extern void qml_register_types_Atlas_Ui();
bool atlasUiInstallTranslations();
bool atlasUiTranslationsDone();

namespace {
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
