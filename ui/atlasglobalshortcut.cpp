#include "atlasglobalshortcut.h"

#include "portallog.h"

#include <QCoreApplication>
#include <QDBusArgument>
#include <QDBusError>
#include <QDBusMetaType>
#include <QDBusObjectPath>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusServiceWatcher>
#include <QDBusVariant>
#include <QMetaObject>
#include <QStringList>

namespace
{
constexpr auto kService = "org.freedesktop.portal.Desktop";
constexpr auto kPath = "/org/freedesktop/portal/desktop";
constexpr auto kShortcuts = "org.freedesktop.portal.GlobalShortcuts";
constexpr auto kRequest = "org.freedesktop.portal.Request";
constexpr auto kSession = "org.freedesktop.portal.Session";
constexpr auto kSessionPrefix = "/org/freedesktop/portal/desktop/session/";
constexpr int kCallTimeoutMs = 10000;
// The user may have to answer a dialog on some desktops.
constexpr int kResponseTimeoutMs = 60000;
constexpr int kMaxNameLength = 64;
constexpr int kMaxDescriptionLength = 200;
constexpr int kMaxTriggerLength = 64;
// More shortcuts than this in one reply are not read.
constexpr int kMaxShortcuts = 1024;

QString clean(const QString &text, int max)
{
    return PortalLog::clean(text, max);
}

QVariant unwrap(QVariant v)
{
    for (int i = 0; i < 2 && v.metaType() == QMetaType::fromType<QDBusVariant>(); ++i) {
        v = v.value<QDBusVariant>().variant();
    }
    return v;
}

QPointer<GlobalShortcutSession> &overrideSession()
{
    static QPointer<GlobalShortcutSession> p;
    return p;
}

// A D-Bus object path: / and [A-Za-z0-9_], no empty element, no trailing /.
bool validPath(const QString &path)
{
    if (path.size() > 256 || !path.startsWith(QLatin1Char('/')) || path.endsWith(QLatin1Char('/')) || path.contains(QLatin1String("//"))) {
        return false;
    }
    for (const QChar c : path) {
        const ushort u = c.unicode();
        if (!((u >= 'a' && u <= 'z') || (u >= 'A' && u <= 'Z') || (u >= '0' && u <= '9') || u == '_' || u == '/')) {
            return false;
        }
    }
    return true;
}

void registerTypes()
{
    static bool done = false;
    if (!done) {
        done = true;
        qDBusRegisterMetaType<PortalShortcut>();
        qDBusRegisterMetaType<QList<PortalShortcut>>();
    }
}
}

QDBusArgument &operator<<(QDBusArgument &arg, const PortalShortcut &s)
{
    arg.beginStructure();
    arg << s.id << s.properties;
    arg.endStructure();
    return arg;
}

const QDBusArgument &operator>>(const QDBusArgument &arg, PortalShortcut &s)
{
    arg.beginStructure();
    arg >> s.id >> s.properties;
    arg.endStructure();
    return arg;
}

// ---- AtlasGlobalShortcut ---------------------------------------------------

AtlasGlobalShortcut::AtlasGlobalShortcut(QObject *parent)
    : QObject(parent)
{
}

AtlasGlobalShortcut::~AtlasGlobalShortcut()
{
    if (m_session) {
        m_session->remove(this);
    }
}

bool AtlasGlobalShortcut::validName(const QString &name)
{
    if (name.isEmpty() || name.size() > kMaxNameLength) {
        return false;
    }
    for (const QChar c : name) {
        const ushort u = c.unicode();
        const bool ok = (u >= 'a' && u <= 'z') || (u >= 'A' && u <= 'Z') || (u >= '0' && u <= '9') || u == '_' || u == '.' || u == '-';
        if (!ok) {
            return false;
        }
    }
    return true;
}

void AtlasGlobalShortcut::setName(const QString &name)
{
    if (name == m_name) {
        return;
    }
    const QPointer<AtlasGlobalShortcut> self(this);
    m_name = name;
    Q_EMIT nameChanged();
    if (!self) {
        return;
    }
    changedWhileLive();
}

void AtlasGlobalShortcut::setDescription(const QString &text)
{
    if (text == m_description) {
        return;
    }
    const QPointer<AtlasGlobalShortcut> self(this);
    m_description = text;
    Q_EMIT descriptionChanged();
    if (!self) {
        return;
    }
    changedWhileLive();
}

