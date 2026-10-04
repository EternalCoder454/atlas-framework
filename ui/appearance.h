// Appearance: the look switches every Atlas app shares. `transparency` is
// the "Transparency effects" setting, `Transparency` under `[Appearance]` in
// `atlasrc` (default true). A KConfigWatcher keeps every open Atlas app in
// step when one of them, or the user, changes the file.
//
// `effective` is what a window acts on: the switch is on AND the compositor
// offers blur (it does not in software rendering or many VMs, or when KWin's
// blur effect is off). Nothing signals a change in the second, so call
// refresh() when a window is shown or activated (AtlasWindow does).
#pragma once

#include <KConfigWatcher>
#include <KSharedConfig>

#include <QObject>
#include <QWindow>
#include <QtQml/qqmlregistration.h>

class Appearance : public QObject
{
    Q_OBJECT
    QML_NAMED_ELEMENT(Appearance)
    QML_SINGLETON

    Q_PROPERTY(bool transparency READ transparency WRITE setTransparency NOTIFY transparencyChanged)
    Q_PROPERTY(bool blurAvailable READ blurAvailable NOTIFY blurAvailableChanged)
    Q_PROPERTY(bool effective READ effective NOTIFY effectiveChanged)

public:
    explicit Appearance(QObject *parent = nullptr);

    bool transparency() const { return m_transparency; }
    void setTransparency(bool on);
    bool blurAvailable() const { return m_blurAvailable; }
    bool effective() const { return m_transparency && m_blurAvailable; }

    // Ask the compositor again whether blur is on.
    Q_INVOKABLE void refresh();
    // Blur (or stop blurring) everything behind the whole window, following
    // `effective`. Needs the window to exist: call it once it is visible.
    Q_INVOKABLE void applyBlur(QWindow *window);

Q_SIGNALS:
    void transparencyChanged();
    void blurAvailableChanged();
    void effectiveChanged();

private:
    void reread();

    KSharedConfig::Ptr m_config;
    KConfigWatcher::Ptr m_watcher;
    bool m_transparency = true;
    bool m_blurAvailable = false;
};
