pragma Singleton
import QtQuick
import org.kde.kirigami as Kirigami
import Atlas.Ui

// AtlasStyle: the design tokens of Atlas apps, in one place. A control or an
// app reads `AtlasStyle.radius` instead of a bare 8, so the look can change
// in one file and every app follows. Everything is read-only except `density`.
//
//   Rectangle {
//       color: AtlasStyle.surface
//       radius: AtlasStyle.radius
//       border.color: AtlasStyle.separator
//       Behavior on color { ColorAnimation { duration: AtlasStyle.durationShort } }
//   }
//
// Colours (follow the system colour scheme and accent, light or dark):
//   accent, accentText      the accent colour, and text readable on it
//   surface                 a raised card over the page (Section's card)
//   surfaceAlt              the alternate row colour of the colour scheme
//   text, textMuted         body text, and secondary text (65% of text)
//   separator               hairlines and card borders
//   success, warning, error  the scheme's positive, neutral and negative text
//
// Spacing: spacingSmall, spacing, spacingLarge (Kirigami.Units small, medium
// and large spacing, in pixels).
//
// Radii: radiusSmall 6 (checkboxes, small buttons, menu items), radius 8
// (list items, steps, tooltips), radiusLarge 10 (cards, menus, banners),
// radiusPill (any height: the button and text field rule, radius = height / 2
// is the same look; use `height / 2` when the exact value matters).
//
// Font sizes, in points, from the application font: fontSizeCaption (footers,
// 0.92 of body), fontSizeBody, fontSizeHeading (dialog titles, 1.15),
// fontSizeTitle (page titles, 1.6).
//
// Motion: durationShort, duration, durationLong (Kirigami.Units short, long
// and very long duration, in ms). They
// are all 0 when `reducedMotion` is true, and `reducedMotion` follows
// Appearance.reducedMotion (Plasma's animation speed set to instant, or
// ATLAS_REDUCED_MOTION=1). A running animation or Behavior reads one of the
// durations; an animation that has no duration (a spinner) checks
// `reducedMotion`.
//
// Density: `density` is AtlasStyle.Normal (0) or AtlasStyle.Compact (1), set
// by the app. `compact` is the same as a bool, and `rowHeight` is the height
// of a list or SectionRow row for the density: Normal is 2.5 grid units,
// Compact 75% of it.
//
// highContrast and textScale pass Appearance's values through.
QtObject {
    id: root

    enum Density {
        Normal,
        Compact
    }

    // Kirigami.Theme is attached to an item, and only an item inside a window
    // gets the real colours (a loose one reads black). This one sits in a
    // window that is never shown, and carries the Window colour set so the
    // colours do not depend on the caller.
    readonly property Window _window: Window {
        visible: false
        Item {
            id: probe
            Kirigami.Theme.colorSet: Kirigami.Theme.Window
        }
    }
    readonly property Item _theme: probe

    readonly property color accent: _theme.Kirigami.Theme.highlightColor
    readonly property color accentText: _theme.Kirigami.Theme.highlightedTextColor
    readonly property color surface: {
        const bg = _theme.Kirigami.Theme.backgroundColor;
        return bg.hslLightness > 0.5 ? Qt.lighter(bg, 1.5) : Qt.tint(bg, Qt.rgba(1, 1, 1, 0.06));
    }
    readonly property color surfaceAlt: _theme.Kirigami.Theme.alternateBackgroundColor
    readonly property color text: _theme.Kirigami.Theme.textColor
    readonly property color textMuted: Qt.alpha(_theme.Kirigami.Theme.textColor, 0.65)
    readonly property color separator: Qt.alpha(_theme.Kirigami.Theme.textColor, 0.12)
    readonly property color success: _theme.Kirigami.Theme.positiveTextColor
    readonly property color warning: _theme.Kirigami.Theme.neutralTextColor
    readonly property color error: _theme.Kirigami.Theme.negativeTextColor

    readonly property real spacingSmall: Kirigami.Units.smallSpacing
    readonly property real spacing: Kirigami.Units.mediumSpacing
    readonly property real spacingLarge: Kirigami.Units.largeSpacing

    readonly property real radiusSmall: 6
    readonly property real radius: 8
    readonly property real radiusLarge: 10
    readonly property real radiusPill: 1000

    readonly property real fontSizeCaption: _theme.Kirigami.Theme.defaultFont.pointSize * 0.92
    readonly property real fontSizeBody: _theme.Kirigami.Theme.defaultFont.pointSize
    readonly property real fontSizeHeading: _theme.Kirigami.Theme.defaultFont.pointSize * 1.15
    readonly property real fontSizeTitle: _theme.Kirigami.Theme.defaultFont.pointSize * 1.6

    readonly property bool reducedMotion: Appearance.reducedMotion
    readonly property int durationShort: reducedMotion ? 0 : Kirigami.Units.shortDuration
    readonly property int duration: reducedMotion ? 0 : Kirigami.Units.longDuration
    readonly property int durationLong: reducedMotion ? 0 : Kirigami.Units.veryLongDuration

    property int density: AtlasStyle.Normal
    readonly property bool compact: density === AtlasStyle.Compact
    readonly property real rowHeight: {
        const normal = Math.round(Kirigami.Units.gridUnit * 2.5);
        return compact ? Math.round(normal * 0.75) : normal;
    }

    readonly property bool highContrast: Appearance.highContrast
    readonly property real textScale: Appearance.textScale
}
