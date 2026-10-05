// Hostile input to the C++ types: AtlasTreeModel with another model's index
// and with an index that outlived setItems(), and the text scale bounds.
// Compiled straight from ui/atlastreemodel.cpp.
#include "atlastreemodel.h"
#include "textscale.h"

#include <QtTest>

#include <limits>

// Mints an index that points at nothing (createIndex is protected).
struct Minter : AtlasTreeModel {
    QModelIndex wild() const { return createIndex(0, 0, quintptr(0x10)); }
};

class TestHardening : public QObject
{
    Q_OBJECT
    static QVariantList sample()
    {
        return {QVariantMap{{"text", "A"}, {"children", QVariantList{QVariantMap{{"text", "A1"}}}}}, QVariantMap{{"text", "B"}}};
    }
private Q_SLOTS:
    void foreignIndex()
    {
        Minter mine;
        AtlasTreeModel other;
        mine.setItems(sample());
        other.setItems(sample());
        const QModelIndex theirs = other.index(0, 0);
        QVERIFY(theirs.isValid());
        QCOMPARE(mine.rowCount(theirs), 0);
        QVERIFY(mine.data(theirs).isNull());
        QVERIFY(!mine.parent(other.index(0, 0, theirs)).isValid());
        QVERIFY(!mine.index(0, 0, theirs).isValid());
        QVERIFY(mine._selectionOf({QVariant::fromValue(theirs)}).isEmpty());
        // A made-up index with a wild pointer is not followed either.
        const QModelIndex wild = mine.wild();
        QCOMPARE(mine.rowCount(wild), 0);
        QVERIFY(mine.data(wild).isNull());
        QVERIFY(!mine.parent(wild).isValid());
        // The model's own indexes still work.
        QCOMPARE(mine.data(mine.index(0, 0)).toString(), QStringLiteral("A"));
        QCOMPARE(mine.rowCount(mine.index(0, 0)), 1);
    }

    void staleIndex()
    {
        AtlasTreeModel m;
        m.setItems(sample());
        const QModelIndex old = m.index(0, 0, m.index(0, 0));
        QVERIFY(old.isValid());
        m.setItems({QVariantMap{{"text", "Z"}}});
        QCOMPARE(m.rowCount(old), 0);
        QVERIFY(m.data(old).isNull());
        QVERIFY(!m.parent(old).isValid());
        QVERIFY(m.checkIndex(m.index(0, 0), QAbstractItemModel::CheckIndexOption::IndexIsValid | QAbstractItemModel::CheckIndexOption::DoNotUseParent));
    }

    void textScale()
    {
        const double inf = std::numeric_limits<double>::infinity();
        QCOMPARE(AtlasTextScale::clamp(std::numeric_limits<double>::quiet_NaN()), 1.0);
        QCOMPARE(AtlasTextScale::clamp(inf), 1.0);
        QCOMPARE(AtlasTextScale::clamp(-inf), 1.0);
        QCOMPARE(AtlasTextScale::clamp(-1), 1.0);
        QCOMPARE(AtlasTextScale::clamp(0), 1.0);
        QCOMPARE(AtlasTextScale::clamp(1e9), 4.0);
        QCOMPARE(AtlasTextScale::clamp(0.01), 0.5);
        QCOMPARE(AtlasTextScale::clamp(1.0), 1.0);
        QCOMPARE(AtlasTextScale::clamp(1.2), 1.2);
    }
};

QTEST_MAIN(TestHardening)
#include "tst_hardening.moc"
