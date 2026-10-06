#include "appearance.h"

#include "portalappearance.h"
#include "textscale.h"

#include <KConfigGroup>
#include <KWindowEffects>

#include <QAccessibilityHints>
#include <QEvent>
#include <QFontDatabase>
#include <QGuiApplication>
#include <QOpenGLContext>
#include <QOpenGLFunctions>
#include <QPointer>
#include <QRegion>
#include <QtMath>
#include <QSGRendererInterface>
#include <QtGui/qtguiglobal.h>
#if QT_CONFIG(vulkan)
#include <QVulkanFunctions>
#include <QVulkanInstance>
#endif
#include <QLoggingCategory>
#include <QPalette>
#include <QStyleHints>
#include <QtGlobal>
#include <atomic>
#include <memory>

namespace
{
constexpr auto kGroup = "Appearance";
constexpr auto kKey = "Transparency";
// Plasma's animation speed: 0 turns animations off.
constexpr auto kGlobalsGroup = "KDE";
constexpr auto kFactorKey = "AnimationDurationFactor";
constexpr qreal kDefaultPointSize = 10.0;
constexpr auto kUiFamily = "IBM Plex Sans";
constexpr auto kMonoFamily = "JetBrains Mono";
// Atlas violet and its text, per theme: AtlasOS's colour schemes.
const QColor kVioletLight(0x68, 0x58, 0xE2);
const QColor kVioletDark(0x8A, 0x7A, 0xF4);

bool hasFamily(const QString &family)
{
    return QFontDatabase::families().contains(family, Qt::CaseInsensitive);
}

bool systemAccent()
{
    const KSharedConfig::Ptr globals = KSharedConfig::openConfig(QStringLiteral("kdeglobals"), KConfig::NoGlobals);
    globals->reparseConfiguration();
    return globals->group(QStringLiteral("General")).hasKey("AccentColor");
}

// The highlight of the current theme: the system accent when chosen, else violet.
void applyPalette()
{
    if (!qGuiApp || systemAccent()) {
        return;
    }
    QPalette palette = qGuiApp->palette();
    const bool dark = palette.color(QPalette::Window).lightnessF() < 0.5;
    const QColor accent = dark ? kVioletDark : kVioletLight;
    if (palette.color(QPalette::Active, QPalette::Highlight) == accent) {
        return;
    }
    // White on the light violet; near-black on the lighter dark violet.
    const QColor onAccent = dark ? QColor(0x14, 0x12, 0x1F) : QColor(Qt::white);
    for (auto group : {QPalette::Active, QPalette::Inactive, QPalette::Disabled}) {
        palette.setColor(group, QPalette::Highlight, accent);
        palette.setColor(group, QPalette::HighlightedText, onAccent);
    }
    qGuiApp->setPalette(palette);
}
}

Appearance::Appearance(QObject *parent)
    : QObject(parent)
    , m_config(KSharedConfig::openConfig(QStringLiteral("atlasrc"), KConfig::FullConfig))
{
    m_transparency = m_config->group(QLatin1String(kGroup)).readEntry(kKey, true);
    m_blurAvailable = KWindowEffects::isEffectAvailable(KWindowEffects::BlurBehind);

    m_watcher = KConfigWatcher::create(m_config);
    connect(m_watcher.data(), &KConfigWatcher::configChanged, this, [this](const KConfigGroup &group, const QByteArrayList &) {
        // Some writers announce the whole file (an empty group name).
        if (group.name() == QLatin1String(kGroup) || group.name().isEmpty()) {
            reread();
        }
    });

    // System preferences. kdeglobals may not exist: a missing file reads as
    // the defaults.
    m_globals = KSharedConfig::openConfig(QStringLiteral("kdeglobals"), KConfig::NoGlobals);
    m_globalsWatcher = KConfigWatcher::create(m_globals);
    connect(m_globalsWatcher.data(), &KConfigWatcher::configChanged, this, [this](const KConfigGroup &group, const QByteArrayList &) {
        if (group.name() == QLatin1String(kGlobalsGroup) || group.name().isEmpty()) {
            readMotion();
        }
    });
    // The portal's contrast and reduced-motion join Qt's and Plasma's.
    m_portal = PortalAppearance::shared();
    if (m_portal) {
        connect(m_portal, &PortalAppearance::changed, this, [this] {
            readSystem();
            readMotion();
        });
    }
    readSystem();
    readMotion();

    const QByteArray forced = qgetenv("ATLAS_SOFTWARE_RENDERING");
    if (forced == "1" || forced == "0") {
        m_softwareRendering = forced == "1";
        m_renderingKnown = true;
    } else if (!forced.isEmpty()) {
        qWarning("Atlas.Ui: ignoring ATLAS_SOFTWARE_RENDERING=\"%s\" (use 1 or 0)", forced.left(32).constData());
    }

    if (qGuiApp) {
        if (!m_renderingKnown) {
            const auto windows = qGuiApp->allWindows();
            for (QWindow *window : windows) {
                if (auto *quick = qobject_cast<QQuickWindow *>(window)) {
                    watchWindow(quick);
                }
            }
        }
        connect(qGuiApp->styleHints(), &QStyleHints::colorSchemeChanged, this, &Appearance::readSystem);
        connect(qGuiApp->styleHints()->accessibility(), &QAccessibilityHints::contrastPreferenceChanged, this, &Appearance::readSystem);
        // The palette and font signals are deprecated: the events are not.
        qGuiApp->installEventFilter(this);
    }
}

