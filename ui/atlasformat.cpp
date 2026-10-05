#include "atlasformat.h"

#include <QCoreApplication>
#include <QLocale>
#include <QSet>
#include <QtMath>

#include <cmath>
#include <limits>

namespace {

// QLocale::formattedDataSize takes a qint64: larger sizes are written in EiB.
constexpr double kMaxInt64Size = 9.0e18;
// Durations beyond a billion days (about 2.7 million years) are clamped to it,
// so the day count fits the int a plural form takes and is never misspelled.
constexpr double kMaxSeconds = 86400.0 * 1.0e9;
constexpr int kMaxPrecision = 10;

// A plural: the catalogue's forms of `one` for n, or, when nothing is
// translated (the source language), English: `one` for 1, `many` otherwise.
// lupdate sees `one` only (marked with QT_TRANSLATE_N_NOOP at the call), so
// `many` is a source-language fallback. Callers
// keep n at or below a billion (duration() clamps its input), so the number
// shown is always the real one.
QString plural(const char *one, qint64 n, const char *many)
{
    const int count = int(qMin<qint64>(n, 1000000000));
    const QString number = QString::number(count);
    const QString result = QCoreApplication::translate("AtlasFormat", one, nullptr, count);
    if (n != 1 && result == QString::fromLatin1(one).replace(QLatin1String("%n"), number)) {
        return QString::fromLatin1(many).replace(QLatin1String("%n"), number);
    }
    return result;
}

QLocale localeFor(const QString &name)
{
    return name.isEmpty() ? QLocale() : QLocale(name);
}

bool isNum(double v)
{
    return std::isfinite(v);
}

// Languages that put a space between the number and the percent sign.
QString percentSpace(const QLocale &l)
{
    static const QSet<QLocale::Language> nbsp = {
        QLocale::German, QLocale::Spanish, QLocale::Russian, QLocale::Ukrainian, QLocale::Swedish,
        QLocale::NorwegianBokmal, QLocale::NorwegianNynorsk, QLocale::Finnish,
        QLocale::Czech, QLocale::Slovak, QLocale::Danish, QLocale::Bulgarian, QLocale::Catalan,
        QLocale::Estonian, QLocale::Lithuanian, QLocale::Latvian, QLocale::Slovenian, QLocale::Croatian,
        QLocale::Serbian, QLocale::Romanian,
    };
    if (l.language() == QLocale::French) {
        return QString(QChar(0x202F)); // narrow no-break space
    }
    return nbsp.contains(l.language()) ? QString(QChar(0x00A0)) : QString();
}

// "-0" is never shown: a value that rounds to zero is written as zero.
double roundsToZero(double n, int precision)
{
    return std::abs(n) < 0.5 * std::pow(10.0, -precision) ? 0.0 : n;
}

QString sized(double n, int precision, const QLocale &l, bool si)
{
    // IEC counts in 1024 (KiB), SI in 1000 (kB); the first unit above bytes.
    const double base = si ? 1000.0 : 1024.0;
    precision = qBound(0, precision, kMaxPrecision);
    const double a = std::abs(n);
    const QString sign = n < 0 ? l.negativeSign() : QString();
    // 1023.5 and up rounds to 1024 B: that is 1.0 KiB, taken below.
    if (std::round(a) < base) {
        // "0 B": QLocale would say "0 bytes".
        const double whole = std::round(a);
        return (whole > 0 ? sign : QString()) + QCoreApplication::translate("AtlasFormat", "%1 B").arg(l.toString(whole, 'f', 0));
    }
    if (a >= kMaxInt64Size) {
        return sign + (si ? l.toString(a / 1.0e18, 'f', precision) + QLatin1String(" EB") : l.toString(a / double(Q_INT64_C(1) << 60), 'f', precision) + QLatin1String(" EiB"));
    }
    // The unit QLocale will pick, and whether the value rounds up to the next
    // one ("1000.0 kB"): then ask for exactly one of the next unit.
    double size = a < base ? base : a;
    int unit = 0;
    for (double v = size; v >= base && unit < 6; v /= base) {
        ++unit;
    }
    // Decided from the number as the locale prints it, so the check and the output agree.
    bool ok = false;
    const double printed = l.toDouble(l.toString(size / std::pow(base, unit), 'f', precision), &ok);
    if (unit < 6 && ok && printed >= base) {
        size = std::pow(base, unit + 1);
    }
    return sign + l.formattedDataSize(qint64(size), precision, si ? QLocale::DataSizeSIFormat : QLocale::DataSizeIecFormat);
}

// "iec" (the default, and what an unknown name means) or "si".
bool isSi(const QString &system)
{
    return system == QLatin1String("si");
}

// The first letter in upper case by the locale's rules (Turkish dotted I); a
// script without case is left alone.
QString upperFirst(const QString &text, const QLocale &l)
{
    if (text.isEmpty()) {
        return text;
    }
    const qsizetype n = text.at(0).isHighSurrogate() && text.size() > 1 ? 2 : 1;
    return l.toUpper(text.left(n)) + text.mid(n);
}

QString twoDigits(qint64 v)
{
    return QStringLiteral("%1").arg(v, 2, 10, QLatin1Char('0'));
}

} // namespace

