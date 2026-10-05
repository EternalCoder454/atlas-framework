#include "atlascolorsprivate.h"

#include <cmath>

namespace {
// NaN is 0; everything else is kept within 0..1.
double unit(double v)
{
    if (std::isnan(v)) {
        return 0.0;
    }
    return qBound(0.0, v, 1.0);
}
} // namespace

AtlasColorsPrivate::AtlasColorsPrivate(QObject *parent)
    : QObject(parent)
{
}

QColor AtlasColorsPrivate::alpha(const QColor &c, double a) const
{
    if (!c.isValid()) {
        return QColor();
    }
    QColor out = c;
    out.setAlphaF(unit(a));
    return out;
}

QColor AtlasColorsPrivate::mix(const QColor &a, const QColor &b, double t) const
{
    if (!a.isValid() || !b.isValid()) {
        return QColor();
    }
    const double w = unit(t);
    const QColor x = a.toRgb();
    const QColor y = b.toRgb();
    // The same maths as Qt.tint: each channel, alpha included, a*(1-t) + b*t.
    const double inv = 1.0 - w;
    return QColor::fromRgbF(float(x.redF() * inv + y.redF() * w), float(x.greenF() * inv + y.greenF() * w),
                            float(x.blueF() * inv + y.blueF() * w), float(x.alphaF() * inv + y.alphaF() * w));
}