void AtlasGlobalShortcut::setPreferredTrigger(const QString &trigger)
{
    if (trigger == m_preferredTrigger) {
        return;
    }
    const QPointer<AtlasGlobalShortcut> self(this);
    m_preferredTrigger = trigger;
    Q_EMIT preferredTriggerChanged();
    if (!self) {
        return;
    }
    changedWhileLive();
}

void AtlasGlobalShortcut::componentComplete()
{
    m_complete = true;
    changedWhileLive();
}

void AtlasGlobalShortcut::changedWhileLive()
{
    if (!m_complete) {
        return;
    }
    GlobalShortcutSession *session = GlobalShortcutSession::shared();
    if (!session) {
        setState(false, tr("Global shortcuts need a running application."), QString());
        return;
    }
    m_session = session;
    session->sync(this);
}

void AtlasGlobalShortcut::setState(bool available, const QString &error, const QString &trigger)
{
    // A handler of these signals may delete this item: stop at once if so.
    const QPointer<AtlasGlobalShortcut> self(this);
    const bool wasAvailable = m_available;
    const bool errorChanged = error != m_errorString;
    const bool triggerChanged = trigger != m_trigger;
    m_available = available;
    m_errorString = error;
    m_trigger = trigger;
    if (triggerChanged) {
        Q_EMIT this->triggerChanged();
        if (!self) {
            return;
        }
    }
    if (errorChanged) {
        Q_EMIT errorStringChanged();
        if (!self) {
            return;
        }
    }
    if (wasAvailable != available) {
        Q_EMIT availableChanged();
    }
}

// ---- GlobalShortcutSession -------------------------------------------------

GlobalShortcutSession::GlobalShortcutSession(const QDBusConnection &bus, const QString &service, int responseTimeoutMs, QObject *parent)
    : QObject(parent)
    , m_bus(bus)
    , m_service(service.isEmpty() ? QString::fromLatin1(kService) : service)
    , m_responseTimeoutMs(responseTimeoutMs > 0 ? responseTimeoutMs : kResponseTimeoutMs)
{
    registerTypes();
    m_timeout.setSingleShot(true);
    connect(&m_timeout, &QTimer::timeout, this, [this] { fail(tr("The desktop did not answer the shortcut request in time.")); });
    m_retry.setSingleShot(true);
    connect(&m_retry, &QTimer::timeout, this, [this] { schedule(); });
    if (QCoreApplication::instance()) {
        connect(QCoreApplication::instance(), &QCoreApplication::aboutToQuit, this, &GlobalShortcutSession::shutdown);
    }
    if (!m_bus.isConnected()) {
        return;
    }
    // Only from the portal's own name: another program cannot press a key for us.
    m_bus.connect(m_service, QString::fromLatin1(kPath), QString::fromLatin1(kShortcuts), QStringLiteral("Activated"), this, SLOT(onActivated(QDBusMessage)));
    m_bus.connect(m_service, QString::fromLatin1(kPath), QString::fromLatin1(kShortcuts), QStringLiteral("Deactivated"), this, SLOT(onDeactivated(QDBusMessage)));
    auto *watcher = new QDBusServiceWatcher(m_service, m_bus, QDBusServiceWatcher::WatchForOwnerChange, this);
    connect(watcher, &QDBusServiceWatcher::serviceOwnerChanged, this, [this](const QString &, const QString &oldOwner, const QString &newOwner) {
        if (!oldOwner.isEmpty()) {
            // The portal is gone, and its session with it.
            if (m_kind != Kind::None) {
                finishRequest();
            }
            dropSession(false); // the session went with the portal: nothing to close
            failAll(tr("The desktop portal stopped."));
        }
        if (!newOwner.isEmpty() && !m_items.isEmpty()) {
            schedule();
        }
    });
}

void GlobalShortcutSession::shutdown()
{
    m_shutdown = true;
    m_retry.stop();
    if (m_kind != Kind::None) {
        finishRequest();
    }
    dropSession(true);
}

GlobalShortcutSession::~GlobalShortcutSession()
{
    dropSession(true);
}

GlobalShortcutSession *GlobalShortcutSession::shared()
{
    if (overrideSession()) {
        return overrideSession();
    }
    static QPointer<GlobalShortcutSession> instance;
    if (!instance && QCoreApplication::instance()) {
        instance = new GlobalShortcutSession(QDBusConnection::sessionBus(), QString(), kResponseTimeoutMs, QCoreApplication::instance());
    }
    return instance;
}

void GlobalShortcutSession::setShared(GlobalShortcutSession *session)
{
    overrideSession() = session;
}