AtlasFormat::AtlasFormat(QObject *parent)
    : QObject(parent)
{
}

QString AtlasFormat::bytes(double n, int precision, const QString &locale, const QString &system) const
{
    return isNum(n) ? sized(n, precision, localeFor(locale), isSi(system)) : QString();
}

QString AtlasFormat::bytesPerSecond(double n, int precision, const QString &locale, const QString &system) const
{
    return isNum(n) ? QCoreApplication::translate("AtlasFormat", "%1/s", "a size per second, e.g. 1.5 MiB/s").arg(sized(n, precision, localeFor(locale), isSi(system))) : QString();
}

QString AtlasFormat::percent(double fraction, int precision, const QString &locale) const
{
    if (!isNum(fraction)) {
        return {};
    }
    precision = qBound(0, precision, kMaxPrecision);
    const QLocale l = localeFor(locale);
    const double v = roundsToZero(fraction * 100.0, precision);
    if (!isNum(v)) {
        return {};
    }
    const QString num = l.toString(v, 'f', precision);
    // Turkish writes the sign first.
    if (l.language() == QLocale::Turkish) {
        return l.percent() + num;
    }
    return num + percentSpace(l) + l.percent();
}

QString AtlasFormat::number(double n, int precision, const QString &locale) const
{
    if (!isNum(n)) {
        return {};
    }
    const QLocale l = localeFor(locale);
    const bool shortest = precision < 0;
    precision = shortest ? 6 : qMin(precision, kMaxPrecision);
    QString text = l.toString(roundsToZero(n, precision), 'f', precision);
    if (shortest && text.contains(l.decimalPoint())) {
        // The locale's own zero: Arabic-Indic digits are not '0'.
        const QString zero = l.zeroDigit();
        while (!zero.isEmpty() && text.endsWith(zero)) {
            text.chop(zero.size());
        }
        if (text.endsWith(l.decimalPoint())) {
            text.chop(l.decimalPoint().size());
        }
    }
    return text;
}

QString AtlasFormat::duration(double seconds, const QString &style, const QString &locale) const
{
    if (!isNum(seconds)) {
        return {};
    }
    const QLocale l = localeFor(locale);
    const bool negative = seconds < 0;
    const qint64 total = qint64(std::round(qMin(std::abs(seconds), kMaxSeconds)));
    const QString sign = negative && total > 0 ? l.negativeSign() : QString();

    const qint64 d = total / 86400;
    const qint64 h = total % 86400 / 3600;
    const qint64 m = total % 3600 / 60;
    const qint64 s = total % 60;

    if (style == QLatin1String("clock")) {
        const qint64 hours = total / 3600;
        const QString tail = twoDigits(m) + QLatin1Char(':') + twoDigits(s);
        return sign + (hours > 0 ? QString::number(hours) + QLatin1Char(':') + tail : tail);
    }

    const bool lng = style == QLatin1String("long");
    struct Unit
    {
        qint64 value;
        QString text;
    };
    const Unit units[] = {
        {d, lng ? plural(QT_TRANSLATE_N_NOOP("AtlasFormat", "%n day"), d, "%n days") : QCoreApplication::translate("AtlasFormat", "%1 d").arg(d)},
        {h, lng ? plural(QT_TRANSLATE_N_NOOP("AtlasFormat", "%n hour"), h, "%n hours") : QCoreApplication::translate("AtlasFormat", "%1 h").arg(h)},
        {m, lng ? plural(QT_TRANSLATE_N_NOOP("AtlasFormat", "%n minute"), m, "%n minutes") : QCoreApplication::translate("AtlasFormat", "%1 min").arg(m)},
        {s, lng ? plural(QT_TRANSLATE_N_NOOP("AtlasFormat", "%n second"), s, "%n seconds") : QCoreApplication::translate("AtlasFormat", "%1 s").arg(s)},
    };
    // The largest unit that is not zero, then the next one if it is not zero.
    int first = 0;
    while (first < 3 && units[first].value == 0) {
        ++first;
    }
    QString out = units[first].text;
    if (first < 3 && units[first + 1].value != 0) {
        out += QLatin1Char(' ') + units[first + 1].text;
    }
    return sign + out;
}

