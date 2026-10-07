import QtQuick
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami

// A rounded single-line password field: TelamonTextField's look, with the text
// masked and an eye at the trailing end that shows or hides it. The text goes
// back to hidden when the field loses the keyboard focus (to anything but the
// eye itself), when its window goes to the background, and when the field is
// hidden or disabled; the selection goes with it. Copy and cut do nothing
// while the text is hidden. Unlike TelamonTextField there is no `clearable`.
// The field sets `echoMode` and `inputMethodHints` itself: setting either can
// show the password or let the keyboard remember it (lint-app.sh warns).
// Keep the password itself out of `errorText`, which screen readers speak.
//
//   TelamonPasswordField {
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
        readonly property real fieldHeight: Math.max(TelamonStyle.controlHeight, Math.ceil(control.contentHeight) + TelamonStyle.spacing)
        readonly property real messageHeight: message.visible ? message.implicitHeight + TelamonStyle.spacing : 0
        readonly property real iconSize: Kirigami.Units.iconSizes.small
        readonly property real errorSpace: control.hasError ? iconSize + TelamonStyle.spacingSmall : 0
        readonly property real toggleSpace: toggle.width + TelamonStyle.spacingSmall + errorSpace
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
    leftPadding: TelamonStyle.spacingLarge + (rtl ? internals.toggleSpace : 0)
    rightPadding: TelamonStyle.spacingLarge + (rtl ? 0 : internals.toggleSpace)
    topPadding: 0
    bottomPadding: internals.messageHeight
    verticalAlignment: TextInput.AlignVCenter
    placeholderTextColor: TelamonStyle.textMuted
    color: enabled ? Kirigami.Theme.textColor : TelamonStyle.textDisabled
    selectionColor: TelamonStyle.accent
    selectedTextColor: TelamonStyle.accentText
    font.family: TelamonStyle.fontFamily
    font.pointSize: TelamonStyle.fontSizeBody
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
        radius: TelamonStyle.radiusSmall
        color: control.hasError ? TelamonStyle.errorFill : control.hovered && !control.activeFocus && control.enabled ? Qt.tint(TelamonStyle.control, TelamonStyle.hover) : TelamonStyle.control
        border.width: 1
        border.color: control.hasError ? TelamonStyle.error : control.activeFocus ? TelamonStyle.focus : TelamonStyle.controlBorder
        opacity: control.enabled ? 1 : 0.6
        TelamonFocusRing {
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
        x: control.rtl ? TelamonStyle.spacingSmall + internals.errorSpace : control.width - width - TelamonStyle.spacingSmall - internals.errorSpace
        y: Math.round((internals.fieldHeight - height) / 2)
        width: Kirigami.Units.iconSizes.small + TelamonStyle.spacingSmall * 2
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
            color: TelamonStyle.alpha(Kirigami.Theme.textColor, toggle.down ? 0.15 : toggle.hovered ? 0.08 : 0)
            TelamonFocusRing {
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
        x: control.rtl ? TelamonStyle.spacingSmall : control.width - width - TelamonStyle.spacingSmall
        y: Math.round((internals.fieldHeight - height) / 2)
        visible: control.hasError
        icon: Symbols.Error
        size: internals.iconSize
        color: TelamonStyle.error
    }

    Text {
        id: message
        x: TelamonStyle.spacingLarge
        y: internals.fieldHeight + TelamonStyle.spacing
        width: control.width - TelamonStyle.spacingLarge * 2
        visible: control.hasError
        text: control.errorText
        font.family: TelamonStyle.fontFamily
        font.pointSize: TelamonStyle.fontSizeCaption
        color: TelamonStyle.error
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
        horizontalAlignment: control.rtl ? Text.AlignRight : Text.AlignLeft
        Accessible.ignored: true
    }
}
