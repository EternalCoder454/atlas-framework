import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

// Text in one of the looks of Telamon apps, so an app does not hard-code
// sizes and weights. `textStyle` picks the look: Body (the default: the
// application font), Title (a page title: large and bold), Heading (a section
// heading: bold, in the full text colour), Caption (small and muted: footers,
// hints), WindowTitle (a window's title: semibold, body size), and Code or
// Mono (the fixed-width font: versions, paths, commands; the two are the
// same). Title and Heading are headings for a screen reader. Secondary
// information ("Step 2 of 2") is Caption, or `TelamonStyle.textMuted`. The text is plain unless `textFormat` is
// set. Everything else is QtQuick.Controls' Label (wrap, elide, alignment).
//
//   TelamonLabel { text: qsTr("Downloads"); textStyle: TelamonLabel.Title }
//   TelamonLabel { text: path; textStyle: TelamonLabel.Mono; elide: Text.ElideMiddle }
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

    // A TelamonLabel.TextStyle value.
    property int textStyle: TelamonLabel.Body

    readonly property bool _heading: textStyle === TelamonLabel.Title || textStyle === TelamonLabel.Heading

    textFormat: Text.PlainText
    readonly property bool _mono: textStyle === TelamonLabel.Mono || textStyle === TelamonLabel.Code

    font.pointSize: textStyle === TelamonLabel.Title ? TelamonStyle.fontSizeTitle : textStyle === TelamonLabel.Caption ? TelamonStyle.fontSizeCaption : textStyle === TelamonLabel.WindowTitle ? TelamonStyle.fontSizeWindowTitle : _mono ? TelamonStyle.fontSizeCode : TelamonStyle.fontSizeBody
    font.weight: _heading ? Font.Bold : textStyle === TelamonLabel.WindowTitle ? TelamonStyle.fontWeightWindowTitle : Font.Normal
    font.family: _mono ? TelamonStyle.monoFamily : TelamonStyle.fontFamily
    color: textStyle === TelamonLabel.Caption ? TelamonStyle.textMuted : TelamonStyle.text

    Accessible.role: _heading ? Accessible.Heading : Accessible.StaticText
    Accessible.name: control.text
}
