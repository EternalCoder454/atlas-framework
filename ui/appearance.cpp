#include "appearance.h"

#include <KConfigGroup>
#include <KWindowEffects>

namespace
{
constexpr auto kGroup = "Appearance";
constexpr auto kKey = "Transparency";
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
