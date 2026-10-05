// logSafe(): a name from a file or an app, made safe for a log line. Internal
// to the module (not installed). Control, format (bidi and invisible),
// separator and unpaired surrogate characters and the backslash are written
// as \uXXXX (\UXXXXXXXX above the BMP), and a long text is cut.
#pragma once

#include <QChar>
#include <QString>

inline QString logSafe(const QString &text)
{
    QString out;
    for (qsizetype i = 0; i < text.size() && out.size() < 120; ++i) {
        const QChar c = text[i];
        char32_t cp = c.unicode();
        bool pair = false;
        bool lone = false;
        if (c.isHighSurrogate() && i + 1 < text.size() && text[i + 1].isLowSurrogate()) {
            cp = QChar::surrogateToUcs4(c, text[i + 1]);
            pair = true;
        } else if (c.isHighSurrogate() || c.isLowSurrogate()) {
            lone = true;
        }
        const auto cat = QChar::category(cp);
        if (lone || cp == U'\\' || cat == QChar::Other_Control || cat == QChar::Other_Format || cat == QChar::Other_Surrogate || cat == QChar::Other_PrivateUse
            || cat == QChar::Separator_Line || cat == QChar::Separator_Paragraph) {
            out += cp > 0xFFFF ? QStringLiteral("\\U%1").arg(qulonglong(cp), 8, 16, QLatin1Char('0')) : QStringLiteral("\\u%1").arg(qulonglong(cp), 4, 16, QLatin1Char('0'));
        } else {
            out += c;
            if (pair) {
                out += text[i + 1];
            }
        }
        if (pair) {
            ++i;
        }
    }
    return out;
}
