// Appearance.textScale goes through the clamp: a pixel-sized font (no point
// size), a huge and a tiny font. Compiled straight from ui/appearance.cpp.
#include "appearance.h"

#include <QFont>
#include <QGuiApplication>
#include <QRegularExpression>
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

    // ATLAS_SOFTWARE_RENDERING forces the flag both ways; anything else is
    // ignored (no window here, so the flag stays false).
    void softwareRenderingOverride()
    {
        qputenv("ATLAS_SOFTWARE_RENDERING", "1");
        QCOMPARE(Appearance().softwareRendering(), true);
        qputenv("ATLAS_SOFTWARE_RENDERING", "0");
        QCOMPARE(Appearance().softwareRendering(), false);

        for (const char *bad : {"yes", "true", "2", "-1", "01", " 1", "1 ", "llvmpipe"}) {
            qputenv("ATLAS_SOFTWARE_RENDERING", bad);
            QTest::ignoreMessage(QtWarningMsg, QRegularExpression("ignoring ATLAS_SOFTWARE_RENDERING"));
            QCOMPARE(Appearance().softwareRendering(), false);
        }
        // Empty counts as unset: no message.
        qputenv("ATLAS_SOFTWARE_RENDERING", "");
        QCOMPARE(Appearance().softwareRendering(), false);
        qunsetenv("ATLAS_SOFTWARE_RENDERING");
        QCOMPARE(Appearance().softwareRendering(), false);
    }

    void softwareRasterizerNames()
    {
        QVERIFY(Appearance::isSoftwareRasterizer("llvmpipe (LLVM 19.1.7, 256 bits)"));
        QVERIFY(Appearance::isSoftwareRasterizer("softpipe"));
        QVERIFY(Appearance::isSoftwareRasterizer("SwiftShader Device (Subzero)"));
        QVERIFY(Appearance::isSoftwareRasterizer("Lavapipe"));
        QVERIFY(!Appearance::isSoftwareRasterizer("AMD Radeon RX 7900 XTX (radeonsi, navi31)"));
        QVERIFY(!Appearance::isSoftwareRasterizer(QString()));
    }
};

QTEST_MAIN(TestAppearance)
#include "tst_appearance.moc"
