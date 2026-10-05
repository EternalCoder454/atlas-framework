// The Atlas validators (ui/atlasvalidators.cpp, compiled into the test):
// acceptable, intermediate and invalid input of each, hostile input included.
#include "atlasvalidators.h"

#include <QDir>
#include <QLocale>
#include <QTemporaryDir>
#include <QtTest>

using S = QValidator::State;
Q_DECLARE_METATYPE(QValidator::State)

static S check(const QValidator &v, QString text)
{
    int pos = text.size();
    return v.validate(text, pos);
}

class TestValidators : public QObject
{
    Q_OBJECT
private Q_SLOTS:
    void initTestCase() { QLocale::setDefault(QLocale(QLocale::English, QLocale::UnitedStates)); }

    void url_data()
    {
        QTest::addColumn<QString>("text");
        QTest::addColumn<S>("state");
        QTest::newRow("empty") << "" << QValidator::Intermediate;
        QTest::newRow("https") << "https://example.com/a?b=c" << QValidator::Acceptable;
        QTest::newRow("upper scheme") << "HTTPS://Example.com" << QValidator::Acceptable;
        QTest::newRow("http, not by default") << "http://localhost:8080" << QValidator::Invalid;
        QTest::newRow("scheme start") << "ht" << QValidator::Intermediate;
        QTest::newRow("scheme colon") << "https:" << QValidator::Intermediate;
        QTest::newRow("no host") << "https://" << QValidator::Intermediate;
        QTest::newRow("padded") << "  https://example.com " << QValidator::Intermediate;
        QTest::newRow("bad scheme") << "ftp://example.com" << QValidator::Invalid;
        QTest::newRow("bare host") << "example.com" << QValidator::Intermediate;
        QTest::newRow("bare host and port") << "example.com:8080/a" << QValidator::Intermediate;
        QTest::newRow("not a url") << "exa<mple" << QValidator::Invalid;
        QTest::newRow("inner space") << "https://exa mple.com" << QValidator::Invalid;
        QTest::newRow("NUL") << QString::fromLatin1("https://a\0b.com", 15) << QValidator::Invalid;
        QTest::newRow("newline") << "https://a.com\n" << QValidator::Intermediate;
        QTest::newRow("too long") << "https://" + QString(5000, 'a') << QValidator::Invalid;
        QTest::newRow("unicode host") << QString::fromUtf8("https://exämple.com") << QValidator::Acceptable;
        QTest::newRow("percent") << "https://a.com/%" << QValidator::Intermediate;
    }
    void url()
    {
        QFETCH(QString, text);
        QFETCH(S, state);
        AtlasUrlValidator v;
        QCOMPARE(check(v, text), state);
    }
    void urlBareHostFixup()
    {
        AtlasUrlValidator v;
        QString s = QStringLiteral("example.com");
        v.fixup(s);
        QCOMPARE(s, QStringLiteral("https://example.com"));
        QCOMPARE(check(v, s), QValidator::Acceptable);
        s = QStringLiteral("ftp://example.com");
        v.fixup(s);
        QCOMPARE(s, QStringLiteral("ftp://example.com"));
    }
    void urlFixupLeavesWhatIsNotABareHost()
    {
        AtlasUrlValidator v;
        v.setSchemes({QStringLiteral("https")});
        QString s = QStringLiteral("http://x");
        v.fixup(s);
        QCOMPARE(s, QStringLiteral("http://x"));
        s = QStringLiteral("user:pw@host");
        v.fixup(s);
        QCOMPARE(s, QStringLiteral("user:pw@host"));
        s = QStringLiteral("example.com:8080");
        v.fixup(s);
        QCOMPARE(s, QStringLiteral("https://example.com:8080"));
        s = QString();
        v.fixup(s);
        QCOMPARE(s, QString());
    }
    void urlSchemes()
    {
        AtlasUrlValidator v;
        v.setSchemes({QStringLiteral("HTTPS")});
        QCOMPARE(check(v, "https://a.com"), QValidator::Acceptable);
        QCOMPARE(check(v, "http://a.com"), QValidator::Invalid);
        v.setSchemes({QStringLiteral("https"), QStringLiteral("http")});
        QCOMPARE(check(v, "http://localhost:8080"), QValidator::Acceptable);
        v.setSchemes({QStringLiteral("mailto")});
        QCOMPARE(check(v, "mailto:a@b.com"), QValidator::Acceptable);
        QString s = QStringLiteral("  https://a.com  ");
        v.setSchemes({QStringLiteral("https")});
        v.fixup(s);
        QCOMPARE(s, QStringLiteral("https://a.com"));
        QCOMPARE(check(v, s), QValidator::Acceptable);
    }

