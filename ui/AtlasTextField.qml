import QtQuick
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami

// A rounded single-line text field. `placeholderText` shows while it is
// empty; a non-empty `errorText` turns the outline red and shows the message
// below the field; with `clearable` a small cross empties it.
//
// `prefix` and `suffix` are fixed, muted text inside the field before and after
// what is typed ("$", "kg"). `showCounter` writes "length/max" under the field
// at its trailing end when `maximumLength` is set. `invalidText` is the message
// for a text the `validator` (or `inputMask`) does not accept: shown while
// typing (`validateOn: "typing"`) or once the focus has left the field
// (`validateOn: "leaving"`, the default). An `errorText` set by the app wins.
//
//   AtlasTextField {
//       placeholderText: qsTr("Name")
//       clearable: true
//       errorText: text.length === 0 ? qsTr("A name is required") : ""
//   }
//   AtlasTextField {
//       maximumLength: 40; showCounter: true
//       validator: RegularExpressionValidator { regularExpression: /[a-z]+/ }
//       invalidText: qsTr("Use lowercase letters only")
//   }
T.TextField {
    id: control

    // The message under the field; empty for no error.
    property string errorText
    // Show a clear button once there is text.
    property bool clearable: false
    // Fixed text inside the field, before and after the input.
    property string prefix
    property string suffix
    // "length/max" under the field; only when maximumLength is set.
    property bool showCounter: false
    // The message for a text that is not acceptable; see the header.
    property string invalidText
    // "leaving" (default) or "typing".
    property string validateOn: "leaving"

    // A TextField is no Control, so it has no `mirrored` of its own.
    readonly property bool rtl: LayoutMirroring.enabled
    // True while errorText or invalidText shows.
    readonly property bool hasError: internals.shownError.length > 0

    QtObject {
        id: internals
        readonly property real fieldHeight: Math.round(Kirigami.Units.gridUnit * 1.9)
        // The user has typed in the field / the focus has been on it and left.
        property bool touched: false
        property bool left: false
        readonly property bool invalidShown: control.invalidText.length > 0 && !control.acceptableInput && (left || (control.validateOn === "typing" && touched))
        // errorText set by the app wins over invalidText.
        readonly property string shownError: control.errorText.length > 0 ? control.errorText : invalidShown ? control.invalidText : ""
        onShownErrorChanged: {
            if (shownError.length > 0) {
                // A new message is spoken when it appears, not only when the field is read.
                control.Accessible.announce(shownError);
            }
        }
        readonly property bool counterShown: control.showCounter && control.maximumLength < 32767
        readonly property bool rowShown: message.visible || counterShown
        readonly property real messageHeight: rowShown ? Math.max(message.visible ? message.implicitHeight : 0, counterShown ? counter.implicitHeight : 0) + AtlasStyle.spacingSmall : 0
        readonly property real prefixSpace: control.prefix.length > 0 ? prefixText.implicitWidth + AtlasStyle.spacingSmall : 0
        readonly property real suffixSpace: control.suffix.length > 0 ? suffixText.implicitWidth + AtlasStyle.spacingSmall : 0
        readonly property real edgePad: AtlasStyle.spacingLarge + AtlasStyle.spacingSmall
        readonly property bool showClear: control.clearable && control.text.length > 0 && control.enabled && !control.readOnly
        readonly property real clearSpace: showClear ? clearButton.width + AtlasStyle.spacingSmall : 0
    }

    implicitWidth: Kirigami.Units.gridUnit * 14
    implicitHeight: internals.fieldHeight + internals.messageHeight
    // The prefix leads and the suffix trails; the clear button is last.
    leftPadding: internals.edgePad + (rtl ? internals.suffixSpace + internals.clearSpace : internals.prefixSpace)
    rightPadding: internals.edgePad + (rtl ? internals.prefixSpace : internals.suffixSpace + internals.clearSpace)
    topPadding: 0
    bottomPadding: internals.messageHeight
    verticalAlignment: TextInput.AlignVCenter
    placeholderTextColor: Qt.alpha(Kirigami.Theme.textColor, 0.5)
    color: Kirigami.Theme.textColor
    selectionColor: AtlasStyle.accent
    selectedTextColor: AtlasStyle.accentText
    font: Kirigami.Theme.defaultFont
    selectByMouse: true
    hoverEnabled: true
    focusPolicy: Qt.StrongFocus
    opacity: enabled ? 1 : 0.5

    Accessible.role: Accessible.EditableText
    //: Spoken name of a text field that has no placeholder or label of its own
    Accessible.name: placeholderText.length > 0 ? placeholderText : qsTr("Text field")
    Accessible.description: internals.shownError

    onTextEdited: internals.touched = true
    onActiveFocusChanged: {
        if (!activeFocus) {
            internals.left = true;
        }
    }

    background: Rectangle {
        height: internals.fieldHeight
        radius: AtlasStyle.radiusPill
        color: Qt.alpha(Kirigami.Theme.textColor, control.hovered && !control.activeFocus ? 0.09 : 0.06)
        border.width: control.activeFocus || control.hasError ? 2 : 1
        border.color: control.hasError ? Kirigami.Theme.negativeTextColor : control.activeFocus ? Qt.alpha(AtlasStyle.focus, 0.85) : Qt.alpha(Kirigami.Theme.textColor, 0.1)
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

    Text {
        id: prefixText
        x: control.rtl ? control.width - internals.edgePad - width : internals.edgePad
        y: Math.round((internals.fieldHeight - height) / 2)
        visible: control.prefix.length > 0
        text: control.prefix
        font: control.font
        color: Qt.alpha(Kirigami.Theme.textColor, 0.6)
        textFormat: Text.PlainText
        renderType: control.renderType
        Accessible.ignored: true
    }

    Text {
        id: suffixText
        x: control.rtl ? internals.edgePad + internals.clearSpace : control.width - internals.edgePad - internals.clearSpace - width
        y: Math.round((internals.fieldHeight - height) / 2)
        visible: control.suffix.length > 0
        text: control.suffix
        font: control.font
        color: Qt.alpha(Kirigami.Theme.textColor, 0.6)
        textFormat: Text.PlainText
        renderType: control.renderType
        Accessible.ignored: true
    }

    T.AbstractButton {
        id: clearButton
        x: control.rtl ? AtlasStyle.spacingSmall + 2 : control.width - width - AtlasStyle.spacingSmall - 2
        y: Math.round((internals.fieldHeight - height) / 2)
        width: Kirigami.Units.iconSizes.small + AtlasStyle.spacingSmall * 2
        height: width
        visible: internals.showClear
        focusPolicy: Qt.NoFocus
        hoverEnabled: true
        //: Spoken name of the button that empties a text field
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
        // The counter sits at the trailing end; the message takes the rest.
        x: control.rtl && internals.counterShown ? counter.implicitWidth + AtlasStyle.spacingLarge * 2 : AtlasStyle.spacingLarge
        y: internals.fieldHeight + AtlasStyle.spacingSmall
        width: control.width - AtlasStyle.spacingLarge * 2 - (internals.counterShown ? counter.implicitWidth + AtlasStyle.spacingLarge : 0)
        visible: control.hasError
        text: internals.shownError
        font: Kirigami.Theme.smallFont
        color: Kirigami.Theme.negativeTextColor
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
        horizontalAlignment: control.rtl ? Text.AlignRight : Text.AlignLeft
        Accessible.ignored: true
    }

    Text {
        id: counter
        x: control.rtl ? AtlasStyle.spacingLarge : control.width - AtlasStyle.spacingLarge - width
        y: internals.fieldHeight + AtlasStyle.spacingSmall
        visible: internals.counterShown
        text: control.length + "/" + control.maximumLength
        font: Kirigami.Theme.smallFont
        color: control.length >= control.maximumLength ? Kirigami.Theme.negativeTextColor : Qt.alpha(Kirigami.Theme.textColor, 0.6)
        textFormat: Text.PlainText
        Accessible.ignored: true
    }
}
