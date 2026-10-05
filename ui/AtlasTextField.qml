import QtQuick
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami

// A single-line text field with small rounded corners, 28 px high (24
// compact; it grows with large text). `placeholderText` shows while it is
// empty; a non-empty `errorText` turns the outline red, tints the field,
// puts an error symbol at the trailing edge and shows the message below the
// field; with `clearable` a small cross empties it.
//
// `prefix` and `suffix` are fixed, muted text inside the field before and after
// what is typed ("$", "kg"). `showCounter` writes "length/max" under the field
// at its trailing end when `maximumLength` is set. `invalidText` is the message
// for a text the `validator` (or `inputMask`) does not accept. It is not
// shown while the user types (the unfinished text of an email or URL
// validator is not an error yet): it appears once the focus has left the field
// or Return is pressed (`validateOn: "leaving"`, the default), or at once with
// `validateOn: "typing"`. After it has appeared it follows the text live and
// goes as soon as the text is acceptable. An `errorText` set by the app shows
// at once and wins.
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
        // Grows when the text (large font) needs more than the control height.
        readonly property real fieldHeight: Math.max(AtlasStyle.controlHeight, Math.ceil(control.contentHeight) + AtlasStyle.spacing)
        // The user has typed in the field / the focus has left it or Return
        // was pressed: from then on a validator error shows and follows live.
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
        readonly property real messageHeight: rowShown ? Math.max(message.visible ? message.implicitHeight : 0, counterShown ? counter.implicitHeight : 0) + AtlasStyle.spacing : 0
        readonly property real prefixSpace: control.prefix.length > 0 ? prefixText.implicitWidth + AtlasStyle.spacingSmall : 0
        readonly property real suffixSpace: control.suffix.length > 0 ? suffixText.implicitWidth + AtlasStyle.spacingSmall : 0
        readonly property real edgePad: AtlasStyle.spacingLarge
        readonly property real iconSize: Kirigami.Units.iconSizes.small
        readonly property real errorSpace: control.hasError ? iconSize + AtlasStyle.spacingSmall : 0
        readonly property bool showClear: control.clearable && control.text.length > 0 && control.enabled && !control.readOnly
        readonly property real clearSpace: errorSpace + (showClear ? clearButton.width + AtlasStyle.spacingSmall : 0)
    }

    implicitWidth: Kirigami.Units.gridUnit * 14
    implicitHeight: internals.fieldHeight + internals.messageHeight
    // The prefix leads and the suffix trails; the clear button is last.
    leftPadding: internals.edgePad + (rtl ? internals.suffixSpace + internals.clearSpace : internals.prefixSpace)
    rightPadding: internals.edgePad + (rtl ? internals.prefixSpace : internals.suffixSpace + internals.clearSpace)
    topPadding: 0
    bottomPadding: internals.messageHeight
    verticalAlignment: TextInput.AlignVCenter
    placeholderTextColor: AtlasStyle.textMuted
    color: enabled ? Kirigami.Theme.textColor : AtlasStyle.textDisabled
    selectionColor: AtlasStyle.accent
    selectedTextColor: AtlasStyle.accentText
    font.family: AtlasStyle.fontFamily
    font.pointSize: AtlasStyle.fontSizeBody
    selectByMouse: true
    hoverEnabled: true
    focusPolicy: Qt.StrongFocus

    Accessible.role: Accessible.EditableText
    //: Spoken name of a text field that has no placeholder or label of its own
    Accessible.name: placeholderText.length > 0 ? placeholderText : qsTr("Text field")
    Accessible.description: internals.shownError

    onTextEdited: internals.touched = true
    // Return reveals a validator error even when the validator refuses it.
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            internals.left = true;
        }
    }
    onActiveFocusChanged: {
        if (!activeFocus) {
            internals.left = true;
        }
    }

    background: Rectangle {
        height: internals.fieldHeight
        radius: AtlasStyle.radiusSmall
        color: control.hasError ? AtlasStyle.errorFill : control.hovered && !control.activeFocus && control.enabled ? Qt.tint(AtlasStyle.control, AtlasStyle.hover) : AtlasStyle.control
        border.width: 1
        border.color: control.hasError ? AtlasStyle.error : control.activeFocus ? AtlasStyle.focus : AtlasStyle.controlBorder
        opacity: control.enabled ? 1 : 0.6
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
        color: AtlasStyle.textMuted
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
        color: AtlasStyle.textMuted
        textFormat: Text.PlainText
        renderType: control.renderType
        Accessible.ignored: true
    }

    T.AbstractButton {
        id: clearButton
        x: control.rtl ? internals.edgePad / 2 + internals.errorSpace : control.width - width - internals.edgePad / 2 - internals.errorSpace
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

    // The error symbol, at the trailing edge (mirrored in RTL).
    Symbol {
        x: control.rtl ? internals.edgePad / 2 : control.width - width - internals.edgePad / 2
        y: Math.round((internals.fieldHeight - height) / 2)
        visible: control.hasError
        icon: Symbols.Error
        size: internals.iconSize
        color: AtlasStyle.error
    }

    Text {
        id: message
        // The counter sits at the trailing end; the message takes the rest.
        x: control.rtl && internals.counterShown ? counter.implicitWidth + AtlasStyle.spacingLarge * 2 : AtlasStyle.spacingLarge
        y: internals.fieldHeight + AtlasStyle.spacing
        width: control.width - AtlasStyle.spacingLarge * 2 - (internals.counterShown ? counter.implicitWidth + AtlasStyle.spacingLarge : 0)
        visible: control.hasError
        text: internals.shownError
        font.family: AtlasStyle.fontFamily
        font.pointSize: AtlasStyle.fontSizeCaption
        color: AtlasStyle.error
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
        horizontalAlignment: control.rtl ? Text.AlignRight : Text.AlignLeft
        Accessible.ignored: true
    }

    Text {
        id: counter
        x: control.rtl ? AtlasStyle.spacingLarge : control.width - AtlasStyle.spacingLarge - width
        y: internals.fieldHeight + AtlasStyle.spacing
        visible: internals.counterShown
        text: control.length + "/" + control.maximumLength
        font.family: AtlasStyle.fontFamily
        font.pointSize: AtlasStyle.fontSizeCaption
        color: control.length >= control.maximumLength ? AtlasStyle.error : AtlasStyle.textMuted
        textFormat: Text.PlainText
        Accessible.ignored: true
    }
}
