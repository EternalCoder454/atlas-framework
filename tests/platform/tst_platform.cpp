// AtlasGlobalShortcut, PortalAppearance, Appearance and AccessibilityState
// against a fake desktop portal on a PRIVATE session bus: the test starts its
// own dbus-daemon (no service directories, so nothing can be activated on it),
// and points DBUS_SESSION_BUS_ADDRESS at it before the first use of the
// session bus. It never talks to the user's bus: it skips itself unless the
// session bus it ends up with has the same id as its private one. Compiled straight from the ui/ sources.
#include "accessibilitystate.h"
#include "appearance.h"
#include "atlasglobalshortcut.h"
#include "portalappearance.h"

#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusReply>
#include <QDBusObjectPath>
#include <QDBusVariant>
#include <QDBusVirtualObject>
#include <QGuiApplication>
#include <QProcess>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QTimer>
#include <QtTest>

namespace
{
const QString kPortal = QStringLiteral("org.freedesktop.portal.Desktop");
const QString kPortalPath = QStringLiteral("/org/freedesktop/portal/desktop");

QString senderPart(const QString &unique)
{
    QString s = unique;
    s.remove(QLatin1Char(':'));
    s.replace(QLatin1Char('.'), QLatin1Char('_'));
    return s;
}

QVariant colorStruct(double r, double g, double b)
{
    QDBusArgument arg;
    arg.beginStructure();
    arg << r << g << b;
    arg.endStructure();
    return QVariant::fromValue(arg);
}
}

class FakePortal : public QDBusVirtualObject
{
public:
    enum class Bind { Good, Malformed, WrongListType, BadResponseArgs, Silent, Cancelled };

    explicit FakePortal(const QDBusConnection &conn)
        : QDBusVirtualObject()
        , m_conn(conn)
    {
    }

    QString introspect(const QString &) const override { return QString(); }

    bool handleMessage(const QDBusMessage &msg, const QDBusConnection &) override
    {
        if (msg.type() != QDBusMessage::MethodCallMessage) {
            return false;
        }
        const QString iface = msg.interface();
        if (iface == QLatin1String("org.freedesktop.portal.GlobalShortcuts")) {
            if (msg.member() == QLatin1String("CreateSession")) {
                const QVariantMap options = qdbus_cast<QVariantMap>(msg.arguments().value(0).value<QDBusArgument>());
                const QString request = requestPath(msg, options);
                session = QStringLiteral("/org/freedesktop/portal/desktop/session/%1/%2").arg(senderPart(msg.service()), options.value(QStringLiteral("session_handle_token")).toString());
                ++creates;
                m_conn.send(msg.createReply(QVariant::fromValue(QDBusObjectPath(request))));
                respond(request, 0, QVariantMap{{QStringLiteral("session_handle"), session}});
                return true;
            }
            if (msg.member() == QLatin1String("BindShortcuts")) {
                const QList<QVariant> args = msg.arguments();
                const QVariantMap options = qdbus_cast<QVariantMap>(args.value(3).value<QDBusArgument>());
                lastBound = qdbus_cast<QList<PortalShortcut>>(args.value(1).value<QDBusArgument>());
                ++binds;
                const QString request = requestPath(msg, options);
                lastRequest = pendingRequest = request;
                m_conn.send(msg.createReply(QVariant::fromValue(QDBusObjectPath(request))));
                bindResponse(request);
                return true;
            }
        }
        if (iface == QLatin1String("org.freedesktop.portal.Session") && msg.member() == QLatin1String("Close")) {
            ++closes;
            m_conn.send(msg.createReply());
            return true;
        }
        if (iface == QLatin1String("org.freedesktop.portal.Settings") && msg.member() == QLatin1String("ReadAll")) {
            QMap<QString, QVariantMap> all;
            all.insert(QStringLiteral("org.freedesktop.appearance"), appearance);
            all.insert(QStringLiteral("org.example.other"), QVariantMap{{QStringLiteral("contrast"), QVariant::fromValue<uint>(1)}});
            m_conn.send(msg.createReply(QVariant::fromValue(all)));
            ++readAlls;
            return true;
        }
        return false;
    }

    void activate(const QString &sessionPath, const QVariant &id, bool on = true)
    {
        QDBusMessage s = QDBusMessage::createSignal(kPortalPath, QStringLiteral("org.freedesktop.portal.GlobalShortcuts"), on ? QStringLiteral("Activated") : QStringLiteral("Deactivated"));
        s << QVariant::fromValue(QDBusObjectPath(sessionPath)) << id << QVariant::fromValue<quint64>(1) << QVariantMap();
        m_conn.send(s);
    }

