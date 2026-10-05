// Appearance.textScale goes through the clamp: a pixel-sized font (no point
// size), a huge and a tiny font. Compiled straight from ui/appearance.cpp.
#include "appearance.h"

#include <QFont>
#include <QGuiApplication>
#include <QtTest>

class TestAppearance : public QObject
{
    Q_OBJECT
private Q_SLOTS:
    void initTestCase() { QStandardPaths::setTestModeEnabled(true); }

    void textScaleIsBounded()
    {
        const QFont original = QGuiApplication::font();
        QFont f = original;

        f.setPointSizeF(10);
        QGuiApplication::setFont(f);
        QCOMPARE(Appearance().textScale(), 1.0);

        f.setPointSizeF(1000);
        QGuiApplication::setFont(f);
        QCOMPARE(Appearance().textScale(), 4.0);

        f.setPointSizeF(1);
        QGuiApplication::setFont(f);
        QCOMPARE(Appearance().textScale(), 0.5);

        f.setPixelSize(14); // no point size: the default
        QGuiApplication::setFont(f);
        QCOMPARE(Appearance().textScale(), 1.0);

        QGuiApplication::setFont(original);
    }
};

QTEST_MAIN(TestAppearance)
#include "tst_appearance.moc"
