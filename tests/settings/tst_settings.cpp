// AtlasSettings (ui/atlassettings.cpp) and AtlasPortal's URL and notification
// rules (ui/atlasportal.cpp), compiled into the test. Every test runs in a
// temporary XDG_CONFIG_HOME: the real config directory is never touched.
// Nothing here opens a URL or talks to a notification server.
#include "atlasportal.h"
#include "atlassettings.h"

#include <KConfig>
#include <KConfigGroup>

#include <QFile>
#include <QGuiApplication>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QSignalSpy>
#include <QUrlQuery>
#include <QTemporaryDir>
#include <QtTest>

#include <thread>

#include <fcntl.h>
#include <sys/stat.h>
#include <sys/file.h>
#include <unistd.h>

namespace
{
// The code under test logs a warning for every refusal; they are expected.
// Anything that is not a warning still goes to the normal handler.
QtMessageHandler g_previous = nullptr;
int g_warnings = 0;
void quiet(QtMsgType type, const QMessageLogContext &ctx, const QString &msg)
{
    if (type == QtWarningMsg) {
        ++g_warnings;
        return;
    }
    g_previous(type, ctx, msg);
}

QString readAll(const QString &path)
{
    QFile f(path);
    return f.open(QIODevice::ReadOnly) ? QString::fromUtf8(f.readAll()) : QString();
}
void writeAll(const QString &path, const QString &text)
{
    QFile f(path);
    QVERIFY2(f.open(QIODevice::WriteOnly | QIODevice::Truncate), qPrintable(path));
    f.write(text.toUtf8());
}
}

class TestSettings : public QObject
{
    Q_OBJECT
    QTemporaryDir m_dir;
    QTemporaryDir m_files; // files for the URL tests: init() empties m_dir
    QString rc() const { return m_dir.filePath(QStringLiteral("atlas-testerrc")); }

    std::unique_ptr<AtlasSettings> make(const QString &group, const QString &fileName = QString())
    {
        auto s = std::make_unique<AtlasSettings>();
        s->setGroup(group);
        s->setFileName(fileName);
        s->componentComplete();
        return s;
    }

private Q_SLOTS:
    void initTestCase()
    {
        g_previous = qInstallMessageHandler(quiet);
        QVERIFY(m_dir.isValid() && m_files.isValid());
        qputenv("XDG_CONFIG_HOME", m_dir.path().toUtf8());
        QGuiApplication::setDesktopFileName(QStringLiteral("net.eterneon.atlas.tester"));
    }
    void cleanupTestCase() { qInstallMessageHandler(g_previous); }
    void init()
    {
        QDir d(m_dir.path());
        const auto entries = d.entryList(QDir::AllEntries | QDir::Hidden | QDir::System | QDir::NoDotAndDotDot);
        for (const QString &e : entries) {
            QFileInfo i(d.filePath(e));
            if (i.isDir() && !i.isSymLink()) {
                QDir(i.filePath()).removeRecursively();
            } else {
                QFile::remove(i.filePath());
            }
        }
    }

    void shortName_data()
    {
        QTest::addColumn<QString>("id");
        QTest::addColumn<QString>("name");
        QTest::newRow("updater") << "net.eterneon.atlas.updater" << "atlas-updater";
        QTest::newRow("upper") << "net.eterneon.atlas.Monitor" << "atlas-monitor";
        QTest::newRow("slash") << "net.eterneon.atlas.a/b c" << "atlas-a_b_c";
        QTest::newRow("empty") << "" << "atlas-app";
        QTest::newRow("prefix") << "x.atlas-notes" << "atlas-notes";
        QTest::newRow("prefix upper") << "x.Atlas-Notes" << "atlas-notes";
        QTest::newRow("dotdot") << "x.." << "atlas-app";
        QTest::newRow("astral") << QString::fromUtf8("x.\xF0\x9F\x98\x80") << "atlas-_";
        QTest::newRow("long") << ("x." + QString(100, QLatin1Char('a'))) << ("atlas-" + QString(58, QLatin1Char('a')));
    }
    void shortName()
    {
        QFETCH(QString, id);
        QFETCH(QString, name);
        QCOMPARE(AtlasSettings::shortName(id), name);
    }

    void names_data()
    {
        QTest::addColumn<QString>("text");
        QTest::addColumn<bool>("group");
        QTest::addColumn<bool>("key");
        QTest::addColumn<bool>("file");
        QTest::newRow("plain") << "View" << true << true << true;
        QTest::newRow("dash") << "Window-main" << true << true << true;
        QTest::newRow("empty") << "" << false << false << false;
        QTest::newRow("open bracket") << "A[b" << false << false << true;
        QTest::newRow("close bracket") << "A]b" << false << false << true;
        QTest::newRow("newline") << "A\nB" << false << false << false;
        QTest::newRow("NUL") << QString::fromLatin1("A\0B", 3) << false << false << false;
        QTest::newRow("escape") << "A\x1b" << false << false << false;
        QTest::newRow("equals") << "A=B" << true << false << true;
        QTest::newRow("comment") << "#A" << false << false << true;
        QTest::newRow("edge space") << " A" << false << false << false;
        QTest::newRow("slash") << "a/b" << true << true << false;
        QTest::newRow("dotdot") << ".." << true << true << false;
        QTest::newRow("hidden") << ".lock" << true << true << false;
        QTest::newRow("backslash") << "a\\b" << true << true << false;
    }
    void names()
    {
        QFETCH(QString, text);
        QFETCH(bool, group);
        QFETCH(bool, key);
        QFETCH(bool, file);
        QCOMPARE(AtlasSettings::validGroup(text), group);
        QCOMPARE(AtlasSettings::validKey(text), key);
        QCOMPARE(AtlasSettings::validFileName(text), file);
    }