    void settingChanged(const QString &key, const QVariant &value, const QString &ns = QStringLiteral("org.freedesktop.appearance"))
    {
        QDBusMessage s = QDBusMessage::createSignal(kPortalPath, QStringLiteral("org.freedesktop.portal.Settings"), QStringLiteral("SettingChanged"));
        s << ns << key << QVariant::fromValue(QDBusVariant(value));
        m_conn.send(s);
    }

    void closeSession()
    {
        m_conn.send(QDBusMessage::createSignal(session, QStringLiteral("org.freedesktop.portal.Session"), QStringLiteral("Closed")));
    }

    // Answers the bind that was left unanswered (mode Silent) with `as`.
    void finishPending(Bind as)
    {
        const Bind before = mode;
        mode = as;
        bindResponse(pendingRequest);
        mode = before;
    }

    Bind mode = Bind::Good;
    QString triggerOverride; // sent as trigger_description when set
    QString lastRequest;
    int closes = 0;
    QString session;
    int creates = 0;
    int binds = 0;
    int readAlls = 0;
    QList<PortalShortcut> lastBound;
    QVariantMap appearance;

private:
    QString pendingRequest;

    QString requestPath(const QDBusMessage &msg, const QVariantMap &options) const
    {
        return QStringLiteral("/org/freedesktop/portal/desktop/request/%1/%2").arg(senderPart(msg.service()), options.value(QStringLiteral("handle_token")).toString());
    }

    void respond(const QString &request, uint code, const QVariantMap &results)
    {
        QDBusMessage s = QDBusMessage::createSignal(request, QStringLiteral("org.freedesktop.portal.Request"), QStringLiteral("Response"));
        s << QVariant::fromValue<uint>(code) << results;
        m_conn.send(s);
    }

    void bindResponse(const QString &request)
    {
        switch (mode) {
        case Bind::Silent:
            return;
        case Bind::Cancelled:
            respond(request, 1, {});
            return;
        case Bind::Malformed:
            respond(request, 0, QVariantMap{{QStringLiteral("shortcuts"), QStringLiteral("not a list")}});
            return;
        case Bind::WrongListType:
            respond(request, 0, QVariantMap{{QStringLiteral("shortcuts"), QVariant::fromValue(QList<int>{1, 2})}});
            return;
        case Bind::BadResponseArgs: {
            QDBusMessage s = QDBusMessage::createSignal(request, QStringLiteral("org.freedesktop.portal.Request"), QStringLiteral("Response"));
            s << QStringLiteral("garbage");
            m_conn.send(s);
            return;
        }
        case Bind::Good:
            break;
        }
        QList<PortalShortcut> out;
        for (const PortalShortcut &s : std::as_const(lastBound)) {
            PortalShortcut r;
            r.id = s.id;
            if (s.id == QLatin1String("badtrigger")) {
                r.properties.insert(QStringLiteral("trigger_description"), QVariant::fromValue<uint>(7));
            } else if (s.id != QLatin1String("refused")) {
                r.properties.insert(QStringLiteral("trigger_description"),
                                    triggerOverride.isEmpty() ? QStringLiteral("Press ") + s.properties.value(QStringLiteral("preferred_trigger")).toString() : triggerOverride);
            } else {
                continue;
            }
            out << r;
        }
        PortalShortcut intruder;
        intruder.id = QStringLiteral("intruder");
        intruder.properties.insert(QStringLiteral("trigger_description"), QStringLiteral("x"));
        out << intruder;
        PortalShortcut weird;
        weird.id = QStringLiteral("a b/../c");
        out << weird;
        respond(request, 0, QVariantMap{{QStringLiteral("shortcuts"), QVariant::fromValue(out)}});
    }

    QDBusConnection m_conn;
};

class TestPlatform : public QObject
{
    Q_OBJECT

    QProcess m_daemon;
    QTemporaryDir m_dir;
    QString m_address;
    QDBusConnection m_client{QStringLiteral("unset")};
    QDBusConnection m_fakeConn{QStringLiteral("unset")};
    QDBusConnection m_spoofer{QStringLiteral("unset")};
    FakePortal *m_portal = nullptr;

    void stopPortal()
    {
        if (!m_portal) {
            return;
        }
        m_fakeConn.unregisterService(kPortal);
        m_fakeConn.unregisterObject(kPortalPath);
        delete m_portal;
        m_portal = nullptr;
        flush(m_fakeConn);
    }