bool Appearance::accentFromSystem() const
{
    return systemAccent();
}

QString Appearance::fontFamily() const
{
    return hasFamily(QLatin1String(kUiFamily)) ? QLatin1String(kUiFamily) : (qGuiApp ? qGuiApp->font().family() : QString());
}

QString Appearance::monoFamily() const
{
    return hasFamily(QLatin1String(kMonoFamily)) ? QLatin1String(kMonoFamily) : QFontDatabase::systemFont(QFontDatabase::FixedFont).family();
}

void atlasUiApplyBrand()
{
    if (!qGuiApp) {
        return;
    }
    // The family only: the size and the rest stay the user's.
    QFont font = qGuiApp->font();
    if (hasFamily(QLatin1String(kUiFamily)) && font.family() != QLatin1String(kUiFamily)) {
        font.setFamily(QLatin1String(kUiFamily));
        qGuiApp->setFont(font);
    }
    applyPalette();
    // A change of colour scheme (light to dark) swaps the violet's shade. Once.
    static bool connected = false;
    if (!connected) {
        connected = true;
        QObject::connect(qGuiApp->styleHints(), &QStyleHints::colorSchemeChanged, qGuiApp, [] { applyPalette(); }, Qt::QueuedConnection);
    }
}

bool Appearance::eventFilter(QObject *watched, QEvent *event)
{
    if (event->type() == QEvent::ApplicationPaletteChange || event->type() == QEvent::ApplicationFontChange) {
        readSystem();
    } else if (!m_renderingKnown && event->type() == QEvent::Show) {
        if (auto *window = qobject_cast<QQuickWindow *>(watched)) {
            watchWindow(window);
        }
    }
    return QObject::eventFilter(watched, event);
}

bool Appearance::isSoftwareRasterizer(const QString &deviceName)
{
    for (const QLatin1String name : {QLatin1String("llvmpipe"), QLatin1String("softpipe"), QLatin1String("swiftshader"), QLatin1String("lavapipe"), QLatin1String("software rasterizer")}) {
        if (deviceName.contains(name, Qt::CaseInsensitive)) {
            return true;
        }
    }
    return false;
}

std::optional<bool> Appearance::decideRendering(int api, const QString &glRenderer, const QString &vulkanDevice)
{
    switch (api) {
    case QSGRendererInterface::Software:
        return true;
    case QSGRendererInterface::OpenGL:
        // An empty string is a failed probe, not "hardware".
        return glRenderer.isEmpty() ? std::nullopt : std::optional<bool>(isSoftwareRasterizer(glRenderer));
    case QSGRendererInterface::Vulkan:
        return vulkanDevice.isEmpty() ? std::nullopt : std::optional<bool>(isSoftwareRasterizer(vulkanDevice));
    case QSGRendererInterface::Unknown:
        return std::nullopt;
    default:
        return false; // Metal, Direct3D: no software variant to tell apart here
    }
}

namespace {
// How many frames the probe may fail before it settles on "not software".
constexpr int kMaxProbeFrames = 10;

// Shared by the render thread and the GUI thread: atomics only.
struct ProbeState {
    std::atomic_bool resolved{false};
    std::atomic_int frames{0};
};
}