void GlobalShortcutSession::sync(AtlasGlobalShortcut *item)
{
    // Handlers of the state signals may delete the item: from here on only
    // copies of its name are used after setState.
    const QString name = item->name();
    const QPointer<AtlasGlobalShortcut> self(item);
    m_refused.removeAll(self);
    m_failures = 0;
    // Forget the old name first: it may have changed.
    if (!item->m_registeredName.isEmpty() && m_items.value(item->m_registeredName) == item) {
        m_items.remove(item->m_registeredName);
        QMetaObject::invokeMethod(this, &GlobalShortcutSession::retryRefused, Qt::QueuedConnection);
    }
    item->m_registeredName.clear();
    if (!AtlasGlobalShortcut::validName(name)) {
        qWarning("AtlasGlobalShortcut: %s is not a valid name", qPrintable(PortalLog::text(name, 80)));
        item->setState(false, tr("The name of a global shortcut is letters, digits, \".\", \"_\" and \"-\", at most %1 characters.").arg(kMaxNameLength), QString());
        return;
    }
    if (m_items.contains(name)) {
        qWarning("AtlasGlobalShortcut: the name %s is used twice", qPrintable(PortalLog::text(name, 80)));
        m_refused.append(self);
        item->setState(false, tr("Another global shortcut in this app already has the name \"%1\".").arg(name), QString());
        return;
    }
    m_items.insert(name, item);
    item->m_registeredName = name;
    schedule();
}

void GlobalShortcutSession::remove(AtlasGlobalShortcut *item)
{
    m_refused.removeAll(QPointer<AtlasGlobalShortcut>(item));
    if (!item->m_registeredName.isEmpty() && m_items.value(item->m_registeredName) == item) {
        m_items.remove(item->m_registeredName);
        QMetaObject::invokeMethod(this, &GlobalShortcutSession::retryRefused, Qt::QueuedConnection);
    }
    item->m_registeredName.clear();
}

// A name that was taken may be free now: the items refused for it ask again.
void GlobalShortcutSession::retryRefused()
{
    const QList<QPointer<AtlasGlobalShortcut>> waiting = m_refused;
    for (const QPointer<AtlasGlobalShortcut> &item : waiting) {
        if (!item) {
            m_refused.removeAll(item);
        } else if (!m_items.contains(item->name())) {
            sync(item); // takes it off the list
        }
    }
}

void GlobalShortcutSession::scheduleRetry()
{
    if (m_shutdown || m_items.isEmpty() || m_failures >= 5) {
        return;
    }
    // 2 s, 4 s, 8 s, 16 s, 32 s.
    m_retry.start(m_retryBaseMs << m_failures);
    ++m_failures;
}

// Everything declared in this turn of the event loop goes into one bind.
void GlobalShortcutSession::schedule()
{
    if (m_scheduled || m_shutdown) {
        return;
    }
    m_scheduled = true;
    QMetaObject::invokeMethod(this, &GlobalShortcutSession::run, Qt::QueuedConnection);
}

void GlobalShortcutSession::run()
{
    m_scheduled = false;
    if (m_items.isEmpty()) {
        return;
    }
    if (m_kind != Kind::None) {
        m_dirty = true; // bound again when the call in flight is done
        return;
    }
    if (!m_bus.isConnected()) {
        failAll(tr("Global shortcuts are not available: there is no session bus."));
        return;
    }
    if (m_session.isEmpty()) {
        QVariantMap options;
        m_sessionToken = QStringLiteral("atlas_session_%1").arg(++m_counter);
        options.insert(QStringLiteral("session_handle_token"), m_sessionToken);
        send(Kind::CreateSession, QStringLiteral("CreateSession"), {}, options);
        return;
    }
    QList<PortalShortcut> list;
    const QStringList names = m_items.keys();
    m_sent = QSet<QString>(names.cbegin(), names.cend());
    for (const QString &name : names) {
        const AtlasGlobalShortcut *item = m_items.value(name);
        PortalShortcut s;
        s.id = name;
        const QString description = clean(item->description(), kMaxDescriptionLength);
        s.properties.insert(QStringLiteral("description"), description.isEmpty() ? name : description);
        const QString trigger = clean(item->preferredTrigger(), kMaxTriggerLength);
        if (!trigger.isEmpty()) {
            s.properties.insert(QStringLiteral("preferred_trigger"), trigger);
        }
        list << s;
    }
    send(Kind::Bind, QStringLiteral("BindShortcuts"), {QVariant::fromValue(QDBusObjectPath(m_session)), QVariant::fromValue(list), QString()}, {});
}