    void roundTrip()
    {
        {
            auto s = make(QStringLiteral("View"));
            QVERIFY(s->setValue(QStringLiteral("Hidden"), true));
            QVERIFY(s->setValue(QStringLiteral("Count"), 42));
            QVERIFY(s->setValue(QStringLiteral("Big"), qlonglong(5000000000)));
            QVERIFY(s->setValue(QStringLiteral("Scale"), 1.25));
            QVERIFY(s->setValue(QStringLiteral("Name"), QStringLiteral("  a=b [c]\nd\\e  ")));
            QVERIFY(s->setValue(QStringLiteral("List"), QStringList{QStringLiteral("a,b"), QStringLiteral("c"), QString()}));
            QVERIFY(s->setValue(QStringLiteral("Sizes"), QVariantList{300, 700}));
            // Read back before it is written.
            QCOMPARE(s->value(QStringLiteral("Count"), 0), QVariant(42));
            QVERIFY(s->contains(QStringLiteral("Count")));
            QVERIFY(s->flush());
        }
        auto s = make(QStringLiteral("View"));
        QCOMPARE(s->value(QStringLiteral("Hidden"), false), QVariant(true));
        QCOMPARE(s->value(QStringLiteral("Count"), 0), QVariant(42));
        QCOMPARE(s->value(QStringLiteral("Big"), 0).toLongLong(), qlonglong(5000000000));
        QCOMPARE(s->value(QStringLiteral("Scale"), 0.5), QVariant(1.25));
        QCOMPARE(s->value(QStringLiteral("Name"), QString()), QVariant(QStringLiteral("  a=b [c]\nd\\e  ")));
        QCOMPARE(s->value(QStringLiteral("List"), QStringList()).toStringList(), (QStringList{QStringLiteral("a,b"), QStringLiteral("c"), QString()}));
        QCOMPARE(s->value(QStringLiteral("Sizes"), QVariantList()).toStringList(), (QStringList{QStringLiteral("300"), QStringLiteral("700")}));
        // A typed default gives typed items.
        const QVariantList sizes = s->value(QStringLiteral("Sizes"), QVariantList{1, 2}).toList();
        QCOMPARE(sizes, (QVariantList{300, 700}));
        QCOMPARE(sizes.at(0).typeId(), int(QMetaType::Int));
        QCOMPARE(s->value(QStringLiteral("Sizes"), QVariantList{1.5}).toList(), (QVariantList{300.0, 700.0}));
        QCOMPARE(s->value(QStringLiteral("List"), QVariantList{1}).toList(), (QVariantList{1})); // "a,b" is no number: the default
        QVERIFY(s->setValue(QStringLiteral("Flags"), QVariantList{true, false}));
        QCOMPARE(s->value(QStringLiteral("Flags"), QVariantList{false}).toList(), (QVariantList{true, false})); // pending
        QVERIFY(s->flush());
        QCOMPARE(s->value(QStringLiteral("Flags"), QVariantList{false}).toList(), (QVariantList{true, false}));
        QCOMPARE(s->value(QStringLiteral("Flags"), QVariantList{0}).toList(), (QVariantList{0})); // "true" is no int: the default
        QCOMPARE(s->value(QStringLiteral("Missing"), QVariantList{7, 8}).toList(), (QVariantList{7, 8}));
        // Wrong shape or missing: the default.
        QCOMPARE(s->value(QStringLiteral("Name"), 7), QVariant(7));
        QCOMPARE(s->value(QStringLiteral("Name"), true), QVariant(true));
        QCOMPARE(s->value(QStringLiteral("Nope"), QStringLiteral("d")), QVariant(QStringLiteral("d")));
        QVERIFY(!s->contains(QStringLiteral("Nope")));
        const QString text = readAll(rc());
        QVERIFY2(text.contains(QStringLiteral("[Atlas]\nFormat=1")), qPrintable(text));
        // Removal.
        QVERIFY(s->remove(QStringLiteral("Hidden")));
        QVERIFY(!s->contains(QStringLiteral("Hidden")));
        QVERIFY(s->flush());
        QVERIFY(!make(QStringLiteral("View"))->contains(QStringLiteral("Hidden")));
        // Mode: owner-only lock file beside it, like the Rust crate's.
        const QFileInfo lock(m_dir.filePath(QStringLiteral(".atlas-testerrc.lock")));
        QVERIFY(lock.exists());
        QCOMPARE(lock.permissions() & (QFile::ReadGroup | QFile::WriteGroup | QFile::ReadOther | QFile::WriteOther), QFileDevice::Permissions());
    }

