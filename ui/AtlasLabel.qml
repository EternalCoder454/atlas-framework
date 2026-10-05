import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

// Text in one of the five looks of Atlas apps, so an app does not hard-code
// sizes and weights. `textStyle` picks the look: Body (the default: the
// application font), Title (a page title: large and bold), Heading (a section
// heading: bold and muted), Caption (small and muted: footers, hints) and
// Mono (the fixed-width font: versions, paths, commands). Title and Heading
// are headings for a screen reader. The text is plain unless `textFormat` is
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
        Mono
    }

    // An AtlasLabel.TextStyle value.
    property int textStyle: AtlasLabel.Body

    readonly property bool _heading: textStyle === AtlasLabel.Title || textStyle === AtlasLabel.Heading

    textFormat: Text.PlainText
    font.pointSize: textStyle === AtlasLabel.Title ? AtlasStyle.fontSizeTitle : textStyle === AtlasLabel.Caption ? AtlasStyle.fontSizeCaption : AtlasStyle.fontSizeBody
    font.bold: _heading
    font.family: textStyle === AtlasLabel.Mono ? Kirigami.Theme.fixedWidthFont.family : Kirigami.Theme.defaultFont.family
    color: textStyle === AtlasLabel.Heading || textStyle === AtlasLabel.Caption ? AtlasStyle.textMuted : AtlasStyle.text

    Accessible.role: _heading ? Accessible.Heading : Accessible.StaticText
    Accessible.name: control.text
}
