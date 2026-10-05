#include "portalappearance.h"

#include "portallog.h"

#include <QCoreApplication>
#include <QDBusArgument>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusServiceWatcher>
#include <QMetaType>
#include <QVariantMap>

namespace
{
constexpr auto kService = "org.freedesktop.portal.Desktop";
constexpr auto kPath = "/org/freedesktop/portal/desktop";
constexpr auto kSettings = "org.freedesktop.portal.Settings";
constexpr auto kNamespace = "org.freedesktop.appearance";
constexpr int kCallTimeoutMs = 10000;
// A reply bigger than this is not read (a real one is a few hundred bytes per
// namespace; this bounds what a hostile peer could make us walk).
constexpr int kMaxEntries = 256;

// A variant that came out of a D-Bus 'v' may be wrapped once more.
QVariant unwrap(QVariant v)
{
    for (int i = 0; i < 2 && v.metaType() == QMetaType::fromType<QDBusVariant>(); ++i) {
        v = v.value<QDBusVariant>().variant();
    }
    return v;
}
}

PortalAppearance::PortalAppearance(const QDBusConnection &bus, const QString &service, QObject *parent)
    : QObject(parent)
    , m_bus(bus)
    , m_service(service.isEmpty() ? QString::fromLatin1(kService) : service)
{
    if (!m_bus.isConnected()) {
        return;
    }
    m_bus.connect(m_service, QString::fromLatin1(kPath), QString::fromLatin1(kSettings), QStringLiteral("SettingChanged"), this, SLOT(onSettingChanged(QDBusMessage)));
    // A portal that starts later, restarts or is replaced is read again; one
    // that goes away takes its values with it.
    m_watcher = new QDBusServiceWatcher(m_service, m_bus, QDBusServiceWatcher::WatchForOwnerChange, this);
    connect(m_watcher, &QDBusServiceWatcher::serviceOwnerChanged, this, [this](const QString &, const QString &oldOwner, const QString &newOwner) {
        if (!oldOwner.isEmpty()) {
            commit(Values());
        }
        if (!newOwner.isEmpty()) {
            readAll();
        }
    });
    readAll();
}

PortalAppearance *PortalAppearance::shared()
{
    static QPointer<PortalAppearance> instance;
    if (!instance && QCoreApplication::instance()) {
        instance = new PortalAppearance(QDBusConnection::sessionBus(), QString(), QCoreApplication::instance());
    }
    return instance;
}

void PortalAppearance::commit(const Values &v)
{
    const bool same = v.highContrast == m_highContrast && v.reducedMotion == m_reducedMotion && v.accent == m_accent && v.accent.isValid() == m_accent.isValid();
    m_highContrast = v.highContrast;
    m_reducedMotion = v.reducedMotion;
    m_accent = v.accent;
    if (!same) {
        Q_EMIT changed();
    }
}

void PortalAppearance::readAll()
{
    QDBusMessage call = QDBusMessage::createMethodCall(m_service, QString::fromLatin1(kPath), QString::fromLatin1(kSettings), QStringLiteral("ReadAll"));
    call << QStringList{QString::fromLatin1(kNamespace)};
    const qulonglong gen = ++m_generation;
    auto *watcher = new QDBusPendingCallWatcher(m_bus.asyncCall(call, kCallTimeoutMs), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, gen](QDBusPendingCallWatcher *w) {
        w->deleteLater();
        if (gen != m_generation) {
            return; // a newer read is on its way
        }
        const QDBusMessage reply = w->reply();
        if (reply.type() != QDBusMessage::ReplyMessage) {
            // No portal, or one without this interface: the defaults.
            qDebug("PortalAppearance: ReadAll: %s", qPrintable(PortalLog::text(reply.errorMessage(), 200)));
            commit(Values());
            return;
        }
        // a{sa{sv}}: namespace -> key -> value. Parsed into a local; nothing
        // is kept unless the whole walk is clean.
        const QList<QVariant> args = reply.arguments();
        if (args.size() != 1 || !args.first().canConvert<QDBusArgument>()) {
            qWarning("PortalAppearance: ReadAll: an unexpected reply");
            return;
        }
        const QDBusArgument arg = args.first().value<QDBusArgument>();
        if (arg.currentType() != QDBusArgument::MapType) {
            qWarning("PortalAppearance: ReadAll: an unexpected reply");
            return;
        }
        Values v;
        int entries = 0;
        bool clean = true;
        arg.beginMap();
        while (!arg.atEnd()) {
            if (++entries > kMaxEntries) {
                clean = false;
                break;
            }
            QString ns;
            arg.beginMapEntry();
            arg >> ns;
            if (ns == QLatin1String(kNamespace) && arg.currentType() == QDBusArgument::MapType) {
                arg.beginMap();
                int keys = 0;
                while (!arg.atEnd()) {
                    if (++keys > kMaxEntries) {
                        clean = false;
                        break;
                    }
                    QString key;
                    QDBusVariant value;
                    arg.beginMapEntry();
                    arg >> key >> value;
                    arg.endMapEntry();
                    apply(key, value.variant(), v);
                }
                if (!clean) {
                    break;
                }
                arg.endMap();
            } else {
                // Not ours: skip the entry's value.
                QVariantMap skip;
                arg >> skip;
            }
            arg.endMapEntry();
        }
        if (!clean) {
            qWarning("PortalAppearance: ReadAll: too many entries; the reply is not used");
            return;
        }
        arg.endMap();
        commit(v);
    });
}

void PortalAppearance::onSettingChanged(const QDBusMessage &message)
{
    // (s namespace, s key, v value)
    const QList<QVariant> args = message.arguments();
    if (args.size() != 3 || args.at(0).userType() != QMetaType::QString || args.at(1).userType() != QMetaType::QString) {
        qWarning("PortalAppearance: SettingChanged: an unexpected message");
        return;
    }
    if (args.at(0).toString() != QLatin1String(kNamespace)) {
        return;
    }
    Values v{m_highContrast, m_reducedMotion, m_accent};
    apply(args.at(1).toString(), args.at(2).value<QDBusVariant>().variant(), v);
    commit(v);
}

// Puts one checked value into `v`; a value of the wrong type changes nothing.
void PortalAppearance::apply(const QString &key, const QVariant &raw, Values &v)
{
    const QVariant value = unwrap(raw);
    if (key == QLatin1String("contrast") || key == QLatin1String("reduced-motion")) {
        if (value.metaType() != QMetaType::fromType<uint>()) {
            qWarning("PortalAppearance: %s is not a number; ignored", qPrintable(PortalLog::text(key, 40)));
            return;
        }
        (key == QLatin1String("contrast") ? v.highContrast : v.reducedMotion) = value.toUInt() == 1;
        return;
    }
    if (key == QLatin1String("accent-color")) {
        if (value.canConvert<QDBusArgument>()) {
            const QDBusArgument arg = value.value<QDBusArgument>();
            if (arg.currentType() == QDBusArgument::StructureType && arg.currentSignature() == QLatin1String("(ddd)")) {
                double r = -1;
                double g = -1;
                double b = -1;
                arg.beginStructure();
                arg >> r >> g >> b;
                arg.endStructure();
                // Out of 0..1 (or NaN) means no accent, as the portal says.
                v.accent = r >= 0 && r <= 1 && g >= 0 && g <= 1 && b >= 0 && b <= 1 ? QColor::fromRgbF(r, g, b) : QColor();
                return;
            }
        }
        qWarning("PortalAppearance: accent-color has the wrong type; ignored");
    }
}
