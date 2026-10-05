// AtlasPortal: what an app asks the desktop to do for it.
//
//   Button { onClicked: AtlasPortal.openUrl("https://example.com/help") }
//
//   const id = AtlasPortal.notify(qsTr("Update ready"), qsTr("Restart to finish."),
//       [{ id: "default", text: qsTr("Open") }, { id: "restart", text: qsTr("Restart") }],
//       { eventId: "updateStaged" })
//   Connections {
//       target: AtlasPortal
//       function onActionInvoked(notificationId, actionId) { ... }
//   }
//
// openUrl(url) opens a link with the user's default app (QDesktopServices,
// which goes through the OpenURI portal under Flatpak). It refuses, with a
// warning in the log and `false`, every URL that is not http or https (with a
// host), mailto (with an address; only its `subject` and `body` are kept, any
// other query key such as attach or bcc is dropped and logged), or file (a
// local path that exists; the real path behind symbolic links is checked, and
// a program, a launcher or any executable file is refused, by content and not
// by name; directories are fine). An app that really needs another scheme lists it in
// `extraSchemes`; the file and host rules still apply to the four above.
//
// notify(title, body, actions, options) shows a desktop notification over
// org.freedesktop.Notifications and returns its id at once ("" when nothing
// was sent: the user turned the event's popup off, or the arguments are bad).
// It follows the notification rules in docs/DESIGN.md, like the Rust crate's
// `notify`:
//  - `body` is plain text: the portal escapes it. `options.markup: true`
//    says the body is markup the caller has escaped (use escape() on
//    everything that came from outside); the server shows it as markup.
//  - `actions` is a list of `{id, text}`; the id "default" is a click on the
//    notification itself. At most 8, ids of letters, digits and `._-`.
//  - `options.eventId`: the notifyrc event, camelCase letters and digits
//    (default "notification"); the user's choice in System Settings is
//    honoured. The app ships `<short name>.notifyrc`.
//  - `options.urgency`: "low" or "normal" (default); anything else is normal.
//    No sounds.
//  - `options.persistent`: stays until the user acts; only when ignoring it has
//    consequences.
//  - `options.icon`: an icon name or an absolute path; anything else is the
//    app's own icon.
// `actionInvoked` comes when the user picks an action of a notification this
// app sent. The component name (`x-kde-appname`) and the desktop entry are
// derived from the app ID, the same as the Rust crate.
#pragma once

#include <QHash>
#include <QList>
#include <QObject>
#include <QStringList>
#include <QUrl>
#include <QVariant>
#include <QtQml/qqmlregistration.h>

class AtlasPortal : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    // Schemes openUrl accepts besides http, https, mailto and file.
    Q_PROPERTY(QStringList extraSchemes READ extraSchemes WRITE setExtraSchemes NOTIFY extraSchemesChanged FINAL)

public:
    explicit AtlasPortal(QObject *parent = nullptr);

    QStringList extraSchemes() const { return m_extraSchemes; }
    void setExtraSchemes(const QStringList &schemes);

    Q_INVOKABLE bool openUrl(const QUrl &url);
    Q_INVOKABLE QString notify(const QString &title, const QString &body, const QVariantList &actions = {}, const QVariantMap &options = {});
    // `text` safe to put in a notification body with `options.markup: true`
    // (markup characters escaped, control characters turned into spaces).
    Q_INVOKABLE QString escape(const QString &text) const;

    // The rule behind openUrl, without opening anything.
    static bool isOpenable(const QUrl &url, const QStringList &extraSchemes = {}, QString *why = nullptr);
    // `url` with, for mailto, every query key but subject and body removed
    // (their names go to `dropped`); any other URL as it is.
    static QUrl cleanMailto(const QUrl &url, QStringList *dropped = nullptr);
    static bool validEventId(const QString &id);
    static bool validIcon(const QString &icon);
    static bool validActionId(const QString &id);

Q_SIGNALS:
    void extraSchemesChanged();
    void actionInvoked(const QString &notificationId, const QString &actionId);

private Q_SLOTS:
    void onServerAction(uint serverId, const QString &actionKey);
    void onServerClosed(uint serverId, uint reason);

private:
    bool popupEnabled(const QString &event) const;
    void ensureConnected();
    bool m_connected = false;
    QStringList m_extraSchemes;
    qulonglong m_counter = 0;
    // The server's number for each notification this app sent -> our id.
    QHash<uint, QString> m_byServerId;
    // The same server ids, oldest first, for eviction.
    QList<uint> m_order;
};
