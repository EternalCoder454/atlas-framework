// PortalAppearance: the accessibility and accent settings of the desktop
// portal's org.freedesktop.appearance namespace (Settings interface, ReadAll
// once, then SettingChanged), cached:
//   contrast       1 = the user wants more contrast  -> highContrast
//   reduced-motion 1 = the user wants less motion    -> reducedMotion
//   accent-color   (ddd) red, green, blue in 0..1    -> accentColor (invalid
//                  when none, or when a value is out of range)
// Without a portal or a session bus nothing is read and every value stays at
// its default; nothing blocks (the calls are asynchronous with a timeout).
// Everything from the bus is checked: the type of each variant, and the range.
// Appearance and AccessibilityState share one instance (shared()).
#pragma once

#include <QColor>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QObject>
#include <QPointer>
#include <QString>

class QDBusServiceWatcher;

class PortalAppearance : public QObject
{
    Q_OBJECT

public:
    // Reads from `bus`, the portal at `service` (a test points both at a fake).
    explicit PortalAppearance(const QDBusConnection &bus, const QString &service = QString(), QObject *parent = nullptr);

    // The one for this process, on the session bus; null without an application.
    static PortalAppearance *shared();

    bool highContrast() const { return m_highContrast; }
    bool reducedMotion() const { return m_reducedMotion; }
    QColor accentColor() const { return m_accent; }

Q_SIGNALS:
    void changed();

private Q_SLOTS:
    void onSettingChanged(const QDBusMessage &message);

private:
    void readAll();
    // Takes one value (already checked to be an appearance key); false when its
    // type is wrong.
    bool apply(const QString &key, const QVariant &value);

    QDBusConnection m_bus;
    QString m_service;
    QDBusServiceWatcher *m_watcher = nullptr;
    bool m_highContrast = false;
    bool m_reducedMotion = false;
    QColor m_accent;
};
