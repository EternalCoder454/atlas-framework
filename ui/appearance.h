// Appearance: the look switches every Atlas app shares. `transparency` is
// the "Transparency effects" setting, `Transparency` under `[Appearance]` in
// `atlasrc` (default true). A KConfigWatcher keeps every open Atlas app in
// step when one of them, or the user, changes the file.
//
// `effective` is what a window acts on: the switch is on AND the compositor
// offers blur (it does not in software rendering or many VMs, or when KWin's
// blur effect is off). Nothing signals a change in the second, so call
// refresh() when a window is shown or activated (AtlasWindow does).
//
// The read-only system preferences below follow the desktop live; each has a
// NOTIFY signal, so a binding on it updates when the user changes the setting:
//   colorScheme    the system colour scheme, an Appearance.ColorScheme value
//                  (UnknownScheme, LightScheme, DarkScheme; QStyleHints).
//   darkMode       colorScheme is Dark; when it is Unknown, whether the
//                  palette's window colour is dark.
//   highContrast   the system asks for high contrast (QStyleHints
//                  accessibility, Qt 6.10+).
//   reducedMotion  Plasma's AnimationDurationFactor in kdeglobals [KDE] is 0
//                  (animations off), or the environment has
//                  ATLAS_REDUCED_MOTION=1. Missing kdeglobals means false.
//   textScale      the application font's point size over 10 (Plasma's
//                  default), so 1.0 is the default size, 1.2 is 20% larger.
#pragma once

#include <KConfigWatcher>
#include <KSharedConfig>

#include <QFont>
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
    Q_PROPERTY(int colorScheme READ colorScheme NOTIFY colorSchemeChanged)
    Q_PROPERTY(bool darkMode READ darkMode NOTIFY darkModeChanged)
    Q_PROPERTY(bool highContrast READ highContrast NOTIFY highContrastChanged)
    Q_PROPERTY(bool reducedMotion READ reducedMotion NOTIFY reducedMotionChanged)
    Q_PROPERTY(qreal textScale READ textScale NOTIFY textScaleChanged)

public:
    enum ColorScheme {
        UnknownScheme,
        LightScheme,
        DarkScheme,
    };
    Q_ENUM(ColorScheme)

    explicit Appearance(QObject *parent = nullptr);

    bool transparency() const { return m_transparency; }
    void setTransparency(bool on);
    bool blurAvailable() const { return m_blurAvailable; }
    bool effective() const { return m_transparency && m_blurAvailable; }

    int colorScheme() const { return m_colorScheme; }
    bool darkMode() const { return m_darkMode; }
    bool highContrast() const { return m_highContrast; }
    bool reducedMotion() const { return m_reducedMotion; }
    qreal textScale() const { return m_textScale; }

    // Ask the compositor again whether blur is on.
    Q_INVOKABLE void refresh();
    // Blur (or stop blurring) everything behind the whole window, following
    // `effective`. Needs the window to exist: call it once it is visible.
    Q_INVOKABLE void applyBlur(QWindow *window);

Q_SIGNALS:
    void transparencyChanged();
    void blurAvailableChanged();
    void effectiveChanged();
    void colorSchemeChanged();
    void darkModeChanged();
    void highContrastChanged();
    void reducedMotionChanged();
    void textScaleChanged();

protected:
    bool eventFilter(QObject *watched, QEvent *event) override;

private:
    void reread();
    void readSystem();
    void readMotion();

    KSharedConfig::Ptr m_globals;
    KConfigWatcher::Ptr m_globalsWatcher;
    int m_colorScheme = UnknownScheme;
    bool m_darkMode = false;
    bool m_highContrast = false;
    bool m_reducedMotion = false;
    qreal m_textScale = 1.0;

    KSharedConfig::Ptr m_config;
    KConfigWatcher::Ptr m_watcher;
    bool m_transparency = true;
    bool m_blurAvailable = false;
};
