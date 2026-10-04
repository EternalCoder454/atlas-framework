#include "atlasapp.h"

#include <QFile>
#include <QGuiApplication>
#include <QHash>
#include <QRegularExpression>

namespace
{
// The value of an os-release line: unquoted, or in single quotes (literal),
// or in double quotes (a backslash escapes the next character).
QString parseValue(const QString &raw)
{
    const QString v = raw.trimmed();
    if (v.size() >= 2 && v.front() == QLatin1Char('\'') && v.back() == QLatin1Char('\'')) {
        return v.mid(1, v.size() - 2);
    }
    if (v.size() >= 2 && v.front() == QLatin1Char('"') && v.back() == QLatin1Char('"')) {
        QString out;
        for (qsizetype i = 1; i < v.size() - 1; ++i) {
            if (v[i] == QLatin1Char('\\') && i + 1 < v.size() - 1) {
                ++i;
            }
            out += v[i];
        }
        return out;
    }
    QString out;
    for (qsizetype i = 0; i < v.size(); ++i) {
        if (v[i] == QLatin1Char('\\') && i + 1 < v.size()) {
            ++i;
        }
        out += v[i];
    }
    return out;
}

QHash<QString, QString> readOsRelease()
{
    // Fixed paths: no environment variable chooses the file.
    for (const char *path : {"/etc/os-release", "/usr/lib/os-release"}) {
        QFile file(QString::fromLatin1(path));
        if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
            continue;
        }
        QHash<QString, QString> map;
        while (!file.atEnd()) {
            const QString line = QString::fromUtf8(file.readLine()).trimmed();
            if (line.isEmpty() || line.startsWith(QLatin1Char('#'))) {
                continue;
            }
            const qsizetype eq = line.indexOf(QLatin1Char('='));
            if (eq <= 0) {
                continue;
            }
            map.insert(line.left(eq).trimmed(), parseValue(line.mid(eq + 1)));
        }
        return map;
    }
    return {};
}
}

AtlasApp::AtlasApp(QObject *parent)
    : QObject(parent)
    , m_qtVersion(QString::fromLatin1(qVersion()))
{
    m_name = QGuiApplication::applicationDisplayName();
    if (m_name.isEmpty()) {
        m_name = QGuiApplication::applicationName();
    }
    m_id = QGuiApplication::desktopFileName();
    m_version = QGuiApplication::applicationVersion();

    static const QRegularExpression repoRe(QStringLiteral("^[A-Za-z0-9._-]+$"));
    const QString repo = qApp ? qApp->property("atlasRepo").toString() : QString();
    if (repoRe.match(repo).hasMatch()) {
        m_repo = repo;
        m_sourceUrl = QStringLiteral("https://github.com/EternalCoder454/") + repo;
        m_issuesUrl = m_sourceUrl + QStringLiteral("/issues");
    }

    const auto os = readOsRelease();
    m_osName = os.value(QStringLiteral("NAME"));
    m_osVersion = os.value(QStringLiteral("VERSION"));
    if (m_osVersion.isEmpty()) {
        m_osVersion = os.value(QStringLiteral("VERSION_ID"));
    }
    m_osPrettyName = os.value(QStringLiteral("PRETTY_NAME"));
    if (m_osPrettyName.isEmpty()) {
        m_osPrettyName = (m_osName + QLatin1Char(' ') + m_osVersion).trimmed();
    }
    m_osLogo = os.value(QStringLiteral("LOGO"));
    if (m_osLogo.isEmpty()) {
        m_osLogo = QStringLiteral("distributor-logo");
    }
    m_osHomeUrl = os.value(QStringLiteral("HOME_URL"));
}
