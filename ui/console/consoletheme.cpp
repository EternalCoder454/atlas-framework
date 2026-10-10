#include "consoletheme.h"

#include <QFont>

#include <algorithm>
#include <cmath>

namespace TelamonConsole {

namespace {

double linear(double v)
{
    return v <= 0.04045 ? v / 12.92 : std::pow((v + 0.055) / 1.055, 2.4);
}

double luminance(const QColor &c)
{
    return 0.2126 * linear(c.redF()) + 0.7152 * linear(c.greenF()) + 0.0722 * linear(c.blueF());
}

// `c` over `under`, opaque.
QColor flatten(const QColor &c, const QColor &under)
{
    const double a = c.alphaF();
    return QColor::fromRgbF(c.redF() * a + under.redF() * (1 - a), c.greenF() * a + under.greenF() * (1 - a),
                            c.blueF() * a + under.blueF() * (1 - a));
}

// How strong the tint of a background colour is.
constexpr double BackgroundTint = 0.22;
// How far a dim colour goes toward the surface.
constexpr double DimAmount = 0.35;

} // namespace

double contrastRatio(const QColor &a, const QColor &b)
{
    const double la = luminance(a);
    const double lb = luminance(b);
    return (std::max(la, lb) + 0.05) / (std::min(la, lb) + 0.05);
}

QColor blend(const QColor &a, const QColor &b, double t)
{
    t = std::clamp(t, 0.0, 1.0);
    return QColor::fromRgbF(a.redF() + (b.redF() - a.redF()) * t, a.greenF() + (b.greenF() - a.greenF()) * t,
                            a.blueF() + (b.blueF() - a.blueF()) * t);
}

QColor makeLegible(const QColor &c, const QColor &on, const QColor &toward, double minimum)
{
    if (contrastRatio(c, on) >= minimum) {
        return c;
    }
    for (int step = 1; step <= 20; ++step) {
        const QColor m = blend(c, toward, step / 20.0);
        if (contrastRatio(m, on) >= minimum) {
            return m;
        }
    }
    return toward;
}

void ConsoleTheme::build(const QList<QColor> &ansi, const QColor &text, const QColor &surface, bool highContrast)
{
    m_text = flatten(text.isValid() ? text : QColor(Qt::black), surface.isValid() ? surface : QColor(Qt::white));
    m_surface = surface.isValid() ? surface : QColor(Qt::white);
    m_highContrast = highContrast;
    for (int i = 0; i < 16; ++i) {
        const QColor c = i < ansi.size() && ansi[i].isValid() ? flatten(ansi[i], m_surface) : m_text;
        m_slot[i] = makeLegible(c, m_surface, m_text);
    }
    for (int i = 0; i < 8; ++i) {
        m_slot[16 + i] = makeLegible(blend(m_slot[0], m_text, i / 7.0), m_surface, m_text);
    }
}

QTextCharFormat ConsoleTheme::format(const Style &s) const
{
    QTextCharFormat f;
    if (s.flags & Bold) {
        f.setFontWeight(QFont::Bold);
    }
    if (s.flags & Italic) {
        f.setFontItalic(true);
    }
    if (s.flags & (Underline)) {
        f.setFontUnderline(true);
    }
    if (s.flags & Strike) {
        f.setFontStrikeOut(true);
    }
    if (m_highContrast) {
        // No colour at all: the text colour stays, and inverse is bold and underlined.
        if (s.flags & Inverse) {
            f.setFontWeight(QFont::Bold);
            f.setFontUnderline(true);
        }
        return f;
    }
    QColor fg = s.fg == NoColor ? m_text : slot(s.fg);
    if (s.flags & Inverse) {
        const QColor back = fg;
        QColor front = s.bg == NoColor ? m_surface : slot(s.bg);
        const QColor toward = contrastRatio(m_surface, back) >= contrastRatio(m_text, back) ? m_surface : m_text;
        front = makeLegible(front, back, toward);
        f.setForeground(front);
        f.setBackground(back);
        return f;
    }
    if (s.bg != NoColor) {
        const QColor tint = blend(m_surface, slot(s.bg), BackgroundTint);
        fg = makeLegible(fg, tint, m_text);
        f.setBackground(tint);
    }
    if (s.flags & Dim) {
        fg = blend(fg, m_surface, DimAmount);
    }
    if (s.fg != NoColor || s.bg != NoColor || (s.flags & Dim)) {
        f.setForeground(fg);
    }
    return f;
}

} // namespace TelamonConsole
