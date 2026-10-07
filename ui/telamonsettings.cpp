#include "telamonsettings.h"
#include "legacyconfig.h"
#include "telamonlogsafe.h"

#include <KConfig>
#include <KConfigGroup>

#include <QCoreApplication>
#include <QDir>
#include <QFileInfo>
#include <QGuiApplication>
#include <QFile>
#include <QMutex>
#include <QMutexLocker>
#include <QRegularExpression>
#include <QSet>
#include <QThread>

#include <cerrno>
#include <fcntl.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <unistd.h>

namespace
{
constexpr int kWriteDelayMs = 400;
constexpr int kWatchDelayMs = 100;
// An explicit flush() waits this long for the lock before giving up (and
// keeping the change for the next flush).
constexpr int kLockWaitMs = 1000;
// The timed write never waits: it tries once, then again after 50 ms,
// doubling up to 1 s, for about 10 s in all, then warns once.
constexpr int kRetryFirstMs = 50;
constexpr int kRetryMaxMs = 1000;
constexpr int kRetryTotalMs = 10000;
// A settings file larger than this is not read (a real one is a few KB).
constexpr qint64 kMaxFileBytes = 4 * 1024 * 1024;
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
    explicit FileLock(const QString &path, int waitMs)
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
        // A fifo or device planted as the lock file must not be used.
        struct stat st;
        if (::fstat(m_fd, &st) != 0 || !S_ISREG(st.st_mode)) {
            m_error = QStringLiteral("the lock file is not a regular file");
            ::close(m_fd);
            m_fd = -1;
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
            if (waited >= waitMs) {
                m_busy = true;
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
    // Not held because another process holds it (not an error of the file).
    bool busy() const { return m_busy; }

private:
    int m_fd = -1;
    bool m_busy = false;
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

// Stored list items as the type of the default's first item (bool, int, real
// or string); an empty or string-list default gives strings. One item that
// does not fit gives `def` whole.
QVariant typedList(const QStringList &raw, const QVariant &def)
{
    if (def.typeId() == QMetaType::QStringList) {
        return raw;
    }
    const QVariantList defList = def.toList();
    if (defList.isEmpty()) {
        return raw;
    }
    const int kind = defList.first().typeId();
    QVariantList out;
    for (const QString &item : raw) {
        const QString t = item.trimmed();
        bool ok = false;
        switch (kind) {
        case QMetaType::Bool: {
            const QString l = t.toLower();
            if (l == QLatin1String("true") || l == QLatin1String("1") || l == QLatin1String("yes") || l == QLatin1String("on")) {
                out << true;
                ok = true;
            } else if (l == QLatin1String("false") || l == QLatin1String("0") || l == QLatin1String("no") || l == QLatin1String("off")) {
                out << false;
                ok = true;
            }
            break;
        }
        case QMetaType::Int:
        case QMetaType::UInt:
        case QMetaType::LongLong:
        case QMetaType::ULongLong: {
            const qlonglong n = t.toLongLong(&ok);
            if (ok) {
                out << ((n >= INT_MIN && n <= INT_MAX) ? QVariant(int(n)) : QVariant(n));
            }
            break;
        }
        case QMetaType::Double:
        case QMetaType::Float: {
            const double d = t.toDouble(&ok);
            ok = ok && qIsFinite(d);
            if (ok) {
                out << d;
            }
            break;
        }
        default:
            out << item;
            ok = true;
        }
        if (!ok) {
            return def;
        }
    }
    return out;
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
        return v.typeId() == QMetaType::QStringList ? typedList(v.toStringList(), def) : def;
    default:
        return v.typeId() == QMetaType::QStringList ? def : QVariant(v.toString());
    }
}

// KConfig's list format: items split at a comma, a backslash quotes the next
// character (the same as KConfigGroup's own reader).
QStringList splitList(const QString &data)
{
    if (data.isEmpty()) {
        return {};
    }
    if (data == QLatin1String("\\0")) {
        return {QString()};
    }
    QStringList out;
    QString item;
    bool quoted = false;
    for (const QChar c : data) {
        if (quoted) {
            item += c;
            quoted = false;
        } else if (c == QLatin1Char('\\')) {
            quoted = true;
        } else if (c == QLatin1Char(',')) {
            out << item;
            item.clear();
        } else {
            item += c;
        }
    }
    out << item;
    return out;
}

// From the raw text of the file (the snapshot): KConfig's own readEntry would
// also expand $VARIABLES in a value marked [$e], which would let a settings
// file leak an environment variable into the app.
QVariant readTyped(const QString &raw, const QVariant &def)
{
    switch (def.typeId()) {
    case QMetaType::Bool: {
        const QString s = raw.trimmed().toLower();
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
        const qlonglong n = raw.trimmed().toLongLong(&ok);
        if (!ok) {
            return def;
        }
        return (n >= INT_MIN && n <= INT_MAX) ? QVariant(int(n)) : QVariant(n);
    }
    case QMetaType::Double:
    case QMetaType::Float: {
        bool ok = false;
        const double d = raw.trimmed().toDouble(&ok);
        return (ok && qIsFinite(d)) ? QVariant(d) : def;
    }
    case QMetaType::QStringList:
    case QMetaType::QVariantList:
        return typedList(splitList(raw), def);
    default:
        return raw;
    }
}

// Keys the file marks `[$e]` (value expansion). KConfig expands them when it
// parses, so such a key cannot be read as written: it is refused instead.
QSet<QString> expandingKeys(const QString &file)
{
    QSet<QString> keys;
    QFile f(file);
    if (!f.open(QIODevice::ReadOnly)) {
        return keys;
    }
    static const QRegularExpression flag(QStringLiteral("\\[\\$[a-zA-Z]*e[a-zA-Z]*\\]"));
    while (!f.atEnd()) {
        const QString line = QString::fromUtf8(f.readLine(64 * 1024));
        if (line.isEmpty() || line.at(0) == QLatin1Char('[') || line.at(0) == QLatin1Char('#')) {
            continue;
        }
        const int eq = line.indexOf(QLatin1Char('='));
        if (eq <= 0) {
            continue;
        }
        const QString left = line.left(eq);
        if (flag.match(left).hasMatch()) {
            keys.insert(left.left(left.indexOf(QLatin1Char('['))).trimmed());
        }
    }
    return keys;
}

// A file KConfig may be given: absent (defaults), or a regular file of a sane
// size. Anything else (a fifo would block the reader, a huge file would fill
// memory) is refused with a warning.
bool readableFile(const QString &file)
{
    const QFileInfo info(file);
    if (!info.exists()) {
        return true;
    }
    if (!info.isFile()) {
        qWarning("TelamonSettings: %s is not a regular file; using defaults", qPrintable(file));
        return false;
    }
    if (info.size() > kMaxFileBytes) {
        qWarning("TelamonSettings: %s is larger than 4 MB; using defaults", qPrintable(file));
        return false;
    }
    return true;
}
}

TelamonSettings::TelamonSettings(QObject *parent)
    : QObject(parent)
{
    m_writeTimer.setSingleShot(true);
    m_writeTimer.setInterval(kWriteDelayMs);
    connect(&m_writeTimer, &QTimer::timeout, this, &TelamonSettings::timedWrite);
    m_watchTimer.setSingleShot(true);
    m_watchTimer.setInterval(kWatchDelayMs);
    connect(&m_watchTimer, &QTimer::timeout, this, &TelamonSettings::fileTouched);
    connect(&m_watcher, &QFileSystemWatcher::fileChanged, &m_watchTimer, qOverload<>(&QTimer::start));
    connect(&m_watcher, &QFileSystemWatcher::directoryChanged, &m_watchTimer, qOverload<>(&QTimer::start));
    if (QCoreApplication::instance()) {
        m_quitConnection = connect(QCoreApplication::instance(), &QCoreApplication::aboutToQuit, this, [this] { flush(); });
    }
}

TelamonSettings::~TelamonSettings()
{
    flush();
}

namespace
{
// `<prefix><last part of the ID>`, without a `telamon-` or `atlas-` of its own.
QString nameWith(const QString &appId, QLatin1String prefix, const QString &empty)
{
    QString last = appId.mid(appId.lastIndexOf(QLatin1Char('.')) + 1);
    for (const QLatin1String brand : {QLatin1String("telamon-"), QLatin1String("atlas-")}) {
        if (last.startsWith(brand, Qt::CaseInsensitive)) {
            last = last.mid(brand.size());
            break;
        }
    }
    QString safe;
    const QList<uint> points = last.toUcs4();
    for (qsizetype i = 0; i < points.size() && i < 64 - prefix.size(); ++i) {
        const uint c = points[i];
        if ((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '_' || c == '-') {
            safe += QChar(c);
        } else if (c >= 'A' && c <= 'Z') {
            safe += QChar(c - 'A' + 'a');
        } else {
            safe += QLatin1Char('_');
        }
    }
    return safe.isEmpty() ? empty : prefix + safe;
}
}

QString TelamonSettings::shortName(const QString &appId)
{
    return nameWith(appId, QLatin1String("telamon-"), QStringLiteral("telamon-app"));
}

QString TelamonSettings::legacyShortName(const QString &appId)
{
    return nameWith(appId, QLatin1String("atlas-"), QStringLiteral("atlas-app"));
}

QString TelamonSettings::configDir()
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

bool TelamonSettings::validGroup(const QString &group)
{
    return !group.isEmpty() && group.size() <= kMaxNameLength && group == group.trimmed() && !group.startsWith(QLatin1Char('#')) && !group.startsWith(QLatin1Char(';'))
        && !group.contains(QLatin1Char('[')) && !group.contains(QLatin1Char(']')) && !hasControl(group);
}

bool TelamonSettings::validKey(const QString &key)
{
    return !key.isEmpty() && key.size() <= kMaxNameLength && key == key.trimmed() && !key.startsWith(QLatin1Char('#')) && !key.startsWith(QLatin1Char(';'))
        && !key.contains(QLatin1Char('[')) && !key.contains(QLatin1Char(']')) && !key.contains(QLatin1Char('=')) && !hasControl(key);
}

bool TelamonSettings::validFileName(const QString &name)
{
    return !name.isEmpty() && name.size() <= kMaxNameLength && name == name.trimmed() && !name.startsWith(QLatin1Char('.')) && !name.contains(QLatin1Char('/'))
        && !name.contains(QLatin1Char('\\')) && !hasControl(name);
}

QString TelamonSettings::resolve(const QString &dir, const QString &name, QString *error)
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

QString TelamonSettings::path() const
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
        qWarning("TelamonSettings: no home directory to keep settings in");
        return QString();
    }
    QString error;
    const QString file = resolve(dir, name, &error);
    if (file.isEmpty()) {
        qWarning("TelamonSettings: %s/%s: %s", qPrintable(dir), qPrintable(name), qPrintable(error));
        return file;
    }
    adoptLegacyFile(dir, name, file);
    return file;
}