    // A blocking call: when it returns, everything sent on `conn` before has
    // reached the daemon.
    static QString flush(QDBusConnection conn)
    {
        const QDBusMessage call = QDBusMessage::createMethodCall(QStringLiteral("org.freedesktop.DBus"), QStringLiteral("/org/freedesktop/DBus"), QStringLiteral("org.freedesktop.DBus"),
                                                                 QStringLiteral("GetId"));
        const QDBusReply<QString> id = conn.call(call, QDBus::Block, 5000);
        return id.isValid() ? id.value() : QString();
    }

    void startPortal(const QVariantMap &appearance = {})
    {
        if (m_portal) {
            return;
        }
        m_portal = new FakePortal(m_fakeConn);
        m_portal->appearance = appearance;
        QVERIFY(m_fakeConn.registerVirtualObject(kPortalPath, m_portal, QDBusConnection::SubPath));
        QVERIFY(m_fakeConn.registerService(kPortal));
    }

    AtlasGlobalShortcut *item(const QString &name, const QString &trigger = QStringLiteral("Meta+Shift+M"), bool complete = true)
    {
        auto *s = new AtlasGlobalShortcut;
        s->setName(name);
        s->setDescription(QStringLiteral("Does %1").arg(name));
        s->setPreferredTrigger(trigger);
        if (complete) {
            s->componentComplete();
        }
        return s;
    }

private Q_SLOTS:
    void initTestCase()
    {
        QStandardPaths::setTestModeEnabled(true);
        QVERIFY(m_dir.isValid());
        QFile conf(m_dir.filePath(QStringLiteral("bus.conf")));
        QVERIFY(conf.open(QIODevice::WriteOnly));
        conf.write("<!DOCTYPE busconfig PUBLIC \"-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN\" "
                   "\"http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd\">\n"
                   "<busconfig><type>session</type><listen>unix:dir=");
        conf.write(m_dir.path().toUtf8());
        conf.write("</listen><auth>EXTERNAL</auth><policy context=\"default\">"
                   "<allow send_destination=\"*\" eavesdrop=\"true\"/><allow eavesdrop=\"true\"/><allow own=\"*\"/>"
                   "</policy></busconfig>\n");
        conf.close();
        m_daemon.start(QStringLiteral("dbus-daemon"), {QStringLiteral("--config-file=") + conf.fileName(), QStringLiteral("--nofork"), QStringLiteral("--print-address=1")});
        if (!m_daemon.waitForStarted(5000)) {
            QSKIP("no dbus-daemon to run a private bus");
        }
        QVERIFY(m_daemon.waitForReadyRead(10000));
        m_address = QString::fromUtf8(m_daemon.readLine()).trimmed();
        QVERIFY2(m_address.startsWith(QLatin1String("unix:")), qPrintable(m_address));
        // Before anything touches the session bus (the shared Appearance and
        // KConfigWatcher do): it is the private one from here on.
        qputenv("DBUS_SESSION_BUS_ADDRESS", m_address.toUtf8());
        m_client = QDBusConnection::connectToBus(m_address, QStringLiteral("client"));
        m_fakeConn = QDBusConnection::connectToBus(m_address, QStringLiteral("fake"));
        m_spoofer = QDBusConnection::connectToBus(m_address, QStringLiteral("spoofer"));
        QVERIFY(m_client.isConnected());
        QVERIFY(m_fakeConn.isConnected());
        QVERIFY(m_spoofer.isConnected());
        // The session bus the app's own code will use must be this private one.
        const QString privateId = flush(m_client);
        const QString sessionId = flush(QDBusConnection::sessionBus());
        if (privateId.isEmpty() || privateId != sessionId) {
            QSKIP("the session bus is not the private one; refusing to run against a real bus");
        }
    }

    void cleanupTestCase()
    {
        delete m_portal;
        m_portal = nullptr;
        m_daemon.terminate();
        if (!m_daemon.waitForFinished(3000)) {
            m_daemon.kill();
            m_daemon.waitForFinished(3000);
        }
    }

    // ---- AtlasGlobalShortcut ----

    void validNames()
    {
        QVERIFY(AtlasGlobalShortcut::validName(QStringLiteral("show-window_2.x")));
        QVERIFY(!AtlasGlobalShortcut::validName(QString()));
        QVERIFY(!AtlasGlobalShortcut::validName(QStringLiteral("a b")));
        QVERIFY(!AtlasGlobalShortcut::validName(QStringLiteral("a/b")));
        QVERIFY(!AtlasGlobalShortcut::validName(QStringLiteral("é")));
        QVERIFY(!AtlasGlobalShortcut::validName(QString(65, QLatin1Char('a'))));
    }

