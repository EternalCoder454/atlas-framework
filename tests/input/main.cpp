// Behaviour tests for input handling: ToolbarButton's keys, AtlasProgressBar's
// layout and the accessibility press action. See tests/README.md.
#include <QAccessible>
#include <QAccessibleActionInterface>
#include <QObject>
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

class Setup : public QObject
{
    Q_OBJECT
public Q_SLOTS:
    void qmlEngineAvailable(QQmlEngine *engine)
    {
        engine->rootContext()->setContextProperty(QStringLiteral("a11y"), new A11yHelper(engine));
    }
};

QUICK_TEST_MAIN_WITH_SETUP(atlas_input, Setup)

#include "main.moc"