// Framework 1.x called the file `atlas-<app>rc` (and kept `[Atlas] Format=1`
// in it). The first time, while there is no file under the new name (not even
// a link), that one is copied to it, with the group renamed; the old file
// stays for apps that have not moved yet.
void TelamonSettings::adoptLegacyFile(const QString &dir, const QString &name, const QString &file) const
{
    if (QFileInfo::exists(file) || QFileInfo(dir + QLatin1Char('/') + name).isSymLink()) {
        return;
    }
    QString legacy;
    if (m_fileName.isEmpty()) {
        legacy = legacyShortName(QGuiApplication::desktopFileName()) + QLatin1String("rc");
    } else if (name.startsWith(QLatin1String("telamon-"))) {
        legacy = QLatin1String("atlas-") + name.mid(8);
    } else {
        return;
    }
    const QString old = resolve(dir, legacy);
    if (!old.isEmpty() && LegacyConfig::adoptFile(file, old, kMaxFileBytes)) {
        qInfo("TelamonSettings: copied %s to %s", qPrintable(old), qPrintable(file));
    }
}

void TelamonSettings::setGroup(const QString &group)
{
    if (group == m_group) {
        return;
    }
    dropPending();
    m_group = group;
    if (!group.isEmpty() && !validGroup(group)) {
        qWarning("TelamonSettings: %s is not a valid group name", qPrintable(group));
    }
    if (m_complete) {
        reload(false);
    } else {
        m_loaded = false;
    }
    Q_EMIT groupChanged();
}

