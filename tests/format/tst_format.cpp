// AtlasFormat (ui/atlasformat.cpp, compiled into the test): every function in
// en_US and de_DE, with 0, 1023, 1024, huge, negative, NaN, invalid dates and
// the plural forms.
#include "atlasformat.h"

#include <QtTest>

#include <limits>

static const double kNaN = std::numeric_limits<double>::quiet_NaN();
static const double kInf = std::numeric_limits<double>::infinity();
static const QString en = QStringLiteral("en_US");
static const QString de = QStringLiteral("de_DE");
static const QString nb = QString(QChar(0x00A0));

class TestFormat : public QObject
{
    Q_OBJECT
    AtlasFormat f;

private Q_SLOTS:
    void bytes()
    {
        QCOMPARE(f.bytes(0, 1, en), "0 B");
        QCOMPARE(f.bytes(512, 1, en), "512 B");
        QCOMPARE(f.bytes(1023, 1, en), "1,023 B");
        QCOMPARE(f.bytes(1536, 1, en), "1.5 KiB");
        QCOMPARE(f.bytes(1536, 1, de), "1,5 KiB");
        QVERIFY(f.bytes(1024, 1, en).startsWith("1"));
        QVERIFY(f.bytes(1024, 1, en).endsWith(" KiB"));
        QCOMPARE(f.bytes(3.2 * 1024 * 1024 * 1024, 1, en), "3.2 GiB");
        QCOMPARE(f.bytes(-1536, 1, en), "-1.5 KiB");
        QCOMPARE(f.bytes(-0.2, 1, en), "0 B");
        QCOMPARE(f.bytes(1e300, 1, en).right(4), " EiB");
        QVERIFY(!f.bytes(1e300, 1, en).isEmpty());
        QCOMPARE(f.bytes(kNaN), "");
        QCOMPARE(f.bytes(kInf), "");
        // 1023.5 up rounds to 1024: that is KiB, never "1,024 B".
        QVERIFY(f.bytes(1023.5, 1, en).endsWith(" KiB"));
        QVERIFY(f.bytes(1023.99, 1, en).startsWith("1"));
        QCOMPARE(f.bytes(1023.4, 1, en), "1,023 B");
        QCOMPARE(f.bytes(1536, -5, en), "2 KiB"); // precision clamps to 0
        QCOMPARE(f.bytes(1536, 999, en).startsWith("1.5"), true);
    }

    void bytesPerSecond()
    {
        QCOMPARE(f.bytesPerSecond(1.5 * 1024 * 1024, 1, en), "1.5 MiB/s");
        QCOMPARE(f.bytesPerSecond(0, 1, en), "0 B/s");
        QCOMPARE(f.bytesPerSecond(kNaN), "");
    }

    void percent()
    {
        QCOMPARE(f.percent(0.423, 0, en), "42%");
        QCOMPARE(f.percent(0.423, 0, de), "42" + nb + "%");
        QCOMPARE(f.percent(0.4235, 1, en), "42.4%"); // round half up on 42.35
        QCOMPARE(f.percent(0, 0, en), "0%");
        QCOMPARE(f.percent(1, 0, en), "100%");
        QCOMPARE(f.percent(1.5, 0, en), "150%");
        QCOMPARE(f.percent(-0.25, 0, en), "-25%");
        QCOMPARE(f.percent(-0.0000001, 0, en), "0%");
        QCOMPARE(f.percent(kNaN), "");
        QCOMPARE(f.percent(kInf), "");
        QCOMPARE(f.percent(1e307 * 10), "");
    }

