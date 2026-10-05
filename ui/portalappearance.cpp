#include "portalappearance.h"

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
    // A portal that starts later (or restarts) is read again.
    m_watcher = new QDBusServiceWatcher(m_service, m_bus, QDBusServiceWatcher::WatchForRegistration, this);
    connect(m_watcher, &QDBusServiceWatcher::serviceRegistered, this, [this] { readAll(); });
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

void PortalAppearance::readAll()
{
    QDBusMessage call = QDBusMessage::createMethodCall(m_service, QString::fromLatin1(kPath), QString::fromLatin1(kSettings), QStringLiteral("ReadAll"));
    call << QStringList{QString::fromLatin1(kNamespace)};
    auto *watcher = new QDBusPendingCallWatcher(m_bus.asyncCall(call, kCallTimeoutMs), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *w) {
        w->deleteLater();
        const QDBusMessage reply = w->reply();
        if (reply.type() != QDBusMessage::ReplyMessage) {
            // No portal, or one without this interface: the defaults stay.
            qDebug("PortalAppearance: ReadAll: %s", qPrintable(reply.errorMessage()));
            return;
        }
        // a{sa{sv}}: namespace -> key -> value.
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
        bool changed = false;
        int entries = 0;
        arg.beginMap();
        while (!arg.atEnd() && ++entries <= kMaxEntries) {
            QString ns;
            arg.beginMapEntry();
            arg >> ns;
            if (ns == QLatin1String(kNamespace) && arg.currentType() == QDBusArgument::MapType) {
                arg.beginMap();
                int keys = 0;
                while (!arg.atEnd() && ++keys <= kMaxEntries) {
                    QString key;
                    QDBusVariant value;
                    arg.beginMapEntry();
                    arg >> key >> value;
                    arg.endMapEntry();
                    changed |= apply(key, value.variant());
                }
                arg.endMap();
            } else {
                // Not ours: skip the entry's value.
                QVariantMap skip;
                arg >> skip;
            }
            arg.endMapEntry();
        }
        arg.endMap();
        if (changed) {
            Q_EMIT this->changed();
        }
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
    if (apply(args.at(1).toString(), args.at(2).value<QDBusVariant>().variant())) {
        Q_EMIT changed();
    }
}

// Returns whether a cached value changed.
bool PortalAppearance::apply(const QString &key, const QVariant &raw)
{
    const QVariant value = unwrap(raw);
    if (key == QLatin1String("contrast") || key == QLatin1String("reduced-motion")) {
        if (value.metaType() != QMetaType::fromType<uint>()) {
            qWarning("PortalAppearance: %s is not a number; ignored", qPrintable(key));
            return false;
        }
        const bool on = value.toUInt() == 1;
        bool &slot = key == QLatin1String("contrast") ? m_highContrast : m_reducedMotion;
        if (slot == on) {
            return false;
        }
        slot = on;
        return true;
    }
    if (key == QLatin1String("accent-color")) {
        QColor color; // invalid: none
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
                if (r >= 0 && r <= 1 && g >= 0 && g <= 1 && b >= 0 && b <= 1) {
                    color = QColor::fromRgbF(r, g, b);
                }
            } else {
                qWarning("PortalAppearance: accent-color has the wrong type; ignored");
                return false;
            }
        } else {
            qWarning("PortalAppearance: accent-color has the wrong type; ignored");
            return false;
        }
        if (color == m_accent && color.isValid() == m_accent.isValid()) {
            return false;
        }
        m_accent = color;
        return true;
    }
    return false;
}