void TelamonSettings::setFileName(const QString &fileName)
{
    if (fileName == m_fileName) {
        return;
    }
    dropPending();
    m_fileName = fileName;
    if (!fileName.isEmpty() && !validFileName(fileName)) {
        qWarning("TelamonSettings: %s is not a plain file name", qPrintable(fileName));
    }
    if (m_complete) {
        reload(false);
        rewatch();
    } else {
        m_loaded = false;
    }
    Q_EMIT fileNameChanged();
}

// Before the group or file changes: write what is waiting; what could not be
// written is dropped (with a warning) and never carried over to the new group
// or file.
void TelamonSettings::dropPending()
{
    if (!flush() && !m_pending.isEmpty()) {
        qWarning("TelamonSettings: %s/%s: %lld unsaved change(s) dropped", qPrintable(m_fileName), qPrintable(logSafe(m_group)), qint64(m_pending.size()));
        m_pending.clear();
    }
}

void TelamonSettings::componentComplete()
{
    m_complete = true;
    if (!m_loaded) {
        reload(false);
    }
    rewatch();
}

// value() and contains() can run before componentComplete(): a binding on a
// sibling item is evaluated while the tree is built and would never run again.
// So the file is read on first use, with the group and file name set so far.
void TelamonSettings::ensureLoaded() const
{
    if (!m_loaded) {
        const_cast<TelamonSettings *>(this)->reload(false);
    }
}

