// The AtlasShortcuts registry: add, remove, conflicts, destroyed actions.
// Compiled straight from ui/atlasshortcuts.cpp, with stand-in actions that
// have the three properties the registry watches.
#include "atlasshortcuts.h"

#include <QKeySequence>
#include <QQuickItem>
#include <QQuickWindow>
#include <QSignalSpy>
#include <QtTest>

class FakeAction : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QVariant shortcut MEMBER m_shortcut NOTIFY shortcutChanged)
    Q_PROPERTY(QString text MEMBER m_text NOTIFY textChanged)
    Q_PROPERTY(bool enabled MEMBER m_enabled NOTIFY enabledChanged)
public:
    FakeAction(const QString &text, const QVariant &shortcut, QObject *parent = nullptr)
        : QObject(parent), m_shortcut(shortcut), m_text(text) {}
    void setShortcut(const QVariant &v) { m_shortcut = v; Q_EMIT shortcutChanged(); }
    void setEnabled(bool on) { m_enabled = on; Q_EMIT enabledChanged(); }
Q_SIGNALS:
    void shortcutChanged();
    void textChanged();
    void enabledChanged();
private:
    QVariant m_shortcut;
    QString m_text;
    bool m_enabled = true;
};

class TestShortcuts : public QObject
{
    Q_OBJECT
private Q_SLOTS:
    void addRemove()
    {
        AtlasShortcuts reg;
        QSignalSpy spy(&reg, &AtlasShortcuts::actionsChanged);
        FakeAction a("Save", "Ctrl+S"), b("Open", "Ctrl+O");
        reg.add(&a);
        reg.add(&a); // twice: still once
        reg.add(&b);
        reg.add(nullptr);
        QCOMPARE(reg.actions(), (QList<QObject *>{&a, &b}));
        QCOMPARE(spy.count(), 2);
        reg.remove(&a);
        QCOMPARE(reg.actions(), (QList<QObject *>{&b}));
        reg.remove(&a); // unknown: no signal
        QCOMPARE(spy.count(), 3);
    }

    void conflict()
    {
        AtlasShortcuts reg;
        QSignalSpy spy(&reg, &AtlasShortcuts::conflictsChanged);
        FakeAction a("&Save", "Ctrl+S"), b("Sort", QVariant::fromValue(QKeySequence(QStringLiteral("ctrl+s")))),
            c("Open", "Ctrl+O");
        reg.add(&a);
        reg.add(&c);
        QVERIFY(reg.conflicts().isEmpty());
        QTest::ignoreMessage(QtWarningMsg, QRegularExpression("Shortcut conflict: .*Ctrl\\+S.*Save.*Sort"));
        reg.add(&b);
        const QVariantList list = reg.conflicts();
        QCOMPARE(list.size(), 1);
        const QVariantMap m = list.first().toMap();
        QCOMPARE(m["shortcut"].toString(), QStringLiteral("Ctrl+S"));
        QCOMPARE(m["texts"].toStringList(), (QStringList{"&Save", "Sort"}).replaceInStrings("&", ""));
        QTRY_COMPARE(spy.count(), 1);

        // Disabled actions do not conflict.
        b.setEnabled(false);
        QVERIFY(reg.conflicts().isEmpty());
        QTRY_COMPARE(spy.count(), 2);
        // Back on: a new conflict, warned again.
        QTest::ignoreMessage(QtWarningMsg, QRegularExpression("Shortcut conflict"));
        b.setEnabled(true);
        QCOMPARE(reg.conflicts().size(), 1);
        // Changing the shortcut resolves it.
        b.setShortcut("Ctrl+Shift+S");
        QVERIFY(reg.conflicts().isEmpty());
    }

    void standardKey()
    {
        AtlasShortcuts reg;
        FakeAction a("Save", int(QKeySequence::Save)), b("Store", "Ctrl+S");
        reg.add(&a);
        QTest::ignoreMessage(QtWarningMsg, QRegularExpression("Shortcut conflict"));
        reg.add(&b);
        QCOMPARE(reg.conflicts().size(), QKeySequence(QKeySequence::Save).toString(QKeySequence::PortableText) == "Ctrl+S" ? 1 : 0);
    }

    void windows()
    {
        QQuickWindow w1, w2;
        FakeAction a("One", "Ctrl+K", w1.contentItem()), b("Two", "Ctrl+K", w2.contentItem());
        AtlasShortcuts reg;
        reg.add(&a);
        reg.add(&b);
        // Different windows: no conflict.
        QVERIFY(reg.conflicts().isEmpty());
        // An action of unknown window meets both.
        FakeAction c("Three", "Ctrl+K");
        QTest::ignoreMessage(QtWarningMsg, QRegularExpression("Shortcut conflict"));
        reg.add(&c);
        QCOMPARE(reg.conflicts().first().toMap()["texts"].toStringList().size(), 3);
    }

    void destroyed()
    {
        AtlasShortcuts reg;
        auto *a = new FakeAction("Save", "Ctrl+S");
        FakeAction b("Sort", "Ctrl+S");
        reg.add(a);
        QTest::ignoreMessage(QtWarningMsg, QRegularExpression("Shortcut conflict"));
        reg.add(&b);
        QCOMPARE(reg.conflicts().size(), 1);
        delete a;
        QCOMPARE(reg.actions(), (QList<QObject *>{&b}));
        QVERIFY(reg.conflicts().isEmpty());
    }

    void keys()
    {
        AtlasShortcuts reg;
        QCOMPARE(reg.keys("Ctrl+Shift+S").size(), 1);
        QCOMPARE(reg.keys("Ctrl+Shift+S").first().toStringList().size(), 3);
        QCOMPARE(reg.keys("Ctrl++").first().toStringList().size(), 2);
        QCOMPARE(reg.keys("Ctrl+K, Ctrl+C").size(), 2);
        QVERIFY(reg.keys("").isEmpty());
        QVERIFY(reg.keys(QVariant()).isEmpty());
        QVERIFY(reg.readable("nonsense-not-a-key").size() >= 0);
        QCOMPARE(reg.plainText("&Save && Close"), QStringLiteral("Save & Close"));
    }
};

QTEST_MAIN(TestShortcuts)
#include "tst_shortcuts.moc"
