// The colour helpers behind AtlasStyle.alpha() and AtlasStyle.mix()
// (ui/atlascolorsprivate.cpp, compiled into the test): opaque and translucent
// colours, clamping, NaN, mixing with alpha, invalid colours.
#include "atlascolorsprivate.h"

#include <QtTest>

#include <limits>

static const double kNaN = std::numeric_limits<double>::quiet_NaN();

static bool near(const QColor &c, double r, double g, double b, double a)
{
    const double eps = 0.002;
    return qAbs(c.redF() - r) < eps && qAbs(c.greenF() - g) < eps && qAbs(c.blueF() - b) < eps && qAbs(c.alphaF() - a) < eps;
}

class TestColors : public QObject
{
    Q_OBJECT
private Q_SLOTS:
    void alphaOpaque()
    {
        AtlasColorsPrivate h;
        const QColor c = h.alpha(QColor(255, 0, 0), 0.5);
        QVERIFY(near(c, 1, 0, 0, 0.5));
    }
    void alphaTranslucent()
    {
        AtlasColorsPrivate h;
        // Replaces the alpha, as Qt.alpha does; it does not multiply.
        const QColor c = h.alpha(QColor(0, 0, 255, 51), 0.8);
        QVERIFY(near(c, 0, 0, 1, 0.8));
    }
    void alphaClamps()
    {
        AtlasColorsPrivate h;
        QVERIFY(near(h.alpha(QColor(10, 20, 30), 2.5), 10 / 255.0, 20 / 255.0, 30 / 255.0, 1));
        QVERIFY(near(h.alpha(QColor(10, 20, 30), -1), 10 / 255.0, 20 / 255.0, 30 / 255.0, 0));
        QVERIFY(near(h.alpha(QColor(10, 20, 30), std::numeric_limits<double>::infinity()), 10 / 255.0, 20 / 255.0, 30 / 255.0, 1));
        QVERIFY(near(h.alpha(QColor(10, 20, 30), -std::numeric_limits<double>::infinity()), 10 / 255.0, 20 / 255.0, 30 / 255.0, 0));
    }
    void alphaNaN()
    {
        AtlasColorsPrivate h;
        QVERIFY(near(h.alpha(QColor(255, 255, 255), kNaN), 1, 1, 1, 0));
    }
    void alphaInvalid()
    {
        AtlasColorsPrivate h;
        QVERIFY(!h.alpha(QColor(), 0.5).isValid());
    }
    void mixEnds()
    {
        AtlasColorsPrivate h;
        const QColor a(255, 0, 0);
        const QColor b(0, 0, 255);
        QVERIFY(near(h.mix(a, b, 0), 1, 0, 0, 1));
        QVERIFY(near(h.mix(a, b, 1), 0, 0, 1, 1));
    }
    void mixHalf()
    {
        AtlasColorsPrivate h;
        QVERIFY(near(h.mix(QColor(0, 0, 0), QColor(255, 255, 255), 0.5), 0.5, 0.5, 0.5, 1));
    }
    void mixAlpha()
    {
        AtlasColorsPrivate h;
        // Alpha blends like a channel: 0 and 1 give 0.5.
        QVERIFY(near(h.mix(QColor(0, 0, 0, 0), QColor(255, 255, 255, 255), 0.5), 0.5, 0.5, 0.5, 0.5));
        // An opaque base mixed with white at t is Qt.tint(base, rgba(1, 1, 1, t)).
        QVERIFY(near(h.mix(QColor(0, 0, 0), QColor(255, 255, 255), 0.25), 0.25, 0.25, 0.25, 1));
    }
    void mixClampsAndNaN()
    {
        AtlasColorsPrivate h;
        const QColor a(255, 0, 0);
        const QColor b(0, 0, 255);
        QVERIFY(near(h.mix(a, b, 7), 0, 0, 1, 1));
        QVERIFY(near(h.mix(a, b, -7), 1, 0, 0, 1));
        QVERIFY(near(h.mix(a, b, kNaN), 1, 0, 0, 1));
    }
    void mixOtherSpec()
    {
        AtlasColorsPrivate h;
        // An HSL colour is converted to RGB first.
        QVERIFY(near(h.mix(QColor::fromHslF(0, 1, 0.5), QColor(255, 0, 0), 0.5), 1, 0, 0, 1));
    }
    void mixInvalid()
    {
        AtlasColorsPrivate h;
        QVERIFY(!h.mix(QColor(), QColor(0, 0, 0), 0.5).isValid());
        QVERIFY(!h.mix(QColor(0, 0, 0), QColor(), 0.5).isValid());
        QVERIFY(!h.mix(QColor(), QColor(), 0.5).isValid());
    }
};

QTEST_MAIN(TestColors)
#include "tst_colors.moc"
