#include "fakeportal.h"

#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusError>
#include <QDBusMetaType>
#include <QFile>
#include <QMap>
#include <QStringList>
#include <QTimer>
#include <QVariantMap>

#include <cstdio>

namespace AtlasVariant {

using Settings = QMap<QString, QVariantMap>;

class Portal : public QObject
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.freedesktop.portal.Settings")
public:
    using QObject::QObject;

public slots:
    // Every namespace that was asked for (or all, when none), as the portal does.
    Settings ReadAll(const QStringList &namespaces)
    {
        Settings all;
        all.insert(QStringLiteral("org.freedesktop.appearance"),
                   {
                       {QStringLiteral("color-scheme"), 2u}, // prefer light
                       {QStringLiteral("contrast"), 1u}, // more contrast
                   });
        if (namespaces.isEmpty()) {
            return all;
        }
        Settings answer;
        for (const QString &ns : namespaces) {
            if (all.contains(ns)) {
                answer.insert(ns, all.value(ns));
            }
        }
        return answer;
    }
};

int runFakePortal(const QString &readyFile, int timeoutSeconds)
{
    qDBusRegisterMetaType<Settings>();
    QDBusConnection bus = QDBusConnection::sessionBus();
    Portal portal;
    if (!bus.isConnected() || !bus.registerService(QStringLiteral("org.freedesktop.portal.Desktop"))
        || !bus.registerObject(QStringLiteral("/org/freedesktop/portal/desktop"), &portal, QDBusConnection::ExportAllSlots)) {
        std::fprintf(stderr, "fake-portal: could not register on the session bus: %s\n", qPrintable(bus.lastError().message()));
        return 1;
    }
    // The bus going away (its session ended) ends the stand-in too.
    bus.connect(QString(), QStringLiteral("/org/freedesktop/DBus/Local"), QStringLiteral("org.freedesktop.DBus.Local"),
                QStringLiteral("Disconnected"), QCoreApplication::instance(), SLOT(quit()));
    if (timeoutSeconds > 0) {
        QTimer::singleShot(timeoutSeconds * 1000, QCoreApplication::instance(), &QCoreApplication::quit);
    }
    QFile ready(readyFile);
    if (!ready.open(QIODevice::WriteOnly)) {
        std::fprintf(stderr, "fake-portal: could not write %s\n", qPrintable(readyFile));
        return 1;
    }
    ready.close();
    return QCoreApplication::exec();
}

} // namespace AtlasVariant

#include "fakeportal.moc"
