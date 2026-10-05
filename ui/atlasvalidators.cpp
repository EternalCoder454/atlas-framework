#include "atlasvalidators.h"

#include <QDir>
#include <QFileInfo>
#include <QLocale>
#include <QUrl>

#include <cmath>
#include <limits>

namespace {
// Longest text any of the validators looks at. Longer is Invalid.
constexpr int kMaxUrl = 2048;
constexpr int kMaxEmail = 254;
constexpr int kMaxLocalPart = 64;
constexpr int kMaxPath = 4096;
constexpr int kMaxNumber = 64;

bool hasControl(const QString &s)
{
    for (const QChar c : s) {
        if (c.unicode() < 0x20 || c.unicode() == 0x7f || c.category() == QChar::Other_Control) {
            return true;
        }
    }
    return false;
}

bool hasSpace(const QString &s)
{
    for (const QChar c : s) {
        if (c.isSpace()) {
            return true;
        }
    }
    return false;
}
}

// URL

AtlasUrlValidator::AtlasUrlValidator(QObject *parent)
    : QValidator(parent)
    , m_schemes{QStringLiteral("https")}
{
}

void AtlasUrlValidator::setSchemes(const QStringList &schemes)
{
    if (schemes == m_schemes) {
        return;
    }
    m_schemes = schemes;
    Q_EMIT schemesChanged();
    Q_EMIT changed();
}

// True when scheme-less text such as "example.com" or "example.com:8080/a" is a
// host and path of an http(s) URL; fixup() then puts the first scheme in front.
static bool bareHost(const QStringList &schemes, const QString &text)
{
    if (schemes.isEmpty()) {
        return false;
    }
    const QString first = schemes.first().toLower();
    if (first != QLatin1String("http") && first != QLatin1String("https")) {
        return false;
    }
    const QUrl url(first + QStringLiteral("://") + text, QUrl::StrictMode);
    return url.isValid() && !url.host().isEmpty();
}

// Text with a colon that is not an allowed scheme: a bare host with a port,
// "example.com:8080", is the only such text that is a URL.
static bool hostWithPort(const QStringList &schemes, const QString &text, qsizetype colon)
{
    const QString rest = text.mid(colon + 1);
    qsizetype end = 0;
    while (end < rest.size() && rest.at(end).isDigit()) {
        ++end;
    }
    const bool port = end > 0 && (end == rest.size() || QStringLiteral("/?#").contains(rest.at(end)));
    return port && bareHost(schemes, text);
}

static bool isScheme(const QStringList &schemes, const QString &scheme)
{
    for (const QString &s : schemes) {
        if (s.compare(scheme, Qt::CaseInsensitive) == 0) {
            return true;
        }
    }
    return false;
}

// True when the (trimmed) text is a host that needs the first scheme put in
// front: the same conditions validate() accepts a bare host under. Text that
// has "://", an allowed scheme, or a colon not followed only by a port is not.
static bool needsScheme(const QStringList &schemes, const QString &text)
{
    if (text.isEmpty() || text.contains(QStringLiteral("://"))) {
        return false;
    }
    const qsizetype colon = text.indexOf(QLatin1Char(':'));
    if (colon < 0) {
        return bareHost(schemes, text);
    }
    return !isScheme(schemes, text.left(colon)) && hostWithPort(schemes, text, colon);
}

