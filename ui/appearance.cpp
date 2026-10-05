#include "appearance.h"

#include "portalappearance.h"
#include "textscale.h"

#include <KConfigGroup>
#include <KWindowEffects>

#include <QAccessibilityHints>
#include <QEvent>
#include <QFontDatabase>
#include <QGuiApplication>
#include <QPalette>
#include <QStyleHints>
#include <QtGlobal>

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

    if (qGuiApp) {
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
    }
    return QObject::eventFilter(watched, event);
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
    if (window) {
        // An empty region is the whole window.
        KWindowEffects::enableBlurBehind(window, effective());
    }
}
