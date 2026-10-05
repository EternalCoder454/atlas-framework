import QtQuick
import QtQuick.Controls as QQC2

// A small icon button that copies `text` to the clipboard (through
// AtlasClipboard) and shows a check mark for a moment, with the tooltip
// "Copied". It looks like a ToolbarButton, and Tab reaches it. `copied()` is
// emitted after each copy. Under reduced motion there is no fade: the symbol
// just swaps.
//
//   AtlasCopyButton { text: command.text }
//   AtlasCopyButton { text: token; onCopied: toast.show(qsTr("Token copied")) }
ToolbarButton {
    id: control

    // Set while the check mark shows.
    property bool _done: false

    signal copied

    focusable: true
    symbol: control._done ? Symbols.Check : Symbols.ContentCopy
    // `text` is what is copied, so the button names itself.
    Accessible.name: qsTr("Copy")
    Accessible.description: ""
    //: Tooltip of the copy button, once the text is on the clipboard
    QQC2.ToolTip.text: control._done ? qsTr("Copied") : qsTr("Copy")
    QQC2.ToolTip.visible: control.hovered || control._done

    onClicked: {
        AtlasClipboard.setText(control.text);
        control._done = true;
        reset.restart();
        control.copied();
    }

    Timer {
        id: reset
        interval: 1500
        onTriggered: control._done = false
    }
}