// ":1.42" -> "1_42", the part of a Request's path that names the caller.
QString GlobalShortcutSession::senderPart() const
{
    QString sender = m_bus.baseService();
    sender.remove(QLatin1Char(':'));
    sender.replace(QLatin1Char('.'), QLatin1Char('_'));
    return sender;
}

QString GlobalShortcutSession::expectedSession() const
{
    return QString::fromLatin1(kSessionPrefix) + senderPart() + QLatin1Char('/') + m_sessionToken;
}

QString GlobalShortcutSession::requestPath(const QString &token) const
{
    return QStringLiteral("/org/freedesktop/portal/desktop/request/%1/%2").arg(senderPart(), token);
}

// Asks the portal to end a session; nobody waits for the answer.
void GlobalShortcutSession::sendClose(const QString &path)
{
    // Only a session path of ours, and never start the portal for this.
    if (!m_bus.isConnected() || !validPath(path) || !path.startsWith(QString::fromLatin1(kSessionPrefix) + senderPart() + QLatin1Char('/'))) {
        return;
    }
    QDBusMessage call = QDBusMessage::createMethodCall(m_service, path, QString::fromLatin1(kSession), QStringLiteral("Close"));
    call.setAutoStartService(false);
    auto *watcher = new QDBusPendingCallWatcher(m_bus.asyncCall(call, kCallTimeoutMs), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, watcher, &QObject::deleteLater);
}

// Forgets the session; `close` also tells the portal (not when the portal is gone).
void GlobalShortcutSession::dropSession(bool close)
{
    if (m_session.isEmpty()) {
        return;
    }
    const QString path = m_session;
    m_session.clear();
    m_bus.disconnect(m_service, path, QString::fromLatin1(kSession), QStringLiteral("Closed"), this, SLOT(onSessionClosed(QDBusMessage)));
    if (close) {
        sendClose(path);
    }
}

void GlobalShortcutSession::send(Kind kind, const QString &method, const QList<QVariant> &args, QVariantMap options)
{
    const qulonglong gen = ++m_counter;
    const QString token = QStringLiteral("atlas_req_%1").arg(gen);
    options.insert(QStringLiteral("handle_token"), token);
    m_kind = kind;
    m_path = requestPath(token);
    m_actualPath.clear();
    // Subscribe first: the portal may answer before the call returns.
    m_bus.connect(m_service, m_path, QString::fromLatin1(kRequest), QStringLiteral("Response"), this, SLOT(onResponse(QDBusMessage)));
    QDBusMessage call = QDBusMessage::createMethodCall(m_service, QString::fromLatin1(kPath), QString::fromLatin1(kShortcuts), method);
    for (const QVariant &a : args) {
        call << a;
    }
    call << options;
    m_timeout.start(m_responseTimeoutMs);
    auto *watcher = new QDBusPendingCallWatcher(m_bus.asyncCall(call, kCallTimeoutMs), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, gen](QDBusPendingCallWatcher *w) {
        w->deleteLater();
        if (gen != m_counter || m_kind == Kind::None) {
            return; // the Response already came, or the request was given up on
        }
        const QDBusMessage reply = w->reply();
        if (reply.type() != QDBusMessage::ReplyMessage) {
            const QDBusError error = w->error();
            QString why;
            switch (error.type()) {
            case QDBusError::ServiceUnknown:
                why = tr("Global shortcuts are not available: the desktop portal is not running.");
                break;
            case QDBusError::UnknownMethod:
            case QDBusError::UnknownInterface:
            case QDBusError::UnknownObject:
            case QDBusError::NotSupported:
                why = tr("This desktop does not offer global shortcuts.");
                break;
            case QDBusError::NoReply:
            case QDBusError::Timeout:
                why = tr("The desktop portal did not answer.");
                break;
            default:
                why = tr("The desktop portal refused the request: %1").arg(clean(error.message(), 200));
            }
            qWarning("AtlasGlobalShortcut: %s failed: %s", qPrintable(PortalLog::text(error.name())), qPrintable(PortalLog::text(error.message(), 200)));
            fail(why);
            return;
        }
        // A portal that does not use the predictable path says where it will answer.
        const QList<QVariant> out = reply.arguments();
        if (out.size() == 1 && out.first().metaType() == QMetaType::fromType<QDBusObjectPath>()) {
            const QString actual = out.first().value<QDBusObjectPath>().path();
            // Only a request of ours: .../request/<our sender>/<a token>.
            const QString ours = QStringLiteral("/org/freedesktop/portal/desktop/request/%1/").arg(senderPart());
            if (actual != m_path && actual.startsWith(ours) && validPath(actual)) {
                m_actualPath = actual;
                m_bus.connect(m_service, actual, QString::fromLatin1(kRequest), QStringLiteral("Response"), this, SLOT(onResponse(QDBusMessage)));
            }
        }
    });
}