    void keepsForeignContent()
    {
        writeAll(rc(), QStringLiteral("# my comment\n[Atlas]\nFormat=7\n\n[Other]\nKey=1\n\n[View]\nFromRust=yes\n"));
        auto s = make(QStringLiteral("View"));
        QCOMPARE(s->value(QStringLiteral("FromRust"), QString()), QVariant(QStringLiteral("yes")));
        QVERIFY(s->setValue(QStringLiteral("Mine"), 1));
        QVERIFY(s->flush());
        const QString text = readAll(rc());
        QVERIFY2(text.contains(QStringLiteral("Format=7")), qPrintable(text)); // a newer app's number stays
        QVERIFY(!text.contains(QStringLiteral("Format=1")));
        QVERIFY(text.contains(QStringLiteral("[Other]\nKey=1")));
        QVERIFY(text.contains(QStringLiteral("FromRust=yes")));
        QVERIFY(text.contains(QStringLiteral("Mine=1")));
    }

    void otherWriterSeen()
    {
        auto s = make(QStringLiteral("View"));
        QVERIFY(s->setValue(QStringLiteral("Mine"), 1));
        QVERIFY(s->flush());
        QSignalSpy spy(s.get(), &AtlasSettings::changed);
        {
            // Another writer (as the Rust crate does it: whole-file replace).
            QString text = readAll(rc());
            text.replace(QStringLiteral("[View]\n"), QStringLiteral("[View]\nTheirs=hello\n"));
            QSaveFile f(rc());
            QVERIFY(f.open(QIODevice::WriteOnly));
            f.write(text.toUtf8());
            QVERIFY(f.commit());
        }
        QTRY_VERIFY_WITH_TIMEOUT(spy.size() >= 1, 5000);
        QCOMPARE(spy.at(0).at(0).toString(), QStringLiteral("Theirs"));
        QCOMPARE(s->value(QStringLiteral("Theirs"), QString()), QVariant(QStringLiteral("hello")));
        // And our next write keeps theirs.
        QVERIFY(s->setValue(QStringLiteral("Mine"), 2));
        QVERIFY(s->flush());
        QVERIFY(readAll(rc()).contains(QStringLiteral("Theirs=hello")));
    }

    void twoInstancesDoNotLoseChanges()
    {
        auto a = make(QStringLiteral("A"));
        auto b = make(QStringLiteral("B"));
        QVERIFY(a->setValue(QStringLiteral("x"), 1));
        QVERIFY(b->setValue(QStringLiteral("y"), 2));
        QVERIFY(a->flush());
        QVERIFY(b->flush());
        auto c = make(QStringLiteral("A"));
        QCOMPARE(c->value(QStringLiteral("x"), 0), QVariant(1));
        QCOMPARE(make(QStringLiteral("B"))->value(QStringLiteral("y"), 0), QVariant(2));
    }

    void batchedAndWrittenOnDestruction()
    {
        {
            auto s = make(QStringLiteral("View"));
            QVERIFY(s->setValue(QStringLiteral("K"), 5));
            QVERIFY(!QFile::exists(rc())); // not yet: batched
        }
        QCOMPARE(make(QStringLiteral("View"))->value(QStringLiteral("K"), 0), QVariant(5));
        // The timer writes too.
        auto s = make(QStringLiteral("View"));
        QVERIFY(s->setValue(QStringLiteral("T"), 6));
        QTRY_VERIFY_WITH_TIMEOUT(readAll(rc()).contains(QStringLiteral("T=6")), 5000);
    }

    void immutableRefused()
    {
        writeAll(rc(), QStringLiteral("[Locked][$i]\nA=1\n\n[View]\nFixed[$i]=1\nOpen=1\n"));
        auto locked = make(QStringLiteral("Locked"));
        QVERIFY(!locked->setValue(QStringLiteral("A"), 2));
        QVERIFY(!locked->setValue(QStringLiteral("New"), 2));
        QVERIFY(!locked->remove(QStringLiteral("A")));
        auto s = make(QStringLiteral("View"));
        QVERIFY(!s->setValue(QStringLiteral("Fixed"), 2));
        QVERIFY(s->setValue(QStringLiteral("Open"), 2));
        QVERIFY(s->flush());
        const QString text = readAll(rc());
        QVERIFY2(text.contains(QStringLiteral("Fixed[$i]=1")) && text.contains(QStringLiteral("A[$i]=1")), qPrintable(text));
        QVERIFY(text.contains(QStringLiteral("Open=2")));
        QVERIFY(!text.contains(QStringLiteral("New")));
        // The whole file immutable.
        writeAll(rc(), QStringLiteral("[$i]\n[View]\nA=1\n"));
        QVERIFY(!make(QStringLiteral("View"))->setValue(QStringLiteral("A"), 2));
    }

