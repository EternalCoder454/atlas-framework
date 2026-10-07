// The text scale Appearance reports, bounded: the point size over 10 is
// kept between 0.5 and 4, and a missing or non-finite value is the default.
#pragma once

#include <QtGlobal>
#include <cmath>

namespace TelamonTextScale {
inline constexpr qreal kMin = 0.5;
inline constexpr qreal kMax = 4.0;
inline constexpr qreal kDefault = 1.0;

inline qreal clamp(qreal scale)
{
    if (!std::isfinite(scale) || !(scale > 0)) {
        return kDefault;
    }
    return scale < kMin ? kMin : (scale > kMax ? kMax : scale);
}
}
