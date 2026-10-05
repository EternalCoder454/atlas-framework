import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

// Text in one of the looks of Atlas apps, so an app does not hard-code
// sizes and weights. `textStyle` picks the look: Body (the default: the
// application font), Title (a page title: large and bold), Heading (a section
// heading: bold, in the full text colour), Caption (small and muted: footers,
// hints), WindowTitle (a window's title: semibold, body size), and Code or
// Mono (the fixed-width font: versions, paths, commands; the two are the
// same). Title and Heading are headings for a screen reader. Secondary
// information ("Step 2 of 2") is Caption, or `AtlasStyle.textMuted`. The text is plain unless `textFormat` is
// set. Everything else is QtQuick.Controls' Label (wrap, elide, alignment).
//
//   AtlasLabel { text: qsTr("Downloads"); textStyle: AtlasLabel.Title }
//   AtlasLabel { text: path; textStyle: AtlasLabel.Mono; elide: Text.ElideMiddle }
QQC2.Label {
    id: control

    enum TextStyle {
        Body,
        Title,
        Heading,
        Caption,
        Mono,
        // Appended in 1.4.0: a window's title; monospace text (same as Mono).
        WindowTitle,
        Code
    }

    // An AtlasLabel.TextStyle value.
    property int textStyle: AtlasLabel.Body

    readonly property bool _heading: textStyle === AtlasLabel.Title || textStyle === AtlasLabel.Heading

    textFormat: Text.PlainText
    readonly property bool _mono: textStyle === AtlasLabel.Mono || textStyle === AtlasLabel.Code

    font.pointSize: textStyle === AtlasLabel.Title ? AtlasStyle.fontSizeTitle : textStyle === AtlasLabel.Caption ? AtlasStyle.fontSizeCaption : textStyle === AtlasLabel.WindowTitle ? AtlasStyle.fontSizeWindowTitle : _mono ? AtlasStyle.fontSizeCode : AtlasStyle.fontSizeBody
    font.weight: _heading ? Font.Bold : textStyle === AtlasLabel.WindowTitle ? AtlasStyle.fontWeightWindowTitle : Font.Normal
    font.family: _mono ? AtlasStyle.monoFamily : AtlasStyle.fontFamily
    color: textStyle === AtlasLabel.Caption ? AtlasStyle.textMuted : AtlasStyle.text

    Accessible.role: _heading ? Accessible.Heading : Accessible.StaticText
    Accessible.name: control.text
}
