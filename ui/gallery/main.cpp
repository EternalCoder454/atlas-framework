// Atlas Symbols: start Qt, give QML the clipboard, load the window.
#include <QApplication>
#include <QClipboard>
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
    QApplication::setApplicationDisplayName(QStringLiteral("Atlas Symbols"));
    // The Wayland app_id: matches the window to its launcher and icon.
    QGuiApplication::setDesktopFileName(QStringLiteral("net.eterneon.atlas.symbols"));

    if (qEnvironmentVariableIsEmpty("QT_QUICK_CONTROLS_STYLE")) {
        QQuickStyle::setStyle(QStringLiteral("org.kde.desktop"));
    }

    Clipboard clipboard;
    QQmlApplicationEngine engine;
    engine.setInitialProperties({{QStringLiteral("clipboard"), QVariant::fromValue(&clipboard)}});
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreationFailed, &app, [] { QCoreApplication::exit(1); }, Qt::QueuedConnection);
    engine.loadFromModule(QStringLiteral("net.eterneon.atlas.symbols"), QStringLiteral("Main"));
    return app.exec();
}

#include "main.moc"
