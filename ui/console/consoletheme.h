// ConsoleTheme: the colours of TelamonConsoleView's text. The view gives it 16
// theme colours (the ANSI colours), the text colour and the surface colour;
// the theme makes every colour legible on the surface and turns a Style into
// the text format of a run. Pure Qt Gui (no QML), so tests/console can try it.
// Not API.
#pragma once

#include "ansiparser.h"

#include <QColor>
#include <QList>
#include <QTextCharFormat>

namespace TelamonConsole {

// The WCAG contrast ratio of two opaque colours, 1 to 21.
double contrastRatio(const QColor &a, const QColor &b);
// `a` blended toward `b` by `t` (0..1), linearly in sRGB, opaque.
QColor blend(const QColor &a, const QColor &b, double t);
// `c` moved toward `toward` until it has at least `minimum` contrast on `on`.
QColor makeLegible(const QColor &c, const QColor &on, const QColor &toward, double minimum = 4.5);

class ConsoleTheme
{
public:
    // `ansi` are the 16 colours of slots 0..15 (they may be translucent); missing
    // ones are the text colour. Slots 16..23 are a ramp from slot 0 to `text`.
    void build(const QList<QColor> &ansi, const QColor &text, const QColor &surface, bool highContrast);

    QColor slot(int index) const { return index >= 0 && index < PaletteSlots ? m_slot[index] : m_text; }
    QColor text() const { return m_text; }
    QColor surface() const { return m_surface; }
    bool highContrast() const { return m_highContrast; }

    // How a run in `style` is drawn.
    QTextCharFormat format(const Style &style) const;

private:
    QColor m_slot[PaletteSlots];
    QColor m_text = Qt::black;
    QColor m_surface = Qt::white;
    bool m_highContrast = false;
};

} // namespace TelamonConsole
