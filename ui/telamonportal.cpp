#include "telamonportal.h"

#include "telamonsettings.h"

#include <KConfig>
#include <KConfigGroup>

#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusServiceWatcher>
#include <QDesktopServices>
#include <QFileInfo>
#include <QGuiApplication>
#include <QMimeDatabase>
#include <QMimeType>
#include <QUrlQuery>
#include <QRegularExpression>

namespace
{
constexpr auto kService = "org.freedesktop.Notifications";
constexpr auto kPath = "/org/freedesktop/Notifications";
constexpr auto kInterface = "org.freedesktop.Notifications";
constexpr int kCallTimeoutMs = 10000;
constexpr int kMaxActions = 8;
constexpr int kMaxEventLength = 64;
constexpr int kMaxUrlLength = 8192;
constexpr int kMaxTextLength = 8192;
// Remembered notifications: the oldest go first, so a long-running app that
// never sees an action does not grow without end.
constexpr int kMaxTracked = 256;

bool hasControl(const QString &s)
{
    for (const QChar c : s) {
        if (c.unicode() < 0x20 || c.unicode() == 0x7f || (c.unicode() >= 0x80 && c.unicode() < 0xa0)) {
            return true;
        }
    }
    return false;
}

// A control character in any part of the URL, after percent-decoding (toString
// keeps %0A encoded, so the parts are decoded one by one).
bool urlHasControl(const QUrl &url)
{
    const QUrl::ComponentFormattingOption f = QUrl::FullyDecoded;
    return hasControl(url.userName(f)) || hasControl(url.password(f)) || hasControl(url.host(f)) || hasControl(url.path(f)) || hasControl(url.query(f)) || hasControl(url.fragment(f))
        || hasControl(url.toString());
}

// Content types that run code (or are launchers) when "opened": never handed
// to the desktop.
bool runsCode(const QMimeType &type)
{
    static const QStringList names = {
        QStringLiteral("application/x-desktop"),         QStringLiteral("application/x-executable"),   QStringLiteral("application/x-sharedlib"),
        QStringLiteral("application/x-shellscript"),     QStringLiteral("application/x-pie-executable"), QStringLiteral("application/vnd.appimage"),
        QStringLiteral("application/x-ms-dos-executable"), QStringLiteral("application/x-msdownload"),  QStringLiteral("application/x-dosexec"),
        QStringLiteral("application/x-perl"),            QStringLiteral("application/x-python"),       QStringLiteral("application/x-python3"),
        QStringLiteral("text/x-python"),                 QStringLiteral("text/x-python3"),             QStringLiteral("text/x-script"),
        QStringLiteral("application/x-java-archive"),    QStringLiteral("application/x-ruby"),         QStringLiteral("application/x-php"),
        QStringLiteral("application/x-msi"),             QStringLiteral("application/x-bat"),          QStringLiteral("application/x-executable-script"),
    };
    for (const QString &n : names) {
        if (type.inherits(n)) {
            return true;
        }
    }
    return false;
}

// The real file behind `file` (symlinks resolved) must exist, be a directory
// or a regular file with no execute bit, and by content not be a program or
// a launcher; a link named .txt that points at a .desktop file is a .desktop
// file.
bool fileOpenable(const QString &file, QString *why)
{
    const auto no = [why](const QString &reason) {
        if (why) {
            *why = reason;
        }
        return false;
    };
    if (file.contains(QChar(0)) || hasControl(file)) {
        return no(QStringLiteral("no such file"));
    }
    const QString real = QFileInfo(file).canonicalFilePath();
    if (real.isEmpty()) {
        return no(QStringLiteral("no such file"));
    }
    if (file.endsWith(QLatin1String(".desktop"), Qt::CaseInsensitive) || real.endsWith(QLatin1String(".desktop"), Qt::CaseInsensitive)) {
        return no(QStringLiteral("a desktop file would run a program"));
    }
    const QFileInfo info(real);
    if (info.isDir()) {
        return true;
    }
    // Not a pipe, socket or device: sniffing the content could block.
    if (!info.isFile()) {
        return no(QStringLiteral("not a regular file or directory"));
    }
    if (info.permissions() & (QFileDevice::ExeOwner | QFileDevice::ExeGroup | QFileDevice::ExeOther)) {
        return no(QStringLiteral("an executable file would run a program"));
    }
    const QMimeType type = QMimeDatabase().mimeTypeForFile(real, QMimeDatabase::MatchContent);
    if (runsCode(type)) {
        return no(QStringLiteral("a %1 file would run a program").arg(type.name()));
    }
    return true;
}
}

