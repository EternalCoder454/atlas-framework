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
    QModelIndex createIndexForTest(int row, int col, const QModelIndex &like) const
    {
        return createIndex(row, col, like.internalPointer());
    }
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

    void columnAndSelection()
    {
        Minter m;
        m.setItems(sample());
        const QModelIndex own = m.index(0, 0);
        const QModelIndex col1 = m.createIndexForTest(0, 1, own);
        QCOMPARE(m.rowCount(col1), 0);
        QVERIFY(m.data(col1).isNull());
        QVERIFY(!m.index(0, 0, col1).isValid());
        QVERIFY(m._selectionOf({QVariant::fromValue(col1)}).isEmpty());
        // A stale index is skipped; a live one is kept.
        const QModelIndex old = m.index(0, 0, own);
        m.setItems({QVariantMap{{"text", "Z"}}});
        QVERIFY(m._selectionOf({QVariant::fromValue(old)}).isEmpty());
        QCOMPARE(m._selectionOf({QVariant::fromValue(m.index(0, 0))}).size(), 1);
    }

    void buildLimits()
    {
        AtlasTreeModel m;
        // Depth past 64 is cut; non-map entries are skipped; NaN/Inf symbols are 0.
        QVariant deep = QVariantList{QVariantMap{{"text", "leaf"}}};
        for (int i = 0; i < 100; ++i) {
            deep = QVariantList{QVariantMap{{"text", "n"}, {"children", deep}}};
        }
        m.setItems({1, "str", QVariant(), QVariantMap{{"text", "ok"}, {"symbol", std::numeric_limits<double>::quiet_NaN()}},
                    QVariantMap{{"text", "inf"}, {"symbol", std::numeric_limits<double>::infinity()}},
                    QVariantMap{{"text", "big"}, {"symbol", 1e300}}, QVariantMap{{"text", "neg"}, {"symbol", -4}},
                    QVariantMap{{"text", "good"}, {"symbol", 61440}}, QVariantMap{{"text", "deep"}, {"children", deep}}});
        QCOMPARE(m.rowCount(), 6);
        for (int r = 0; r < 4; ++r) {
            QCOMPARE(m.data(m.index(r, 0), Qt::UserRole + 1).toInt(), 0);
        }
        QCOMPARE(m.data(m.index(4, 0), Qt::UserRole + 1).toInt(), 61440);
        int depth = 0;
        for (QModelIndex i = m.index(5, 0); i.isValid(); i = m.index(0, 0, i)) {
            ++depth;
        }
        QVERIFY(depth <= 66 && depth > 10);
    }

    void nodeCap()
    {
        AtlasTreeModel m;
        QVariantList items;
        for (int i = 0; i < 100500; ++i) {
            items << QVariantMap{{"text", "x"}};
        }
        QTest::ignoreMessage(QtWarningMsg, QRegularExpression("more than 100000 nodes"));
        m.setItems(items);
        QCOMPARE(m.rowCount(), 100000);
        m.setItems({QVariantMap{{"text", "a"}}}); // the cap resets with each setItems
        QCOMPARE(m.rowCount(), 1);
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