QString AtlasFormat::date(const QDateTime &d, const QString &style, const QString &locale, const QDateTime &nowArg) const
{
    if (!d.isValid()) {
        return {};
    }
    const QLocale l = localeFor(locale);
    if (style == QLatin1String("atTimeSentence") || style == QLatin1String("relativeSentence")) {
        const bool at = style == QLatin1String("atTimeSentence");
        return upperFirst(date(d, at ? QStringLiteral("atTime") : QStringLiteral("relative"), locale, nowArg), l);
    }
    const QDateTime when = d.toLocalTime();
    const QString shortDate = l.toString(when.date(), QLocale::ShortFormat);
    const QString shortTime = l.toString(when.time(), QLocale::ShortFormat);

    if (style == QLatin1String("long")) {
        return l.toString(when.date(), QLocale::LongFormat);
    }
    if (style == QLatin1String("longAtTime")) {
        return QCoreApplication::translate("AtlasFormat", "%1 at %2", "a date, then a time of day").arg(l.toString(when.date(), QLocale::LongFormat), shortTime);
    }
    if (style == QLatin1String("dateTime")) {
        return l.toString(when, QLocale::ShortFormat);
    }
    if (style == QLatin1String("time")) {
        return shortTime;
    }
    if (style != QLatin1String("atTime") && style != QLatin1String("relative")) {
        return shortDate;
    }

    const QDateTime now = (nowArg.isValid() ? nowArg : QDateTime::currentDateTime()).toLocalTime();
    const qint64 days = now.date().toJulianDay() - when.date().toJulianDay(); // > 0: in the past

    if (style == QLatin1String("atTime")) {
        if (days == 0) {
            return QCoreApplication::translate("AtlasFormat", "today at %1").arg(shortTime);
        }
        if (days == 1) {
            return QCoreApplication::translate("AtlasFormat", "yesterday at %1").arg(shortTime);
        }
        return QCoreApplication::translate("AtlasFormat", "%1 at %2", "a date, then a time of day").arg(shortDate, shortTime);
    }

    // relative
    const qint64 secs = when.secsTo(now); // > 0: in the past
    const qint64 a = qAbs(secs);
    const bool past = secs >= 0;
    if (a < 60) {
        return QCoreApplication::translate("AtlasFormat", "just now");
    }
    if (a < 3600) {
        const qint64 n = a / 60;
        return past ? plural(QT_TRANSLATE_N_NOOP("AtlasFormat", "%n minute ago"), n, "%n minutes ago") : plural(QT_TRANSLATE_N_NOOP("AtlasFormat", "in %n minute"), n, "in %n minutes");
    }
    // Within a day: hours, unless it crossed midnight a good while ago.
    if (a < 86400 && (days == 0 || a < 6 * 3600)) {
        const qint64 n = a / 3600;
        return past ? plural(QT_TRANSLATE_N_NOOP("AtlasFormat", "%n hour ago"), n, "%n hours ago") : plural(QT_TRANSLATE_N_NOOP("AtlasFormat", "in %n hour"), n, "in %n hours");
    }
    if (days == 1) {
        return QCoreApplication::translate("AtlasFormat", "yesterday");
    }
    if (days == -1) {
        return QCoreApplication::translate("AtlasFormat", "tomorrow");
    }
    if (days > 1 && days < 7) {
        return plural(QT_TRANSLATE_N_NOOP("AtlasFormat", "%n day ago"), days, "%n days ago");
    }
    if (days < -1 && days > -7) {
        return plural(QT_TRANSLATE_N_NOOP("AtlasFormat", "in %n day"), -days, "in %n days");
    }
    return shortDate;
}