void TelamonSettings::reload(bool announce)
{
    m_loaded = true;
    const QHash<QString, QString> before = m_snapshot;
    m_snapshot.clear();
    m_cfg.reset();
    const QString file = path();
    if (!file.isEmpty() && readableFile(file)) {
        m_cfg = std::make_unique<KConfig>(file, KConfig::SimpleConfig);
        const QMap<QString, QString> entries = m_cfg->entryMap(m_group);
        for (auto it = entries.cbegin(); it != entries.cend(); ++it) {
            m_snapshot.insert(it.key(), it.value());
        }
        for (const QString &key : expandingKeys(file)) {
            if (m_snapshot.remove(key)) {
                qWarning("TelamonSettings: %s: %s/%s is marked [$e] (variable expansion); ignored", qPrintable(file), qPrintable(logSafe(m_group)), qPrintable(logSafe(key)));
            }
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

void TelamonSettings::rewatch()
{
    const QStringList old = m_watcher.files() + m_watcher.directories();
    if (!old.isEmpty()) {
        m_watcher.removePaths(old);
    }
    const QString file = path();
    if (file.isEmpty()) {
        return;
    }
    // The file while it is there; the directory only while it is missing (to
    // see it appear), so a busy config directory does not wake us.
    if (QFileInfo::exists(file)) {
        m_watcher.addPath(file);
        return;
    }
    const QString dir = QFileInfo(file).absolutePath();
    if (QFileInfo(dir).isDir()) {
        m_watcher.addPath(dir);
    }
}

void TelamonSettings::fileTouched()
{
    reload(true);
    rewatch();
}

QVariant TelamonSettings::value(const QString &key, const QVariant &defaultValue) const
{
    if (!validKey(key)) {
        return defaultValue;
    }
    ensureLoaded();
    const auto pending = m_pending.constFind(key);
    if (pending != m_pending.cend()) {
        return pending->isValid() ? coerce(defaultValue, *pending) : defaultValue;
    }
    if (!m_cfg || !m_snapshot.contains(key)) {
        return defaultValue;
    }
    return readTyped(m_snapshot.value(key), defaultValue);
}

bool TelamonSettings::contains(const QString &key) const
{
    if (!validKey(key)) {
        return false;
    }
    ensureLoaded();
    const auto pending = m_pending.constFind(key);
    if (pending != m_pending.cend()) {
        return pending->isValid();
    }
    return m_snapshot.contains(key);
}

bool TelamonSettings::setValue(const QString &key, const QVariant &value)
{
    const QVariant stored = normalise(value);
    if (!stored.isValid()) {
        qWarning("TelamonSettings: %s/%s: this value cannot be stored", qPrintable(logSafe(m_group)), qPrintable(logSafe(key)));
        return false;
    }
    if (!validGroup(m_group) || !validKey(key)) {
        qWarning("TelamonSettings: %s/%s is not a valid group and key", qPrintable(logSafe(m_group)), qPrintable(logSafe(key)));
        return false;
    }
    if (m_cfg && (m_cfg->isImmutable() || m_cfg->group(m_group).isImmutable() || m_cfg->group(m_group).isEntryImmutable(key))) {
        qWarning("TelamonSettings: %s/%s is immutable", qPrintable(logSafe(m_group)), qPrintable(logSafe(key)));
        return false;
    }
    m_pending.insert(key, stored);
    m_retryMs = 0;
    m_retryWaitedMs = 0;
    m_writeTimer.start(kWriteDelayMs); // a retry may have changed the interval
    return true;
}

bool TelamonSettings::remove(const QString &key)
{
    if (!validGroup(m_group) || !validKey(key)) {
        qWarning("TelamonSettings: %s/%s is not a valid group and key", qPrintable(logSafe(m_group)), qPrintable(logSafe(key)));
        return false;
    }
    if (m_cfg && (m_cfg->isImmutable() || m_cfg->group(m_group).isImmutable() || m_cfg->group(m_group).isEntryImmutable(key))) {
        qWarning("TelamonSettings: %s/%s is immutable", qPrintable(logSafe(m_group)), qPrintable(logSafe(key)));
        return false;
    }
    m_pending.insert(key, QVariant());
    m_retryMs = 0;
    m_retryWaitedMs = 0;
    m_writeTimer.start(kWriteDelayMs); // a retry may have changed the interval
    return true;
}

bool TelamonSettings::flush()
{
    if (writePending(kLockWaitMs)) {
        return true;
    }
    if (m_lockBusy && !m_pending.isEmpty()) {
        // Stopped by another program's lock: the timer goes on trying.
        m_retryMs = 0;
        m_retryWaitedMs = 0;
        m_writeTimer.start(kRetryFirstMs);
    }
    return false;
}

// The debounce timer fired: never wait for the lock on the GUI thread. When
// another process holds it, the changes stay pending and this runs again
// after a growing delay, up to once a second; past about 10 s it warns
// once and goes on trying each second until the write succeeds.
void TelamonSettings::timedWrite()
{
    if (writePending(0) || !m_lockBusy) {
        m_retryMs = 0;
        m_retryWaitedMs = 0;
        m_lockWarned = false;
        return;
    }
    if (m_retryWaitedMs >= kRetryTotalMs && !m_lockWarned) {
        m_lockWarned = true;
        qWarning("TelamonSettings: %s: another program has held the settings lock for %d seconds; %lld change(s) wait and are written when it lets go", qPrintable(path()), kRetryTotalMs / 1000, qint64(m_pending.size()));
    }
    m_retryMs = m_retryMs ? qMin(m_retryMs * 2, kRetryMaxMs) : kRetryFirstMs;
    m_retryWaitedMs = qMin(m_retryWaitedMs + m_retryMs, kRetryTotalMs);
    m_writeTimer.start(m_retryMs);
}

bool TelamonSettings::writePending(int lockWaitMs)
{
    m_writeTimer.stop();
    m_lockBusy = false;
    if (m_pending.isEmpty()) {
        return true;
    }
    const QString file = path();
    if (file.isEmpty()) {
        qWarning("TelamonSettings: %s: no settings file to write; %lld change(s) dropped", qPrintable(m_fileName), qint64(m_pending.size()));
        m_pending.clear();
        return false;
    }
    if (!QDir().mkpath(QFileInfo(file).absolutePath())) {
        qWarning("TelamonSettings: %s: cannot create its directory", qPrintable(file));
        return false;
    }
    bool ok = false;
    {
        QMutexLocker thread(&writers());
        const FileLock lock(file, lockWaitMs);
        if (!lock.held()) {
            m_lockBusy = lock.busy();
            if (lockWaitMs == 0 && lock.busy()) {
                return false; // the caller retries; no warning per try
            }
            qWarning("TelamonSettings: %s: cannot lock it: %s", qPrintable(file), qPrintable(lock.error()));
            return false;
        }
        if (!readableFile(file)) {
            qWarning("TelamonSettings: %s: not written", qPrintable(file));
            return false;
        }
        // A new file is created private (0600), like the Rust crate's; KConfig's
        // save keeps the mode of the file that is there.
        const bool created = !QFileInfo::exists(file);
        // A private file (new, or already without group and other access)
        // stays private.
        const QFileDevice::Permissions others = QFileDevice::ReadGroup | QFileDevice::WriteGroup | QFileDevice::ExeGroup | QFileDevice::ReadOther | QFileDevice::WriteOther | QFileDevice::ExeOther;
        const bool keepPrivate = created || !(QFileInfo(file).permissions() & others);
        if (created) {
            const int fd = ::open(QFile::encodeName(file).constData(), O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0600);
            if (fd >= 0) {
                ::close(fd);
            } else if (errno != EEXIST) {
                qWarning("TelamonSettings: %s: cannot create it: %s", qPrintable(file), strerror(errno));
                return false;
            }
        }
        // Read under the lock: another writer may have just changed it.
        KConfig cfg(file, KConfig::SimpleConfig);
        KConfigGroup g = cfg.group(m_group);
        if (cfg.isImmutable() || g.isImmutable()) {
            qWarning("TelamonSettings: %s: group %s is immutable; changes dropped", qPrintable(file), qPrintable(logSafe(m_group)));
            m_pending.clear();
            reload(false);
            return false;
        }
        for (auto it = m_pending.cbegin(); it != m_pending.cend(); ++it) {
            const QString &key = it.key();
            if (g.isEntryImmutable(key)) {
                qWarning("TelamonSettings: %s: %s/%s is immutable; change dropped", qPrintable(file), qPrintable(logSafe(m_group)), qPrintable(logSafe(key)));
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
        KConfigGroup telamon = cfg.group(QStringLiteral("Telamon"));
        // A file nobody copied from before 2.0.0 may still say `[Atlas] Format=`.
        if (!telamon.hasKey("Format") && !cfg.group(QStringLiteral("Atlas")).hasKey("Format") && !telamon.isImmutable() && !g.isImmutable()) {
            telamon.writeEntry("Format", 1);
        }
        ok = cfg.sync();
        if (ok && keepPrivate) {
            // KConfig's own save does not keep the mode; make it private again.
            const int fd = ::open(QFile::encodeName(file).constData(), O_RDONLY | O_NOFOLLOW | O_CLOEXEC);
            if (fd >= 0) {
                if (::fchmod(fd, 0600) != 0) {
                    qWarning("TelamonSettings: %s: cannot set its mode to 0600: %s", qPrintable(file), strerror(errno));
                }
                ::close(fd);
            }
        }
    }
    if (!ok) {
        qWarning("TelamonSettings: %s: cannot write it (kept; tried again at the next change or on exit)", qPrintable(file));
        return false;
    }
    m_pending.clear();
    reload(false);
    rewatch();
    return true;
}
