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
// Durations beyond this many seconds are clamped (about 285 billion years).
constexpr double kMaxSeconds = 9.0e18;
constexpr int kMaxPrecision = 10;

QString tr(const char *source, const char *comment = nullptr)
{
    return QCoreApplication::translate("AtlasFormat", source, comment);
}

// A plural: the catalogue's forms of `one` for n, or, when nothing is
// translated (the source language), English: `one` for 1, `many` otherwise.
// lupdate sees `one` only, so `many` is a source-language fallback.
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

QString sized(double n, int precision, const QLocale &l)
{
    precision = qBound(0, precision, kMaxPrecision);
    const double a = std::abs(n);
    const QString sign = n < 0 ? l.negativeSign() : QString();
    if (a < 1024.0) {
        // "0 B": QLocale would say "0 bytes".
        const double whole = std::round(a);
        return (whole > 0 ? sign : QString()) + tr("%1 B").arg(l.toString(whole, 'f', 0));
    }
    if (a >= kMaxInt64Size) {
        return sign + l.toString(a / double(Q_INT64_C(1) << 60), 'f', precision) + QLatin1String(" EiB");
    }
    return sign + l.formattedDataSize(qint64(a), precision, QLocale::DataSizeIecFormat);
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

QString AtlasFormat::bytes(double n, int precision, const QString &locale) const
{
    return isNum(n) ? sized(n, precision, localeFor(locale)) : QString();
}

QString AtlasFormat::bytesPerSecond(double n, int precision, const QString &locale) const
{
    return isNum(n) ? tr("%1/s", "a size per second, e.g. 1.5 MiB/s").arg(sized(n, precision, localeFor(locale))) : QString();
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
        while (text.endsWith(QLatin1Char('0'))) {
            text.chop(1);
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
        {d, lng ? plural("%n day", d, "%n days") : tr("%1 d").arg(d)},
        {h, lng ? plural("%n hour", h, "%n hours") : tr("%1 h").arg(h)},
        {m, lng ? plural("%n minute", m, "%n minutes") : tr("%1 min").arg(m)},
        {s, lng ? plural("%n second", s, "%n seconds") : tr("%1 s").arg(s)},
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
    const QDateTime when = d.toLocalTime();
    const QString shortDate = l.toString(when.date(), QLocale::ShortFormat);
    const QString shortTime = l.toString(when.time(), QLocale::ShortFormat);

    if (style == QLatin1String("long")) {
        return l.toString(when.date(), QLocale::LongFormat);
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
            return tr("today at %1").arg(shortTime);
        }
        if (days == 1) {
            return tr("yesterday at %1").arg(shortTime);
        }
        return tr("%1 at %2", "a date, then a time of day").arg(shortDate, shortTime);
    }

    // relative
    const qint64 secs = when.secsTo(now); // > 0: in the past
    const qint64 a = qAbs(secs);
    const bool past = secs >= 0;
    if (a < 60) {
        return tr("just now");
    }
    if (a < 3600) {
        const qint64 n = a / 60;
        return past ? plural("%n minute ago", n, "%n minutes ago") : plural("in %n minute", n, "in %n minutes");
    }
    // Within a day: hours, unless it crossed midnight a good while ago.
    if (a < 86400 && (days == 0 || a < 6 * 3600)) {
        const qint64 n = a / 3600;
        return past ? plural("%n hour ago", n, "%n hours ago") : plural("in %n hour", n, "in %n hours");
    }
    if (days == 1) {
        return tr("yesterday");
    }
    if (days == -1) {
        return tr("tomorrow");
    }
    if (days > 1 && days < 7) {
        return plural("%n day ago", days, "%n days ago");
    }
    if (days < -1 && days > -7) {
        return plural("in %n day", -days, "in %n days");
    }
    return shortDate;
}