    void badGroupRefused()
    {
        for (const QString &g : {QStringLiteral("a[b"), QStringLiteral("a]b"), QStringLiteral("a\nb"), QString::fromLatin1("a\0b", 3), QStringLiteral("")}) {
            auto s = make(g);
            QVERIFY(!s->setValue(QStringLiteral("k"), 1));
            QVERIFY(!s->contains(QStringLiteral("k")));
            QCOMPARE(s->value(QStringLiteral("k"), 3), QVariant(3));
        }
        auto s = make(QStringLiteral("Ok"));
        for (const QString &k : {QStringLiteral("a=b"), QStringLiteral("a[$i]"), QStringLiteral("a\nb"), QStringLiteral("")}) {
            QVERIFY(!s->setValue(k, 1));
        }
        // A value that cannot be stored.
        QVERIFY(!s->setValue(QStringLiteral("k"), QString::fromLatin1("a\0b", 3)));
        QVERIFY(!s->setValue(QStringLiteral("k"), QVariant::fromValue(QSize(1, 1))));
        QVERIFY(!QFile::exists(rc()));
    }

    void fileNameIsBare()
    {
        auto s = make(QStringLiteral("G"), QStringLiteral("../escape"));
        QVERIFY(s->setValue(QStringLiteral("k"), 1)); // accepted, then dropped at the write
        QVERIFY(!s->flush());
        QVERIFY(!QFile::exists(QDir(m_dir.path()).filePath(QStringLiteral("../escape"))));
        auto own = make(QStringLiteral("G"), QStringLiteral("other.conf"));
        QVERIFY(own->setValue(QStringLiteral("k"), 1));
        QVERIFY(own->flush());
        QVERIFY(QFile::exists(m_dir.filePath(QStringLiteral("other.conf"))));
        QVERIFY(!QFile::exists(rc()));
    }

    void symlinkInsideIsKept()
    {
        QVERIFY(QDir(m_dir.path()).mkpath(QStringLiteral("dots")));
        const QString target = m_dir.filePath(QStringLiteral("dots/real"));
        writeAll(target, QStringLiteral("[View]\nA=1\n"));
        QVERIFY(QFile::link(QStringLiteral("dots/real"), rc()));
        auto s = make(QStringLiteral("View"));
        QCOMPARE(s->value(QStringLiteral("A"), 0), QVariant(1));
        QVERIFY(s->setValue(QStringLiteral("A"), 2));
        QVERIFY(s->flush());
        QVERIFY(QFileInfo(rc()).isSymLink()); // still a link
        QVERIFY(readAll(target).contains(QStringLiteral("A=2")));
    }

    void symlinkEscapeRefused()
    {
        QTemporaryDir outside;
        QVERIFY(outside.isValid());
        const QString victim = outside.filePath(QStringLiteral("victim"));
        writeAll(victim, QStringLiteral("[View]\nA=1\n"));
        QVERIFY(QFile::link(victim, rc()));
        QString why;
        QVERIFY(AtlasSettings::resolve(m_dir.path(), QStringLiteral("atlas-testerrc"), &why).isEmpty());
        QVERIFY(!why.isEmpty());
        auto s = make(QStringLiteral("View"));
        QCOMPARE(s->value(QStringLiteral("A"), 0), QVariant(0)); // not even read
        QVERIFY(s->setValue(QStringLiteral("A"), 2));
        QVERIFY(!s->flush());
        QCOMPARE(readAll(victim), QStringLiteral("[View]\nA=1\n"));
        QVERIFY(g_warnings > 0); // and it said so
        // A dangling link out, and a link to a directory out, too.
        QFile::remove(rc());
        QVERIFY(QFile::link(outside.filePath(QStringLiteral("new")), rc()));
        QVERIFY(AtlasSettings::resolve(m_dir.path(), QStringLiteral("atlas-testerrc")).isEmpty());
        QFile::remove(rc());
        QVERIFY(QFile::link(outside.path(), m_dir.filePath(QStringLiteral("sub"))));
        QVERIFY(AtlasSettings::resolve(m_dir.path(), QStringLiteral("sub")).isEmpty());
        // A lock file that is a link is not followed.
        QFile::remove(m_dir.filePath(QStringLiteral("sub")));
        const QString lockVictim = outside.filePath(QStringLiteral("lockvictim"));
        QVERIFY(QFile::link(lockVictim, m_dir.filePath(QStringLiteral(".atlas-testerrc.lock"))));
        auto t = make(QStringLiteral("View"));
        QVERIFY(t->setValue(QStringLiteral("A"), 2));
        QVERIFY(!t->flush());
        QVERIFY(!QFile::exists(lockVictim));
        t->remove(QStringLiteral("A"));
    }