TelamonPortal::TelamonPortal(QObject *parent)
    : QObject(parent)
{
}

void TelamonPortal::setExtraSchemes(const QStringList &schemes)
{
    QStringList clean;
    for (const QString &s : schemes) {
        const QString lower = s.toLower();
        // A scheme is a letter, then letters, digits, + - . (RFC 3986).
        static const QRegularExpression ok(QStringLiteral("^[a-z][a-z0-9+.-]*$"));
        if (!ok.match(lower).hasMatch()) {
            qWarning("TelamonPortal: %s is not a URL scheme", qPrintable(s));
            continue;
        }
        if (!clean.contains(lower)) {
            clean << lower;
        }
    }
    if (clean != m_extraSchemes) {
        m_extraSchemes = clean;
        Q_EMIT extraSchemesChanged();
    }
}

bool TelamonPortal::isOpenable(const QUrl &url, const QStringList &extraSchemes, QString *why)
{
    const auto no = [why](const QString &reason) {
        if (why) {
            *why = reason;
        }
        return false;
    };
    if (!url.isValid() || url.isEmpty()) {
        return no(QStringLiteral("not a valid URL"));
    }
    const QString text = url.toString(QUrl::FullyEncoded);
    if (text.size() > kMaxUrlLength || urlHasControl(url)) {
        return no(QStringLiteral("too long, or has control characters"));
    }
    const QString scheme = url.scheme().toLower();
    if (scheme == QLatin1String("http") || scheme == QLatin1String("https")) {
        return url.host().isEmpty() ? no(QStringLiteral("no host")) : true;
    }
    if (scheme == QLatin1String("mailto")) {
        return url.path().isEmpty() ? no(QStringLiteral("no address")) : true;
    }
    if (scheme == QLatin1String("file")) {
        if (!url.isLocalFile()) {
            return no(QStringLiteral("not a local file"));
        }
        return fileOpenable(url.toLocalFile(), why);
    }
    if (!scheme.isEmpty() && extraSchemes.contains(scheme)) {
        return true;
    }
    return no(QStringLiteral("scheme %1 is not allowed").arg(scheme.isEmpty() ? QStringLiteral("(none)") : scheme));
}

QUrl TelamonPortal::cleanMailto(const QUrl &url, QStringList *dropped)
{
    if (url.scheme().toLower() != QLatin1String("mailto")) {
        return url;
    }
    // Only subject and body: attach, bcc, cc and the rest could leak a file or
    // copy the mail to someone else.
    const QUrlQuery in(url);
    QUrlQuery out;
    for (const auto &item : in.queryItems(QUrl::FullyDecoded)) {
        const QString key = item.first.toLower();
        if ((key == QLatin1String("subject") || key == QLatin1String("body")) && !out.hasQueryItem(key)) {
            out.addQueryItem(key, item.second);
        } else if (dropped) {
            *dropped << item.first.left(40);
        }
    }
    QUrl clean = url;
    clean.setQuery(out.isEmpty() ? QString() : out.query(QUrl::FullyEncoded), QUrl::StrictMode);
    return clean;
}

bool TelamonPortal::openUrl(const QUrl &url)
{
    QString why;
    if (!isOpenable(url, m_extraSchemes, &why)) {
        qWarning("TelamonPortal: not opening %s: %s", qPrintable(url.toDisplayString().left(200)), qPrintable(why));
        return false;
    }
    QStringList dropped;
    const QUrl target = cleanMailto(url, &dropped);
    if (!dropped.isEmpty()) {
        qWarning("TelamonPortal: mailto: dropped %s (only subject and body are kept)", qPrintable(dropped.join(QLatin1Char(','))));
    }
    if (!QDesktopServices::openUrl(target)) {
        qWarning("TelamonPortal: nothing opened %s", qPrintable(url.toDisplayString().left(200)));
        return false;
    }
    return true;
}

bool TelamonPortal::validEventId(const QString &id)
{
    if (id.isEmpty() || id.size() > kMaxEventLength || id.at(0).isDigit()) {
        return false;
    }
    for (const QChar c : id) {
        if (c.unicode() > 0x7f || !c.isLetterOrNumber()) {
            return false;
        }
    }
    return true;
}

