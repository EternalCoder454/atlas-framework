// AtlasFormat: one way to show sizes, speeds, percentages, numbers, durations
// and dates, so every Atlas app spells them alike and in the user's language.
// Every function takes an optional last `locale` ("de_DE", "en"); without one
// it uses the application's QLocale. The unit and wording strings belong to
// Atlas.Ui and are translated with its catalogue (a translation follows the
// application's language, not the `locale` argument; that one only decides
// digits, separators and date formats).
//
// A value that is not a number (NaN, infinity) or a date that is invalid gives
// "", never "NaN". A negative size or duration keeps its sign. An unknown
// duration or date `style` is treated as the default one.
//
//   Label { text: AtlasFormat.bytes(file.size) }                  // "1.5 MiB"
//   Label { text: AtlasFormat.percent(progress) }                 // "42%"
//   Label { text: AtlasFormat.duration(remaining) }               // "1 h 5 min"
//   Label { text: AtlasFormat.date(modified, "relative") }        // "5 minutes ago"
//
// date() styles: "short", "long", "dateTime", "time", "atTime" ("today at
// 14:05"), "relative" ("just now", "3 hours ago", "yesterday", "in 5 minutes";
// a date a week or more away shows its short form). "atTime" and "relative"
// take the moment to compare with as `now` (default: the current time).
#pragma once

#include <QDateTime>
#include <QObject>
#include <QString>
#include <QtQml/qqmlregistration.h>

class AtlasFormat : public QObject
{
    Q_OBJECT
    QML_NAMED_ELEMENT(AtlasFormat)
    QML_SINGLETON

public:
    explicit AtlasFormat(QObject *parent = nullptr);

    // IEC units: "0 B", "512 B", "1.5 KiB", "3.2 GiB". precision 0..10.
    Q_INVOKABLE QString bytes(double n, int precision = 1, const QString &locale = QString()) const;
    // "1.5 MiB/s"
    Q_INVOKABLE QString bytesPerSecond(double n, int precision = 1, const QString &locale = QString()) const;
    // 0.423 -> "42%" (en), "42 %" (de)
    Q_INVOKABLE QString percent(double fraction, int precision = 0, const QString &locale = QString()) const;
    // Grouped by the locale; precision -1 is the shortest exact form, up to 6 decimals.
    Q_INVOKABLE QString number(double n, int precision = -1, const QString &locale = QString()) const;
    // style "short" ("1 h 5 min", two largest units), "long" ("1 hour 5
    // minutes") or "clock" ("1:05:09", "05:09").
    Q_INVOKABLE QString duration(double seconds, const QString &style = QStringLiteral("short"),
                                 const QString &locale = QString()) const;
    Q_INVOKABLE QString date(const QDateTime &d, const QString &style = QStringLiteral("short"),
                             const QString &locale = QString(), const QDateTime &now = QDateTime()) const;
};
