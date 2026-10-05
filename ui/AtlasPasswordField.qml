import QtQuick
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami

// A rounded single-line password field: AtlasTextField's look, with the text
// masked and an eye at the trailing end that shows or hides it. The text goes
// back to hidden when the field loses the keyboard focus (to anything but the
// eye itself), when its window goes to the background, and when the field is
// hidden or disabled; the selection goes with it. Copy and cut do nothing
// while the text is hidden. Unlike AtlasTextField there is no `clearable`.
// The field sets `echoMode` and `inputMethodHints` itself: setting either can
// show the password or let the keyboard remember it (lint-app.sh warns).
// Keep the password itself out of `errorText`, which screen readers speak.
//
//   AtlasPasswordField {
//       placeholderText: qsTr("Password")
//       errorText: text.length < 8 ? qsTr("Use at least 8 characters") : ""
//       onAccepted: confirm.forceActiveFocus()
//   }
T.TextField {
    id: control

    // The message under the field; empty for no error.
    property string errorText

    // True while the text is shown in clear. `reveal()` and `hide()` change
    // it; the eye does the same. Only ever true while the field (or its eye)
    // has the keyboard focus in the active window, whatever asked for it.
    readonly property bool revealed: internals.shown && control.enabled && internals.focused && internals.windowActive

    // A TextField is no Control, so it has no `mirrored` of its own.
    readonly property bool rtl: LayoutMirroring.enabled
    readonly property bool hasError: errorText.length > 0

    // Shows the text in clear while the field (or its eye) has the keyboard
    // focus. Does nothing when it hasn't, or while the field is disabled.
    function reveal(): void {
        internals.shown = control.enabled && internals.focused;
    }

    // Masks the text again.
    function hide(): void {
        internals.shown = false;
    }

    QtObject {
        id: internals
        property bool shown: false
        // Grows when the text (large font) needs more than the control height.
        readonly property real fieldHeight: Math.max(AtlasStyle.controlHeight, Math.ceil(control.contentHeight) + AtlasStyle.spacing)
        readonly property real messageHeight: message.visible ? message.implicitHeight + AtlasStyle.spacing : 0
        readonly property real iconSize: Kirigami.Units.iconSizes.small
        readonly property real errorSpace: control.hasError ? iconSize + AtlasStyle.spacingSmall : 0
        readonly property real toggleSpace: toggle.width + AtlasStyle.spacingSmall + errorSpace
        // Focus on the eye is still focus on the field.
        readonly property bool focused: control.activeFocus || toggle.activeFocus
        onFocusedChanged: {
            if (!focused) {
                shown = false;
            }
        }
        // A window in the background (or a locked screen) shows no password.
        readonly property bool windowActive: control.Window.active
        onWindowActiveChanged: {
            if (!windowActive) {
                shown = false;
            }
        }
    }

    onEnabledChanged: {
        if (!enabled) {
            internals.shown = false;
        }
    }
    // A page that is only hidden keeps its fields: hide the text too.
    onVisibleChanged: {
        if (!visible) {
            internals.shown = false;
        }
    }
    // A selection made while shown would stay on X11's and Wayland's primary
    // selection; once masked there is nothing to select anyway.
    onRevealedChanged: {
        if (!revealed) {
            control.deselect();
        }
    }

    implicitWidth: Kirigami.Units.gridUnit * 14
    implicitHeight: internals.fieldHeight + internals.messageHeight
    leftPadding: AtlasStyle.spacingLarge + (rtl ? internals.toggleSpace : 0)
    rightPadding: AtlasStyle.spacingLarge + (rtl ? 0 : internals.toggleSpace)
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
    echoMode: revealed ? TextInput.Normal : TextInput.Password
    // No suggestions, no capital first letter, and keyboards keep it out of
    // their history. Qt's Password echo already refuses copy and cut.
    inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase

    Accessible.role: Accessible.EditableText
    //: Spoken name of a password field that has no placeholder or label of its own
    Accessible.name: placeholderText.length > 0 ? placeholderText : qsTr("Password")
    Accessible.description: errorText
    // Qt reports no name for a password edit, on purpose; the name stays set
    // for the moment the text is shown.
    Accessible.passwordEdit: !control.revealed
    // A new message is spoken when it appears, not only when the field is read.
    onErrorTextChanged: {
        if (control.errorText.length > 0) {
            Accessible.announce(control.errorText);
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

    // The eye. Tab reaches it; a click does not take the focus from the field.
    T.AbstractButton {
        id: toggle
        x: control.rtl ? AtlasStyle.spacingSmall + internals.errorSpace : control.width - width - AtlasStyle.spacingSmall - internals.errorSpace
        y: Math.round((internals.fieldHeight - height) / 2)
        width: Kirigami.Units.iconSizes.small + AtlasStyle.spacingSmall * 2
        height: width
        focusPolicy: Qt.TabFocus
        hoverEnabled: true
        Accessible.role: Accessible.Button
        Accessible.name: control.revealed
            //: Spoken name of the eye in a password field while the text is shown: it hides the text again
            ? qsTr("Hide password")
            //: Spoken name of the eye in a password field while the text is hidden: it shows the text
            : qsTr("Show password")
        onClicked: {
            if (!toggle.activeFocus) {
                control.forceActiveFocus();
            }
            internals.shown = !internals.shown && control.enabled && internals.focused;
        }
        background: Rectangle {
            radius: width / 2
            color: Qt.alpha(Kirigami.Theme.textColor, toggle.down ? 0.15 : toggle.hovered ? 0.08 : 0)
            AtlasFocusRing {
                radius: parent.radius + gap
                shown: toggle.activeFocus && (toggle.focusReason === Qt.TabFocusReason || toggle.focusReason === Qt.BacktabFocusReason)
            }
        }
        contentItem: Symbol {
            icon: control.revealed ? Symbols.VisibilityOff : Symbols.Visibility
            size: Kirigami.Units.iconSizes.small
            opacity: 0.6
        }
    }

    // The error symbol, left of the eye at the trailing edge (mirrored in RTL).
    Symbol {
        x: control.rtl ? AtlasStyle.spacingSmall : control.width - width - AtlasStyle.spacingSmall
        y: Math.round((internals.fieldHeight - height) / 2)
        visible: control.hasError
        icon: Symbols.Error
        size: internals.iconSize
        color: AtlasStyle.error
    }

    Text {
        id: message
        x: AtlasStyle.spacingLarge
        y: internals.fieldHeight + AtlasStyle.spacing
        width: control.width - AtlasStyle.spacingLarge * 2
        visible: control.hasError
        text: control.errorText
        font.family: AtlasStyle.fontFamily
        font.pointSize: AtlasStyle.fontSizeCaption
        color: AtlasStyle.error
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
        horizontalAlignment: control.rtl ? Text.AlignRight : Text.AlignLeft
        Accessible.ignored: true
    }
}
