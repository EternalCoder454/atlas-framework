#include "atlassettings.h"

#include <KConfig>
#include <KConfigGroup>

#include <QCoreApplication>
#include <QDir>
#include <QFileInfo>
#include <QGuiApplication>
#include <QMutex>
#include <QMutexLocker>
#include <QSet>
#include <QThread>

#include <cerrno>
#include <fcntl.h>
#include <sys/file.h>
#include <unistd.h>

namespace
{
constexpr int kWriteDelayMs = 400;
constexpr int kWatchDelayMs = 100;
// A writer waits this long for the lock before giving up (and keeping the
// change for the next flush).
constexpr int kLockWaitMs = 3000;
constexpr int kMaxNameLength = 200;

bool hasControl(const QString &s)
{
    for (const QChar c : s) {
        if (c.unicode() < 0x20 || c.unicode() == 0x7f || (c.unicode() >= 0x80 && c.unicode() < 0xa0)) {
            return true;
        }
    }
    return false;
}

// Threads of this process take turns; flock separates processes (and is
// per open file, so it does not separate two threads).
QMutex &writers()
{
    static QMutex m;
    return m;
}

// `flock` on `.<name>.lock` beside `path`, held while this lives. Same file
// and mode as the Rust crate's. The lock file is never removed: removing it
// would race the next writer. O_NOFOLLOW: a planted link is not followed.
class FileLock
{
public:
    explicit FileLock(const QString &path)
    {
        const QFileInfo info(path);
        const QByteArray lockPath = QFile::encodeName(info.absolutePath() + QLatin1String("/.") + info.fileName() + QLatin1String(".lock"));
        m_fd = ::open(lockPath.constData(), O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0600);
        if (m_fd < 0 && errno == EACCES) {
            // Someone else's lock file this user may only read: enough for flock.
            m_fd = ::open(lockPath.constData(), O_RDONLY | O_NOFOLLOW | O_CLOEXEC);
        }
        if (m_fd < 0) {
            m_error = QString::fromLocal8Bit(strerror(errno));
            return;
        }
        for (int waited = 0;; waited += 10) {
            if (::flock(m_fd, LOCK_EX | LOCK_NB) == 0) {
                return;
            }
            if (errno != EWOULDBLOCK && errno != EINTR) {
                m_error = QString::fromLocal8Bit(strerror(errno));
                break;
            }
            if (waited >= kLockWaitMs) {
                m_error = QStringLiteral("another program holds the lock");
                break;
            }
            QThread::msleep(10);
        }
        ::close(m_fd);
        m_fd = -1;
    }
    ~FileLock()
    {
        if (m_fd >= 0) {
            ::close(m_fd); // closing releases the flock
        }
    }
    FileLock(const FileLock &) = delete;
    FileLock &operator=(const FileLock &) = delete;
    bool held() const { return m_fd >= 0; }
    QString error() const { return m_error; }

private:
    int m_fd = -1;
    QString m_error;
};

// A QVariant from QML as something KConfig stores, or invalid.
QVariant normalise(const QVariant &v)
{
    switch (v.typeId()) {
    case QMetaType::Bool:
        return v.toBool();
    case QMetaType::Int:
    case QMetaType::UInt:
    case QMetaType::LongLong:
    case QMetaType::ULongLong:
        return v.toLongLong();
    case QMetaType::Double:
    case QMetaType::Float: {
        const double d = v.toDouble();
        return qIsFinite(d) ? QVariant(d) : QVariant();
    }
    case QMetaType::QString:
    case QMetaType::QUrl: {
        const QString s = v.toString();
        return s.contains(QChar(0)) ? QVariant() : QVariant(s);
    }
    case QMetaType::QStringList:
    case QMetaType::QVariantList: {
        QStringList out;
        const QVariantList list = v.toList();
        for (const QVariant &item : list) {
            const QVariant n = normalise(item);
            if (!n.isValid() || n.typeId() == QMetaType::QStringList) {
                return QVariant();
            }
            const QString s = n.toString();
            out << s;
        }
        return out;
    }
    default:
        return QVariant();
    }
}

// `v` (a pending, normalised value) as the type `def` asks for, or `def`.
QVariant coerce(const QVariant &def, const QVariant &v)
{
    switch (def.typeId()) {
    case QMetaType::Bool:
        return v.typeId() == QMetaType::Bool ? v : def;
    case QMetaType::Int:
    case QMetaType::UInt:
    case QMetaType::LongLong:
    case QMetaType::ULongLong: {
        bool ok = false;
        const double d = v.typeId() == QMetaType::QString || v.typeId() == QMetaType::QStringList || v.typeId() == QMetaType::Bool ? 0 : v.toDouble(&ok);
        if (!ok || d != qlonglong(d)) {
            return def;
        }
        const qlonglong n = qlonglong(d);
        return (n >= INT_MIN && n <= INT_MAX) ? QVariant(int(n)) : QVariant(n);
    }
    case QMetaType::Double:
    case QMetaType::Float: {
        bool ok = false;
        const double d = v.typeId() == QMetaType::QString || v.typeId() == QMetaType::QStringList || v.typeId() == QMetaType::Bool ? 0 : v.toDouble(&ok);
        return ok ? QVariant(d) : def;
    }
    case QMetaType::QStringList:
    case QMetaType::QVariantList:
        return v.typeId() == QMetaType::QStringList ? v : def;
    default:
        return v.typeId() == QMetaType::QStringList ? def : QVariant(v.toString());
    }
}

QVariant readTyped(const KConfigGroup &g, const QString &key, const QVariant &def)
{
    switch (def.typeId()) {
    case QMetaType::Bool: {
        const QString s = g.readEntry(key, QString()).trimmed().toLower();
        if (s == QLatin1String("true") || s == QLatin1String("1") || s == QLatin1String("yes") || s == QLatin1String("on")) {
            return true;
        }
        if (s == QLatin1String("false") || s == QLatin1String("0") || s == QLatin1String("no") || s == QLatin1String("off")) {
            return false;
        }
        return def;
    }
    case QMetaType::Int:
    case QMetaType::UInt:
    case QMetaType::LongLong:
    case QMetaType::ULongLong: {
        bool ok = false;
        const qlonglong n = g.readEntry(key, QString()).trimmed().toLongLong(&ok);
        if (!ok) {
            return def;
        }
        return (n >= INT_MIN && n <= INT_MAX) ? QVariant(int(n)) : QVariant(n);
    }
    case QMetaType::Double:
    case QMetaType::Float: {
        bool ok = false;
        const double d = g.readEntry(key, QString()).trimmed().toDouble(&ok);
        return (ok && qIsFinite(d)) ? QVariant(d) : def;
    }
    case QMetaType::QStringList:
    case QMetaType::QVariantList:
        return g.readEntry(key, QStringList());
    default:
        return g.readEntry(key, QString());
    }
}
}