bool TelamonPortal::validIcon(const QString &icon)
{
    if (icon.isEmpty()) {
        return true;
    }
    if (icon.startsWith(QLatin1Char('/'))) {
        return !hasControl(icon) && !icon.split(QLatin1Char('/')).contains(QLatin1String(".."));
    }
    for (const QChar c : icon) {
        if (c.unicode() > 0x7f || !(c.isLetterOrNumber() || c == QLatin1Char('.') || c == QLatin1Char('_') || c == QLatin1Char('+') || c == QLatin1Char('-'))) {
            return false;
        }
    }
    return true;
}

bool TelamonPortal::validActionId(const QString &id)
{
    if (id.isEmpty() || id.size() > kMaxEventLength) {
        return false;
    }
    for (const QChar c : id) {
        if (c.unicode() > 0x7f || !(c.isLetterOrNumber() || c == QLatin1Char('.') || c == QLatin1Char('_') || c == QLatin1Char('-'))) {
            return false;
        }
    }
    return true;
}

QString TelamonPortal::escape(const QString &text) const
{
    QString out;
    out.reserve(text.size());
    for (const QChar c : text) {
        switch (c.unicode()) {
        case '&':
            out += QLatin1String("&amp;");
            break;
        case '<':
            out += QLatin1String("&lt;");
            break;
        case '>':
            out += QLatin1String("&gt;");
            break;
        case '"':
            out += QLatin1String("&quot;");
            break;
        case '\'':
            out += QLatin1String("&#39;");
            break;
        case '\n':
        case '\t':
            out += c;
            break;
        default:
            out += hasControl(QString(c)) ? QLatin1Char(' ') : c;
        }
    }
    return out;
}

// The user's choice in System Settings (<component>.notifyrc under the config
// dir): an event without Popup in its Action list is off. No file or no entry:
// on, as in the Rust crate. A choice made before 2.0.0, in the file named after
// the old component (atlas-<app>.notifyrc), counts while the new file has none
// for the event.
bool TelamonPortal::popupEnabled(const QString &event) const
{
    const QString dir = TelamonSettings::configDir();
    if (dir.isEmpty()) {
        return true;
    }
    const QString id = QGuiApplication::desktopFileName();
    const QStringList components = {TelamonSettings::shortName(id), TelamonSettings::legacyShortName(id)};
    for (const QString &component : components) {
        const QString file = dir + QLatin1Char('/') + component + QLatin1String(".notifyrc");
        const QFileInfo info(file);
        // Only a regular file: anything else could block the reader.
        if (!info.isFile()) {
            continue;
        }
        KConfig cfg(file, KConfig::SimpleConfig);
        const KConfigGroup g = cfg.group(QLatin1String("Event/") + event);
        if (!g.hasKey("Action")) {
            continue;
        }
        const QStringList actions = g.readEntry("Action", QString()).split(QLatin1Char('|'));
        for (const QString &a : actions) {
            if (a.trimmed() == QLatin1String("Popup")) {
                return true;
            }
        }
        return false;
    }
    return true;
}

void TelamonPortal::ensureConnected()
{
    if (m_connected) {
        return;
    }
    m_connected = true;
    QDBusConnection bus = QDBusConnection::sessionBus();
    // Only from the notification server's well-known name, so another
    // program cannot invent an action.
    bus.connect(QString::fromLatin1(kService), QString::fromLatin1(kPath), QString::fromLatin1(kInterface), QStringLiteral("ActionInvoked"), this, SLOT(onServerAction(uint, QString)));
    bus.connect(QString::fromLatin1(kService), QString::fromLatin1(kPath), QString::fromLatin1(kInterface), QStringLiteral("NotificationClosed"), this, SLOT(onServerClosed(uint, uint)));
    // A restarted server numbers from the start again: the old numbers would
    // match other notifications, so forget them when the server's owner goes.
    auto *owner = new QDBusServiceWatcher(QString::fromLatin1(kService), bus, QDBusServiceWatcher::WatchForOwnerChange, this);
    connect(owner, &QDBusServiceWatcher::serviceOwnerChanged, this, [this](const QString &, const QString &oldOwner, const QString &) {
        if (!oldOwner.isEmpty()) {
            ++m_ownerGeneration; // replies to Notify calls made before this are stale
            m_byServerId.clear();
            m_order.clear();
        }
    });
}

