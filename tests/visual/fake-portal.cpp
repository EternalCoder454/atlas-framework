// A stand-in for xdg-desktop-portal, for the visual-contrast variant only.
// Qt reads "the user wants high contrast" from the settings portal
// (org.freedesktop.appearance, key "contrast"); there is no other switch, so
// the test serves that one answer on its private session bus. run-variant.sh
// starts it, waits for the file named by argv[1], and the app then runs with
// QT_QPA_PLATFORMTHEME=xdgdesktopportal.
//
//   fake-portal <ready-file>
#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusError>
#include <QDBusMetaType>
#include <QFile>
#include <QMap>
#include <QStringList>
#include <QVariantMap>

#include <cstdio>

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

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    if (argc != 2) {
        std::fprintf(stderr, "usage: fake-portal <ready-file>\n");
        return 2;
    }
    qDBusRegisterMetaType<Settings>();
    QDBusConnection bus = QDBusConnection::sessionBus();
    Portal portal;
    if (!bus.isConnected() || !bus.registerService(QStringLiteral("org.freedesktop.portal.Desktop"))
        || !bus.registerObject(QStringLiteral("/org/freedesktop/portal/desktop"), &portal,
                               QDBusConnection::ExportAllSlots)) {
        std::fprintf(stderr, "fake-portal: could not register on the session bus: %s\n", qPrintable(bus.lastError().message()));
        return 1;
    }
    QFile ready(QString::fromLocal8Bit(argv[1]));
    if (!ready.open(QIODevice::WriteOnly)) {
        std::fprintf(stderr, "fake-portal: could not write %s\n", argv[1]);
        return 1;
    }
    ready.close();
    return app.exec();
}

#include "fake-portal.moc"
