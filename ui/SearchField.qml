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

    implicitWidth: Kirigami.Units.gridUnit * 14
    implicitHeight: Math.max(AtlasStyle.controlHeight, Math.ceil(contentHeight) + AtlasStyle.spacing)
    leftPadding: (rtl ? clearButton.width : icon.width) + AtlasStyle.spacingLarge
    rightPadding: (rtl ? icon.width : clearButton.width) + AtlasStyle.spacingLarge
    verticalAlignment: TextInput.AlignVCenter
    placeholderText: qsTr("Search")
    placeholderTextColor: AtlasStyle.textMuted
    color: enabled ? Kirigami.Theme.textColor : AtlasStyle.textDisabled
    hoverEnabled: true
    selectionColor: AtlasStyle.accent
    selectedTextColor: AtlasStyle.accentText
    font.family: AtlasStyle.fontFamily
    font.pointSize: AtlasStyle.fontSizeBody
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
        radius: AtlasStyle.radiusSmall
        color: control.hovered && !control.activeFocus && control.enabled ? Qt.tint(AtlasStyle.control, AtlasStyle.hover) : AtlasStyle.control
        border.width: 1
        border.color: control.activeFocus ? AtlasStyle.focus : AtlasStyle.controlBorder
        opacity: control.enabled ? 1 : 0.6
        AtlasFocusRing {
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

    Kirigami.Icon {
        id: icon
        x: control.rtl ? control.width - width - AtlasStyle.spacingLarge : AtlasStyle.spacingLarge
        anchors.verticalCenter: parent.verticalCenter
        width: Kirigami.Units.iconSizes.small
        height: width
        source: "search"
        isMask: true
        color: AtlasStyle.textMuted
    }

    T.AbstractButton {
        id: clearButton
        x: control.rtl ? AtlasStyle.spacingSmall : control.width - width - AtlasStyle.spacingSmall
        anchors.verticalCenter: parent.verticalCenter
        width: Kirigami.Units.iconSizes.small + AtlasStyle.spacingSmall * 2
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
            color: Qt.alpha(Kirigami.Theme.textColor, clearButton.down ? 0.15 : clearButton.hovered ? 0.08 : 0)
        }
        contentItem: Kirigami.Icon {
            source: "edit-clear"
            isMask: true
            color: Kirigami.Theme.textColor
            opacity: 0.6
        }
    }
}
