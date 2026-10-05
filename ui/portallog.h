// Text that came over D-Bus, made safe to show or to log. Works per code
// point, so characters outside the BMP (tag characters, musical format
// characters) are caught too. Control, format, surrogate, private-use and
// unassigned characters, and line and paragraph separators, are unsafe.
#pragma once

#include <QChar>
#include <QString>

namespace PortalLog
{
inline bool unsafe(char32_t cp)
{
    switch (QChar::category(cp)) {
    case QChar::Other_Control:
    case QChar::Other_Format:
    case QChar::Other_Surrogate:
    case QChar::Other_PrivateUse:
    case QChar::Other_NotAssigned:
    case QChar::Separator_Line:
    case QChar::Separator_Paragraph:
        return true;
    default:
        return false;
    }
}

// The next code point of `in` at `i` (a lone surrogate comes out as itself);
// moves `i` past it.
inline char32_t next(const QString &in, qsizetype &i)
{
    const QChar c = in.at(i++);
    if (c.isHighSurrogate() && i < in.size() && in.at(i).isLowSurrogate()) {
        return QChar::surrogateToUcs4(c, in.at(i++));
    }
    return c.unicode();
}

// `in` without its unsafe characters, cut to about `max` UTF-16 units, trimmed.
inline QString clean(const QString &in, int max)
{
    QString out;
    qsizetype i = 0;
    while (i < in.size() && out.size() < max) {
        const qsizetype start = i;
        const char32_t cp = next(in, i);
        if (!unsafe(cp)) {
            out += QStringView(in).mid(start, i - start);
        }
    }
    return out.trimmed();
}

// For a log line: unsafe characters and the backslash are escaped.
inline QString text(const QString &in, int max = 120)
{
    QString out;
    qsizetype i = 0;
    while (i < in.size() && i < max) {
        const qsizetype start = i;
        const char32_t cp = next(in, i);
        if (cp == U'\\') {
            out += QLatin1String("\\\\");
        } else if (unsafe(cp)) {
            out += QStringLiteral("\\u{%1}").arg(uint(cp), 0, 16);
        } else {
            out += QStringView(in).mid(start, i - start);
        }
    }
    return out;
}
}