QString TelamonPortal::notify(const QString &title, const QString &body, const QVariantList &actions, const QVariantMap &options)
{
    const QString eventId = options.value(QStringLiteral("eventId"), QStringLiteral("notification")).toString();
    if (!validEventId(eventId)) {
        qWarning("TelamonPortal: notify: %s is not an event id (letters and digits, camelCase)", qPrintable(eventId.left(80)));
        return QString();
    }
    if (title.isEmpty() || title.size() > kMaxTextLength || body.size() > kMaxTextLength) {
        qWarning("TelamonPortal: notify: the title is empty, or the title or body is too long");
        return QString();
    }
    // Plain text unless the caller says it escaped the markup itself.
    const QString shownBody = options.value(QStringLiteral("markup")).toBool() ? body : escape(body);
    QStringList actionList;
    for (const QVariant &a : actions) {
        const QVariantMap m = a.toMap();
        const QString id = m.value(QStringLiteral("id")).toString();
        const QString text = m.value(QStringLiteral("text")).toString();
        if (!validActionId(id) || text.isEmpty() || text.size() > 200 || hasControl(text) || actionList.size() / 2 >= kMaxActions) {
            qWarning("TelamonPortal: notify: action %s skipped (bad id or text, or more than %d)", qPrintable(id.left(40)), kMaxActions);
            continue;
        }
        actionList << id << text;
    }
    if (!popupEnabled(eventId)) {
        return QString();
    }
    const QString appId = QGuiApplication::desktopFileName();
    QString icon = options.value(QStringLiteral("icon")).toString();
    if (icon.isEmpty() || !validIcon(icon)) {
        if (!icon.isEmpty()) {
            qWarning("TelamonPortal: notify %s: the icon is not a name or an absolute path; using the app icon", qPrintable(eventId));
        }
        icon = appId;
    }
    QString appName = QGuiApplication::applicationDisplayName();
    if (appName.isEmpty()) {
        appName = QGuiApplication::applicationName();
    }
    QVariantMap hints;
    hints.insert(QStringLiteral("desktop-entry"), appId);
    hints.insert(QStringLiteral("x-kde-appname"), TelamonSettings::shortName(appId));
    hints.insert(QStringLiteral("x-kde-eventId"), eventId);
    // Low or normal; the spec's critical has no place in Telamon OS apps. A
    // byte, as the spec says.
    const QString urgency = options.value(QStringLiteral("urgency")).toString();
    hints.insert(QStringLiteral("urgency"), QVariant::fromValue<uchar>(urgency == QLatin1String("low") ? 0 : 1));
    const int timeout = options.value(QStringLiteral("persistent")).toBool() ? 0 : -1;

    ensureConnected();
    QDBusMessage call = QDBusMessage::createMethodCall(QString::fromLatin1(kService), QString::fromLatin1(kPath), QString::fromLatin1(kInterface), QStringLiteral("Notify"));
    call << appName << uint(0) << icon << title << shownBody << actionList << hints << timeout;
    const QString ourId = QStringLiteral("telamon-notification-%1").arg(++m_counter);
    // Asynchronous: the UI thread never waits for the server.
    auto *watcher = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(call, kCallTimeoutMs), this);
    const uint generation = m_ownerGeneration;
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, ourId, eventId, generation](QDBusPendingCallWatcher *w) {
        w->deleteLater();
        const QDBusPendingReply<uint> reply = *w;
        if (reply.isError()) {
            qWarning("TelamonPortal: notification %s was not shown: %s", qPrintable(eventId), qPrintable(reply.error().message()));
            return;
        }
        // A server that restarted since the call numbers from the start again:
        // this id belongs to the old server and could match another notification.
        // Untested: it needs a fake notification server on a private bus.
        if (generation != m_ownerGeneration) {
            return;
        }
        const uint serverId = reply.value();
        if (m_byServerId.contains(serverId)) {
            m_order.removeOne(serverId); // the server reused a number
        }
        // The oldest goes first (a QHash has no order, so m_order keeps it).
        while (m_order.size() >= kMaxTracked) {
            m_byServerId.remove(m_order.takeFirst());
        }
        m_byServerId.insert(serverId, ourId);
        m_order.append(serverId);
    });
    return ourId;
}

void TelamonPortal::onServerAction(uint serverId, const QString &actionKey)
{
    const auto it = m_byServerId.constFind(serverId);
    if (it == m_byServerId.cend() || !validActionId(actionKey)) {
        return; // not ours (the signal goes to every program)
    }
    Q_EMIT actionInvoked(*it, actionKey);
}

void TelamonPortal::onServerClosed(uint serverId, uint)
{
    if (m_byServerId.remove(serverId)) {
        m_order.removeOne(serverId);
    }
}