    void noSessionBus()
    {
        GlobalShortcutSession session(QDBusConnection(QStringLiteral("no-such-connection")), QString(), 500);
        GlobalShortcutSession::setShared(&session);
        std::unique_ptr<AtlasGlobalShortcut> s(item(QStringLiteral("a")));
        QTRY_VERIFY(!s->errorString().isEmpty());
        QVERIFY(!s->available());
        QVERIFY2(s->errorString().contains(QLatin1String("session bus")), qPrintable(s->errorString()));
        GlobalShortcutSession::setShared(nullptr);
    }

    void unavailableWithoutPortal()
    {
        // The portal is not on the bus yet.
        GlobalShortcutSession session(m_client, QString(), 500);
        GlobalShortcutSession::setShared(&session);
        std::unique_ptr<AtlasGlobalShortcut> s(item(QStringLiteral("a")));
        QVERIFY(!s->available());
        QVERIFY(s->errorString().isEmpty()); // nothing asked yet
        QTRY_VERIFY(!s->errorString().isEmpty());
        QVERIFY(!s->available());
        QVERIFY2(s->errorString().contains(QLatin1String("not running")), qPrintable(s->errorString()));
        QVERIFY(s->trigger().isEmpty());
        GlobalShortcutSession::setShared(nullptr);
    }

    void bindsInOneCall()
    {
        startPortal();
        GlobalShortcutSession session(m_client, QString(), 2000);
        GlobalShortcutSession::setShared(&session);
        m_portal->mode = FakePortal::Bind::Good;
        m_portal->creates = m_portal->binds = 0;
        std::unique_ptr<AtlasGlobalShortcut> a(item(QStringLiteral("one"), QStringLiteral("Meta+Shift+M")));
        std::unique_ptr<AtlasGlobalShortcut> b(item(QStringLiteral("two"), QString()));
        std::unique_ptr<AtlasGlobalShortcut> bad(item(QStringLiteral("badtrigger")));
        std::unique_ptr<AtlasGlobalShortcut> refused(item(QStringLiteral("refused")));
        QTRY_VERIFY(a->available());
        QVERIFY(b->available());
        QVERIFY(bad->available());
        QCOMPARE(m_portal->creates, 1);
        QCOMPARE(m_portal->binds, 1); // one call for all four
        QCOMPARE(m_portal->lastBound.size(), 4);
        QCOMPARE(a->trigger(), QStringLiteral("Press Meta+Shift+M"));
        QCOMPARE(a->errorString(), QString());
        QCOMPARE(b->trigger(), QStringLiteral("Press")); // no preferred trigger sent (the fake echoes ""; the text is trimmed)
        QVERIFY(bad->trigger().isEmpty());                // a wrong-typed trigger is ignored
        QVERIFY(!refused->available());
        QVERIFY(!refused->errorString().isEmpty());
        for (const PortalShortcut &s : std::as_const(m_portal->lastBound)) {
            if (s.id == QLatin1String("two")) {
                QVERIFY(!s.properties.contains(QStringLiteral("preferred_trigger")));
            }
            if (s.id == QLatin1String("one")) {
                QCOMPARE(s.properties.value(QStringLiteral("preferred_trigger")).toString(), QStringLiteral("Meta+Shift+M"));
                QCOMPARE(s.properties.value(QStringLiteral("description")).toString(), QStringLiteral("Does one"));
            }
        }

        // Activated and deactivated reach the right item only.
        QSignalSpy on(a.get(), &AtlasGlobalShortcut::activated);
        QSignalSpy off(a.get(), &AtlasGlobalShortcut::deactivated);
        QSignalSpy onB(b.get(), &AtlasGlobalShortcut::activated);
        m_portal->activate(m_portal->session, QStringLiteral("one"));
        QTRY_COMPARE(on.count(), 1);
        m_portal->activate(m_portal->session, QStringLiteral("one"), false);
        QTRY_COMPARE(off.count(), 1);
        QCOMPARE(onB.count(), 0);
        // Not ours: another session, an id nobody registered, a bad spelling,
        // a wrong type. None is delivered, none crashes.
        m_portal->activate(QStringLiteral("/org/freedesktop/portal/desktop/session/1_1/other"), QStringLiteral("one"));
        m_portal->activate(m_portal->session, QStringLiteral("intruder"));
        m_portal->activate(m_portal->session, QStringLiteral("a b/../c"));
        m_portal->activate(m_portal->session, QVariant::fromValue<uint>(5));
        m_portal->activate(m_portal->session, QStringLiteral("two")); // the sentinel: arrives after the rest
        QTRY_COMPARE(onB.count(), 1);
        QCOMPARE(on.count(), 1);
        QCOMPARE(off.count(), 1);

        // A shortcut declared later is bound with a second call, on the same session.
        std::unique_ptr<AtlasGlobalShortcut> late(item(QStringLiteral("late"), QStringLiteral("Meta+L")));
        QTRY_VERIFY(late->available());
        QCOMPARE(m_portal->creates, 1);
        QCOMPARE(m_portal->binds, 2);
        QCOMPARE(m_portal->lastBound.size(), 5);

        // A changed description is a new bind too.
        a->setDescription(QStringLiteral("Changed"));
        QTRY_COMPARE(m_portal->binds, 3);

        // The portal closes the session: unavailable, then a new one for the next change.
        m_portal->closeSession();
        QTRY_VERIFY(!a->available());
        QVERIFY(a->errorString().contains(QLatin1String("closed")));
        a->setPreferredTrigger(QStringLiteral("Meta+K"));
        QTRY_VERIFY(a->available());
        QCOMPARE(m_portal->creates, 2);
        GlobalShortcutSession::setShared(nullptr);
    }