    void noHome()
    {
        qunsetenv("XDG_CONFIG_HOME");
        const QByteArray home = qgetenv("HOME");
        qunsetenv("HOME");
        QVERIFY(AtlasSettings::configDir().isEmpty());
        qputenv("XDG_CONFIG_HOME", "relative/dir");
        QVERIFY(AtlasSettings::configDir().isEmpty());
        qputenv("HOME", home);
        QCOMPARE(AtlasSettings::configDir(), QDir::cleanPath(QString::fromLocal8Bit(home) + QStringLiteral("/.config")));
        qputenv("XDG_CONFIG_HOME", m_dir.path().toUtf8());
    }

    void lockIsHeldByOthers()
    {
        // A foreign writer holding the lock delays us but never loses data:
        // here it lets go after a moment.
        QVERIFY(make(QStringLiteral("View"))->setValue(QStringLiteral("Z"), 1));
        auto s = make(QStringLiteral("View"));
        QVERIFY(s->setValue(QStringLiteral("K"), 1));
        const QByteArray lockPath = QFile::encodeName(m_dir.filePath(QStringLiteral(".atlas-testerrc.lock")));
        const int fd = ::open(lockPath.constData(), O_RDWR | O_CREAT | O_CLOEXEC, 0600);
        QVERIFY(fd >= 0);
        QCOMPARE(::flock(fd, LOCK_EX), 0);
        // Let go from another thread: flush() blocks this one.
        std::thread release([fd] {
            QThread::msleep(300);
            ::close(fd);
        });
        QElapsedTimer t;
        t.start();
        const bool flushed = s->flush();
        release.join();
        QVERIFY(flushed);
        QVERIFY2(t.elapsed() >= 250, "did not wait for the lock");
        QVERIFY(readAll(rc()).contains(QStringLiteral("K=1")));
    }

