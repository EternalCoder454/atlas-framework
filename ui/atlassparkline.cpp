#include "atlassparkline.h"

#include <QPainter>
#include <QPainterPath>

#include <algorithm>
#include <cmath>

namespace
{
// Equal doubles, a NaN counting as equal to a NaN.
bool same(qreal a, qreal b)
{
    return a == b || (std::isnan(a) && std::isnan(b));
}
}

AtlasSparklineItem::AtlasSparklineItem(QQuickItem *parent)
    : QQuickPaintedItem(parent)
{
    setAntialiasing(true);
}

void AtlasSparklineItem::repaint()
{
    ++m_updates;
    update();
}

void AtlasSparklineItem::setValues(const QList<qreal> &v)
{
    // A poll that brings the same numbers repaints nothing.
    if (std::equal(v.cbegin(), v.cend(), m_values.cbegin(), m_values.cend(), same)) {
        return;
    }
    m_values = v;
    repaint();
    Q_EMIT valuesChanged();
}

void AtlasSparklineItem::setMinimum(qreal v)
{
    if (same(v, m_minimum)) {
        return;
    }
    m_minimum = v;
    repaint();
    Q_EMIT minimumChanged();
}

void AtlasSparklineItem::setMaximum(qreal v)
{
    if (same(v, m_maximum)) {
        return;
    }
    m_maximum = v;
    repaint();
    Q_EMIT maximumChanged();
}

void AtlasSparklineItem::setMinimumRange(qreal v)
{
    if (!std::isfinite(v) || v < 0) {
        v = 0;
    }
    if (v == m_minimumRange) {
        return;
    }
    m_minimumRange = v;
    repaint();
    Q_EMIT minimumRangeChanged();
}

void AtlasSparklineItem::setColor(const QColor &c)
{
    if (c == m_color) {
        return;
    }
    m_color = c;
    repaint();
    Q_EMIT colorChanged();
}

void AtlasSparklineItem::setFill(bool f)
{
    if (f == m_fill) {
        return;
    }
    m_fill = f;
    repaint();
    Q_EMIT fillChanged();
}

void AtlasSparklineItem::setLineWidth(qreal w)
{
    if (!std::isfinite(w) || w < 0) {
        w = 0;
    }
    if (w == m_lineWidth) {
        return;
    }
    m_lineWidth = w;
    repaint();
    Q_EMIT lineWidthChanged();
}

void AtlasSparklineItem::resolve(qreal &lo, qreal &hi) const
{
    qreal dataLo = std::numeric_limits<qreal>::infinity();
    qreal dataHi = -std::numeric_limits<qreal>::infinity();
    for (qreal v : m_values) {
        if (std::isfinite(v)) {
            dataLo = std::min(dataLo, v);
            dataHi = std::max(dataHi, v);
        }
    }
    if (dataLo > dataHi) { // no samples at all
        dataLo = 0;
        dataHi = 0;
    }
    const bool fixedLo = std::isfinite(m_minimum);
    const bool fixedHi = std::isfinite(m_maximum);
    lo = fixedLo ? m_minimum : dataLo;
    hi = fixedHi ? m_maximum : dataHi;
    // Automatic limits widen to the minimum range around their middle; a
    // fixed one stays where it was put and the other gives way.
    if (hi - lo < m_minimumRange) {
        if (fixedLo && !fixedHi) {
            hi = lo + m_minimumRange;
        } else if (fixedHi && !fixedLo) {
            lo = hi - m_minimumRange;
        } else if (!fixedLo && !fixedHi) {
            const qreal mid = (lo + hi) / 2;
            lo = mid - m_minimumRange / 2;
            hi = mid + m_minimumRange / 2;
        }
    }
    // Still no span (a flat series, no minimumRange, or limits the wrong way
    // round): something to divide by.
    if (!(hi > lo)) {
        if (fixedLo || fixedHi) {
            hi = lo + 1;
        } else {
            lo -= 0.5;
            hi += 0.5;
        }
    }
}

qreal AtlasSparklineItem::scaleMinimum() const
{
    qreal lo, hi;
    resolve(lo, hi);
    return lo;
}

qreal AtlasSparklineItem::scaleMaximum() const
{
    qreal lo, hi;
    resolve(lo, hi);
    return hi;
}

void AtlasSparklineItem::paint(QPainter *p)
{
    const double w = width();
    const double h = height();
    const qsizetype n = m_values.size();
    if (w <= 0 || h <= 0 || n == 0) {
        return;
    }
    qreal lo, hi;
    resolve(lo, hi);
    const double span = hi - lo;
    // The line's own width stays inside the item.
    const double pad = m_lineWidth / 2;
    const double top = pad, plotH = std::max(0.0, h - 2 * pad);
    const double x0 = pad, plotW = std::max(0.0, w - 2 * pad);
    const double dx = n > 1 ? plotW / double(n - 1) : 0;
    auto pointAt = [&](qsizetype i) {
        const double r = std::clamp((m_values[i] - lo) / span, 0.0, 1.0);
        return QPointF(n > 1 ? x0 + dx * double(i) : x0 + plotW / 2, top + plotH * (1 - r));
    };

    QColor fillColor = m_color;
    fillColor.setAlphaF(fillColor.alphaF() * 0.18);
    QPen pen(m_color, m_lineWidth, Qt::SolidLine, Qt::RoundCap, Qt::RoundJoin);
    // Each unbroken run of samples is drawn alone; a lone sample is a dot.
    for (qsizetype i = 0; i < n;) {
        if (!std::isfinite(m_values[i])) {
            ++i;
            continue;
        }
        qsizetype end = i;
        while (end < n && std::isfinite(m_values[end])) {
            ++end;
        }
        if (end - i == 1) {
            p->setPen(Qt::NoPen);
            p->setBrush(m_color);
            p->drawEllipse(pointAt(i), std::max(m_lineWidth, 1.0), std::max(m_lineWidth, 1.0));
        } else {
            QPainterPath line;
            line.moveTo(pointAt(i));
            for (qsizetype k = i + 1; k < end; ++k) {
                line.lineTo(pointAt(k));
            }
            if (m_fill) {
                QPainterPath area = line;
                area.lineTo(pointAt(end - 1).x(), top + plotH);
                area.lineTo(pointAt(i).x(), top + plotH);
                area.closeSubpath();
                p->setPen(Qt::NoPen);
                p->setBrush(fillColor);
                p->drawPath(area);
            }
            p->setPen(pen);
            p->setBrush(Qt::NoBrush);
            p->drawPath(line);
        }
        i = end;
    }
}