    void badAndDuplicateNames()
    {
        startPortal();
        GlobalShortcutSession session(m_client, QString(), 2000);
        GlobalShortcutSession::setShared(&session);
        m_portal->mode = FakePortal::Bind::Good;
        m_portal->binds = 0;
        std::unique_ptr<AtlasGlobalShortcut> bad(item(QStringLiteral("has space")));
        QVERIFY(!bad->available());
        QVERIFY(!bad->errorString().isEmpty());
        std::unique_ptr<AtlasGlobalShortcut> a(item(QStringLiteral("dup")));
        std::unique_ptr<AtlasGlobalShortcut> b(item(QStringLiteral("dup")));
        QVERIFY(!b->errorString().isEmpty());
        QTRY_VERIFY(a->available());
        QVERIFY(!b->available());
        QCOMPARE(m_portal->binds, 1);
        QCOMPARE(m_portal->lastBound.size(), 1);
        // Renaming the second makes it real.
        b->setName(QStringLiteral("other"));
        QTRY_VERIFY(b->available());
        QCOMPARE(m_portal->lastBound.size(), 2);
        GlobalShortcutSession::setShared(nullptr);
    }

    void malformedReplies_data()
    {
        QTest::addColumn<int>("mode");
        QTest::newRow("shortcuts is a string") << int(FakePortal::Bind::Malformed);
        QTest::newRow("shortcuts is a list of numbers") << int(FakePortal::Bind::WrongListType);
        QTest::newRow("Response with the wrong arguments") << int(FakePortal::Bind::BadResponseArgs);
    }

    void malformedReplies()
    {
        QFETCH(int, mode);
        startPortal();
        GlobalShortcutSession session(m_client, QString(), 2000);
        GlobalShortcutSession::setShared(&session);
        m_portal->mode = static_cast<FakePortal::Bind>(mode);
        std::unique_ptr<AtlasGlobalShortcut> a(item(QStringLiteral("a")));
        QTRY_VERIFY(!a->errorString().isEmpty());
        QVERIFY(!a->available());
        QVERIFY2(a->errorString().contains(QLatin1String("could not be understood")), qPrintable(a->errorString()));
        // And it recovers when the portal behaves.
        m_portal->mode = FakePortal::Bind::Good;
        a->setDescription(QStringLiteral("again"));
        QTRY_VERIFY(a->available());
        GlobalShortcutSession::setShared(nullptr);
    }

    void cancelled()
    {
        startPortal();
        GlobalShortcutSession session(m_client, QString(), 2000);
        GlobalShortcutSession::setShared(&session);
        m_portal->mode = FakePortal::Bind::Cancelled;
        std::unique_ptr<AtlasGlobalShortcut> a(item(QStringLiteral("a")));
        QTRY_VERIFY(!a->errorString().isEmpty());
        QVERIFY(a->errorString().contains(QLatin1String("cancelled")));
        m_portal->mode = FakePortal::Bind::Good;
        GlobalShortcutSession::setShared(nullptr);
    }

    void timeout()
    {
        startPortal();
        GlobalShortcutSession session(m_client, QString(), 300);
        GlobalShortcutSession::setShared(&session);
        m_portal->mode = FakePortal::Bind::Silent;
        std::unique_ptr<AtlasGlobalShortcut> a(item(QStringLiteral("a")));
        QElapsedTimer t;
        t.start();
        QTRY_VERIFY_WITH_TIMEOUT(!a->errorString().isEmpty(), 5000);
        QVERIFY(t.elapsed() >= 250);
        QVERIFY(!a->available());
        QVERIFY2(a->errorString().contains(QLatin1String("in time")), qPrintable(a->errorString()));
        // A late answer to the abandoned request changes nothing.
        QTest::qWait(100);
        QVERIFY(!a->available());
        m_portal->mode = FakePortal::Bind::Good;
        GlobalShortcutSession::setShared(nullptr);
    }