QValidator::State AtlasUrlValidator::validate(QString &input, int &) const
{
    if (input.size() > kMaxUrl) {
        return Invalid;
    }
    const QString text = input.trimmed();
    if (text.isEmpty()) {
        return Intermediate;
    }
    // Spaces inside, NUL and other control characters never become a URL.
    if (hasControl(text) || hasSpace(text)) {
        return Invalid;
    }
    const bool padded = text.size() != input.size();
    const QString lower = text.toLower();
    const qsizetype colon = text.indexOf(QLatin1Char(':'));
    if (colon < 0) {
        // Still typing the scheme: it must be the start of an allowed one.
        for (const QString &scheme : m_schemes) {
            if (scheme.toLower().startsWith(lower)) {
                return Intermediate;
            }
        }
        return bareHost(m_schemes, text) ? Intermediate : Invalid;
    }
    const QString scheme = lower.left(colon);
    if (!isScheme(m_schemes, scheme)) {
        return hostWithPort(m_schemes, text, colon) ? Intermediate : Invalid;
    }
    const QUrl url(text, QUrl::StrictMode);
    if (!url.isValid()) {
        return Intermediate;
    }
    if ((scheme == QLatin1String("http") || scheme == QLatin1String("https")) && url.host().isEmpty()) {
        return Intermediate;
    }
    // Surrounding whitespace is removed by fixup(), so it is not final yet.
    return padded ? Intermediate : Acceptable;
}

void AtlasUrlValidator::fixup(QString &input) const
{
    input = input.trimmed();
    // "example.com" becomes "https://example.com" (the first scheme). Only a bare
    // host, with a port or path: a bad scheme such as ftp:// stays as typed.
    if (needsScheme(m_schemes, input)) {
        input = m_schemes.first() + QStringLiteral("://") + input;
    }
}

// Email

AtlasEmailValidator::AtlasEmailValidator(QObject *parent)
    : QValidator(parent)
{
}

QValidator::State AtlasEmailValidator::validate(QString &input, int &) const
{
    if (input.size() > kMaxEmail) {
        return Invalid;
    }
    const QString text = input.trimmed();
    if (text.isEmpty()) {
        return Intermediate;
    }
    if (hasControl(text) || hasSpace(text)) {
        return Invalid;
    }
    const qsizetype at = text.indexOf(QLatin1Char('@'));
    if (at < 0) {
        return Intermediate;
    }
    if (text.indexOf(QLatin1Char('@'), at + 1) >= 0) {
        return Invalid;
    }
    const QString local = text.left(at);
    const QString domain = text.mid(at + 1);
    if (local.size() > kMaxLocalPart) {
        return Invalid;
    }
    // Characters that are legal only in quoted local parts, and that let an
    // address smuggle extra recipients or parameters into mailto: or a header.
    static const QString special = QStringLiteral(",;<>\"()[]\\:?&%#");
    for (const QChar c : local) {
        if (special.contains(c) || c.category() == QChar::Other_Format) {
            return Invalid;
        }
    }
    for (const QChar c : domain) {
        if (!(c.isLetterOrNumber() || c == QLatin1Char('-') || c == QLatin1Char('.'))) {
            return Invalid;
        }
    }
    if (local.isEmpty() || domain.isEmpty() || !domain.contains(QLatin1Char('.'))) {
        return Intermediate;
    }
    if (local.startsWith(QLatin1Char('.')) || local.endsWith(QLatin1Char('.')) || local.contains(QLatin1String(".."))) {
        return Intermediate;
    }
    const QStringList labels = domain.split(QLatin1Char('.'));
    for (const QString &label : labels) {
        if (label.isEmpty() || label.startsWith(QLatin1Char('-')) || label.endsWith(QLatin1Char('-'))) {
            return Intermediate;
        }
    }
    return text.size() != input.size() ? Intermediate : Acceptable;
}

void AtlasEmailValidator::fixup(QString &input) const
{
    input = input.trimmed();
}

// Path

AtlasPathValidator::AtlasPathValidator(QObject *parent)
    : QValidator(parent)
{
}

void AtlasPathValidator::setAbsolute(bool on)
{
    if (on != m_absolute) {
        m_absolute = on;
        Q_EMIT absoluteChanged();
        Q_EMIT changed();
    }
}

void AtlasPathValidator::setMustExist(bool on)
{
    if (on != m_mustExist) {
        m_mustExist = on;
        Q_EMIT mustExistChanged();
        Q_EMIT changed();
    }
}

