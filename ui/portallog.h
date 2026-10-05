// Text that came over D-Bus, made safe to write to a log: control characters,
// line and paragraph separators and invisible format characters (bidi
// overrides, zero-width) become \uXXXX, and the text is cut to `max` characters.
#pragma once

#include <QChar>
#include <QString>

namespace PortalLog
{
inline bool unsafe(QChar c)
{
    const QChar::Category cat = c.category();
    return c.unicode() < 0x20 || c.unicode() == 0x7f || (c.unicode() >= 0x80 && c.unicode() < 0xa0) || cat == QChar::Other_Format || cat == QChar::Separator_Line
        || cat == QChar::Separator_Paragraph;
}

inline QString text(const QString &in, int max = 120)
{
    QString out;
    for (const QChar c : in.left(max)) {
        if (unsafe(c)) {
            out += QStringLiteral("\\u%1").arg(uint(c.unicode()), 4, 16, QLatin1Char('0'));
        } else {
            out += c;
        }
    }
    return out;
}
}