    // ---- PortalAppearance, Appearance, AccessibilityState ----

    void portalAppearanceReadsAndFollows()
    {
        startPortal();
        m_portal->appearance = QVariantMap{
            {QStringLiteral("contrast"), QVariant::fromValue<uint>(1)},
            {QStringLiteral("reduced-motion"), QVariant::fromValue<uint>(0)},
            {QStringLiteral("accent-color"), colorStruct(1.0, 0.0, 0.0)},
            {QStringLiteral("color-scheme"), QVariant::fromValue<uint>(1)},
        };
        PortalAppearance p(m_client);
        QSignalSpy spy(&p, &PortalAppearance::changed);
        QTRY_VERIFY(p.highContrast());
        QVERIFY(!p.reducedMotion());
        QCOMPARE(p.accentColor(), QColor(Qt::red));

        m_portal->settingChanged(QStringLiteral("reduced-motion"), QVariant::fromValue<uint>(1));
        QTRY_VERIFY(p.reducedMotion());
        m_portal->settingChanged(QStringLiteral("contrast"), QVariant::fromValue<uint>(0));
        QTRY_VERIFY(!p.highContrast());
        // Out of range: no accent. Wrong type: ignored, nothing changes.
        m_portal->settingChanged(QStringLiteral("accent-color"), colorStruct(2.0, 0.0, 0.0));
        QTRY_VERIFY(!p.accentColor().isValid());
        m_portal->settingChanged(QStringLiteral("accent-color"), colorStruct(0.0, 1.0, 0.0));
        QTRY_COMPARE(p.accentColor(), QColor(Qt::green));
        const int before = spy.count();
        m_portal->settingChanged(QStringLiteral("contrast"), QStringLiteral("yes"));
        m_portal->settingChanged(QStringLiteral("accent-color"), QStringLiteral("red"));
        m_portal->settingChanged(QStringLiteral("contrast"), QVariant::fromValue<uint>(1), QStringLiteral("org.example.other"));
        m_portal->settingChanged(QStringLiteral("reduced-motion"), QVariant::fromValue<uint>(0)); // the sentinel
        QTRY_VERIFY(!p.reducedMotion());
        QCOMPARE(spy.count(), before + 1);
        QVERIFY(!p.highContrast());
        QCOMPARE(p.accentColor(), QColor(Qt::green));
    }

    void portalAppearanceWithoutPortal()
    {
        PortalAppearance none{QDBusConnection(QStringLiteral("no-such-connection"))};
        QVERIFY(!none.highContrast());
        QVERIFY(!none.reducedMotion());
        QVERIFY(!none.accentColor().isValid());
    }

    void appearanceAndAccessibilityStateFollowThePortal()
    {
        startPortal();
        m_portal->appearance = QVariantMap{
            {QStringLiteral("contrast"), QVariant::fromValue<uint>(1)},
            {QStringLiteral("reduced-motion"), QVariant::fromValue<uint>(1)},
            {QStringLiteral("accent-color"), colorStruct(0.0, 0.0, 1.0)},
        };
        Appearance appearance;
        AccessibilityState state;
        QSignalSpy contrast(&appearance, &Appearance::highContrastChanged);
        QSignalSpy motion(&appearance, &Appearance::reducedMotionChanged);
        QSignalSpy stateContrast(&state, &AccessibilityState::highContrastChanged);
        QTRY_VERIFY(appearance.highContrast());
        QTRY_VERIFY(appearance.reducedMotion());
        QTRY_VERIFY(state.highContrast());
        QVERIFY(state.reducedMotion());
        QCOMPARE(state.accentColor(), QColor(Qt::blue));

        m_portal->settingChanged(QStringLiteral("contrast"), QVariant::fromValue<uint>(0));
        m_portal->settingChanged(QStringLiteral("reduced-motion"), QVariant::fromValue<uint>(0));
        QTRY_VERIFY(!appearance.highContrast());
        QTRY_VERIFY(!appearance.reducedMotion());
        QTRY_VERIFY(!state.highContrast());
        QVERIFY(!state.reducedMotion());
        QVERIFY(contrast.count() >= 1);
        QVERIFY(motion.count() >= 1);
        QVERIFY(stateContrast.count() >= 2);

        // Qt's own preference is still honoured: the portal saying "no
        // preference" does not hide it (offscreen has none, so only the
        // portal's half is checked here).
        m_portal->settingChanged(QStringLiteral("contrast"), QVariant::fromValue<uint>(1));
        QTRY_VERIFY(appearance.highContrast());
    }

