import QtQuick
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami

// A rounded single-line text field. `placeholderText` shows while it is
// empty; a non-empty `errorText` turns the outline red and shows the message
// below the field; with `clearable` a small cross empties it.
//
//   AtlasTextField {
//       placeholderText: qsTr("Name")
//       clearable: true
//       errorText: text.length === 0 ? qsTr("A name is required") : ""
//   }
T.TextField {
    id: control

    // The message under the field; empty for no error.
    property string errorText
    // Show a clear button once there is text.
    property bool clearable: false

    // A TextField is no Control, so it has no `mirrored` of its own.
    readonly property bool rtl: LayoutMirroring.enabled
    readonly property bool hasError: errorText.length > 0

    QtObject {
        id: internals
        readonly property real fieldHeight: Math.round(Kirigami.Units.gridUnit * 1.9)
        readonly property real messageHeight: message.visible ? message.implicitHeight + Kirigami.Units.smallSpacing : 0
        readonly property bool showClear: control.clearable && control.length > 0 && control.enabled && !control.readOnly
        readonly property real clearSpace: showClear ? clearButton.width + Kirigami.Units.smallSpacing : 0
    }

    implicitWidth: Kirigami.Units.gridUnit * 14
    implicitHeight: internals.fieldHeight + internals.messageHeight
    leftPadding: Kirigami.Units.largeSpacing + Kirigami.Units.smallSpacing + (rtl ? internals.clearSpace : 0)
    rightPadding: Kirigami.Units.largeSpacing + Kirigami.Units.smallSpacing + (rtl ? 0 : internals.clearSpace)
    topPadding: 0
    bottomPadding: internals.messageHeight
    verticalAlignment: TextInput.AlignVCenter
    placeholderTextColor: Qt.alpha(Kirigami.Theme.textColor, 0.5)
    color: Kirigami.Theme.textColor
    selectionColor: Kirigami.Theme.highlightColor
    selectedTextColor: Kirigami.Theme.highlightedTextColor
    font: Kirigami.Theme.defaultFont
    selectByMouse: true
    hoverEnabled: true
    focusPolicy: Qt.StrongFocus
    opacity: enabled ? 1 : 0.5

    Accessible.role: Accessible.EditableText
    Accessible.name: placeholderText
    Accessible.description: errorText

    background: Rectangle {
        height: internals.fieldHeight
        radius: height / 2
        color: Qt.alpha(Kirigami.Theme.textColor, control.hovered && !control.activeFocus ? 0.09 : 0.06)
        border.width: control.activeFocus || control.hasError ? 2 : 1
        border.color: control.hasError ? Kirigami.Theme.negativeTextColor : control.activeFocus ? Qt.alpha(Kirigami.Theme.highlightColor, 0.7) : Qt.alpha(Kirigami.Theme.textColor, 0.1)
        AtlasFocusRing {
            radius: parent.radius + gap
            shown: control.activeFocus && (control.focusReason === Qt.TabFocusReason || control.focusReason === Qt.BacktabFocusReason || control.focusReason === Qt.ShortcutFocusReason)
        }
    }

    // A template field keeps placeholderText but draws nothing for it.
    Text {
        x: control.leftPadding
        y: Math.round((internals.fieldHeight - height) / 2)
        width: control.width - control.leftPadding - control.rightPadding
        visible: control.length === 0 && control.preeditText.length === 0
        text: control.placeholderText
        font: control.font
        color: control.placeholderTextColor
        elide: Text.ElideRight
        horizontalAlignment: control.rtl ? Text.AlignRight : Text.AlignLeft
        textFormat: Text.PlainText
        renderType: control.renderType
        Accessible.ignored: true
    }

    T.AbstractButton {
        id: clearButton
        x: control.rtl ? Kirigami.Units.smallSpacing + 2 : control.width - width - Kirigami.Units.smallSpacing - 2
        y: Math.round((internals.fieldHeight - height) / 2)
        width: Kirigami.Units.iconSizes.small + Kirigami.Units.smallSpacing * 2
        height: width
        visible: internals.showClear
        focusPolicy: Qt.NoFocus
        hoverEnabled: true
        Accessible.name: qsTr("Clear")
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

    Text {
        id: message
        x: Kirigami.Units.largeSpacing
        y: internals.fieldHeight + Kirigami.Units.smallSpacing
        width: control.width - Kirigami.Units.largeSpacing * 2
        visible: control.hasError
        text: control.errorText
        font: Kirigami.Theme.smallFont
        color: Kirigami.Theme.negativeTextColor
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
        horizontalAlignment: control.rtl ? Text.AlignRight : Text.AlignLeft
        Accessible.ignored: true
    }
}
