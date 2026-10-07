// Appearance.textScale goes through the clamp: a pixel-sized font (no point
// size), a huge and a tiny font. Compiled straight from ui/appearance.cpp.
#include "appearance.h"

#include <QFont>
#include <QGuiApplication>
#include <QRegularExpression>
#include <QSGRendererInterface>
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

    // TELAMON_SOFTWARE_RENDERING forces the flag both ways; anything else is
    // ignored (no window here, so the flag stays false).
    void softwareRenderingOverride()
    {
        qputenv("TELAMON_SOFTWARE_RENDERING", "1");
        QCOMPARE(Appearance().softwareRendering(), true);
        qputenv("TELAMON_SOFTWARE_RENDERING", "0");
        QCOMPARE(Appearance().softwareRendering(), false);

        for (const char *bad : {"yes", "true", "2", "-1", "01", " 1", "1 ", "llvmpipe"}) {
            qputenv("TELAMON_SOFTWARE_RENDERING", bad);
            QTest::ignoreMessage(QtWarningMsg, QRegularExpression("ignoring TELAMON_SOFTWARE_RENDERING"));
            QCOMPARE(Appearance().softwareRendering(), false);
        }
        // Empty counts as unset: no message.
        qputenv("TELAMON_SOFTWARE_RENDERING", "");
        QCOMPARE(Appearance().softwareRendering(), false);
        qunsetenv("TELAMON_SOFTWARE_RENDERING");
        QCOMPARE(Appearance().softwareRendering(), false);
    }

    void softwareRasterizerNames()
    {
        QVERIFY(Appearance::isSoftwareRasterizer("llvmpipe (LLVM 19.1.7, 256 bits)"));
        QVERIFY(Appearance::isSoftwareRasterizer("softpipe"));
        QVERIFY(Appearance::isSoftwareRasterizer("SwiftShader Device (Subzero)"));
        QVERIFY(Appearance::isSoftwareRasterizer("Lavapipe"));
        QVERIFY(Appearance::isSoftwareRasterizer("Mesa Software Rasterizer"));
        QVERIFY(!Appearance::isSoftwareRasterizer("AMD Radeon RX 7900 XTX (radeonsi, navi31)"));
        QVERIFY(!Appearance::isSoftwareRasterizer(QString()));
    }

    // A probe that gives up does not latch: a later real result still counts.
    void giveUpDoesNotLatch()
    {
        qunsetenv("TELAMON_SOFTWARE_RENDERING");
        Appearance a;
        QSignalSpy spy(&a, &Appearance::softwareRenderingChanged);
        QTest::ignoreMessage(QtWarningMsg, QRegularExpression("could not tell the rendering mode"));
        a.applyRendering(nullptr, std::nullopt, 1, QString());
        QCOMPARE(a.softwareRendering(), false);
        a.applyRendering(nullptr, true, 1, QStringLiteral("llvmpipe"));
        QCOMPARE(a.softwareRendering(), true);
        QCOMPARE(spy.count(), 1);
        // A real result latches.
        a.applyRendering(nullptr, false, 1, QStringLiteral("hardware"));
        QCOMPARE(a.softwareRendering(), true);
    }

    // The probe's decision: a failed probe (empty string) is "unknown", never
    // "hardware".
    void probeDecision()
    {
        using A = QSGRendererInterface;
        const QString hardware = QStringLiteral("AMD Radeon RX 7900 XTX (radeonsi, navi31)");
        QCOMPARE(Appearance::decideRendering(A::Software, QString(), QString()), std::optional<bool>(true));
        QCOMPARE(Appearance::decideRendering(A::OpenGL, "llvmpipe (LLVM 19, 256 bits)", QString()), std::optional<bool>(true));
        QCOMPARE(Appearance::decideRendering(A::OpenGL, "Software Rasterizer", QString()), std::optional<bool>(true));
        QCOMPARE(Appearance::decideRendering(A::OpenGL, hardware, QString()), std::optional<bool>(false));
        QCOMPARE(Appearance::decideRendering(A::OpenGL, QString(), QString()), std::optional<bool>());
        QCOMPARE(Appearance::decideRendering(A::Vulkan, QString(), "llvmpipe (LLVM 19)"), std::optional<bool>(true));
        QCOMPARE(Appearance::decideRendering(A::Vulkan, QString(), hardware), std::optional<bool>(false));
        QCOMPARE(Appearance::decideRendering(A::Vulkan, hardware, QString()), std::optional<bool>());
        QCOMPARE(Appearance::decideRendering(A::Unknown, hardware, hardware), std::optional<bool>());
    }
};

QTEST_MAIN(TestAppearance)
#include "tst_appearance.moc"
