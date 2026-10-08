pragma Singleton
import QtQuick
import org.kde.kirigami as Kirigami
import Telamon.Ui

// TelamonStyle: the design tokens of Telamon apps, in one place. A control or an
// app reads `TelamonStyle.radius` instead of a bare 8, so the look can change
// in one file and every app follows. Everything is read-only except `density`.
//
//   Rectangle {
//       color: TelamonStyle.surface
//       radius: TelamonStyle.radius
//       border.color: TelamonStyle.separator
//       Behavior on color { ColorAnimation { duration: TelamonStyle.durationShort } }
//   }
//
// Colours follow the system colour scheme, light or dark, with the neutrals
// tinted slightly toward Telamon violet (not under high contrast). Light and
// Dark are tuned separately.
//   accent                  selection, indicators, checked states: Telamon violet
//                           (#6858E2 light, #8A7AF4 dark) unless the user chose
//                           an accent in Plasma, which then wins
//   accentText              text readable on `accent`
//   accentStrong            the prominent (primary) button fill: the darker
//                           violet in Light (#5B4BD6, 6:1 with white), the
//                           brighter one in Dark (#A396F7)
//   accentStrongText        text on `accentStrong` (4.5:1 or more)
//   focus                   the keyboard focus ring: the accent, nudged
//                           toward the text colour only when it would fall
//                           under 3:1 against the window, a control or a
//                           raised surface (the Telamon violet never is)
//   base                    the window background (tonal step 0)
//   surface                 a card over the page (Section's card, step 1)
//   surfaceRaised           menus, popovers, dialogs, tooltips (step 2)
//   control                 the fill of fields and default buttons (step 3)
//   codeSurface             a code view's own background
//   surfaceAlt              the alternate row colour of the colour scheme
//   hover, pressed          grey overlays for hover and press, never the
//                           accent, so hover never looks like selection
//   selection               a selected row or item (quiet accent tint);
//                           selectionInactive when the view has no focus
//   text, textMuted         body text; secondary info ("Step 2 of 2"),
//                           captions, units (65% of text)
//   textDisabled            disabled text, still readable (55% of text)
//   separator               decorative hairlines and card borders (light)
//   controlBorder           control edges (stronger than separator)
//   outline                 the 1 px edge of a floating surface (menu, dialog):
//                           stronger than `separator`, so it still parts a
//                           menu from the sidebar behind it in Dark
//   success, warning        the scheme's positive and neutral text
//   error                   the negative colour, per scheme: #AB1E2C in Light,
//                           #FF959E in Dark, each 4.5:1 or more as text on the
//                           surfaces and on `errorFill` (the scheme's own
//                           negative colour under high contrast)
//   errorFill               the faint fill of an invalid field or a
//                           destructive button
//   sakura                  the signature gradient runs from violet (`accent`)
//                           to sakura. Only for the edge glow, an active
//                           progress shimmer and "update ready": never on
//                           buttons, selection or text
//   floatingBackground      menus, popovers, notifications, launcher: strongly
//                           tinted over the blur (85%), solid without it
//   chromeBackground        header bars, sidebars, floating toolbars: lightly
//                           blurred (94%), solid without it
// Tables, text fields, code views and dense forms stay solid.
//
// Spacing: one fixed scale, used by every control: spacingXSmall 2,
// spacingSmall 4, spacing 8, spacingLarge 12, spacingXLarge 16,
// spacingXXLarge 24.
//
// Radii: radiusSmall 4 (controls: buttons, fields, combo boxes, search fields,
// menu items, tabs, sidebar and list selections), radius 6 (menus, cards,
// popovers, tooltips), radiusLarge 8 (dialogs, the command palette, drop zones,
// the segmented control's track, an unchecked checkable chip), radiusPill
// (switch tracks, badges, checked or plain chips, toasts: any height).
//
// Sizes: controlHeight is the height of a button, field or combo box: 28 px,
// 24 px when compact (a control grows when its text needs more).
//
// Fonts: fontFamily is IBM Plex Sans and monoFamily is JetBrains Mono when
// installed, else the system font and the system fixed font. Telamon apps already
// use fontFamily as the application font; set `font.family: TelamonStyle.monoFamily`
// on code.
//
// Font sizes, in points, from the application font: fontSizeCaption (footers,
// 0.92 of body), fontSizeBody, fontSizeHeading (dialog titles, 1.15),
// fontSizeTitle (page titles, 1.6).
//
// WindowTitle (a header bar's title) is fontSizeWindowTitle, the body size,
// in fontWeightWindowTitle (DemiBold); Code is the body size in monoFamily.
//
// Motion: durationShort 100, duration 150, durationLong 250 ms (quick and
// subtle). They are all 0 when `reducedMotion` is true, and `reducedMotion` follows
// Appearance.reducedMotion (Plasma's animation speed set to instant, or
// TELAMON_REDUCED_MOTION=1). A running animation or Behavior reads one of the
// durations; an animation that has no duration (a spinner) checks
// `reducedMotion`.
//
// Density: `density` is TelamonStyle.Normal (0) or TelamonStyle.Compact (1), set
// by the app. `compact` is the same as a bool, and `rowHeight` is the height
// of a list or SectionRow row for the density: Normal is 2.5 grid units,
// Compact 75% of it.
//
// Springs: spatial movement (a panel opening, a row expanding, a selection
// indicator sliding) uses TelamonSpringAnimation: standard (no overshoot) by
// default, `expressive: true` (a small overshoot) only for the signature
// moments: sliding selection indicators, the focus ring growing in, the
// switch thumb, a drop zone accepting. Colour and opacity never spring: they
// fade with the durations above. Under reducedMotion a spring is off and the
// change is a short fade or a jump.
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

    // Telamon violet, unless the user chose an accent in Plasma: then theirs.
    readonly property bool _dark: _theme.Kirigami.Theme.backgroundColor.hslLightness < 0.5
    readonly property bool _system: Appearance.accentFromSystem
    readonly property color accent: _system ? _theme.Kirigami.Theme.highlightColor : (_dark ? "#8A7AF4" : "#6858E2")
    readonly property color accentText: _system ? _theme.Kirigami.Theme.highlightedTextColor : (_dark ? "#14121F" : "#FFFFFF")
    readonly property color accentStrong: _system ? _theme.Kirigami.Theme.highlightColor : (_dark ? "#A396F7" : "#5B4BD6")
    readonly property color accentStrongText: _system ? _theme.Kirigami.Theme.highlightedTextColor : (_dark ? "#14121F" : "#FFFFFF")
    // The ring is the accent, so it never clashes with a selection, a checked
    // control or the text cursor beside it. It must keep 3:1 (WCAG 1.4.11)
    // against the surfaces it is drawn on: the Telamon violet does in both
    // schemes; a Plasma accent that does not is mixed toward the text colour
    // until it does.
    readonly property color focus: {
        const surfaces = [base, control, surfaceRaised];
        const ink = _theme.Kirigami.Theme.textColor;
        for (let t = 0; t < 1; t += 0.05) {
            const c = mix(accent, ink, t);
            if (surfaces.every(s => _contrast(c, s) >= 3.0)) {
                return c;
            }
        }
        return ink;
    }

    // Neutrals: the scheme's window colour tinted toward violet, then tonal
    // steps. Light steps up toward white; Dark toward a lighter grey.
    readonly property color _tint: _dark ? "#8A7AF4" : "#6858E2"
    readonly property color base: {
        const bg = _theme.Kirigami.Theme.backgroundColor;
        return highContrast ? bg : mix(bg, _tint, _dark ? 0.06 : 0.045);
    }
    readonly property color surface: _dark ? mix(base, "white", 0.045) : mix(base, "white", 0.6)
    readonly property color surfaceRaised: _dark ? mix(base, "white", 0.085) : mix(base, "white", 0.85)
    readonly property color control: _dark ? mix(base, "white", 0.065) : mix(base, _theme.Kirigami.Theme.textColor, 0.055)
    readonly property color codeSurface: _dark ? mix(base, "black", 0.18) : mix(base, _tint, 0.035)
    readonly property color surfaceAlt: _theme.Kirigami.Theme.alternateBackgroundColor
    readonly property color hover: alpha(_theme.Kirigami.Theme.textColor, _dark ? 0.07 : 0.055)
    readonly property color pressed: alpha(_theme.Kirigami.Theme.textColor, _dark ? 0.12 : 0.1)
    readonly property color selection: alpha(accent, _dark ? 0.24 : 0.16)
    readonly property color selectionInactive: alpha(accent, _dark ? 0.15 : 0.1)
    readonly property color text: _theme.Kirigami.Theme.textColor
    readonly property color textMuted: alpha(_theme.Kirigami.Theme.textColor, 0.65)
    readonly property color textDisabled: alpha(_theme.Kirigami.Theme.textColor, 0.55)
    readonly property color separator: alpha(_theme.Kirigami.Theme.textColor, highContrast ? 0.4 : 0.08)
    readonly property color controlBorder: alpha(_theme.Kirigami.Theme.textColor, highContrast ? 0.8 : 0.22)
    readonly property color outline: alpha(_theme.Kirigami.Theme.textColor, highContrast ? 0.8 : (_dark ? 0.3 : 0.16))
    readonly property color success: _theme.Kirigami.Theme.positiveTextColor
    readonly property color warning: _theme.Kirigami.Theme.neutralTextColor
    // The scheme's own negative colour (Breeze's rgb(218,68,83)) is 2.5:1 on a
    // Dark surface and 3.2:1 on a Light control: too faint for text.
    readonly property color error: highContrast ? _theme.Kirigami.Theme.negativeTextColor : (_dark ? "#FF959E" : "#AB1E2C")
    readonly property color errorFill: alpha(error, _dark ? 0.08 : 0.06)
    readonly property color sakura: _dark ? "#F4B3CF" : "#E58BB4"
    readonly property color floatingBackground: Appearance.effective ? alpha(surfaceRaised, 0.85) : surfaceRaised
    readonly property color chromeBackground: Appearance.effective ? alpha(base, 0.94) : base

    // `c` with alpha `a`, and `a` blended toward `b` by `t`, both kept to 0..1
    // (NaN is 0). Typed, unlike Qt.alpha and Qt.rgba, so bindings compile.
    function alpha(c: color, a: real): color { return TelamonColorsPrivate.alpha(c, a); }
    function mix(a: color, b: color, t: real): color { return TelamonColorsPrivate.mix(a, b, t); }
    // The WCAG contrast ratio of two colours, 1 to 21 (alpha is ignored); `focus` uses it.
    function _contrast(a: color, b: color): real {
        const la = _luminance(a);
        const lb = _luminance(b);
        return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05);
    }
    function _luminance(c: color): real {
        const lin = v => v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
        return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b);
    }

    readonly property real spacingXSmall: 2
    readonly property real spacingSmall: 4
    readonly property real spacing: 8
    readonly property real spacingLarge: 12
    readonly property real spacingXLarge: 16
    readonly property real spacingXXLarge: 24

    readonly property real radiusSmall: 4
    readonly property real radius: 6
    readonly property real radiusLarge: 8
    readonly property real radiusPill: 1000

    readonly property real controlHeight: compact ? 24 : 28

    readonly property string fontFamily: Appearance.fontFamily
    readonly property string monoFamily: Appearance.monoFamily

    readonly property real fontSizeCaption: _theme.Kirigami.Theme.defaultFont.pointSize * 0.92
    readonly property real fontSizeBody: _theme.Kirigami.Theme.defaultFont.pointSize
    readonly property real fontSizeHeading: _theme.Kirigami.Theme.defaultFont.pointSize * 1.15
    readonly property real fontSizeTitle: _theme.Kirigami.Theme.defaultFont.pointSize * 1.6

    readonly property real fontSizeWindowTitle: fontSizeBody
    readonly property int fontWeightWindowTitle: Font.DemiBold
    readonly property real fontSizeCode: fontSizeBody

    readonly property bool reducedMotion: Appearance.reducedMotion
    // Rendering is in software (the software adaptation, or llvmpipe and
    // the like): effects and always-running animations go static or slow.
    readonly property bool softwareRendering: Appearance.softwareRendering
    readonly property int durationShort: reducedMotion ? 0 : 100
    readonly property int duration: reducedMotion ? 0 : 150
    readonly property int durationLong: reducedMotion ? 0 : 250

    property int density: TelamonStyle.Normal
    readonly property bool compact: density === TelamonStyle.Compact
    readonly property real rowHeight: {
        const normal = Math.round(Kirigami.Units.gridUnit * 2.5);
        return compact ? Math.round(normal * 0.75) : normal;
    }

    readonly property bool highContrast: Appearance.highContrast
    readonly property real textScale: Appearance.textScale
}