// The rendering mode is known on the first frames: the GL renderer string is
// only readable on the render thread, with the context current. So
// beforeRendering reads what it needs into plain values and queues them to the
// GUI thread; nothing of this object is touched over there. A probe that finds
// nothing (no context yet, an empty string) is retried on the next frames, and
// gives up after kMaxProbeFrames.
void Appearance::watchWindow(QQuickWindow *window)
{
    if (m_renderingKnown || m_probes.contains(window)) {
        return;
    }
    auto state = std::make_shared<ProbeState>();
    QPointer<Appearance> self(this);
    auto report = [self, window](std::optional<bool> result, int api, QString device) {
        // Queued to the GUI thread, with the window as the context object: a
        // window that is gone drops the call.
        QMetaObject::invokeMethod(window, [self, window, result, api, device] {
            if (self) {
                self->applyRendering(window, result, api, device);
            }
        }, Qt::QueuedConnection);
    };
    const QMetaObject::Connection connection = connect(window, &QQuickWindow::beforeRendering, window, [state, report, window] {
        if (state->resolved.load(std::memory_order_relaxed)) {
            return;
        }
        int api = QSGRendererInterface::Unknown;
        QString gl;
        QString vulkan;
        bool software = window->sceneGraphBackend() == QLatin1String("software");
        if (QSGRendererInterface *ri = window->rendererInterface()) {
            api = ri->graphicsApi();
            if (api == QSGRendererInterface::OpenGL) {
                if (QOpenGLContext *context = QOpenGLContext::currentContext()) {
                    if (const GLubyte *renderer = context->functions()->glGetString(GL_RENDERER)) {
                        gl = QString::fromLatin1(reinterpret_cast<const char *>(renderer));
                    }
                }
            }
#if QT_CONFIG(vulkan)
            else if (api == QSGRendererInterface::Vulkan && window->vulkanInstance()) {
                const void *resource = ri->getResource(window, QSGRendererInterface::PhysicalDeviceResource);
                QVulkanFunctions *functions = window->vulkanInstance()->functions();
                if (resource && functions) {
                    VkPhysicalDeviceProperties properties = {};
                    functions->vkGetPhysicalDeviceProperties(*static_cast<const VkPhysicalDevice *>(resource), &properties);
                    vulkan = QString::fromUtf8(properties.deviceName);
                }
            }
#endif
        }
        std::optional<bool> result = software ? std::optional<bool>(true) : decideRendering(api, gl, vulkan);
        const QString device = api == QSGRendererInterface::Vulkan ? vulkan : gl;
        if (!result && state->frames.fetch_add(1) + 1 < kMaxProbeFrames) {
            return; // unknown: try again next frame
        }
        if (!state->resolved.exchange(true)) {
            report(result, api, device);
        }
    }, Qt::DirectConnection);
    const QMetaObject::Connection destroyed = connect(window, &QObject::destroyed, this, [this, window] { m_probes.remove(window); });
    m_probes.insert(window, Probe{connection, destroyed});
}

// Stops probing one window.
void Appearance::dropProbe(QQuickWindow *window)
{
    const auto it = m_probes.find(window);
    if (it != m_probes.end()) {
        QObject::disconnect(it->frames);
        QObject::disconnect(it->destroyed);
        m_probes.erase(it);
    }
}

Appearance::~Appearance()
{
    // The frame connections have the window as their context, not this.
    for (auto it = m_probes.begin(); it != m_probes.end(); ++it) {
        QObject::disconnect(it->frames);
        QObject::disconnect(it->destroyed);
    }
}

// GUI thread only. `result` is empty when the window's probe gave up: that
// does not latch, so another window can still find the answer.
void Appearance::applyRendering(QQuickWindow *window, std::optional<bool> result, int api, const QString &device)
{
    if (m_renderingKnown) {
        return;
    }
    if (!result) {
        qWarning("Atlas.Ui: could not tell the rendering mode (graphics API %d, device \"%s\"): assuming hardware; set ATLAS_SOFTWARE_RENDERING=1 to force", api,
                 device.toUtf8().constData());
        if (window) {
            dropProbe(window);
        }
        return;
    }
    m_renderingKnown = true;
    const auto windows = m_probes.keys();
    for (QQuickWindow *w : windows) {
        dropProbe(w);
    }
    qInfo("Atlas.Ui: graphics API %d, device \"%s\": software rendering %s", api, device.toUtf8().constData(), *result ? "yes" : "no");
    if (*result != m_softwareRendering) {
        m_softwareRendering = *result;
        Q_EMIT softwareRenderingChanged();
    }
}

