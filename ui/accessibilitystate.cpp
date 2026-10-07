#include "accessibilitystate.h"

#include "legacyconfig.h"
#include "portalappearance.h"

#include <QAccessibilityHints>
#include <QGuiApplication>
#include <QStyleHints>

AccessibilityState::AccessibilityState(QObject *parent)
    : QObject(parent)
{
    QAccessible::installActivationObserver(this);
    if (qGuiApp) {
        connect(qGuiApp->styleHints()->accessibility(), &QAccessibilityHints::contrastPreferenceChanged, this, &AccessibilityState::refresh);
    }
    if (const PortalAppearance *portal = PortalAppearance::shared()) {
        connect(portal, &PortalAppearance::changed, this, &AccessibilityState::refresh);
    }
    refresh();
}

AccessibilityState::~AccessibilityState()
{
    QAccessible::removeActivationObserver(this);
}

void AccessibilityState::refresh()
{
    const PortalAppearance *portal = PortalAppearance::shared();
    const bool contrast = (qGuiApp && qGuiApp->styleHints()->accessibility()->contrastPreference() == Qt::ContrastPreference::HighContrast) || (portal && portal->highContrast());
    const bool motion = LegacyConfig::env("TELAMON_REDUCED_MOTION", "ATLAS_REDUCED_MOTION") == "1" || (portal && portal->reducedMotion());
    const QColor accent = portal ? portal->accentColor() : QColor();
    if (contrast != m_highContrast) {
        m_highContrast = contrast;
        Q_EMIT highContrastChanged();
    }
    if (motion != m_reducedMotion) {
        m_reducedMotion = motion;
        Q_EMIT reducedMotionChanged();
    }
    if (accent != m_accentColor || accent.isValid() != m_accentColor.isValid()) {
        m_accentColor = accent;
        Q_EMIT accentColorChanged();
    }
}

void AccessibilityState::_stackAfter(QQuickItem *item, QQuickItem *sibling) const
{
    if (item && sibling && item != sibling && item->parentItem() && item->parentItem() == sibling->parentItem()) {
        item->stackAfter(sibling);
    }
}
