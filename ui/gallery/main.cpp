// Atlas Gallery: start Qt, give QML the clipboard and the generated list of
// demos and snippets, load the window.
#include <QApplication>
#include <QClipboard>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QDebug>
#include <QQmlApplicationEngine>
#include <QQuickStyle>
#include <QVariant>

class Clipboard : public QObject
{
    Q_OBJECT
public:
    using QObject::QObject;
    Q_INVOKABLE void copy(const QString &text) { QGuiApplication::clipboard()->setText(text); }
};

int main(int argc, char *argv[])
{
    QApplication app(argc, argv);
    QApplication::setApplicationName(QStringLiteral("atlas-symbols"));
    QApplication::setApplicationDisplayName(QStringLiteral("Atlas Gallery"));
    // The Wayland app_id: matches the window to its launcher and icon.
    QGuiApplication::setDesktopFileName(QStringLiteral("net.eterneon.atlas.symbols"));

    if (qEnvironmentVariableIsEmpty("QT_QUICK_CONTROLS_STYLE")) {
        QQuickStyle::setStyle(QStringLiteral("org.kde.desktop"));
    }

    // snippets.json is generated at build time and compiled in (see CMakeLists.txt).
    QFile catalogFile(QStringLiteral(":/net/eterneon/atlas/symbols/snippets.json"));
    QJsonParseError parseError;
    QJsonDocument catalog;
    if (catalogFile.open(QIODevice::ReadOnly)) {
        catalog = QJsonDocument::fromJson(catalogFile.readAll(), &parseError);
    }
    if (!catalog.isObject()) {
        qWarning() << "Atlas Gallery: the control list is missing or damaged:" << (catalogFile.isOpen() ? parseError.errorString() : catalogFile.errorString());
        return 1;
    }

    Clipboard clipboard;
    QQmlApplicationEngine engine;
    engine.setInitialProperties({
        {QStringLiteral("clipboard"), QVariant::fromValue(&clipboard)},
        {QStringLiteral("catalog"), catalog.object().toVariantMap()},
    });
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreationFailed, &app, [] { QCoreApplication::exit(1); }, Qt::QueuedConnection);
    engine.loadFromModule(QStringLiteral("net.eterneon.atlas.symbols"), QStringLiteral("Main"));
    return app.exec();
}

#include "main.moc"