    void number()
    {
        QCOMPARE(f.number(1234567.891, 2, en), "1,234,567.89");
        QCOMPARE(f.number(1234567.891, 2, de), "1.234.567,89");
        QCOMPARE(f.number(1234.5, -1, en), "1,234.5");
        QCOMPARE(f.number(1234.5, -1, de), "1.234,5");
        QCOMPARE(f.number(3, -1, en), "3");
        QCOMPARE(f.number(0, -1, en), "0");
        QCOMPARE(f.number(0.1234567891, -1, en), "0.123457");
        QCOMPARE(f.number(-0.0000001, -1, en), "0");
        QCOMPARE(f.number(-12.5, 0, en), "-13");
        QCOMPARE(f.number(100, 0, en), "100");
        QCOMPARE(f.number(kNaN), "");
        QCOMPARE(f.number(-kInf), "");
        QVERIFY(f.number(1e300, -1, en).size() > 300);
        // The shortest form trims the locale's own zero digit.
        const QString ar = QStringLiteral("ar_EG");
        const QLocale arLocale(ar);
        QCOMPARE(f.number(2, -1, ar), arLocale.toString(2.0, 'f', 0));
        QVERIFY(!f.number(1.5, -1, ar).endsWith(arLocale.zeroDigit()));
        QCOMPARE(f.number(10, -1, ar), arLocale.toString(10.0, 'f', 0));
    }

    void durationHugeIsClampedNotMisspelled()
    {
        QCOMPARE(f.duration(1e18, "long", en), "1000000000 days");
        QCOMPARE(f.duration(86400.0 * 1e9, "long", en), "1000000000 days");
        QCOMPARE(f.duration(86400.0 * 123456789, "long", en), "123456789 days");
    }

    void durationShort()
    {
        QCOMPARE(f.duration(0, "short", en), "0 s");
        QCOMPARE(f.duration(45, "short", en), "45 s");
        QCOMPARE(f.duration(60, "short", en), "1 min");
        QCOMPARE(f.duration(3900, "short", en), "1 h 5 min");
        QCOMPARE(f.duration(3600, "short", en), "1 h");
        QCOMPARE(f.duration(2 * 86400 + 3 * 3600 + 59, "short", en), "2 d 3 h");
        QCOMPARE(f.duration(2 * 86400, "short", en), "2 d");
        QCOMPARE(f.duration(59.6, "short", en), "1 min");
        QCOMPARE(f.duration(-3900, "short", en), "-1 h 5 min");
        QCOMPARE(f.duration(-0.2, "short", en), "0 s");
        QCOMPARE(f.duration(3900, "short", de), "1 h 5 min");
        QCOMPARE(f.duration(kNaN), "");
        QCOMPARE(f.duration(kInf), "");
        QVERIFY(f.duration(1e30, "short", en).contains(" d"));
        QCOMPARE(f.duration(3900, "bogus", en), "1 h 5 min");
    }

    void durationLong()
    {
        QCOMPARE(f.duration(0, "long", en), "0 seconds");
        QCOMPARE(f.duration(1, "long", en), "1 second");
        QCOMPARE(f.duration(2, "long", en), "2 seconds");
        QCOMPARE(f.duration(3900, "long", en), "1 hour 5 minutes");
        QCOMPARE(f.duration(7260, "long", en), "2 hours 1 minute");
        QCOMPARE(f.duration(86400, "long", en), "1 day");
        QCOMPARE(f.duration(3 * 86400 + 3600, "long", en), "3 days 1 hour");
        QCOMPARE(f.duration(-60, "long", en), "-1 minute");
    }

    void durationClock()
    {
        QCOMPARE(f.duration(3909, "clock", en), "1:05:09");
        QCOMPARE(f.duration(309, "clock", en), "05:09");
        QCOMPARE(f.duration(0, "clock", en), "00:00");
        QCOMPARE(f.duration(90000, "clock", en), "25:00:00");
        QCOMPARE(f.duration(-309, "clock", en), "-05:09");
        QCOMPARE(f.duration(kNaN, "clock"), "");
    }

