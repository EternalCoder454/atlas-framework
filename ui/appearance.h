// Appearance: the look switches every Atlas app shares. `transparency` is
// the "Transparency and blur" setting, `Transparency` under `[Appearance]` in
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
//                  accessibility, Qt 6.10+, or the portal's `contrast`).
//   reducedMotion  Plasma's AnimationDurationFactor in kdeglobals [KDE] is 0
//                  (animations off), or the environment has
//                  ATLAS_REDUCED_MOTION=1, or the portal's `reduced-motion`
//                  (since 1.5.0). Missing kdeglobals means false.
//   softwareRendering  rendering is in software: the Qt Quick software
//                  adaptation, or OpenGL or Vulkan on a software rasterizer
//                  (GL_RENDERER or the Vulkan device named llvmpipe, softpipe,
//                  SwiftShader or lavapipe). Known once the first frame is
//                  drawn, so it changes at most once, false to true.
//                  ATLAS_SOFTWARE_RENDERING=1 or =0 forces it (anything else
//                  is logged and ignored).
//   textScale      the application font's point size over 10 (Plasma's
//                  default), so 1.0 is the default size, 1.2 is 20% larger. Kept
//                  between 0.5 and 4.
//
// The Atlas brand (since 1.4.0), set once when Atlas.Ui loads:
//   accentFromSystem  the user chose an accent colour in Plasma (AccentColor
//                  in kdeglobals [General]). Then that accent is used; if not,
//                  the Atlas violet (and magenta-violet focus ring) is, by putting it
//                  in the application palette as the highlight colour.
//   fontFamily     "IBM Plex Sans" when installed, else the system font's
//                  family. It is also the application font's family.
//   monoFamily     "JetBrains Mono" when installed, else the system fixed font.
#pragma once

#include "portalappearance.h"

#include <KConfigWatcher>
#include <KSharedConfig>

#include <QFont>
#include <QHash>
#include <QObject>
#include <QPointer>
#include <QQuickWindow>
#include <QWindow>
#include <QtQml/qqmlregistration.h>

#include <optional>

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
    Q_PROPERTY(bool softwareRendering READ softwareRendering NOTIFY softwareRenderingChanged)
    Q_PROPERTY(qreal textScale READ textScale NOTIFY textScaleChanged)
    Q_PROPERTY(bool accentFromSystem READ accentFromSystem CONSTANT)
    Q_PROPERTY(QString fontFamily READ fontFamily CONSTANT)
    Q_PROPERTY(QString monoFamily READ monoFamily CONSTANT)

public:
    enum ColorScheme {
        UnknownScheme,
        LightScheme,
        DarkScheme,
    };
    Q_ENUM(ColorScheme)

    explicit Appearance(QObject *parent = nullptr);
    ~Appearance() override;

    bool transparency() const { return m_transparency; }
    void setTransparency(bool on);
    bool blurAvailable() const { return m_blurAvailable; }
    bool effective() const { return m_transparency && m_blurAvailable; }

    int colorScheme() const { return m_colorScheme; }
    bool darkMode() const { return m_darkMode; }
    bool highContrast() const { return m_highContrast; }
    bool reducedMotion() const { return m_reducedMotion; }
    bool softwareRendering() const { return m_softwareRendering; }
    qreal textScale() const { return m_textScale; }
    bool accentFromSystem() const;
    QString fontFamily() const;
    QString monoFamily() const;

    // True when a GL_RENDERER or Vulkan device name is a software rasterizer.
    static bool isSoftwareRasterizer(const QString &deviceName);
    // The probe's decision from the graphics API (a QSGRendererInterface::
    // GraphicsApi), the GL_RENDERER string and the Vulkan device name: empty
    // while the answer is unknown (no usable string yet).
    static std::optional<bool> decideRendering(int api, const QString &glRenderer, const QString &vulkanDevice);

    // The probe's answer for `window` (internal; public for the tests). An
    // empty result is a probe that gave up: logged, not latched.
    void applyRendering(QQuickWindow *window, std::optional<bool> result, int api, const QString &device);

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
    void softwareRenderingChanged();
    void textScaleChanged();

protected:
    bool eventFilter(QObject *watched, QEvent *event) override;

private:
    void reread();
    void readSystem();
    void readMotion();
    void watchWindow(QQuickWindow *window);
    void dropProbe(QQuickWindow *window);

    QPointer<PortalAppearance> m_portal;
    KSharedConfig::Ptr m_globals;
    KConfigWatcher::Ptr m_globalsWatcher;
    int m_colorScheme = UnknownScheme;
    bool m_darkMode = false;
    bool m_highContrast = false;
    bool m_reducedMotion = false;
    bool m_softwareRendering = false;
    // The environment forced the value, or the first window has been checked.
    bool m_renderingKnown = false;
    // Windows whose first frames are being probed, with their connection.
    struct Probe {
        QMetaObject::Connection frames; // beforeRendering
        QMetaObject::Connection destroyed;
    };
    QHash<QQuickWindow *, Probe> m_probes;
    qreal m_textScale = 1.0;

    KSharedConfig::Ptr m_config;
    KConfigWatcher::Ptr m_watcher;
    bool m_transparency = true;
    bool m_blurAvailable = false;
};

// Puts the Atlas brand into the application: the violet highlight (unless the
// user has chosen a Plasma accent) and the UI font family. Safe to call more
// than once; the Atlas.Ui plugin calls it when the module loads.
void atlasUiApplyBrand();