void AtlasPathValidator::setDirectory(bool on)
{
    if (on != m_directory) {
        m_directory = on;
        Q_EMIT directoryChanged();
        Q_EMIT changed();
    }
}

QValidator::State AtlasPathValidator::validate(QString &input, int &) const
{
    if (input.size() > kMaxPath || hasControl(input)) {
        return Invalid;
    }
    if (input.isEmpty()) {
        return Intermediate;
    }
    QString path = input;
    if (path.startsWith(QLatin1Char('~'))) {
        if (path.size() > 1 && path.at(1) != QLatin1Char('/')) {
            // "~user" is not supported.
            return Invalid;
        }
        path = QDir::homePath() + path.mid(1);
    } else if (m_absolute && !path.startsWith(QLatin1Char('/'))) {
        return Invalid;
    }
    if (!m_mustExist) {
        return Acceptable;
    }
    // QFileInfo asks the file system; there is no shell and no expansion.
    const QFileInfo info(path);
    if (m_directory ? info.isDir() : info.exists()) {
        return Acceptable;
    }
    return Intermediate;
}

// Number

AtlasNumberValidator::AtlasNumberValidator(QObject *parent)
    : QValidator(parent)
    , m_bottom(-std::numeric_limits<qreal>::infinity())
    , m_top(std::numeric_limits<qreal>::infinity())
{
}

void AtlasNumberValidator::setBottom(qreal bottom)
{
    if (std::isnan(bottom) || bottom == m_bottom) {
        return;
    }
    m_bottom = bottom;
    Q_EMIT bottomChanged();
    Q_EMIT changed();
}

void AtlasNumberValidator::setTop(qreal top)
{
    if (std::isnan(top) || top == m_top) {
        return;
    }
    m_top = top;
    Q_EMIT topChanged();
    Q_EMIT changed();
}

void AtlasNumberValidator::setDecimals(int decimals)
{
    decimals = qBound(0, decimals, 15);
    if (decimals == m_decimals) {
        return;
    }
    m_decimals = decimals;
    Q_EMIT decimalsChanged();
    Q_EMIT changed();
}

void AtlasNumberValidator::setLocaleName(const QString &name)
{
    const QLocale wanted = name.isEmpty() ? QLocale() : QLocale(name);
    if (wanted == locale()) {
        return;
    }
    setLocale(wanted);
    Q_EMIT localeNameChanged(); // QValidator::setLocale() emits changed() itself
}

void AtlasNumberValidator::configure(QDoubleValidator &inner) const
{
    inner.setLocale(locale());
    inner.setNotation(QDoubleValidator::StandardNotation);
    inner.setDecimals(m_decimals);
    inner.setRange(m_bottom, m_top, m_decimals);
}

QValidator::State AtlasNumberValidator::validate(QString &input, int &pos) const
{
    if (input.size() > kMaxNumber || hasControl(input)) {
        return Invalid;
    }
    if (input.isEmpty()) {
        return Intermediate;
    }
    QDoubleValidator inner;
    configure(inner);
    const State state = inner.validate(input, pos);
    // "1." is a number to Qt, but the user is still typing the decimals.
    if (state == Acceptable && input.endsWith(locale().decimalPoint())) {
        return Intermediate;
    }
    return state;
}

void AtlasNumberValidator::fixup(QString &input) const
{
    // Enter or focus-out must never leave the user stuck: drop a trailing
    // decimal point ("1." becomes "1") and pull a number outside the range back
    // to the nearest end of it.
    input = input.trimmed();
    if (input.endsWith(locale().decimalPoint())) {
        input.chop(locale().decimalPoint().size());
    }
    bool ok = false;
    const double v = locale().toDouble(input, &ok);
    if (!ok || std::isnan(v)) {
        return;
    }
    const double clamped = qBound(m_bottom, v, m_top);
    if (clamped != v) {
        input = locale().toString(clamped, 'f', QLocale::FloatingPointShortest);
    }
}
