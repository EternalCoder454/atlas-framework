// The Atlas.Ui plugin class. Qt would generate it; this one also tells each
// QML engine that loads the module to re-evaluate its translated strings,
// and installs the module's translator as the module loads (translations.cpp).
#include <QtCore/qcoreapplication.h>
#include <QtCore/qmetaobject.h>
#include <QtCore/qplugin.h>
#include <QtCore/qpointer.h>
#include <QtQml/qqmlengine.h>
#include <QtQml/qqmlextensionplugin.h>

extern void qml_register_types_Atlas_Ui();
bool atlasUiInstallTranslations();

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
        if (QCoreApplication *app = QCoreApplication::instance()) {
            QPointer<QQmlEngine> target(engine);
            QMetaObject::invokeMethod(app, [target] {
                if (target) {
                    QMetaObject::invokeMethod(target.data(), &QQmlEngine::retranslate, Qt::QueuedConnection);
                }
            }, Qt::QueuedConnection);
        }
    }
};

#include "atlasuiplugin.moc"
