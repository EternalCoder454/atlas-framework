// TelamonSparklineItem (ui/telamonsparkline.cpp, compiled into the test): the
// automatic scale, its limits, and that equal values cause no repaint.
#include "telamonsparkline.h"

#include <QSignalSpy>
#include <QtTest>

#include <cmath>
#include <limits>

static const double NaN = std::numeric_limits<double>::quiet_NaN();

class TestSparkline : public QObject
{
    Q_OBJECT
private Q_SLOTS:
    void autoScale()
    {
        TelamonSparklineItem s;
        s.setValues({3, 7, 5, NaN});
        QCOMPARE(s.scaleMinimum(), 3.0);
        QCOMPARE(s.scaleMaximum(), 7.0);
    }
    void minimumRangeWidensAroundTheMiddle()
    {
        TelamonSparklineItem s;
        s.setMinimumRange(10);
        s.setValues({4, 6});
        QCOMPARE(s.scaleMinimum(), 0.0);
        QCOMPARE(s.scaleMaximum(), 10.0);
        // A series wider than the minimum is left alone.
        s.setValues({0, 20});
        QCOMPARE(s.scaleMinimum(), 0.0);
        QCOMPARE(s.scaleMaximum(), 20.0);
    }
    void explicitLimits()
    {
        TelamonSparklineItem s;
        s.setValues({4, 6});
        s.setMinimum(0);
        s.setMaximum(100);
        QCOMPARE(s.scaleMinimum(), 0.0);
        QCOMPARE(s.scaleMaximum(), 100.0);
        s.setMaximum(NaN);
        s.setMinimumRange(50);
        QCOMPARE(s.scaleMinimum(), 0.0);
        QCOMPARE(s.scaleMaximum(), 50.0);
    }
    void degenerate()
    {
        TelamonSparklineItem s;
        // Nothing, only gaps, and a flat line: always a span to divide by.
        for (const QList<qreal> &v : {QList<qreal>{}, QList<qreal>{NaN, NaN}, QList<qreal>{5, 5, 5}}) {
            s.setValues(v);
            QVERIFY(s.scaleMaximum() > s.scaleMinimum());
        }
        s.setMinimum(10);
        s.setMaximum(2); // the wrong way round
        QVERIFY(s.scaleMaximum() > s.scaleMinimum());
        s.setMinimumRange(-3); // hostile: taken as 0
        QCOMPARE(s.minimumRange(), 0.0);
        s.setMinimumRange(NaN);
        QCOMPARE(s.minimumRange(), 0.0);
    }
    void equalValuesDoNotRepaint()
    {
        TelamonSparklineItem s;
        QSignalSpy changed(&s, &TelamonSparklineItem::valuesChanged);
        s.setValues({1, NaN, 3});
        QCOMPARE(changed.count(), 1);
        const int updates = s.updateCount();
        s.setValues({1, NaN, 3}); // a NaN equals a NaN
        QCOMPARE(changed.count(), 1);
        QCOMPARE(s.updateCount(), updates);
        s.setValues({1, 2, 3});
        QCOMPARE(changed.count(), 2);
        QVERIFY(s.updateCount() > updates);
        s.setValues({1, 2});
        QCOMPARE(changed.count(), 3);
    }
};

QTEST_MAIN(TestSparkline)
#include "tst_sparkline.moc"
