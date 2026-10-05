import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

// Read-only monospace text: a command, a log excerpt, a snippet, a config.
// The text is selectable (mouse, Ctrl+A, Ctrl+C) and plain: nothing in it is
// taken as HTML. It is as tall as its text up to `maximumHeight`, then it
// scrolls, down and sideways (unless `wrap`). `framed` draws a card around it;
// `showCopy` adds a copy button in the top trailing corner; `lineNumbers`
// adds a number column (a wrapped line has one number).
//
//   AtlasCodeView {
//       text: "flatpak install flathub org.example.App"
//       showCopy: true
//   }
//   AtlasCodeView { text: log; lineNumbers: true; maximumHeight: 240 }
//
// Screen readers get the text field, named "Code"; set Accessible.name on
// the view to say what the code is ("Install command").
Item {
    id: control

    property string text
    property bool framed: true
    // Taller text scrolls; Infinity for as tall as the text.
    property real maximumHeight: Infinity
    property bool wrap: false
    property bool showCopy: false
    property bool lineNumbers: false

    // True once the mouse pressed in the view: the focus ring is for the keyboard.
    property bool _byMouse: false
    readonly property real _pad: control.framed ? AtlasStyle.spacingLarge : 0
    // One number per logical line; a wrapped line's other rows stay blank.
    readonly property string _numbers: {
        if (!control.lineNumbers) {
            return "";
        }
        const lines = control.text.split("\n");
        const out = [];
        const wrapped = control.wrap && lines.length <= 5000;
        // Read here so a change of width or text numbers again.
        const total = edit.contentHeight;
        const lineHeight = Math.max(1, edit.positionToRectangle(0).height);
        let offset = 0;
        for (let i = 0; i < lines.length; ++i) {
            out.push(String(i + 1));
            if (wrapped) {
                const start = edit.positionToRectangle(offset).y;
                const next = i + 1 < lines.length ? edit.positionToRectangle(offset + lines[i].length + 1).y : total;
                for (let r = Math.round((next - start) / lineHeight); r > 1; --r) {
                    out.push("");
                }
            }
            offset += lines[i].length + 1;
        }
        return out.join("\n");
    }

    implicitWidth: Kirigami.Units.gridUnit * 30
    implicitHeight: Math.min(control.maximumHeight, content.height + control._pad * 2)
    opacity: control.enabled ? 1 : 0.5

    // The name is the view's to set; the text field below forwards it.
    Accessible.ignored: true
    Accessible.name: qsTr("Code")

    Rectangle {
        id: frame
        anchors.fill: parent
        radius: AtlasStyle.radius
        color: control.framed ? AtlasStyle.codeSurface : "transparent"
        border.width: control.framed ? 1 : 0
        border.color: AtlasStyle.separator
        AtlasFocusRing {
            radius: frame.radius + gap
            shown: edit.activeFocus && !control._byMouse
        }
    }

    Flickable {
        id: flick
        anchors.fill: parent
        anchors.margins: control._pad
        anchors.rightMargin: control._pad + (control.showCopy ? copyButton.width + AtlasStyle.spacingSmall : 0)
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        contentWidth: content.width
        contentHeight: content.height

        QQC2.ScrollBar.vertical: QQC2.ScrollBar {}
        QQC2.ScrollBar.horizontal: QQC2.ScrollBar {}

        Row {
            id: content
            spacing: AtlasStyle.spacing

            Text {
                id: gutter
                visible: control.lineNumbers
                width: visible ? implicitWidth : 0
                horizontalAlignment: Text.AlignRight
                text: control._numbers
                font.family: AtlasStyle.monoFamily
                font.pointSize: Kirigami.Theme.fixedWidthFont.pointSize
                color: AtlasStyle.textMuted
                textFormat: Text.PlainText
                Accessible.ignored: true
            }
            TextEdit {
                id: edit
                width: control.wrap ? Math.max(0, flick.width - (gutter.visible ? gutter.width + content.spacing : 0)) : implicitWidth
                readOnly: true
                selectByMouse: true
                persistentSelection: true
                activeFocusOnTab: true
                text: control.text
                textFormat: TextEdit.PlainText
                wrapMode: control.wrap ? TextEdit.Wrap : TextEdit.NoWrap
                font.family: AtlasStyle.monoFamily
                font.pointSize: Kirigami.Theme.fixedWidthFont.pointSize
                color: Kirigami.Theme.textColor
                selectionColor: AtlasStyle.accent
                selectedTextColor: AtlasStyle.accentText

                Accessible.role: Accessible.EditableText
                Accessible.name: control.Accessible.name
                Accessible.readOnly: true

                onActiveFocusChanged: {
                    if (!activeFocus) {
                        control._byMouse = false;
                    }
                }
                // Keyboard selection and caret moves keep the caret in view.
                onCursorRectangleChanged: {
                    const r = cursorRectangle;
                    if (r.y < flick.contentY) {
                        flick.contentY = r.y;
                    } else if (r.y + r.height > flick.contentY + flick.height) {
                        flick.contentY = r.y + r.height - flick.height;
                    }
                    if (r.x < flick.contentX) {
                        flick.contentX = r.x;
                    } else if (r.x + 2 > flick.contentX + flick.width) {
                        flick.contentX = r.x + 2 - flick.width;
                    }
                }
                TapHandler {
                    acceptedButtons: Qt.AllButtons
                    onPressedChanged: {
                        if (pressed) {
                            control._byMouse = true;
                        }
                    }
                }
            }
        }
    }

    AtlasCopyButton {
        id: copyButton
        visible: control.showCopy
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: AtlasStyle.spacingSmall
        text: control.text
    }
}