    // ---- spoofing, re-entrancy, teardown ----

    void forgedMessagesFromAnotherProgramAreIgnored()
    {
        // The portal is not on the bus when the session is made, and appears later.
        stopPortal();
        GlobalShortcutSession session(m_client, QString(), 3000);
        GlobalShortcutSession::setShared(&session);
        PortalAppearance appearance(m_client);
        std::unique_ptr<AtlasGlobalShortcut> a(item(QStringLiteral("a")));
        QSignalSpy activated(a.get(), &AtlasGlobalShortcut::activated);
        QTRY_VERIFY(!a->errorString().isEmpty());

        startPortal();
        m_portal->mode = FakePortal::Bind::Silent;
        QTRY_VERIFY(!m_portal->lastRequest.isEmpty()); // the bind is in flight, unanswered
        QTRY_COMPARE(m_portal->binds, 1);
        const QString request = m_portal->lastRequest;
        const QString sessionPath = m_portal->session;

        // The same messages the portal would send, from a program that is not the portal.
        PortalShortcut forged;
        forged.id = QStringLiteral("a");
        forged.properties.insert(QStringLiteral("trigger_description"), QStringLiteral("forged"));
        QDBusMessage response = QDBusMessage::createSignal(request, QStringLiteral("org.freedesktop.portal.Request"), QStringLiteral("Response"));
        response << QVariant::fromValue<uint>(0) << QVariantMap{{QStringLiteral("shortcuts"), QVariant::fromValue(QList<PortalShortcut>{forged})}};
        m_spoofer.send(response);
        QDBusMessage press = QDBusMessage::createSignal(kPortalPath, QStringLiteral("org.freedesktop.portal.GlobalShortcuts"), QStringLiteral("Activated"));
        press << QVariant::fromValue(QDBusObjectPath(sessionPath)) << QStringLiteral("a") << QVariant::fromValue<quint64>(1) << QVariantMap();
        m_spoofer.send(press);
        QDBusMessage setting = QDBusMessage::createSignal(kPortalPath, QStringLiteral("org.freedesktop.portal.Settings"), QStringLiteral("SettingChanged"));
        setting << QStringLiteral("org.freedesktop.appearance") << QStringLiteral("contrast") << QVariant::fromValue(QDBusVariant(QVariant::fromValue<uint>(1)));
        m_spoofer.send(setting);
        QVERIFY(!flush(m_spoofer).isEmpty());
        // A sentinel from the real portal, sent after all three.
        m_portal->settingChanged(QStringLiteral("reduced-motion"), QVariant::fromValue<uint>(1));
        QTRY_VERIFY(appearance.reducedMotion());
        QTest::qWait(50);
        QVERIFY(!appearance.highContrast());
        QCOMPARE(activated.count(), 0);
        QVERIFY(!a->available());
        QVERIFY(a->trigger().isEmpty());

        // The real answer still works, and the real press.
        m_portal->finishPending(FakePortal::Bind::Good);
        QTRY_VERIFY(a->available());
        QCOMPARE(a->trigger(), QStringLiteral("Press Meta+Shift+M"));
        m_portal->activate(sessionPath, QStringLiteral("a"));
        QTRY_COMPARE(activated.count(), 1);
        // And a forged press after binding is still not delivered.
        m_spoofer.send(press);
        QVERIFY(!flush(m_spoofer).isEmpty());
        m_portal->activate(sessionPath, QStringLiteral("a"));
        QTRY_COMPARE(activated.count(), 2);
        m_portal->mode = FakePortal::Bind::Good;
        GlobalShortcutSession::setShared(nullptr);
    }

    void handlersMayRenameAndDeleteItems_data()
    {
        QTest::addColumn<int>("mode");
        QTest::newRow("while every shortcut is failed") << int(FakePortal::Bind::Cancelled);
        QTest::newRow("while a bind result is applied") << int(FakePortal::Bind::Good);
    }

