// Behaviour tests for input handling: ToolbarButton's keys, TelamonProgressBar's
// layout and the accessibility press action. See tests/README.md.
#include <QAccessible>
#include <QAccessibleActionInterface>
#include <QGuiApplication>
#include <QObject>
#include <QQuickWindow>
#include <QScreen>
#include <QQmlContext>
#include <QQmlEngine>
#include <QtQuickTest/quicktest.h>

// `a11y.press(item)` triggers the item's accessible press action, as a screen
// reader would, and returns whether the item offers one.
class A11yHelper : public QObject
{
    Q_OBJECT
public:
    using QObject::QObject;
    Q_INVOKABLE bool press(QObject *item)
    {
        QAccessibleInterface *iface = QAccessible::queryAccessibleInterface(item);
        QAccessibleActionInterface *action = iface ? iface->actionInterface() : nullptr;
        if (!action || !action->actionNames().contains(QAccessibleActionInterface::pressAction())) {
            return false;
        }
        action->doAction(QAccessibleActionInterface::pressAction());
        return true;
    }
};

// `pixels.colorIn(window, rect)` counts the clearly coloured (not grey) pixels of the window's
// own picture (the screen's copy of it, as the software renderer's partial
// repaints left it, not a fresh render) inside rect, in the window's pixels.
class PixelHelper : public QObject
{
    Q_OBJECT
public:
    using QObject::QObject;
    Q_INVOKABLE int colorIn(QQuickWindow *window, const QRect &rect)
    {
        if (!window) {
            return -1;
        }
        const QImage shot = window->screen()->grabWindow(window->winId()).toImage().convertToFormat(QImage::Format_RGB32);
        const qreal dpr = shot.devicePixelRatio();
        int count = 0;
        for (int y = rect.top(); y <= rect.bottom(); ++y) {
            for (int x = rect.left(); x <= rect.right(); ++x) {
                const QColor c = shot.pixelColor(QPoint(qRound(x * dpr), qRound(y * dpr)));
                if (qMax(c.red(), qMax(c.green(), c.blue())) - qMin(c.red(), qMin(c.green(), c.blue())) > 60) {
                    ++count;
                }
            }
        }
        return count;
    }
};

class Setup : public QObject
{
    Q_OBJECT
public Q_SLOTS:
    void qmlEngineAvailable(QQmlEngine *engine)
    {
        engine->rootContext()->setContextProperty(QStringLiteral("a11y"), new A11yHelper(engine));
        engine->rootContext()->setContextProperty(QStringLiteral("pixels"), new PixelHelper(engine));
    }
};

QUICK_TEST_MAIN_WITH_SETUP(telamon_input, Setup)

#include "main.moc"
