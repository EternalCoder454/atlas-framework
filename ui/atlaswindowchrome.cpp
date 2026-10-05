#include "atlaswindowchrome.h"

#include <KConfigGroup>

#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCall>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>

namespace
{
constexpr auto kGroup = "org.kde.kdecoration2";
constexpr auto kRegistrar = "com.canonical.AppMenu.Registrar";
constexpr int kDBusTimeoutMs = 1000;
}

AtlasWindowChrome::AtlasWindowChrome(QObject *parent)
    : QObject(parent)
    , m_config(KSharedConfig::openConfig(QStringLiteral("kwinrc"), KConfig::NoGlobals))
{
    readButtons();
    m_watcher = KConfigWatcher::create(m_config);
    connect(m_watcher.data(), &KConfigWatcher::configChanged, this, [this](const KConfigGroup &group, const QByteArrayList &) {
        if (group.name() == QLatin1String(kGroup) || group.name().isEmpty()) {
            readButtons();
        }
    });

    QDBusConnection bus = QDBusConnection::sessionBus();
    if (bus.isConnected()) {
        m_serviceWatcher = new QDBusServiceWatcher(QLatin1String(kRegistrar), bus, QDBusServiceWatcher::WatchForOwnerChange, this);
        connect(m_serviceWatcher, &QDBusServiceWatcher::serviceOwnerChanged, this, [this](const QString &, const QString &, const QString &newOwner) {
            setGlobalMenu(!newOwner.isEmpty());
        });
        checkGlobalMenu();
    }
}

QStringList AtlasWindowChrome::parseButtons(const QString &letters)
{
    QStringList out;
    for (const QChar c : letters) {
        QString name;
        switch (c.unicode()) {
        case 'M':
            name = QStringLiteral("menu");
            break;
        case 'I':
            name = QStringLiteral("minimize");
            break;
        case 'A':
            name = QStringLiteral("maximize");
            break;
        case 'X':
            name = QStringLiteral("close");
            break;
        default:
            break;
        }
        if (!name.isEmpty() && !out.contains(name)) {
            out << name;
        }
    }
    return out;
}

void AtlasWindowChrome::readButtons()
{
    m_config->reparseConfiguration();
    const KConfigGroup group = m_config->group(QLatin1String(kGroup));
    QStringList left = parseButtons(group.readEntry("ButtonsOnLeft", QStringLiteral("M")));
    QStringList right = parseButtons(group.readEntry("ButtonsOnRight", QStringLiteral("HIAX")));
    // Without minimize, maximize or close anywhere, use KWin's default.
    const auto hasWindowButton = [](const QStringList &l) { return l.contains(QLatin1String("minimize")) || l.contains(QLatin1String("maximize")) || l.contains(QLatin1String("close")); };
    if (!hasWindowButton(left) && !hasWindowButton(right)) {
        right = parseButtons(QStringLiteral("IAX"));
    }
    if (left != m_left || right != m_right) {
        m_left = left;
        m_right = right;
        Q_EMIT buttonsChanged();
    }
}

void AtlasWindowChrome::checkGlobalMenu()
{
    QDBusMessage call = QDBusMessage::createMethodCall(QStringLiteral("org.freedesktop.DBus"),
                                                       QStringLiteral("/org/freedesktop/DBus"),
                                                       QStringLiteral("org.freedesktop.DBus"),
                                                       QStringLiteral("NameHasOwner"));
    call << QString::fromLatin1(kRegistrar);
    auto *watcher = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(call, kDBusTimeoutMs), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *w) {
        const QDBusPendingReply<bool> reply = *w;
        w->deleteLater();
        // An error (no bus, timeout) means: no global menu.
        if (reply.isValid()) {
            setGlobalMenu(reply.value());
        }
    });
}

void AtlasWindowChrome::setGlobalMenu(bool on)
{
    if (on != m_globalMenu) {
        m_globalMenu = on;
        Q_EMIT globalMenuChanged();
    }
}