    void email_data()
    {
        QTest::addColumn<QString>("text");
        QTest::addColumn<S>("state");
        QTest::newRow("empty") << "" << QValidator::Intermediate;
        QTest::newRow("ok") << "zach@example.com" << QValidator::Acceptable;
        QTest::newRow("plus") << "a+b@mail.example.org" << QValidator::Acceptable;
        QTest::newRow("no at") << "zach" << QValidator::Intermediate;
        QTest::newRow("no domain") << "zach@" << QValidator::Intermediate;
        QTest::newRow("no dot") << "zach@example" << QValidator::Intermediate;
        QTest::newRow("trailing dot") << "zach@example." << QValidator::Intermediate;
        QTest::newRow("no local") << "@example.com" << QValidator::Intermediate;
        QTest::newRow("two at") << "a@b@c.com" << QValidator::Invalid;
        QTest::newRow("space") << "a b@c.com" << QValidator::Invalid;
        QTest::newRow("NUL") << QString::fromLatin1("a\0@c.com", 8) << QValidator::Invalid;
        QTest::newRow("bad domain char") << "a@exa!mple.com" << QValidator::Invalid;
        QTest::newRow("too long") << QString(300, 'a') + "@example.com" << QValidator::Invalid;
        QTest::newRow("long local") << QString(65, 'a') + "@example.com" << QValidator::Invalid;
        QTest::newRow("unicode") << QString::fromUtf8("jörg@bücher.de") << QValidator::Acceptable;
        QTest::newRow("mailto param") << "a?bcc=x@evil.com" << QValidator::Invalid;
        QTest::newRow("comma") << "x,y@evil.com" << QValidator::Invalid;
        QTest::newRow("angle") << "a<b>@x.com" << QValidator::Invalid;
        QTest::newRow("quote") << "a\"b@x.com" << QValidator::Invalid;
        QTest::newRow("format char") << QString::fromUtf8("a\u202Eb@x.com") << QValidator::Invalid;
        QTest::newRow("dotted local") << "a.b@x.com" << QValidator::Acceptable;
        QTest::newRow("leading dot") << ".a@x.com" << QValidator::Intermediate;
        QTest::newRow("double dot") << "a..b@x.com" << QValidator::Intermediate;
    }
    void email()
    {
        QFETCH(QString, text);
        QFETCH(S, state);
        AtlasEmailValidator v;
        QCOMPARE(check(v, text), state);
    }

    void path()
    {
        AtlasPathValidator v;
        QCOMPARE(check(v, ""), QValidator::Intermediate);
        QCOMPARE(check(v, "/usr/lib"), QValidator::Acceptable);
        QCOMPARE(check(v, "~"), QValidator::Acceptable);
        QCOMPARE(check(v, "~/Documents"), QValidator::Acceptable);
        QCOMPARE(check(v, "~root/x"), QValidator::Invalid);
        QCOMPARE(check(v, "relative/x"), QValidator::Invalid);
        QCOMPARE(check(v, QString::fromLatin1("/a\0b", 4)), QValidator::Invalid);
        QCOMPARE(check(v, "/a\nb"), QValidator::Invalid);
        QCOMPARE(check(v, "/" + QString(5000, 'a')), QValidator::Invalid);
        QCOMPARE(check(v, QString::fromUtf8("/tmp/ünï/日本")), QValidator::Acceptable);
        v.setAbsolute(false);
        QCOMPARE(check(v, "relative/x"), QValidator::Acceptable);
    }
    void pathMustExist()
    {
        QTemporaryDir dir;
        QVERIFY(dir.isValid());
        QFile f(dir.filePath("file.txt"));
        QVERIFY(f.open(QIODevice::WriteOnly));
        f.close();
        AtlasPathValidator v;
        v.setMustExist(true);
        QCOMPARE(check(v, dir.path()), QValidator::Acceptable);
        QCOMPARE(check(v, dir.filePath("file.txt")), QValidator::Acceptable);
        QCOMPARE(check(v, dir.filePath("missing")), QValidator::Intermediate);
        QCOMPARE(check(v, dir.filePath("file.txt") + "/x"), QValidator::Intermediate);
        v.setDirectory(true);
        QCOMPARE(check(v, dir.path()), QValidator::Acceptable);
        QCOMPARE(check(v, dir.filePath("file.txt")), QValidator::Intermediate);
        // No shell: a command substitution is just a name that does not exist.
        QCOMPARE(check(v, "/tmp/$(id)"), QValidator::Intermediate);
        QCOMPARE(check(v, "~"), QValidator::Acceptable);
    }

