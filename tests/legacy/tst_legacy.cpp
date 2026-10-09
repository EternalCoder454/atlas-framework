// What Telamon.Ui 2.0.0 still reads from before the rename (ui/legacyconfig.cpp
// and its users in ui/appearance.cpp, compiled into the test): the group
// renamed in a copied file, the copy itself, the environment variables of
// 1.x, and Appearance finding `atlasrc` when there is no `telamonrc`. Every
// file lives in a temporary XDG_CONFIG_HOME (set by CMake; the test also
// points it at a directory of its own).
#include "appearance.h"
#include "legacyconfig.h"

#include <QDir>
#include <QFile>
#include <QGuiApplication>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QTemporaryDir>
#include <QtTest>

#include <sys/stat.h>
#include <unistd.h>

namespace
{
void writeAll(const QString &path, const QByteArray &data)
{
    QFile f(path);
    QVERIFY2(f.open(QIODevice::WriteOnly | QIODevice::Truncate), qPrintable(path));
    f.write(data);
}
QByteArray readAll(const QString &path)
{
    QFile f(path);
    return f.open(QIODevice::ReadOnly) ? f.readAll() : QByteArray();
}
}

class TestLegacy : public QObject
{
    Q_OBJECT
    QTemporaryDir m_dir;
    QString p(const char *name) const { return m_dir.filePath(QString::fromLatin1(name)); }

private Q_SLOTS:
    void initTestCase()
    {
        QVERIFY(m_dir.isValid());
        // Not test mode: the config directory is the temporary one.
        QStandardPaths::setTestModeEnabled(false);
        qputenv("XDG_CONFIG_HOME", m_dir.path().toUtf8());
        for (const char *v : {"TELAMON_SOFTWARE_RENDERING", "ATLAS_SOFTWARE_RENDERING", "TELAMON_REDUCED_MOTION", "ATLAS_REDUCED_MOTION"}) {
            qunsetenv(v);
        }
    }

    void renameGroupChangesOnlyTheHeader()
    {
        const QString in = QStringLiteral("# [Atlas] in a comment\n[Atlas]\nFormat=1\n[Atlas][$i]\nA=1\n[Atlas][Sub]\nB=2\n[AtlasX]\nC=3\n[General]\nName=[Atlas]\n[Atlas] \r\nD=4\r\n[Atlas]");
        const QString out = QStringLiteral("# [Atlas] in a comment\n[Telamon]\nFormat=1\n[Telamon][$i]\nA=1\n[Telamon][Sub]\nB=2\n[AtlasX]\nC=3\n[General]\nName=[Atlas]\n[Telamon] \r\nD=4\r\n[Telamon]");
        QCOMPARE(LegacyConfig::renameGroup(in), out);
        QCOMPARE(LegacyConfig::renameGroup(QString()), QString());
        QCOMPARE(LegacyConfig::renameGroup(QStringLiteral("[Appearance]\nTransparency=false\n")), QStringLiteral("[Appearance]\nTransparency=false\n"));
    }

    void adoptCopiesOnceKeepsModeAndTheOldFile()
    {
        const QString old = p("atlas-xrc"), fresh = p("telamon-xrc");
        writeAll(old, "[Atlas]\nFormat=1\n[View]\nSide=left\n");
        QFile::setPermissions(old, QFileDevice::ReadOwner | QFileDevice::WriteOwner);
        QVERIFY(LegacyConfig::adoptFile(fresh, old));
        QCOMPARE(readAll(fresh), QByteArray("[Telamon]\nFormat=1\n[View]\nSide=left\n"));
        QCOMPARE(int(QFileInfo(fresh).permissions()), int(QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ReadUser | QFileDevice::WriteUser));
        QVERIFY(QFileInfo::exists(old));
        // Never over a file that is there, and no temp file is left.
        writeAll(fresh, "[View]\nSide=right\n");
        writeAll(old, "[View]\nSide=top\n");
        QVERIFY(!LegacyConfig::adoptFile(fresh, old));
        QCOMPARE(readAll(fresh), QByteArray("[View]\nSide=right\n"));
        QStringList names = QDir(m_dir.path()).entryList(QDir::Files | QDir::Hidden);
        names.removeAll(QStringLiteral("atlas-xrc"));
        names.removeAll(QStringLiteral("telamon-xrc"));
        QVERIFY2(names.isEmpty(), qPrintable(names.join(QLatin1Char(' '))));
    }

    void adoptDoesNotCopyWriteAccessOfGroupAndOthers()
    {
        const QString old = p("atlas-wrc"), fresh = p("telamon-wrc");
        writeAll(old, "[Atlas]\nFormat=1\n");
        QVERIFY(::chmod(QFile::encodeName(old).constData(), 0666) == 0);
        QVERIFY(LegacyConfig::adoptFile(fresh, old));
        QCOMPARE(int(QFileInfo(fresh).permissions()),
                 int(QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ReadUser | QFileDevice::WriteUser | QFileDevice::ReadGroup | QFileDevice::ReadOther));
    }