    void handlersMayRenameAndDeleteItems()
    {
        QFETCH(int, mode);
        startPortal();
        m_portal->binds = 0;
        GlobalShortcutSession session(m_client, QString(), 2000);
        GlobalShortcutSession::setShared(&session);
        m_portal->mode = static_cast<FakePortal::Bind>(mode);
        QPointer<AtlasGlobalShortcut> a = item(QStringLiteral("a"), QString(), false);
        QPointer<AtlasGlobalShortcut> victim = item(QStringLiteral("victim"), QString(), false);
        QPointer<AtlasGlobalShortcut> renamed = item(QStringLiteral("renamed-soon"), QString(), false);
        QPointer<AtlasGlobalShortcut> other = item(QStringLiteral("other"), QString(), false);
        int calls = 0;
        const auto handler = [&] {
            ++calls;
            delete victim.data();
            if (renamed) {
                renamed->setName(QStringLiteral("renamed"));
            }
        };
        connect(a.data(), &AtlasGlobalShortcut::errorStringChanged, a.data(), handler);
        connect(a.data(), &AtlasGlobalShortcut::availableChanged, a.data(), handler);
        for (AtlasGlobalShortcut *s : {a.data(), victim.data(), renamed.data(), other.data()}) {
            s->componentComplete(); // all four in one turn, so one bind
        }
        QTRY_VERIFY(calls >= 1);
        QVERIFY(!victim);
        QCOMPARE(renamed->name(), QStringLiteral("renamed"));
        if (mode == int(FakePortal::Bind::Good)) {
            // The renamed item is bound again under its new name.
            QTRY_VERIFY(renamed->available());
            QVERIFY(other->available());
            QTRY_COMPARE(m_portal->binds, 2);
            bool found = false;
            for (const PortalShortcut &p : std::as_const(m_portal->lastBound)) {
                QVERIFY(p.id != QLatin1String("victim"));
                found |= p.id == QLatin1String("renamed");
            }
            QVERIFY(found);
        } else {
            QVERIFY(!other->errorString().isEmpty());
        }
        delete a.data();
        delete renamed.data();
        delete other.data();
        m_portal->mode = FakePortal::Bind::Good;
        GlobalShortcutSession::setShared(nullptr);
    }

    void failedBindClosesTheSession()
    {
        startPortal();
        GlobalShortcutSession session(m_client, QString(), 2000);
        GlobalShortcutSession::setShared(&session);
        m_portal->mode = FakePortal::Bind::Malformed;
        m_portal->closes = 0;
        m_portal->creates = 0;
        std::unique_ptr<AtlasGlobalShortcut> a(item(QStringLiteral("a")));
        QTRY_VERIFY(!a->errorString().isEmpty());
        QTRY_COMPARE(m_portal->closes, 1);
        // The next try makes a new session.
        m_portal->mode = FakePortal::Bind::Good;
        a->setDescription(QStringLiteral("again"));
        QTRY_VERIFY(a->available());
        QCOMPARE(m_portal->creates, 2);
        GlobalShortcutSession::setShared(nullptr);
    }

    void closesTheSessionAtTeardown()
    {
        startPortal();
        m_portal->closes = 0;
        {
            GlobalShortcutSession session(m_client, QString(), 2000);
            GlobalShortcutSession::setShared(&session);
            std::unique_ptr<AtlasGlobalShortcut> a(item(QStringLiteral("a")));
            QTRY_VERIFY(a->available());
            GlobalShortcutSession::setShared(nullptr);
        }
        QVERIFY(!flush(m_client).isEmpty());
        QTRY_COMPARE(m_portal->closes, 1);
    }

    void textFromThePortalIsCleaned()
    {
        startPortal();
        GlobalShortcutSession session(m_client, QString(), 2000);
        GlobalShortcutSession::setShared(&session);
        // A bidi override, a zero-width space, a line separator and a newline.
        m_portal->triggerOverride = QStringLiteral("Meta‮+X​ \ny");
        std::unique_ptr<AtlasGlobalShortcut> a(item(QStringLiteral("a")));
        QTRY_VERIFY(a->available());
        QCOMPARE(a->trigger(), QStringLiteral("Meta+Xy"));
        m_portal->triggerOverride.clear();
        GlobalShortcutSession::setShared(nullptr);
    }

    void portalAppearanceForgetsWhatIsGone()
    {
        stopPortal();
        startPortal(QVariantMap{{QStringLiteral("contrast"), QVariant::fromValue<uint>(1)}, {QStringLiteral("accent-color"), colorStruct(1.0, 0.0, 0.0)}});
        PortalAppearance p(m_client);
        QTRY_VERIFY(p.highContrast());
        QVERIFY(p.accentColor().isValid());
        QSignalSpy spy(&p, &PortalAppearance::changed);
        // A portal that comes back with nothing set: a new read resets everything.
        stopPortal();
        startPortal();
        QTRY_VERIFY(!p.highContrast());
        QVERIFY(!p.accentColor().isValid());
        QCOMPARE(spy.count(), 1);
        // And one that reads the same again changes nothing.
        stopPortal();
        startPortal();
        QTRY_VERIFY(m_portal->readAlls >= 1);
        QTest::qWait(100);
        QCOMPARE(spy.count(), 1);
    }
};

QTEST_MAIN(TestPlatform)
#include "tst_platform.moc"
