// Symbols: Google's Material Symbols, about 4,000 icons in three styles
// (Outlined, Rounded, Sharp), for any Telamon app. Draw one with Symbol:
//
//   Symbol { icon: Symbols.Settings }
//   Symbol { name: "arrow_back"; filled: true }
//
// Every symbol is a value of Symbols (Symbols.ArrowBack, Symbols.TenK for
// "10k"), whose value is its codepoint in the fonts, so qmllint (the
// <app>_qmllint target) catches a misspelled one. `name` takes the name Google
// lists it under at fonts.google.com/icons, or one of its older names, and
// warns at run time if there is no such symbol.
//
// The Rounded font (the default) is installed by the telamon-symbols-fonts
// package; Outlined and Sharp by telamon-symbols-fonts-extra. A missing Rounded
// is reported when the fonts load, a missing Outlined or Sharp when a Symbol
// first asks for it. Without the packages, a
// development build (any install prefix but /usr) loads them from
// $TELAMON_UI_SYMBOLS_DIR or ui/symbols/. A packaged build reads neither.
#pragma once

#include "symbols/symbolnames.h"

#include <QObject>
#include <QStringList>
#include <QtQml/qqmlregistration.h>

class Symbols : public QObject
{
    Q_OBJECT
    QML_NAMED_ELEMENT(Symbols)
    QML_SINGLETON
    QML_EXTENDED_NAMESPACE(SymbolNames)

public:
    explicit Symbols(QObject *parent = nullptr);

    // The codepoint for a name ("arrow_back", "arrow-back", "ArrowBack" or an
    // older name such as "check_circle_outline"); 0, with a warning, for none.
    Q_INVOKABLE int codepoint(const QString &name) const;
    // Google's name for a codepoint ("arrow_back"); empty for none.
    Q_INVOKABLE QString name(int codepoint) const;
    // The QML name for a codepoint ("ArrowBack", for Symbols.ArrowBack).
    Q_INVOKABLE QString key(int codepoint) const;
    // Every symbol's name, sorted, without the older names.
    Q_INVOKABLE QStringList names() const;
    // The font family of a Symbol.Style (0 Outlined, 1 Rounded, 2 Sharp).
    Q_INVOKABLE QString family(int style) const;
    // Whether the font of a Symbol.Style is installed (no warning if not).
    Q_INVOKABLE bool available(int style) const;

    // codepoint() without the warning, for C++.
    static int lookup(QStringView name);

private:
    static void loadFonts();
    static bool resolveStyle(int style);
};