void GlobalShortcutSession::finishRequest()
{
    m_timeout.stop();
    m_bus.disconnect(m_service, m_path, QString::fromLatin1(kRequest), QStringLiteral("Response"), this, SLOT(onResponse(QDBusMessage)));
    if (!m_actualPath.isEmpty()) {
        m_bus.disconnect(m_service, m_actualPath, QString::fromLatin1(kRequest), QStringLiteral("Response"), this, SLOT(onResponse(QDBusMessage)));
    }
    m_kind = Kind::None;
    m_path.clear();
    m_actualPath.clear();
}

QList<QPointer<AtlasGlobalShortcut>> GlobalShortcutSession::snapshot() const
{
    QList<QPointer<AtlasGlobalShortcut>> out;
    out.reserve(m_items.size());
    for (AtlasGlobalShortcut *item : m_items) {
        out << item;
    }
    return out;
}

void GlobalShortcutSession::failAll(const QString &why)
{
    // Handlers of the signals may rename or delete items: walk a copy.
    for (const QPointer<AtlasGlobalShortcut> &item : snapshot()) {
        if (item) {
            item->setState(false, why, QString());
        }
    }
}

void GlobalShortcutSession::fail(const QString &why)
{
    const Kind was = m_kind;
    finishRequest();
    // A CreateSession that gave up may still be made by the portal, late.
    if (was == Kind::CreateSession && !m_sessionToken.isEmpty()) {
        sendClose(expectedSession());
    }
    // Whatever went wrong, start from a new session next time.
    dropSession(true);
    m_dirty = false;
    failAll(why);
    scheduleRetry();
}

void GlobalShortcutSession::onResponse(const QDBusMessage &message)
{
    if (m_kind == Kind::None || (message.path() != m_path && message.path() != m_actualPath)) {
        return;
    }
    const Kind kind = m_kind;
    const QList<QVariant> args = message.arguments();
    if (args.size() != 2 || args.at(0).metaType() != QMetaType::fromType<uint>() || !args.at(1).canConvert<QDBusArgument>()) {
        qWarning("AtlasGlobalShortcut: a malformed Response");
        fail(tr("The desktop sent an answer that could not be understood."));
        return;
    }
    const QDBusArgument resultsArg = args.at(1).value<QDBusArgument>();
    if (resultsArg.currentSignature() != QLatin1String("a{sv}")) {
        qWarning("AtlasGlobalShortcut: a Response with results of the wrong type");
        fail(tr("The desktop sent an answer that could not be understood."));
        return;
    }
    const uint code = args.at(0).toUInt();
    if (code != 0) {
        fail(code == 1 ? tr("The shortcut request was cancelled.") : tr("The desktop could not set up global shortcuts."));
        return;
    }
    const QVariantMap results = qdbus_cast<QVariantMap>(resultsArg);
    finishRequest();
    if (kind == Kind::CreateSession) {
        onSessionResults(results);
    } else {
        onBindResults(results);
    }
}

void GlobalShortcutSession::onSessionResults(const QVariantMap &results)
{
    const QVariant handle = unwrap(results.value(QStringLiteral("session_handle")));
    QString path;
    if (handle.metaType() == QMetaType::fromType<QString>()) {
        path = handle.toString();
    } else if (handle.metaType() == QMetaType::fromType<QDBusObjectPath>()) {
        path = handle.value<QDBusObjectPath>().path();
    }
    // The portal's rule: .../session/<our sender>/<the token we sent>.
    if (path != expectedSession()) {
        qWarning("AtlasGlobalShortcut: the session handle %s is not the one asked for", qPrintable(PortalLog::text(path, 120)));
        // A session the portal may have made all the same: do not leave it open.
        if (path.startsWith(QLatin1String(kSessionPrefix))) {
            sendClose(path);
        }
        fail(tr("The desktop sent an answer that could not be understood."));
        return;
    }
    m_session = path;
    m_bus.connect(m_service, m_session, QString::fromLatin1(kSession), QStringLiteral("Closed"), this, SLOT(onSessionClosed(QDBusMessage)));
    m_dirty = false;
    run();
}

