// The visual-test matrix, shared by tests/visual (the goldens) and
// atlas-preview: which variants there are, and what each one does to the
// application (font, palette, layout direction) and to its configuration
// (colour scheme, transparency).
#pragma once

#include <QByteArray>
#include <QString>
#include <QStringList>

namespace AtlasVariant {

// light, dark, accent, opaque, rtl, text200, compact, contrast.
QStringList names();
bool isValid(const QString &variant);

// The font, palette and layout direction of the variant. Call it before the
// first window exists (from QQmlEngine setup or right after the application
// object). An unknown name behaves as light.
void applyToApplication(const QString &variant);

// The kdeglobals the variant runs with: a Breeze scheme, with the accent
// colour for `accent`. Empty for an unknown variant.
QByteArray kdeglobals(const QString &variant);

// True when the variant runs with transparency off (atlasrc: [Appearance] Transparency=false).
bool transparencyOff(const QString &variant);

} // namespace AtlasVariant