AtlasSettings::AtlasSettings(QObject *parent)
    : QObject(parent)
{
    m_writeTimer.setSingleShot(true);
    m_writeTimer.setInterval(kWriteDelayMs);
    connect(&m_writeTimer, &QTimer::timeout, this, [this] { flush(); });
    m_watchTimer.setSingleShot(true);
    m_watchTimer.setInterval(kWatchDelayMs);
    connect(&m_watchTimer, &QTimer::timeout, this, &AtlasSettings::fileTouched);
    connect(&m_watcher, &QFileSystemWatcher::fileChanged, &m_watchTimer, qOverload<>(&QTimer::start));
    connect(&m_watcher, &QFileSystemWatcher::directoryChanged, &m_watchTimer, qOverload<>(&QTimer::start));
    if (QCoreApplication::instance()) {
        m_quitConnection = connect(QCoreApplication::instance(), &QCoreApplication::aboutToQuit, this, [this] { flush(); });
    }
}

AtlasSettings::~AtlasSettings()
{
    flush();
}

QString AtlasSettings::shortName(const QString &appId)
{
    QString last = appId.mid(appId.lastIndexOf(QLatin1Char('.')) + 1);
    if (last.startsWith(QLatin1String("atlas-"), Qt::CaseInsensitive)) {
        last = last.mid(6);
    }
    QString safe;
    const QList<uint> points = last.toUcs4();
    for (qsizetype i = 0; i < points.size() && i < 58; ++i) {
        const uint c = points[i];
        if ((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '_' || c == '-') {
            safe += QChar(c);
        } else if (c >= 'A' && c <= 'Z') {
            safe += QChar(c - 'A' + 'a');
        } else {
            safe += QLatin1Char('_');
        }
    }
    return safe.isEmpty() ? QStringLiteral("atlas-app") : QLatin1String("atlas-") + safe;
}

QString AtlasSettings::configDir()
{
    const auto absolute = [](const char *name) {
        const QString v = qEnvironmentVariable(name);
        return QDir::isAbsolutePath(v) ? v : QString();
    };
    const QString xdg = absolute("XDG_CONFIG_HOME");
    if (!xdg.isEmpty()) {
        return QDir::cleanPath(xdg);
    }
    const QString home = absolute("HOME");
    return home.isEmpty() ? QString() : QDir::cleanPath(home + QLatin1String("/.config"));
}

bool AtlasSettings::validGroup(const QString &group)
{
    return !group.isEmpty() && group.size() <= kMaxNameLength && group == group.trimmed() && !group.startsWith(QLatin1Char('#')) && !group.startsWith(QLatin1Char(';'))
        && !group.contains(QLatin1Char('[')) && !group.contains(QLatin1Char(']')) && !hasControl(group);
}

bool AtlasSettings::validKey(const QString &key)
{
    return !key.isEmpty() && key.size() <= kMaxNameLength && key == key.trimmed() && !key.startsWith(QLatin1Char('#')) && !key.startsWith(QLatin1Char(';'))
        && !key.contains(QLatin1Char('[')) && !key.contains(QLatin1Char(']')) && !key.contains(QLatin1Char('=')) && !hasControl(key);
}

bool AtlasSettings::validFileName(const QString &name)
{
    return !name.isEmpty() && name.size() <= kMaxNameLength && name == name.trimmed() && !name.startsWith(QLatin1Char('.')) && !name.contains(QLatin1Char('/'))
        && !name.contains(QLatin1Char('\\')) && !hasControl(name);
}

QString AtlasSettings::resolve(const QString &dir, const QString &name, QString *error)
{
    const auto fail = [error](const QString &why) {
        if (error) {
            *error = why;
        }
        return QString();
    };
    if (!validFileName(name)) {
        return fail(QStringLiteral("not a plain file name"));
    }
    // The directory may itself be a link (dotfiles): that is the user's.
    const QString root = QFileInfo(dir).canonicalFilePath();
    if (root.isEmpty()) {
        // Not there yet: nothing in it to follow.
        return QDir::cleanPath(dir + QLatin1Char('/') + name);
    }
    QString path = root + QLatin1Char('/') + name;
    for (int hops = 0;; ++hops) {
        const QFileInfo info(path);
        if (!info.isSymLink()) {
            break;
        }
        if (hops >= 40) {
            return fail(QStringLiteral("too many levels of symbolic links"));
        }
        // symLinkTarget is absolute and does not need the target to exist.
        path = info.symLinkTarget();
        if (path.isEmpty()) {
            return fail(QStringLiteral("an unreadable symbolic link"));
        }
    }
    // Where the final file would live, with its directory resolved.
    const QFileInfo last(path);
    const QString parent = last.dir().canonicalPath();
    const QString resolved = parent + QLatin1Char('/') + last.fileName();
    if (parent.isEmpty() || !(resolved.startsWith(root + QLatin1Char('/')))) {
        return fail(QStringLiteral("a symbolic link leads out of %1").arg(root));
    }
    return resolved;
}

QString AtlasSettings::path() const
{
    if (!validGroup(m_group)) {
        return QString();
    }
    QString name = m_fileName;
    if (name.isEmpty()) {
        name = shortName(QGuiApplication::desktopFileName()) + QLatin1String("rc");
    }
    const QString dir = configDir();
    if (dir.isEmpty()) {
        qWarning("AtlasSettings: no home directory to keep settings in");
        return QString();
    }
    QString error;
    const QString file = resolve(dir, name, &error);
    if (file.isEmpty()) {
        qWarning("AtlasSettings: %s/%s: %s", qPrintable(dir), qPrintable(name), qPrintable(error));
    }
    return file;
}

void AtlasSettings::setGroup(const QString &group)
{
    if (group == m_group) {
        return;
    }
    flush();
    m_group = group;
    if (!group.isEmpty() && !validGroup(group)) {
        qWarning("AtlasSettings: %s is not a valid group name", qPrintable(group));
    }
    if (m_complete) {
        reload(false);
    }
    Q_EMIT groupChanged();
}

void AtlasSettings::setFileName(const QString &fileName)
{
    if (fileName == m_fileName) {
        return;
    }
    flush();
    m_fileName = fileName;
    if (!fileName.isEmpty() && !validFileName(fileName)) {
        qWarning("AtlasSettings: %s is not a plain file name", qPrintable(fileName));
    }
    if (m_complete) {
        reload(false);
        rewatch();
    }
    Q_EMIT fileNameChanged();
}

void AtlasSettings::componentComplete()
{
    m_complete = true;
    reload(false);
    rewatch();
}

void AtlasSettings::reload(bool announce)
{
    const QHash<QString, QString> before = m_snapshot;
    m_snapshot.clear();
    m_cfg.reset();
    const QString file = path();
    if (!file.isEmpty()) {
        m_cfg = std::make_unique<KConfig>(file, KConfig::SimpleConfig);
        const QMap<QString, QString> entries = m_cfg->entryMap(m_group);
        for (auto it = entries.cbegin(); it != entries.cend(); ++it) {
            m_snapshot.insert(it.key(), it.value());
        }
    }
    if (!announce) {
        return;
    }
    QSet<QString> keys;
    for (auto it = before.cbegin(); it != before.cend(); ++it) {
        if (m_snapshot.value(it.key(), QString()) != it.value() || !m_snapshot.contains(it.key())) {
            keys.insert(it.key());
        }
    }
    for (auto it = m_snapshot.cbegin(); it != m_snapshot.cend(); ++it) {
        if (!before.contains(it.key())) {
            keys.insert(it.key());
        }
    }
    for (const QString &key : std::as_const(keys)) {
        Q_EMIT changed(key);
    }
}

void AtlasSettings::rewatch()
{
    const QStringList old = m_watcher.files() + m_watcher.directories();
    if (!old.isEmpty()) {
        m_watcher.removePaths(old);
    }
    const QString file = path();
    if (file.isEmpty()) {
        return;
    }
    const QString dir = QFileInfo(file).absolutePath();
    if (QFileInfo(dir).isDir()) {
        m_watcher.addPath(dir);
    }
    if (QFileInfo::exists(file)) {
        m_watcher.addPath(file);
    }
}

void AtlasSettings::fileTouched()
{
    reload(true);
    rewatch();
}

QVariant AtlasSettings::value(const QString &key, const QVariant &defaultValue) const
{
    if (!validKey(key)) {
        return defaultValue;
    }
    const auto pending = m_pending.constFind(key);
    if (pending != m_pending.cend()) {
        return pending->isValid() ? coerce(defaultValue, *pending) : defaultValue;
    }
    if (!m_cfg || !m_snapshot.contains(key)) {
        return defaultValue;
    }
    return readTyped(m_cfg->group(m_group), key, defaultValue);
}

bool AtlasSettings::contains(const QString &key) const
{
    if (!validKey(key)) {
        return false;
    }
    const auto pending = m_pending.constFind(key);
    if (pending != m_pending.cend()) {
        return pending->isValid();
    }
    return m_snapshot.contains(key);
}

bool AtlasSettings::setValue(const QString &key, const QVariant &value)
{
    const QVariant stored = normalise(value);
    if (!stored.isValid()) {
        qWarning("AtlasSettings: %s/%s: this value cannot be stored", qPrintable(m_group), qPrintable(key));
        return false;
    }
    if (!validGroup(m_group) || !validKey(key)) {
        qWarning("AtlasSettings: %s/%s is not a valid group and key", qPrintable(m_group), qPrintable(key));
        return false;
    }
    if (m_cfg && (m_cfg->isImmutable() || m_cfg->group(m_group).isImmutable() || m_cfg->group(m_group).isEntryImmutable(key))) {
        qWarning("AtlasSettings: %s/%s is immutable", qPrintable(m_group), qPrintable(key));
        return false;
    }
    m_pending.insert(key, stored);
    m_writeTimer.start();
    return true;
}

bool AtlasSettings::remove(const QString &key)
{
    if (!validGroup(m_group) || !validKey(key)) {
        qWarning("AtlasSettings: %s/%s is not a valid group and key", qPrintable(m_group), qPrintable(key));
        return false;
    }
    if (m_cfg && (m_cfg->isImmutable() || m_cfg->group(m_group).isImmutable() || m_cfg->group(m_group).isEntryImmutable(key))) {
        qWarning("AtlasSettings: %s/%s is immutable", qPrintable(m_group), qPrintable(key));
        return false;
    }
    m_pending.insert(key, QVariant());
    m_writeTimer.start();
    return true;
}

bool AtlasSettings::flush()
{
    m_writeTimer.stop();
    if (m_pending.isEmpty()) {
        return true;
    }
    const QString file = path();
    if (file.isEmpty()) {
        qWarning("AtlasSettings: %s: no settings file to write; %lld change(s) dropped", qPrintable(m_fileName), qint64(m_pending.size()));
        m_pending.clear();
        return false;
    }
    if (!QDir().mkpath(QFileInfo(file).absolutePath())) {
        qWarning("AtlasSettings: %s: cannot create its directory", qPrintable(file));
        return false;
    }
    bool ok = false;
    {
        QMutexLocker thread(&writers());
        const FileLock lock(file);
        if (!lock.held()) {
            qWarning("AtlasSettings: %s: cannot lock it: %s", qPrintable(file), qPrintable(lock.error()));
            return false;
        }
        // Read under the lock: another writer may have just changed it.
        KConfig cfg(file, KConfig::SimpleConfig);
        KConfigGroup g = cfg.group(m_group);
        if (cfg.isImmutable() || g.isImmutable()) {
            qWarning("AtlasSettings: %s: group %s is immutable; changes dropped", qPrintable(file), qPrintable(m_group));
            m_pending.clear();
            reload(false);
            return false;
        }
        for (auto it = m_pending.cbegin(); it != m_pending.cend(); ++it) {
            const QString &key = it.key();
            if (g.isEntryImmutable(key)) {
                qWarning("AtlasSettings: %s: %s/%s is immutable; change dropped", qPrintable(file), qPrintable(m_group), qPrintable(key));
                continue;
            }
            const QVariant &v = it.value();
            switch (v.typeId()) {
            case QMetaType::Bool:
                g.writeEntry(key, v.toBool());
                break;
            case QMetaType::LongLong:
                g.writeEntry(key, v.toLongLong());
                break;
            case QMetaType::Double:
                g.writeEntry(key, v.toDouble());
                break;
            case QMetaType::QStringList:
                g.writeEntry(key, v.toStringList());
                break;
            case QMetaType::QString:
                g.writeEntry(key, v.toString());
                break;
            default:
                g.deleteEntry(key);
                break;
            }
        }
        KConfigGroup atlas = cfg.group(QStringLiteral("Atlas"));
        if (!atlas.hasKey("Format") && !atlas.isImmutable() && !g.isImmutable()) {
            atlas.writeEntry("Format", 1);
        }
        ok = cfg.sync();
    }
    if (!ok) {
        qWarning("AtlasSettings: %s: cannot write it (kept; tried again at the next change or on exit)", qPrintable(file));
        return false;
    }
    m_pending.clear();
    reload(false);
    rewatch();
    return true;
}