void GlobalShortcutSession::onBindResults(const QVariantMap &results)
{
    const QVariant list = unwrap(results.value(QStringLiteral("shortcuts")));
    QHash<QString, QString> bound; // id -> trigger description
    if (!list.canConvert<QDBusArgument>()) {
        qWarning("AtlasGlobalShortcut: the bind reply has no shortcuts list");
        fail(tr("The desktop sent an answer that could not be understood."));
        return;
    }
    const QDBusArgument arg = list.value<QDBusArgument>();
    if (arg.currentSignature() != QLatin1String("a(sa{sv})")) {
        qWarning("AtlasGlobalShortcut: the shortcuts list is %s", qPrintable(PortalLog::text(arg.currentSignature(), 40)));
        fail(tr("The desktop sent an answer that could not be understood."));
        return;
    }
    const QList<PortalShortcut> shortcuts = qdbus_cast<QList<PortalShortcut>>(arg);
    int seen = 0;
    for (const PortalShortcut &s : shortcuts) {
        if (++seen > kMaxShortcuts) {
            break;
        }
        // Only ids this app registered, however they are spelled.
        if (!AtlasGlobalShortcut::validName(s.id) || !m_sent.contains(s.id) || !m_items.contains(s.id)) {
            qWarning("AtlasGlobalShortcut: the portal reported a shortcut this app has not registered: %s", qPrintable(PortalLog::text(s.id, 80)));
            continue;
        }
        QString trigger;
        const QVariant t = unwrap(s.properties.value(QStringLiteral("trigger_description")));
        if (t.metaType() == QMetaType::fromType<QString>()) {
            trigger = clean(t.toString(), 200);
        } else if (t.isValid()) {
            qWarning("AtlasGlobalShortcut: trigger_description of %s is not a string", qPrintable(PortalLog::text(s.id, 80)));
        }
        bound.insert(s.id, trigger);
    }
    // Work out every result first, then apply them: a handler may change m_items.
    struct Result {
        QPointer<AtlasGlobalShortcut> item;
        bool ok;
        QString trigger;
    };
    QList<Result> outcome;
    for (auto it = m_items.cbegin(); it != m_items.cend(); ++it) {
        if (!m_sent.contains(it.key())) {
            continue; // added or renamed since the call: the next bind answers for it
        }
        const auto b = bound.constFind(it.key());
        outcome.append({it.value(), b != bound.cend(), b != bound.cend() ? *b : QString()});
    }
    const QPointer<GlobalShortcutSession> self(this);
    m_failures = 0;
    m_retry.stop();
    for (const Result &r : std::as_const(outcome)) {
        if (!r.item) {
            continue;
        }
        if (r.ok) {
            r.item->setState(true, QString(), r.trigger);
        } else {
            r.item->setState(false, tr("The desktop did not accept this shortcut."), QString());
        }
    }
    if (self && m_dirty) {
        m_dirty = false;
        schedule();
    }
}

void GlobalShortcutSession::onSessionClosed(const QDBusMessage &message)
{
    if (m_session.isEmpty() || message.path() != m_session) {
        return;
    }
    dropSession(false); // it is closed already
    if (m_kind != Kind::None) {
        // An answer to a request on the old session would bind nothing.
        finishRequest();
    }
    failAll(tr("The desktop closed the shortcuts session."));
    // A new session, without anyone having to edit a property.
    schedule();
}

void GlobalShortcutSession::onActivated(const QDBusMessage &message)
{
    route(message, true);
}

void GlobalShortcutSession::onDeactivated(const QDBusMessage &message)
{
    route(message, false);
}

// (o session_handle, s shortcut_id, t timestamp, a{sv} options)
void GlobalShortcutSession::route(const QDBusMessage &message, bool active)
{
    const QList<QVariant> args = message.arguments();
    if (m_session.isEmpty() || args.size() < 2 || args.at(0).metaType() != QMetaType::fromType<QDBusObjectPath>() || args.at(1).metaType() != QMetaType::fromType<QString>()) {
        return;
    }
    if (args.at(0).value<QDBusObjectPath>().path() != m_session) {
        return; // another app's session
    }
    const QString id = args.at(1).toString();
    AtlasGlobalShortcut *item = AtlasGlobalShortcut::validName(id) ? m_items.value(id) : nullptr;
    if (!item) {
        return;
    }
    if (active) {
        Q_EMIT item->activated();
    } else {
        Q_EMIT item->deactivated();
    }
}