    void adoptRefusesWhatIsNotASettingsFile()
    {
        QVERIFY(!LegacyConfig::adoptFile(p("telamon-none"), p("atlas-none")));
        QVERIFY(!QFileInfo::exists(p("telamon-none")));
        QVERIFY(QDir(m_dir.path()).mkdir(QStringLiteral("atlas-dir")));
        QVERIFY(!LegacyConfig::adoptFile(p("telamon-dir"), p("atlas-dir")));
        QVERIFY(QFile::link(QStringLiteral("nowhere"), p("atlas-broken")));
        QVERIFY(!LegacyConfig::adoptFile(p("telamon-broken"), p("atlas-broken")));
        writeAll(p("atlas-big"), QByteArray(5000, '#'));
        QVERIFY(!LegacyConfig::adoptFile(p("telamon-big"), p("atlas-big"), 4096));
        QVERIFY(LegacyConfig::adoptFile(p("telamon-big"), p("atlas-big"), 5000));
        // A link at the new name counts as present, even a dangling one.
        writeAll(p("atlas-l"), "[G]\nK=1\n");
        QVERIFY(QFile::link(QStringLiteral("elsewhere"), p("telamon-l")));
        QVERIFY(!LegacyConfig::adoptFile(p("telamon-l"), p("atlas-l")));
        QVERIFY(!QFileInfo::exists(p("elsewhere")));
    }

    void adoptFollowsAnOldLinkAndKeepsOddBytes()
    {
        writeAll(p("dotfiles"), "[Atlas]\nFormat=1\n# \xff\xfe\n");
        QVERIFY(QFile::link(p("dotfiles"), p("atlas-odd")));
        QVERIFY(LegacyConfig::adoptFile(p("telamon-odd"), p("atlas-odd")));
        QVERIFY(!QFileInfo(p("telamon-odd")).isSymLink());
        QCOMPARE(readAll(p("telamon-odd")), QByteArray("[Atlas]\nFormat=1\n# \xff\xfe\n"));
    }

    void adoptCreatesTheDirectory()
    {
        writeAll(p("atlas-d"), "[G]\nK=1\n");
        QVERIFY(LegacyConfig::adoptFile(m_dir.filePath(QStringLiteral("sub/dir/telamon-d")), p("atlas-d")));
        QCOMPARE(readAll(m_dir.filePath(QStringLiteral("sub/dir/telamon-d"))), QByteArray("[G]\nK=1\n"));
    }

    void envPrefersTheNewNameWhenItIsSet()
    {
        qunsetenv("TELAMON_T");
        qunsetenv("ATLAS_T");
        QCOMPARE(LegacyConfig::env("TELAMON_T", "ATLAS_T"), QByteArray());
        qputenv("ATLAS_T", "old");
        QCOMPARE(LegacyConfig::env("TELAMON_T", "ATLAS_T"), QByteArray("old"));
        qputenv("TELAMON_T", "new");
        QCOMPARE(LegacyConfig::env("TELAMON_T", "ATLAS_T"), QByteArray("new"));
        // Set but empty is an answer: the old name is not looked at.
        qputenv("TELAMON_T", "");
        QCOMPARE(LegacyConfig::env("TELAMON_T", "ATLAS_T"), QByteArray(""));
        qunsetenv("TELAMON_T");
        qunsetenv("ATLAS_T");
    }

    // Appearance: no telamonrc yet, an atlasrc of 1.x with the switch off.
    // Goes before anything else opens the shared file: KSharedConfig keeps it.
    void appearanceFindsAtlasrc()
    {
        writeAll(p("atlasrc"), "[Appearance]\nTransparency=false\n");
        QVERIFY(!QFileInfo::exists(p("telamonrc")));
        Appearance a;
        QCOMPARE(a.transparency(), false);
        QCOMPARE(readAll(p("telamonrc")), QByteArray("[Appearance]\nTransparency=false\n"));
        QVERIFY(QFileInfo::exists(p("atlasrc")));
    }

    void appearanceFollowsTheVariablesOfOneX()
    {
        qputenv("ATLAS_SOFTWARE_RENDERING", "1");
        QCOMPARE(Appearance().softwareRendering(), true);
        qputenv("TELAMON_SOFTWARE_RENDERING", "0");
        QCOMPARE(Appearance().softwareRendering(), false); // the new name wins
        qunsetenv("TELAMON_SOFTWARE_RENDERING");
        qputenv("ATLAS_SOFTWARE_RENDERING", "maybe");
        QTest::ignoreMessage(QtWarningMsg, QRegularExpression("ignoring TELAMON_SOFTWARE_RENDERING"));
        QCOMPARE(Appearance().softwareRendering(), false);
        qunsetenv("ATLAS_SOFTWARE_RENDERING");

        qputenv("ATLAS_REDUCED_MOTION", "1");
        QCOMPARE(Appearance().reducedMotion(), true);
        qputenv("TELAMON_REDUCED_MOTION", "0");
        QCOMPARE(Appearance().reducedMotion(), false);
        qunsetenv("TELAMON_REDUCED_MOTION");
        qunsetenv("ATLAS_REDUCED_MOTION");
    }
};

QTEST_MAIN(TestLegacy)
#include "tst_legacy.moc"
