// AtlasSettings: an app's own settings, in the file the Rust crate
// (atlas_framework_core::settings) reads and writes:
// `$XDG_CONFIG_HOME/atlas-<last part of AtlasApp.id>rc` (default ~/.config),
// KConfig's INI format, `[Atlas] Format=1`. Declare one per group:
//
//   AtlasSettings {
//       id: view
//       group: "View"
//   }
//   AtlasSwitch {
//       checked: view.value("ShowHidden", false)
//       onToggled: view.setValue("ShowHidden", checked)
//   }
//
// `value()` reads the file on first use, so a binding on a sibling that runs
// while the tree is built sees the saved value (a `group` or `fileName` set
// by a binding is not known yet then; set it as a literal).
// `value(key, defaultValue)` is typed by the default: a bool, int, real or
// string list default gives that type back (a stored value of another shape
// gives the default); anything else gives a string. `setValue` and `remove`
// are batched (a short timer, `flush()`, the end of the program) and written
// atomically (a temp file renamed over the file), under the same `flock` on
// `.<name>.lock` beside the file that the Rust crate takes, so a Rust writer
// and this one never lose each other's change. Keys the user or an admin
// marked immutable (`[$i]`) are refused. `changed(key)` comes when another
// process (the Rust crate, KDE tools, a text editor) changed a key of the
// group.
//
// A change that cannot be written when the group or file name changes is
// dropped with a warning, never moved into the other group or file. A file
// that is not a regular file, or is over 4 MB, is not read (defaults) and not
// written. Values are read as written: `$VARIABLE` expansion (`[$e]`) is not
// done. A new file is created with mode 0600. The lock is waited for at most
// 1 s.
//
// `group` is required; a name with brackets or control characters is refused.
// `fileName` is empty for the app's own file, or a bare file name in the
// config directory (no path). A settings file that is a symlink pointing out
// of the config directory is refused, so a link planted there cannot make the
// app write elsewhere. Every problem is logged with the file's name; nothing
// throws or aborts.
//
// Window sizes: `AtlasWindow.stateKey` saves the window by itself. An app
// saves a split view's sizes (a base64 string) or a sidebar's width the same
// way, under its own group:
//
//   AtlasSettings { id: layout; group: "Layout" }
//   AtlasSplitView {
//       Component.onCompleted: restoreSizes(layout.value("Split", ""))
//       onResizingChanged: if (!resizing) layout.setValue("Split", saveSizes())
//   }
//   AtlasSidebar {
//       width: layout.value("SidebarWidth", 240)
//       onWidthChanged: layout.setValue("SidebarWidth", width)
//   }
#pragma once

#include <QFileSystemWatcher>
#include <QHash>
#include <QObject>
#include <QQmlParserStatus>
#include <QString>
#include <QTimer>
#include <QVariant>
#include <memory>
#include <QtQml/qqmlregistration.h>

class KConfig;

class AtlasSettings : public QObject, public QQmlParserStatus
{
    Q_OBJECT
    Q_INTERFACES(QQmlParserStatus)
    QML_ELEMENT

    Q_PROPERTY(QString group READ group WRITE setGroup NOTIFY groupChanged FINAL)
    Q_PROPERTY(QString fileName READ fileName WRITE setFileName NOTIFY fileNameChanged FINAL)

public:
    explicit AtlasSettings(QObject *parent = nullptr);
    ~AtlasSettings() override;

    QString group() const { return m_group; }
    void setGroup(const QString &group);
    QString fileName() const { return m_fileName; }
    void setFileName(const QString &fileName);

    Q_INVOKABLE QVariant value(const QString &key, const QVariant &defaultValue = QVariant()) const;
    // False (and logged) for a bad group or key, a value that cannot be
    // stored, or an immutable key.
    Q_INVOKABLE bool setValue(const QString &key, const QVariant &value);
    Q_INVOKABLE bool remove(const QString &key);
    Q_INVOKABLE bool contains(const QString &key) const;
    // Writes what is waiting now. True when nothing is left unwritten.
    Q_INVOKABLE bool flush();

    // Rules shared with the tests and AtlasPortal.
    // The part of an app ID the file is named after ("atlas-updater"); the
    // same rule as AppInfo::short_name in the Rust crate.
    static QString shortName(const QString &appId);
    // $XDG_CONFIG_HOME if absolute, else $HOME/.config, else empty.
    static QString configDir();
    static bool validGroup(const QString &group);
    static bool validKey(const QString &key);
    static bool validFileName(const QString &name);
    // The file to use: `name` in `dir`, following a symlink only while it
    // stays inside `dir`. Empty, with `error` set, when it would leave.
    static QString resolve(const QString &dir, const QString &name, QString *error = nullptr);

    void classBegin() override { }
    void componentComplete() override;

Q_SIGNALS:
    void groupChanged();
    void fileNameChanged();
    // Another process changed `key` of the group in the file.
    void changed(const QString &key);

private:
    QString path() const; // empty when there is no usable file
    void reload(bool announce);
    void rewatch();
    void ensureLoaded() const;
    void fileTouched();
    void dropPending();
    void timedWrite();
    bool writePending(int lockWaitMs);
    QString m_group, m_fileName;
    bool m_complete = false;
    bool m_loaded = false; // the snapshot matches the current group and file
    // What the file held at the last read: raw entries of the group.
    QHash<QString, QString> m_snapshot;
    std::unique_ptr<KConfig> m_cfg;
    // Waiting to be written: a value, or an invalid QVariant for "remove".
    QHash<QString, QVariant> m_pending;
    QTimer m_writeTimer, m_watchTimer;
    // Timed-write backoff while another process holds the lock.
    int m_retryMs = 0, m_retryWaitedMs = 0;
    bool m_lockBusy = false;
    QFileSystemWatcher m_watcher;
    QMetaObject::Connection m_quitConnection;
};
