// AtlasGlobalShortcut: a system-wide shortcut through the desktop portal's
// GlobalShortcuts interface. Behaviour and API: docs/reference/atlas-ui/atlas-global-shortcut.md.
// GlobalShortcutSession (below) is the implementation: one portal session per
// app, one bind call per event-loop turn, every reply checked.
#pragma once

#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QHash>
#include <QObject>
#include <QPointer>
#include <QSet>
#include <QQmlParserStatus>
#include <QTimer>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

class GlobalShortcutSession;

class AtlasGlobalShortcut : public QObject, public QQmlParserStatus
{
    Q_OBJECT
    Q_INTERFACES(QQmlParserStatus)
    QML_ELEMENT

    Q_PROPERTY(QString name READ name WRITE setName NOTIFY nameChanged FINAL)
    Q_PROPERTY(QString description READ description WRITE setDescription NOTIFY descriptionChanged FINAL)
    Q_PROPERTY(QString preferredTrigger READ preferredTrigger WRITE setPreferredTrigger NOTIFY preferredTriggerChanged FINAL)
    Q_PROPERTY(QString trigger READ trigger NOTIFY triggerChanged FINAL)
    Q_PROPERTY(bool available READ available NOTIFY availableChanged FINAL)
    Q_PROPERTY(QString errorString READ errorString NOTIFY errorStringChanged FINAL)

public:
    explicit AtlasGlobalShortcut(QObject *parent = nullptr);
    ~AtlasGlobalShortcut() override;

    QString name() const { return m_name; }
    void setName(const QString &name);
    QString description() const { return m_description; }
    void setDescription(const QString &text);
    QString preferredTrigger() const { return m_preferredTrigger; }
    void setPreferredTrigger(const QString &trigger);
    QString trigger() const { return m_trigger; }
    bool available() const { return m_available; }
    QString errorString() const { return m_errorString; }

    static bool validName(const QString &name);

    void classBegin() override {}
    void componentComplete() override;

Q_SIGNALS:
    void nameChanged();
    void descriptionChanged();
    void preferredTriggerChanged();
    void triggerChanged();
    void availableChanged();
    void errorStringChanged();
    void activated();
    void deactivated();

private:
    friend class GlobalShortcutSession;
    void changedWhileLive();
    // What the session reports (not API).
    void setState(bool available, const QString &error, const QString &trigger);

    QString m_name;
    QString m_description;
    QString m_preferredTrigger;
    QString m_trigger;
    QString m_errorString;
    bool m_available = false;
    bool m_complete = false;
    // The name under which the session knows this item, "" when it does not.
    QString m_registeredName;
    QPointer<GlobalShortcutSession> m_session;
};

// One entry of the portal's a(sa{sv}) list.
struct PortalShortcut {
    QString id;
    QVariantMap properties;
};
Q_DECLARE_METATYPE(PortalShortcut)
QDBusArgument &operator<<(QDBusArgument &arg, const PortalShortcut &s);
const QDBusArgument &operator>>(const QDBusArgument &arg, PortalShortcut &s);

// The app's one portal session: creates it, binds every registered shortcut
// with one call, and hands the portal's activations to the right item. The
// plugin uses shared(); a test makes its own on a private bus and passes it to
// setShared().
class GlobalShortcutSession : public QObject
{
    Q_OBJECT

public:
    // `service` is the portal's well-known name; `responseTimeoutMs` how long a
    // Request's Response is waited for (the call itself has its own timeout).
    GlobalShortcutSession(const QDBusConnection &bus, const QString &service, int responseTimeoutMs, QObject *parent = nullptr);

    ~GlobalShortcutSession() override;

    static GlobalShortcutSession *shared();
    // For tests: replaces the shared session (not owned); nullptr goes back to
    // the default.
    // For tests only: items of the session it replaces keep raw pointers to it.
    static void setShared(GlobalShortcutSession *session);

    // Tests: the first retry after a failure waits this long (default 2000).
    void setRetryBaseMs(int ms) { m_retryBaseMs = ms; }
    // Tests: how long a session must live before it counts as healthy (default 60 s).
    void setStableMs(int ms) { m_stableMs = ms; }
    bool retryPending() const { return m_retry.isActive(); }
    int failures() const { return m_failures; }
    // Closes the session and stops all work; the app is quitting.
    void shutdown();

    void sync(AtlasGlobalShortcut *item);
    void remove(AtlasGlobalShortcut *item);

private Q_SLOTS:
    void onResponse(const QDBusMessage &message);
    void onActivated(const QDBusMessage &message);
    void onDeactivated(const QDBusMessage &message);
    void onSessionClosed(const QDBusMessage &message);

private:
    enum class Kind { None, CreateSession, Bind };

    void schedule();
    void run();
    void send(Kind kind, const QString &method, const QList<QVariant> &args, QVariantMap options);
    void finishRequest();
    void fail(const QString &why);
    void failAll(const QString &why);
    void onSessionResults(const QVariantMap &results);
    void onBindResults(const QVariantMap &results);
    void route(const QDBusMessage &message, bool active);
    QString requestPath(const QString &token) const;
    QString senderPart() const;
    void sendClose(const QString &path);
    void dropSession(bool close);
    QList<QPointer<AtlasGlobalShortcut>> snapshot() const;
    void scheduleRetry();
    void retryRefused();
    QString expectedSession() const;

    QDBusConnection m_bus;
    QString m_service;
    int m_responseTimeoutMs;
    QHash<QString, AtlasGlobalShortcut *> m_items;
    QString m_session;
    QString m_sessionToken;
    Kind m_kind = Kind::None;
    QString m_path;
    QString m_actualPath;
    QTimer m_timeout;
    QTimer m_retry;
    int m_failures = 0;
    int m_retryBaseMs = 2000;
    int m_stableMs = 60000;
    // Running while the session is younger than m_stableMs; when it fires the
    // failures are forgotten.
    QTimer m_stable;
    bool m_shutdown = false;
    // The names in the bind call in flight or last answered.
    QSet<QString> m_sent;
    // Items refused for a duplicate name: tried again when the name is free.
    QList<QPointer<AtlasGlobalShortcut>> m_refused;
    bool m_scheduled = false;
    bool m_dirty = false;
    qulonglong m_counter = 0;
};