    void dates()
    {
        const QDateTime d(QDate(2026, 3, 9), QTime(14, 5), QTimeZone::LocalTime);
        QCOMPARE(f.date(d, "short", en), "3/9/26");
        QCOMPARE(f.date(d, "short", de), "09.03.26");
        QCOMPARE(f.date(d, "long", en), "Monday, March 9, 2026");
        QCOMPARE(f.date(d, "long", de), "Montag, 9. März 2026");
        QVERIFY(f.date(d, "time", en).startsWith("2:05"));
        QVERIFY(f.date(d, "time", de).startsWith("14:05"));
        QVERIFY(f.date(d, "dateTime", en).startsWith("3/9/26"));
        QVERIFY(f.date(d, "dateTime", en).contains("2:05"));
        QCOMPARE(f.date(d, "bogus", en), "3/9/26");
        QCOMPARE(f.date(QDateTime(), "short", en), "");
        QCOMPARE(f.date(QDateTime(), "relative", en), "");
        QCOMPARE(f.date(QDateTime(), "atTime", en), "");
    }

    void atTime()
    {
        const QDateTime now(QDate(2026, 3, 9), QTime(15, 0), QTimeZone::LocalTime);
        const auto at = [&](QDate day, QString loc) {
            return f.date(QDateTime(day, QTime(14, 5), QTimeZone::LocalTime), "atTime", loc, now);
        };
        QVERIFY(at(QDate(2026, 3, 9), en).startsWith("today at 2:05"));
        QVERIFY(at(QDate(2026, 3, 8), en).startsWith("yesterday at 2:05"));
        QVERIFY(at(QDate(2026, 3, 1), en).startsWith("3/1/26 at 2:05"));
        QVERIFY(at(QDate(2026, 3, 1), de).startsWith("01.03.26 at 14:05"));
        QVERIFY(at(QDate(2026, 3, 10), en).startsWith("3/10/26 at")); // future: a date
    }

    void relative_data()
    {
        QTest::addColumn<qint64>("secondsAgo");
        QTest::addColumn<QString>("text");
        QTest::newRow("now") << qint64(0) << "just now";
        QTest::newRow("59 s") << qint64(59) << "just now";
        QTest::newRow("future 30 s") << qint64(-30) << "just now";
        QTest::newRow("1 min") << qint64(60) << "1 minute ago";
        QTest::newRow("5 min") << qint64(300) << "5 minutes ago";
        QTest::newRow("59 min") << qint64(3599) << "59 minutes ago";
        QTest::newRow("1 h") << qint64(3600) << "1 hour ago";
        QTest::newRow("3 h") << qint64(3 * 3600) << "3 hours ago";
        QTest::newRow("in 5 min") << qint64(-300) << "in 5 minutes";
        QTest::newRow("in 1 min") << qint64(-60) << "in 1 minute";
        QTest::newRow("in 2 h") << qint64(-2 * 3600) << "in 2 hours";
        QTest::newRow("yesterday") << qint64(24 * 3600) << "yesterday";
        QTest::newRow("tomorrow") << qint64(-24 * 3600) << "tomorrow";
        QTest::newRow("4 days") << qint64(4 * 86400) << "4 days ago";
        QTest::newRow("in 3 days") << qint64(-3 * 86400) << "in 3 days";
        QTest::newRow("a month") << qint64(30 * 86400) << "2/6/26";
        QTest::newRow("far future") << qint64(-30 * 86400) << "4/7/26";
    }
    void relative()
    {
        QFETCH(qint64, secondsAgo);
        QFETCH(QString, text);
        // Noon, so a whole number of days back never crosses into the wrong date.
        const QDateTime now(QDate(2026, 3, 8), QTime(12, 0), QTimeZone::LocalTime);
        QCOMPARE(f.date(now.addSecs(-secondsAgo), "relative", en, now), text);
    }
    void relativeCrossesMidnight()
    {
        const QDateTime now(QDate(2026, 3, 9), QTime(2, 0), QTimeZone::LocalTime);
        QCOMPARE(f.date(QDateTime(QDate(2026, 3, 8), QTime(22, 0), QTimeZone::LocalTime), "relative", en, now),
                 "4 hours ago");
        QCOMPARE(f.date(QDateTime(QDate(2026, 3, 8), QTime(2, 0), QTimeZone::LocalTime).addSecs(60), "relative", en, now),
                 "yesterday");
    }
};

QTEST_MAIN(TestFormat)
#include "tst_format.moc"
