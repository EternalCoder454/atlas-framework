// Accessibility test for Atlas.Ui: every ui/gallery/demos/*Demo.qml is loaded
// and its item tree walked. Any visible, enabled item the keyboard can reach
// with Tab must have an accessible role and a non-empty accessible name.
// See tests/README.md.
//
// Environment (set by visual/run-variant.sh through ctest): ATLAS_DEMO_DIR,
// ATLAS_DEMO_FILTER (see demolist.h).
#include "../demolist.h"

#include <QtQuickTest/quicktest.h>

#include <QAccessible>
#include <QGuiApplication>
#include <QQmlContext>
#include <QQmlEngine>
#include <QQuickItem>
#include <QQuickWindow>

class Audit : public DemoList
{
    Q_OBJECT
public:
    // The problems found under `root` (an Item, or a window), one sentence
    // each, naming the demo, the item's type and its path. Empty when clean.
    Q_INVOKABLE QStringList audit(QObject *root, const QString &demo) const
    {
        QStringList problems;
        QQuickItem *item = qobject_cast<QQuickItem *>(root);
        if (auto *window = qobject_cast<QQuickWindow *>(root)) {
            item = window->contentItem();
        }
        if (item) {
            walk(item, demo, QString(), problems);
        } else {
            problems << QStringLiteral("%1: the root is neither an Item nor a window").arg(demo);
        }
        return problems;
    }

private:
    static QString typeName(const QObject *o)
    {
        // "AtlasButton_QMLTYPE_12" or "QQuickTextField" -> a readable name.
        QString name = QString::fromLatin1(o->metaObject()->className());
        const qsizetype at = name.indexOf(QLatin1String("_QMLTYPE_"));
        if (at > 0) {
            name.truncate(at);
        }
        if (name.startsWith(QLatin1String("QQuick"))) {
            name.remove(0, 6);
        }
        return name;
    }

    static void walk(QQuickItem *item, const QString &demo, const QString &parentPath, QStringList &problems)
    {
        // An item that is not visible hides its children too.
        if (!item->isVisible()) {
            return;
        }
        const QString type = typeName(item);
        const QString label = item->objectName().isEmpty() ? type : type + QLatin1Char('#') + item->objectName();
        const QString path = parentPath.isEmpty() ? label : parentPath + QLatin1Char('/') + label;

        if (item->isEnabled() && item->activeFocusOnTab()) {
            QAccessibleInterface *iface = QAccessible::queryAccessibleInterface(item);
            if (!iface) {
                problems << QStringLiteral("%1: %2 (%3) is reachable with Tab but has no accessible interface").arg(demo, type, path);
            } else {
                if (iface->role() == QAccessible::NoRole) {
                    problems << QStringLiteral("%1: %2 (%3) is reachable with Tab but has no Accessible.role").arg(demo, type, path);
                }
                if (iface->text(QAccessible::Name).trimmed().isEmpty()) {
                    problems << QStringLiteral("%1: %2 (%3) is reachable with Tab but has no Accessible.name").arg(demo, type, path);
                }
            }
        }
        const QList<QQuickItem *> children = item->childItems();
        for (QQuickItem *child : children) {
            walk(child, demo, path, problems);
        }
    }
};

class Setup : public QObject
{
    Q_OBJECT
public slots:
    void applicationAvailable() { QGuiApplication::setFont(QFont(QStringLiteral("Noto Sans"), 10)); }
    void qmlEngineAvailable(QQmlEngine *engine) { engine->rootContext()->setContextProperty(QStringLiteral("A11y"), &m_audit); }

private:
    Audit m_audit;
};

QUICK_TEST_MAIN_WITH_SETUP(atlas_a11y, Setup)

#include "main.moc"
