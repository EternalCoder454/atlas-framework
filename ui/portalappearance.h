// PortalAppearance: the desktop portal's org.freedesktop.appearance values
// that Appearance and AccessibilityState use (contrast, reduced-motion,
// accent-color), read once with ReadAll and followed through SettingChanged.
// Every value from the bus is type- and range-checked; without a portal the
// defaults stay. Described in docs/reference/telamon-ui/accessibility-state.md.
#pragma once

#include <QColor>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QObject>
#include <QPointer>
#include <QString>
#include <QTimer>

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
    struct Values {
        bool highContrast = false;
        bool reducedMotion = false;
        QColor accent;
    };
    void apply(const QString &key, const QVariant &value, Values &into);
    void commit(const Values &v);

    QDBusConnection m_bus;
    QString m_service;
    QDBusServiceWatcher *m_watcher = nullptr;
    qulonglong m_generation = 0;
    QTimer m_reread; // debounce: one read after a run of changes
    bool m_highContrast = false;
    bool m_reducedMotion = false;
    QColor m_accent;
};
