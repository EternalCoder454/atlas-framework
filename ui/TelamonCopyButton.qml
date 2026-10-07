import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami

// A ToolbarButton that copies `text` through TelamonClipboard. In text mode the
// content item keeps room for the wider of `label` and `copiedLabel`.
// See docs/reference/telamon-ui/telamon-copy-button.md.
ToolbarButton {
    id: control

    // Text beside the icon; empty keeps the icon-only button.
    property string label: ""
    // The text shown after a copy, in text mode, and announced.
    property string copiedLabel: qsTr("Copied")

    // Set while the check mark shows.
    property bool _done: false

    signal copied

    focusable: true
    display: control.label.length > 0 ? T.AbstractButton.TextBesideIcon : T.AbstractButton.IconOnly
    symbol: control._done ? Symbols.Check : Symbols.ContentCopy
    // `text` is what is copied, so the button names itself.
    Accessible.name: control.label.length > 0 ? control.label : qsTr("Copy")
    // Said after a copy, until the check mark goes.
    Accessible.description: control._done ? control.copiedLabel : ""
    //: Tooltip of the copy button, once the text is on the clipboard
    QQC2.ToolTip.text: control._done ? control.copiedLabel : qsTr("Copy")
    // The label says it already in text mode.
    QQC2.ToolTip.visible: control.label.length === 0 && (control.hovered || control._done)

    onClicked: {
        TelamonClipboard.setText(control.text);
        control._done = true;
        reset.restart();
        Accessible.announce(control.copiedLabel);
        control.copied();
    }

    // The symbol, then in text mode the label; the room is that of the wider
    // of label and copiedLabel, so the button does not change width.
    contentItem: Item {
        implicitWidth: row.implicitWidth
        implicitHeight: row.implicitHeight
        Row {
            id: row
            anchors.centerIn: parent
            spacing: TelamonStyle.spacingSmall
            Symbol {
                anchors.verticalCenter: parent.verticalCenter
                icon: control.symbol
                size: Math.round(Kirigami.Units.iconSizes.small * 1.2)
                color: control._iconColor
            }
            Item {
                visible: control.label.length > 0
                anchors.verticalCenter: parent.verticalCenter
                implicitWidth: Math.max(shownLabel.implicitWidth, hiddenLabel.implicitWidth)
                implicitHeight: shownLabel.implicitHeight
                width: implicitWidth
                height: implicitHeight
                Text {
                    id: shownLabel
                    anchors.centerIn: parent
                    text: control._done ? control.copiedLabel : control.label
                    font.family: TelamonStyle.fontFamily
                    font.pointSize: TelamonStyle.fontSizeBody
                    color: Kirigami.Theme.textColor
                    textFormat: Text.PlainText
                }
                // Not drawn: it holds the width of the other text.
                Text {
                    id: hiddenLabel
                    visible: false
                    text: control._done ? control.label : control.copiedLabel
                    font: shownLabel.font
                    textFormat: Text.PlainText
                }
            }
        }
    }

    Timer {
        id: reset
        interval: 1500
        onTriggered: control._done = false
    }
}