    // AtlasPortal
    void openUrl_data()
    {
        QTest::addColumn<QString>("url");
        QTest::addColumn<bool>("ok");
        const QString existing = m_files.filePath(QStringLiteral("exists.txt"));
        writeAll(existing, QStringLiteral("x"));
        writeAll(m_files.filePath(QStringLiteral("a.desktop")), QStringLiteral("x"));
        QTest::newRow("https") << "https://example.com/a?b=c" << true;
        QTest::newRow("HTTP upper") << "HTTP://example.com" << true;
        QTest::newRow("mailto") << "mailto:me@example.com?subject=hi" << true;
        QTest::newRow("file") << QUrl::fromLocalFile(existing).toString() << true;
        QTest::newRow("file dir") << QUrl::fromLocalFile(m_files.path()).toString() << true;
        QTest::newRow("file missing") << QUrl::fromLocalFile(m_files.filePath(QStringLiteral("nope"))).toString() << false;
        QTest::newRow("file desktop") << QUrl::fromLocalFile(m_files.filePath(QStringLiteral("a.desktop"))).toString() << false;
        QTest::newRow("file remote host") << "file://example.com/etc/passwd" << false;
        QTest::newRow("no host") << "https://" << false;
        QTest::newRow("no address") << "mailto:" << false;
        QTest::newRow("javascript") << "javascript:alert(1)" << false;
        QTest::newRow("ftp") << "ftp://example.com/x" << false;
        QTest::newRow("data") << "data:text/html,<b>x</b>" << false;
        QTest::newRow("smb") << "smb://host/share" << false;
        QTest::newRow("ssh") << "ssh://host" << false;
        QTest::newRow("x-scheme-handler") << "x-scheme-handler/http://a" << false;
        QTest::newRow("relative") << "docs/readme.md" << false;
        QTest::newRow("empty") << "" << false;
        QTest::newRow("bare path") << "/etc/passwd" << false;
        QTest::newRow("long") << ("https://example.com/" + QString(9000, QLatin1Char('a'))) << false;
    }
    void openUrl()
    {
        QFETCH(QString, url);
        QFETCH(bool, ok);
        QString why;
        QCOMPARE(AtlasPortal::isOpenable(QUrl(url), {}, &why), ok);
        QCOMPARE(why.isEmpty(), ok);
    }
    void openUrlExtraScheme()
    {
        const QUrl u(QStringLiteral("atlas-app://thing"));
        QVERIFY(!AtlasPortal::isOpenable(u));
        QVERIFY(AtlasPortal::isOpenable(u, {QStringLiteral("atlas-app")}));
        QVERIFY(!AtlasPortal::isOpenable(QUrl(QStringLiteral("file:///nonexistent-zzz")), {QStringLiteral("file")}));
        AtlasPortal portal;
        QVERIFY(!portal.openUrl(QUrl(QStringLiteral("javascript:alert(1)"))));
        portal.setExtraSchemes({QStringLiteral("a b"), QStringLiteral("OK")});
        QCOMPARE(portal.extraSchemes(), QStringList{QStringLiteral("ok")});
    }
    void notificationRules()
    {
        QVERIFY(AtlasPortal::validEventId(QStringLiteral("updateStaged")));
        for (const QString &bad : {QStringLiteral(""), QStringLiteral("1a"), QStringLiteral("a]b"), QStringLiteral("a/b"), QStringLiteral("a b"), QStringLiteral("a\nb"), QString(65, QLatin1Char('a'))}) {
            QVERIFY2(!AtlasPortal::validEventId(bad), qPrintable(bad));
        }
        QVERIFY(AtlasPortal::validIcon(QString()));
        QVERIFY(AtlasPortal::validIcon(QStringLiteral("dialog-information")));
        QVERIFY(AtlasPortal::validIcon(QStringLiteral("/usr/share/icons/x.png")));
        for (const QString &bad : {QStringLiteral("https://x/y.png"), QStringLiteral("file:///x"), QStringLiteral("rel/x.png"), QStringLiteral("/a/../b"), QStringLiteral("/a\nb"), QStringLiteral("a b")}) {
            QVERIFY2(!AtlasPortal::validIcon(bad), qPrintable(bad));
        }
        QVERIFY(AtlasPortal::validActionId(QStringLiteral("default")));
        QVERIFY(!AtlasPortal::validActionId(QStringLiteral("a b")));
        AtlasPortal portal;
        QCOMPARE(portal.escape(QStringLiteral("<b>Tom & \"Jerry's\"</b>")), QStringLiteral("&lt;b&gt;Tom &amp; &quot;Jerry&#39;s&quot;&lt;/b&gt;"));
        QCOMPARE(portal.escape(QStringLiteral("a\x1b" "b\nc")), QStringLiteral("a b\nc"));
        // Bad arguments send nothing (and reach no D-Bus).
        QCOMPARE(portal.notify(QStringLiteral("t"), QStringLiteral("b"), {}, {{QStringLiteral("eventId"), QStringLiteral("bad id")}}), QString());
        QCOMPARE(portal.notify(QString(), QStringLiteral("b")), QString());
    }
    void popupSwitchedOff()
    {
        // The user's per-event choice in <component>.notifyrc is honoured.
        writeAll(m_dir.filePath(QStringLiteral("atlas-tester.notifyrc")), QStringLiteral("[Event/quiet]\nAction=\n\n[Event/loud]\nAction=Popup\n"));
        AtlasPortal portal;
        QCOMPARE(portal.notify(QStringLiteral("t"), QStringLiteral("b"), {}, {{QStringLiteral("eventId"), QStringLiteral("quiet")}}), QString());
    }
    // Fix-sec: AtlasSettings
    void failedFlushDoesNotCarryOver()
    {
        QVERIFY(make(QStringLiteral("A"))->setValue(QStringLiteral("Seed"), 1));
        auto s = make(QStringLiteral("A"));
        QVERIFY(s->setValue(QStringLiteral("K"), 1));
        const QByteArray lockPath = QFile::encodeName(m_dir.filePath(QStringLiteral(".atlas-testerrc.lock")));
        const int fd = ::open(lockPath.constData(), O_RDWR | O_CREAT | O_CLOEXEC, 0600);
        QVERIFY(fd >= 0);
        QCOMPARE(::flock(fd, LOCK_EX), 0);
        s->setGroup(QStringLiteral("B")); // the flush fails: the lock is held
        QVERIFY(!s->contains(QStringLiteral("K")));
        ::close(fd);
        QVERIFY(s->flush());
        const KConfig cfg(rc(), KConfig::SimpleConfig);
        QVERIFY(!cfg.group(QStringLiteral("B")).hasKey("K"));
        QVERIFY(!cfg.group(QStringLiteral("A")).hasKey("K"));
    }
    void lockWaitIsShort()
    {
        auto s = make(QStringLiteral("A"));
        QVERIFY(s->setValue(QStringLiteral("K"), 1));
        const QByteArray lockPath = QFile::encodeName(m_dir.filePath(QStringLiteral(".atlas-testerrc.lock")));
        const int fd = ::open(lockPath.constData(), O_RDWR | O_CREAT | O_CLOEXEC, 0600);
        QVERIFY(fd >= 0);
        QCOMPARE(::flock(fd, LOCK_EX), 0);
        QElapsedTimer t;
        t.start();
        QVERIFY(!s->flush());
        const qint64 ms = t.elapsed();
        ::close(fd);
        QVERIFY2(ms < 2000, "waited longer than about 1 s");
        QVERIFY(s->flush());
    }
    void lockFileMustBeRegular()
    {
        const QByteArray lockPath = QFile::encodeName(m_dir.filePath(QStringLiteral(".atlas-testerrc.lock")));
        QCOMPARE(::mkfifo(lockPath.constData(), 0600), 0);
        auto s = make(QStringLiteral("A"));
        QVERIFY(s->setValue(QStringLiteral("K"), 1));
        QVERIFY(!s->flush()); // open(O_RDWR) on a fifo succeeds: fstat refuses it
        ::unlink(lockPath.constData());
    }
    void oversizeOrIrregularFileIsIgnored()
    {
        QFile f(rc());
        QVERIFY(f.open(QIODevice::WriteOnly));
        f.write("[A]\nK=big\n");
        f.write(QByteArray(5 * 1024 * 1024, '#'));
        f.close();
        QCOMPARE(make(QStringLiteral("A"))->value(QStringLiteral("K"), QStringLiteral("def")).toString(), QStringLiteral("def"));
        QVERIFY(QFile::remove(rc()));
        QCOMPARE(::mkfifo(QFile::encodeName(rc()).constData(), 0600), 0);
        QCOMPARE(make(QStringLiteral("A"))->value(QStringLiteral("K"), QStringLiteral("def")).toString(), QStringLiteral("def"));
        QVERIFY(QFile::remove(rc()));
    }
    void noVariableExpansion()
    {
        qputenv("ATLAS_TEST_SECRET", "hunter2");
        writeAll(rc(), QStringLiteral("[A]\nK[$e]=$ATLAS_TEST_SECRET\nL=plain\nList[$e]=$ATLAS_TEST_SECRET,x\n"));
        auto s = make(QStringLiteral("A"));
        // A key marked [$e] is refused (the default comes back), never expanded.
        QCOMPARE(s->value(QStringLiteral("K"), QStringLiteral("none")).toString(), QStringLiteral("none"));
        QVERIFY(!s->contains(QStringLiteral("K")));
        QCOMPARE(s->value(QStringLiteral("L"), QStringLiteral("")).toString(), QStringLiteral("plain"));
        QVERIFY(!s->contains(QStringLiteral("List")));
        qunsetenv("ATLAS_TEST_SECRET");
    }
    // A binding on a sibling is evaluated while the tree is built, before
    // componentComplete(), and never again: it must already see the file.
    void bindingSeesSavedValueBeforeComplete()
    {
        writeAll(rc(), QStringLiteral("[View]\nShowHidden=true\nWidth=321\n"));
        qmlRegisterType<AtlasSettings>("AtlasTest", 1, 0, "AtlasSettings");
        QQmlEngine engine;
        QQmlComponent c(&engine);
        c.setData("import QtQuick\nimport AtlasTest\nItem {\n"
                  "  property bool shown: s.value(\"ShowHidden\", false)\n"
                  "  property int width2: s.value(\"Width\", 5)\n"
                  "  AtlasSettings { id: s; group: \"View\" }\n}\n",
                  QUrl());
        std::unique_ptr<QObject> o(c.create());
        QVERIFY2(o, qPrintable(c.errorString()));
        QCOMPARE(o->property("shown").toBool(), true);
        QCOMPARE(o->property("width2").toInt(), 321);
    }
    void newFileIsPrivate()
    {
        const QString other = m_dir.filePath(QStringLiteral("atlas-privaterc"));
        const mode_t old = ::umask(0);
        auto s = make(QStringLiteral("A"), QStringLiteral("atlas-privaterc"));
        QVERIFY(s->setValue(QStringLiteral("K"), 1));
        QVERIFY(s->flush());
        ::umask(old);
        QVERIFY(QFileInfo::exists(other));
        QCOMPARE(int(QFileInfo(other).permissions() & ~(QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ReadUser | QFileDevice::WriteUser)), 0);
        // A second write keeps the mode.
        QVERIFY(s->setValue(QStringLiteral("K"), 2));
        QVERIFY(s->flush());
        QCOMPARE(int(QFileInfo(other).permissions() & ~(QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ReadUser | QFileDevice::WriteUser)), 0);
    }
    void watchesDirectoryOnlyWhileMissing()
    {
        auto s = make(QStringLiteral("A"));
        QSignalSpy spy(s.get(), &AtlasSettings::changed);
        writeAll(rc(), QStringLiteral("[A]\nK=1\n")); // appears: seen through the directory
        QVERIFY(spy.wait(3000));
        spy.clear();
        writeAll(rc(), QStringLiteral("[A]\nK=2\n")); // changes: seen through the file
        QVERIFY(spy.wait(3000));
    }

