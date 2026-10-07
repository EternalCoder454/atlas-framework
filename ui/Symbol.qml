import QtQuick
import org.kde.kirigami as Kirigami

// One Material Symbol, tinted like text. Pick one by value (checked at build
// time) or by Google's name:
//
//   Symbol { icon: Symbols.Settings }
//   Symbol { name: "arrow_back"; size: 24 }
//   Symbol { icon: Symbols.Favorite; filled: liked; color: Kirigami.Theme.negativeTextColor }
//   Symbol { icon: Symbols.Home; style: Symbol.Sharp; weight: 300 }
//
// Browse them all with the telamon-symbols gallery (ui/gallery) or at
// fonts.google.com/icons. Decorative: screen readers skip it, so give the
// control around it the accessible name.
Item {
    id: root

    enum Style {
        Outlined,
        Rounded,
        Sharp
    }

    // Symbols.<Name>, or 0 to use `name`.
    property int icon: 0
    // Google's name ("arrow_back"), used when `icon` is 0.
    property string name
    property int style: Symbol.Rounded
    property real size: Kirigami.Units.iconSizes.smallMedium
    property color color: Kirigami.Theme.textColor
    // The solid version. Changes to `fill` animate, including ones set
    // directly (0 to 1) for anything in between.
    property bool filled: false
    property real fill: filled ? 1 : 0
    // Stroke weight, 100 (thin) to 700 (bold). 400 matches regular text.
    property int weight: 400
    // Finer weight changes that keep the symbol's size, -50 to 200. Light
    // symbols on a dark background look heavier: -25 evens them out.
    property int grade: 0

    readonly property int codepoint: icon !== 0 ? icon : name.length > 0 ? Symbols.codepoint(name) : 0

    implicitWidth: size
    implicitHeight: size
    Accessible.ignored: true

    Behavior on fill {
        NumberAnimation {
            duration: TelamonStyle.durationShort
            easing.type: Easing.OutCubic
        }
    }

    Text {
        // The fonts put each symbol in the middle of its line, so centring the
        // text centres the symbol.
        anchors.centerIn: parent
        text: root.codepoint > 0 ? String.fromCodePoint(root.codepoint) : ""
        textFormat: Text.PlainText
        color: root.color
        // Only once there is something to draw: an empty Symbol doesn't load the fonts.
        font.family: root.codepoint > 0 ? Symbols.family(root.style) : ""
        font.pixelSize: Math.max(1, Math.round(root.size))
        font.hintingPreference: Font.PreferNoHinting
        // The optical size follows the drawn size, so small symbols get the
        // sturdier strokes the font draws for them.
        font.variableAxes: ({
                "FILL": root.fill,
                "wght": root.weight,
                "GRAD": root.grade,
                "opsz": Math.max(20, Math.min(48, root.size))
            })
    }
}