// Colour scheme, dark mode, high contrast and text scale: all from Qt.
void Appearance::readSystem()
{
    if (!qGuiApp) {
        return;
    }
    const auto *hints = qGuiApp->styleHints();
    const int scheme = static_cast<int>(hints->colorScheme());
    int mine = UnknownScheme;
    if (scheme == static_cast<int>(Qt::ColorScheme::Light)) {
        mine = LightScheme;
    } else if (scheme == static_cast<int>(Qt::ColorScheme::Dark)) {
        mine = DarkScheme;
    }
    const bool dark = mine == DarkScheme || (mine == UnknownScheme && qGuiApp->palette().color(QPalette::Window).lightnessF() < 0.5);
    const bool contrast = hints->accessibility()->contrastPreference() == Qt::ContrastPreference::HighContrast || (m_portal && m_portal->highContrast());
    qreal scale = qGuiApp->font().pointSizeF() / kDefaultPointSize;
    // A pixel-sized font has no point size (-1): that and NaN are the default;
    // anything else is held between 0.5 and 4.
    scale = AtlasTextScale::clamp(scale);

    if (mine != m_colorScheme) {
        m_colorScheme = mine;
        Q_EMIT colorSchemeChanged();
    }
    if (dark != m_darkMode) {
        m_darkMode = dark;
        Q_EMIT darkModeChanged();
    }
    if (contrast != m_highContrast) {
        m_highContrast = contrast;
        Q_EMIT highContrastChanged();
    }
    if (!qFuzzyCompare(scale, m_textScale)) {
        m_textScale = scale;
        Q_EMIT textScaleChanged();
    }
}

void Appearance::readMotion()
{
    bool reduced = qEnvironmentVariable("ATLAS_REDUCED_MOTION") == QLatin1String("1");
    if (!reduced) {
        m_globals->reparseConfiguration();
        const QString raw = m_globals->group(QLatin1String(kGlobalsGroup)).readEntry(kFactorKey, QString());
        bool ok = false;
        const double factor = raw.toDouble(&ok);
        reduced = ok && factor == 0.0;
    }
    reduced = reduced || (m_portal && m_portal->reducedMotion());
    if (reduced != m_reducedMotion) {
        m_reducedMotion = reduced;
        Q_EMIT reducedMotionChanged();
    }
}

void Appearance::reread()
{
    const bool before = effective();
    const bool on = m_config->group(QLatin1String(kGroup)).readEntry(kKey, true);
    if (on != m_transparency) {
        m_transparency = on;
        Q_EMIT transparencyChanged();
    }
    if (before != effective()) {
        Q_EMIT effectiveChanged();
    }
}

void Appearance::setTransparency(bool on)
{
    if (on == m_transparency) {
        return;
    }
    KConfigGroup group = m_config->group(QLatin1String(kGroup));
    group.writeEntry(kKey, on);
    m_config->sync();
    // Our own write may not come back through the watcher.
    reread();
}

void Appearance::refresh()
{
    const bool before = effective();
    const bool available = KWindowEffects::isEffectAvailable(KWindowEffects::BlurBehind);
    if (available != m_blurAvailable) {
        m_blurAvailable = available;
        Q_EMIT blurAvailableChanged();
    }
    if (before != effective()) {
        Q_EMIT effectiveChanged();
    }
}

void Appearance::applyBlur(QWindow *window)
{
    if (!window) {
        return;
    }
    // An empty region is the whole window. A frameless AtlasWindow rounds its
    // top corners (its _cornerRadius): the blur leaves them out too, or a
    // square of blur would show behind each one.
    QRegion region;
    const int r = qCeil(window->property("_cornerRadius").toReal());
    const int w = window->width();
    const int h = window->height();
    if (r > 0 && w > 2 * r && h > 2 * r) {
        region = QRegion(0, r, w, h - r) + QRegion(r, 0, w - 2 * r, r) + QRegion(0, 0, 2 * r, 2 * r, QRegion::Ellipse)
            + QRegion(w - 2 * r, 0, 2 * r, 2 * r, QRegion::Ellipse);
    }
    KWindowEffects::enableBlurBehind(window, effective(), region);
}