    void number()
    {
        AtlasNumberValidator v;
        QCOMPARE(check(v, ""), QValidator::Intermediate);
        QCOMPARE(check(v, "42"), QValidator::Acceptable);
        QCOMPARE(check(v, "-"), QValidator::Intermediate);
        QCOMPARE(check(v, "-7"), QValidator::Acceptable);
        QCOMPARE(check(v, "1,234"), QValidator::Acceptable);
        QCOMPARE(check(v, "1.5"), QValidator::Acceptable); // decimals are allowed by default
        QCOMPARE(check(v, "abc"), QValidator::Invalid);
        QCOMPARE(check(v, "1e5"), QValidator::Invalid);
        v.setDecimals(0);
        QCOMPARE(check(v, "1.5"), QValidator::Invalid);
        v.setDecimals(15);
        QCOMPARE(check(v, QString::fromLatin1("1\0" "2", 3)), QValidator::Invalid);
        QCOMPARE(check(v, QString(500, '1')), QValidator::Invalid);
        QCOMPARE(check(v, QString::fromUtf8("٣")), QValidator::Invalid);

        v.setDecimals(2);
        v.setBottom(0);
        v.setTop(100);
        QCOMPARE(check(v, "1."), QValidator::Intermediate);
        QCOMPARE(check(v, "1.25"), QValidator::Acceptable);
        QCOMPARE(check(v, "1.256"), QValidator::Invalid);
        QCOMPARE(check(v, "100"), QValidator::Acceptable);
        QCOMPARE(check(v, "-"), QValidator::Invalid); // bottom is not negative
        QVERIFY(check(v, "101") != QValidator::Acceptable);
        QVERIFY(check(v, "1000") != QValidator::Acceptable);
    }
    void numberLocale()
    {
        AtlasNumberValidator v;
        v.setLocale(QLocale(QLocale::German, QLocale::Germany));
        v.setDecimals(2);
        QCOMPARE(check(v, "1,5"), QValidator::Acceptable);
        QCOMPARE(check(v, "1."), QValidator::Intermediate);
        QCOMPARE(check(v, "1,"), QValidator::Intermediate);
        QCOMPARE(check(v, "1.234,5"), QValidator::Acceptable);
    }
    void numberFixup()
    {
        AtlasNumberValidator v;
        v.setLocale(QLocale(QLocale::English, QLocale::UnitedStates));
        v.setBottom(0);
        v.setTop(100);
        const auto fix = [&](const QString &text) {
            QString t = text;
            v.fixup(t);
            return t;
        };
        QCOMPARE(fix("1."), QString("1"));
        QCOMPARE(fix("250"), QString("100"));
        QCOMPARE(fix("-5"), QString("0"));
        QCOMPARE(fix("100.5"), QString("100"));
        QCOMPARE(fix("12.5"), QString("12.5"));
        QCOMPARE(fix("abc"), QString("abc"));
    }
    void numberSignals()
    {
        AtlasNumberValidator v;
        QSignalSpy changed(&v, &QValidator::changed);
        v.setLocaleName("de_DE");
        QCOMPARE(changed.size(), 1);
        QCOMPARE(v.localeName(), QString("de_DE"));
        changed.clear();
        v.setTop(5);
        v.setTop(5);
        v.setDecimals(3);
        v.setDecimals(99);
        QCOMPARE(v.decimals(), 15);
        QCOMPARE(changed.size(), 3);
    }
};

QTEST_MAIN(TestValidators)
#include "tst_validators.moc"
