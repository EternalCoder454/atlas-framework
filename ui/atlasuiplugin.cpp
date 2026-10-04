// The Atlas.Ui plugin class. Qt would generate it; this one also tells each
// QML engine that loads the module to re-evaluate its translated strings,
// and installs the module's translator as the module loads (translations.cpp).
#include <QtCore/qplugin.h>
#include <QtQml/qqmlengine.h>
#include <QtQml/qqmlextensionplugin.h>

extern void qml_register_types_Atlas_Ui();
void atlasUiInstallTranslations();

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
        if (engine) {
            // Before the engine evaluates any qsTr(), then once more so that an
            // engine that cached translations earlier looks again.
            atlasUiInstallTranslations();
            engine->retranslate();
        }
    }
};

#include "atlasuiplugin.moc"
