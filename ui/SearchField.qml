import QtQuick
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami

// A search field with small rounded corners: a magnifier, the text, and a clear button once
// there is text. `query` follows the text after a short pause, so a live
// list filters once per word rather than per key; bind to it, not to text.
// Escape clears the field (and, when it is already empty, lets the key go
// on to close whatever it is in).
T.TextField {
    id: control

    // The text after `delay` ms without typing; at once when cleared.
    property string query
    property int delay: 150
    // A TextField is no Control, so it has no `mirrored` of its own.
    readonly property bool rtl: LayoutMirroring.enabled

    // The magnifier and the clear symbol share one inset from their edge of the
    // field, and the text keeps a gap from each.
    readonly property real _inset: TelamonStyle.spacingLarge
    readonly property real _glyph: Kirigami.Units.iconSizes.small

    implicitWidth: Kirigami.Units.gridUnit * 14
    implicitHeight: Math.max(TelamonStyle.controlHeight, Math.ceil(contentHeight) + TelamonStyle.spacing)
    leftPadding: _inset + _glyph + TelamonStyle.spacing
    rightPadding: leftPadding
    verticalAlignment: TextInput.AlignVCenter
    placeholderText: qsTr("Search")
    placeholderTextColor: TelamonStyle.textMuted
    color: enabled ? Kirigami.Theme.textColor : TelamonStyle.textDisabled
    hoverEnabled: true
    selectionColor: TelamonStyle.accent
    selectedTextColor: TelamonStyle.accentText
    font.family: TelamonStyle.fontFamily
    font.pointSize: TelamonStyle.fontSizeBody
    selectByMouse: true
    inputMethodHints: Qt.ImhNoPredictiveText

    Accessible.role: Accessible.EditableText
    Accessible.name: placeholderText
    Accessible.searchEdit: true

    onTextChanged: {
        if (text.length === 0) {
            pause.stop();
            query = "";
        } else {
            pause.restart();
        }
    }
    // Return and Enter give the app the text typed so far, not the one before the pause.
    Keys.onReturnPressed: event => {
        pause.stop();
        query = text;
        event.accepted = false;
    }
    Keys.onEnterPressed: event => {
        pause.stop();
        query = text;
        event.accepted = false;
    }
    Keys.onEscapePressed: event => {
        if (text.length > 0 && !readOnly) {
            clear();
        } else {
            event.accepted = false;
        }
    }

    Timer {
        id: pause
        interval: control.delay
        onTriggered: control.query = control.text
    }

    background: Rectangle {
        radius: TelamonStyle.radiusSmall
        color: control.hovered && !control.activeFocus && control.enabled ? Qt.tint(TelamonStyle.control, TelamonStyle.hover) : TelamonStyle.control
        border.width: 1
        border.color: control.activeFocus ? TelamonStyle.focus : TelamonStyle.controlBorder
        opacity: control.enabled ? 1 : 0.6
        TelamonFocusRing {
            radius: parent.radius + gap
            shown: control.activeFocus && (control.focusReason === Qt.TabFocusReason || control.focusReason === Qt.BacktabFocusReason || control.focusReason === Qt.ShortcutFocusReason)
        }
    }

    // A template field keeps placeholderText but draws nothing for it.
    Text {
        x: control.leftPadding
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(0, control.width - control.leftPadding - control.rightPadding)
        visible: control.length === 0 && control.preeditText.length === 0
        text: control.placeholderText
        font: control.font
        color: control.placeholderTextColor
        verticalAlignment: control.verticalAlignment
        elide: Text.ElideRight
        textFormat: Text.PlainText
        renderType: control.renderType
        Accessible.ignored: true
    }

    Symbol {
        id: icon
        x: control.rtl ? control.width - width - control._inset : control._inset
        anchors.verticalCenter: parent.verticalCenter
        icon: Symbols.Search
        size: control._glyph
        color: TelamonStyle.textMuted
    }

    T.AbstractButton {
        id: clearButton
        // The symbol, not the button, sits at the inset: the button reaches
        // a few pixels past it, so it is easy to hit.
        readonly property real reach: TelamonStyle.spacingSmall
        x: control.rtl ? control._inset - reach : control.width - width - control._inset + reach
        anchors.verticalCenter: parent.verticalCenter
        width: control._glyph + reach * 2
        height: width
        visible: control.text.length > 0 && !control.readOnly
        focusPolicy: Qt.NoFocus
        hoverEnabled: true
        Accessible.name: qsTr("Clear Search")
        onClicked: {
            control.clear();
            control.forceActiveFocus();
        }

        background: Rectangle {
            radius: width / 2
            color: TelamonStyle.alpha(Kirigami.Theme.textColor, clearButton.down ? 0.15 : clearButton.hovered ? 0.08 : 0)
        }
        contentItem: Item {
            Symbol {
                anchors.centerIn: parent
                icon: Symbols.Cancel
                filled: true
                size: control._glyph
                color: TelamonStyle.textMuted
            }
        }
    }
}
