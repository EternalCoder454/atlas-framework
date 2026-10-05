#include "variant.h"

#include <QColor>
#include <QFile>
#include <QFont>
#include <QGuiApplication>
#include <QPalette>

namespace AtlasVariant {

namespace {

// The accent colour of the `accent` variant, #e5487a.
constexpr const char *kAccent = "229,72,122";

QByteArray resource(const char *name)
{
    QFile file(QStringLiteral(":/atlas-preview/schemes/") + QLatin1String(name));
    return file.open(QIODevice::ReadOnly) ? file.readAll() : QByteArray();
}

// What Plasma writes when an accent colour is chosen: the colour in the
// highlight, focus and hover decorations, and the selection background.
QByteArray withAccent(const QByteArray &scheme)
{
    QByteArray out;
    QByteArray section;
    for (const QByteArray &line : scheme.split('\n')) {
        QByteArray l = line;
        if (l.startsWith('[')) {
            section = l;
        }
        if (l.startsWith("DecorationFocus=") || l.startsWith("DecorationHover=")
            || (section.startsWith("[Colors:Selection]") && l.startsWith("BackgroundNormal="))) {
            l = l.left(l.indexOf('=') + 1) + kAccent;
        }
        out += l + '\n';
    }
    out += QByteArray("\n[General]\nAccentColor=") + kAccent + "\n";
    return out;
}

} // namespace

QStringList names()
{
    return {QStringLiteral("light"), QStringLiteral("dark"),     QStringLiteral("accent"),  QStringLiteral("opaque"),
            QStringLiteral("rtl"),   QStringLiteral("text200"), QStringLiteral("compact"), QStringLiteral("contrast")};
}

bool isValid(const QString &variant)
{
    return names().contains(variant);
}

void applyToApplication(const QString &variant)
{
    // A fixed font, so the pictures do not depend on the machine's setting.
    // text200 doubles it, as a desktop set to 200% text does (the font's
    // point size over the default 10 is Appearance.textScale).
    QGuiApplication::setFont(QFont(QStringLiteral("Noto Sans"), variant == QLatin1String("text200") ? 20 : 10));
    if (variant == QLatin1String("contrast")) {
        // The portal theme (see fakeportal.cpp) brings Qt's own palette and
        // Kirigami follows it, not kdeglobals: give it the colours of
        // schemes/BreezeHighContrast.colors.
        QPalette p;
        const QColor black(0, 0, 0), white(255, 255, 255), yellow(255, 255, 0), grey(40, 40, 40);
        p.setColor(QPalette::Window, black);
        p.setColor(QPalette::WindowText, white);
        p.setColor(QPalette::Base, black);
        p.setColor(QPalette::AlternateBase, QColor(28, 28, 28));
        p.setColor(QPalette::Text, white);
        p.setColor(QPalette::Button, black);
        p.setColor(QPalette::ButtonText, white);
        p.setColor(QPalette::Highlight, yellow);
        p.setColor(QPalette::HighlightedText, black);
        p.setColor(QPalette::ToolTipBase, black);
        p.setColor(QPalette::ToolTipText, white);
        p.setColor(QPalette::PlaceholderText, QColor(200, 200, 200));
        p.setColor(QPalette::Link, QColor(102, 204, 255));
        p.setColor(QPalette::LinkVisited, QColor(230, 150, 255));
        p.setColor(QPalette::Light, grey);
        p.setColor(QPalette::Mid, QColor(160, 160, 160));
        p.setColor(QPalette::Dark, white);
        p.setColor(QPalette::Disabled, QPalette::WindowText, QColor(150, 150, 150));
        p.setColor(QPalette::Disabled, QPalette::Text, QColor(150, 150, 150));
        p.setColor(QPalette::Disabled, QPalette::ButtonText, QColor(150, 150, 150));
        QGuiApplication::setPalette(p);
    }
    // rtl: an Arabic or Hebrew desktop sets the application's layout
    // direction, and every item and window mirrors with it.
    if (variant == QLatin1String("rtl")) {
        QGuiApplication::setLayoutDirection(Qt::RightToLeft);
    }
}

QByteArray kdeglobals(const QString &variant)
{
    if (!isValid(variant)) {
        return {};
    }
    if (variant == QLatin1String("dark")) {
        return resource("BreezeDark.colors");
    }
    if (variant == QLatin1String("contrast")) {
        return resource("BreezeHighContrast.colors");
    }
    const QByteArray light = resource("BreezeLight.colors");
    return variant == QLatin1String("accent") && !light.isEmpty() ? withAccent(light) : light;
}

bool transparencyOff(const QString &variant)
{
    return variant == QLatin1String("opaque");
}

} // namespace AtlasVariant