    // Fix-sec: AtlasPortal
    void openUrlRefusesPrograms()
    {
        const QString dir = m_files.path();
        const QString desktop = QStringLiteral("[Desktop Entry]\nType=Application\nName=x\nExec=/bin/true\n");
        writeAll(dir + QStringLiteral("/real.desktop"), desktop);
        QVERIFY(QFile::link(dir + QStringLiteral("/real.desktop"), dir + QStringLiteral("/looks-like.txt")));
        writeAll(dir + QStringLiteral("/noext"), desktop);
        writeAll(dir + QStringLiteral("/script.txt"), QStringLiteral("#!/bin/sh\necho hi\n"));
        QVERIFY(QFile::setPermissions(dir + QStringLiteral("/script.txt"), QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ExeOwner));
        writeAll(dir + QStringLiteral("/plain-script"), QStringLiteral("#!/bin/sh\necho hi\n")); // no exec bit: sniffed
        writeAll(dir + QStringLiteral("/ok.txt"), QStringLiteral("hello\n"));
        QVERIFY(QFile::link(dir + QStringLiteral("/ok.txt"), dir + QStringLiteral("/ok-link.txt")));
        QCOMPARE(::mkfifo(QFile::encodeName(dir + QStringLiteral("/pipe")).constData(), 0600), 0);
        for (const char *name : {"looks-like.txt", "noext", "script.txt", "plain-script", "pipe"}) {
            QString why;
            QVERIFY2(!AtlasPortal::isOpenable(QUrl::fromLocalFile(dir + QLatin1Char('/') + QLatin1String(name)), {}, &why), name);
            QVERIFY2(!why.isEmpty(), name);
        }
        QVERIFY(AtlasPortal::isOpenable(QUrl::fromLocalFile(dir + QStringLiteral("/ok.txt"))));
        QVERIFY(AtlasPortal::isOpenable(QUrl::fromLocalFile(dir + QStringLiteral("/ok-link.txt"))));
        QVERIFY(AtlasPortal::isOpenable(QUrl::fromLocalFile(dir)));
        // A control character in the decoded URL.
        QVERIFY(!AtlasPortal::isOpenable(QUrl(QStringLiteral("https://example.com/a%0Ab"))));
        QVERIFY(!AtlasPortal::isOpenable(QUrl(QStringLiteral("file://%1/ok.txt%0A").arg(dir))));
    }
    void mailtoKeepsSubjectAndBodyOnly()
    {
        QStringList dropped;
        const QUrl in(QStringLiteral("mailto:a@example.com?subject=Hi%20there&attach=/etc/passwd&BCC=x@y.z&body=Hello&cc=c@d.e&Subject=dup"));
        const QUrl out = AtlasPortal::cleanMailto(in, &dropped);
        QCOMPARE(out.path(), QStringLiteral("a@example.com"));
        const QUrlQuery q(out);
        QCOMPARE(q.queryItemValue(QStringLiteral("subject"), QUrl::FullyDecoded), QStringLiteral("Hi there"));
        QCOMPARE(q.queryItemValue(QStringLiteral("body"), QUrl::FullyDecoded), QStringLiteral("Hello"));
        QCOMPARE(q.queryItems().size(), 2);
        QVERIFY(dropped.contains(QStringLiteral("attach")) && dropped.contains(QStringLiteral("BCC")) && dropped.contains(QStringLiteral("cc")));
        QCOMPARE(AtlasPortal::cleanMailto(QUrl(QStringLiteral("mailto:a@example.com?cc=x@y.z"))).toString(), QStringLiteral("mailto:a@example.com"));
        const QUrl web(QStringLiteral("https://example.com/?attach=1"));
        QCOMPARE(AtlasPortal::cleanMailto(web), web);
    }
    void timedWriteNeverBlocksOnTheLock()
    {
        auto s = make(QStringLiteral("Busy"));
        const int fd = ::open(QFile::encodeName(m_dir.filePath(QStringLiteral(".atlas-testerrc.lock"))).constData(), O_RDWR | O_CREAT | O_CLOEXEC, 0600);
        QVERIFY(fd >= 0);
        QCOMPARE(::flock(fd, LOCK_EX | LOCK_NB), 0);
        QVERIFY(s->setValue(QStringLiteral("K"), 7));
        // The event loop keeps turning while the timed write tries and retries.
        qint64 worst = 0;
        QElapsedTimer sinceTick;
        sinceTick.start();
        QTimer ticker;
        ticker.setInterval(10);
        connect(&ticker, &QTimer::timeout, this, [&] {
            worst = qMax(worst, sinceTick.elapsed());
            sinceTick.restart();
        });
        ticker.start();
        QTest::qWait(1800);
        ticker.stop();
        QVERIFY2(worst < 400, qPrintable(QString::number(worst)));
        QVERIFY(!QFile::exists(m_dir.filePath(QStringLiteral("atlas-testerrc")))); // still pending
        QCOMPARE(s->value(QStringLiteral("K"), 0).toInt(), 7);
        // Explicit flush still waits about a second, then fails and keeps the change.
        QElapsedTimer t;
        t.start();
        QVERIFY(!s->flush());
        QVERIFY2(t.elapsed() >= 900 && t.elapsed() < 3000, qPrintable(QString::number(t.elapsed())));
        // Released: the next retry writes it.
        ::close(fd);
        QTRY_VERIFY_WITH_TIMEOUT(readAll(rc()).contains(QStringLiteral("K=7")), 4000);
    }
    void notifyBodyIsPlainByDefault()
    {
        // No D-Bus here: the call is checked through the rules that run first.
        AtlasPortal portal;
        QCOMPARE(portal.escape(QStringLiteral("<b>x</b>")), QStringLiteral("&lt;b&gt;x&lt;/b&gt;"));
        // An event switched off returns before anything is sent, with markup either way.
        writeAll(m_dir.filePath(QStringLiteral("atlas-tester.notifyrc")), QStringLiteral("[Event/quiet]\nAction=\n"));
        QCOMPARE(portal.notify(QStringLiteral("t"), QStringLiteral("<b>x</b>"), {}, {{QStringLiteral("eventId"), QStringLiteral("quiet")}, {QStringLiteral("markup"), true}}), QString());
    }
};

QTEST_MAIN(TestSettings)
#include "tst_settings.moc"
