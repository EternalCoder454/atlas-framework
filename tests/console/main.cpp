// Behaviour tests for TelamonConsoleView (tests/console/tst_console.qml). See tests/README.md.
#include <QGuiApplication>
#include <QClipboard>
#include <QMimeData>
#include <QObject>
#include <QQmlContext>
#include <QQmlEngine>
#include <QtQuickTest/quicktest.h>

// `clipHelper.text()` is the system clipboard's plain text, `clipHelper.hasHtml()` whether
// it also holds HTML, and `clipHelper.clear()` empties it.
class ClipHelper : public QObject
{
    Q_OBJECT
public:
    using QObject::QObject;
    Q_INVOKABLE QString text() const { return QGuiApplication::clipboard()->text(); }
    Q_INVOKABLE bool hasHtml() const { return QGuiApplication::clipboard()->mimeData()->hasHtml(); }
    Q_INVOKABLE void clear() { QGuiApplication::clipboard()->clear(); }
};

class Setup : public QObject
{
    Q_OBJECT
public Q_SLOTS:
    void qmlEngineAvailable(QQmlEngine *engine)
    {
        engine->rootContext()->setContextProperty(QStringLiteral("clipHelper"), new ClipHelper(engine));
    }
};

QUICK_TEST_MAIN_WITH_SETUP(telamon_console, Setup)

#include "main.moc"
