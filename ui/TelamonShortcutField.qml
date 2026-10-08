import QtQuick
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami

// A field that records a key combination. Click it, or press Space or Return
// while it has the focus, then press the shortcut: the first key that is not a
// modifier, with the modifiers held, becomes `sequence` and recording stops.
// Escape cancels and keeps the old value; Backspace or Delete clears it; losing
// the focus cancels. While recording, the window's own shortcuts are
// suspended so that Ctrl+S can be recorded instead of saving.
//
// `sequence` is portable text ("Ctrl+Shift+K"), "" for none. `conflictText`
// names the registered TelamonAction that already has the same shortcut (not
// `ignoreAction`, the one being edited), and shows under the field; it is
// empty when there is none. The field only reports: the app decides whether to
// accept the shortcut, in `onEdited`. `sequence` already holds the new value
// when `edited` fires: to reject it, the app assigns the old (or another)
// value to `sequence` there.
//
//   TelamonShortcutField {
//       sequence: saveAction.shortcut
//       ignoreAction: saveAction
//       onEdited: saveAction.shortcut = sequence
//       Accessible.name: qsTr("Save shortcut")
//   }
T.Control {
    id: control

    // The shortcut as portable text; "" for none.
    property string sequence
    // True while the field waits for the keys.
    readonly property bool recording: internals.recording
    // Set when another registered TelamonAction already uses `sequence`.
    readonly property string conflictText: internals.conflictText
    // The action being edited: its own shortcut is no conflict.
    property QtObject ignoreAction: null
    property string placeholderText: qsTr("Press a shortcut")

    // The user recorded or cleared the shortcut (`sequence` has the new value).
    signal edited

    // Starts recording, as a click does.
    function startRecording() {
        if (enabled) {
            internals.recording = true;
            forceActiveFocus();
        }
    }

    QtObject {
        id: internals
        property bool recording: false
        readonly property real fieldHeight: Math.max(TelamonStyle.controlHeight, Math.ceil(label.implicitHeight) + TelamonStyle.spacing)
        readonly property real iconSize: Kirigami.Units.iconSizes.small
        readonly property real errorSpace: hasConflict ? iconSize + TelamonStyle.spacingSmall : 0
        readonly property string wanted: TelamonShortcuts.portable(control.sequence)
        readonly property string conflictText: {
            if (wanted.length === 0) {
                return "";
            }
            const actions = TelamonShortcuts.actions;
            for (let i = 0; i < actions.length; ++i) {
                const action = actions[i];
                if (action === control.ignoreAction || TelamonShortcuts.portable(action.shortcut) !== wanted) {
                    continue;
                }
                //: Under a shortcut field: %1 is the name of the action that already has that shortcut
                return qsTr("Already used by “%1”").arg(TelamonShortcuts.plainText(action.text));
            }
            return "";
        }
        readonly property bool hasConflict: conflictText.length > 0
        readonly property bool showClear: control.sequence.length > 0 && !recording && control.enabled
        readonly property real messageHeight: hasConflict ? message.implicitHeight + TelamonStyle.spacingSmall : 0

        function isModifier(key) {
            return key === Qt.Key_Shift || key === Qt.Key_Control || key === Qt.Key_Alt || key === Qt.Key_Meta
                || key === Qt.Key_AltGr || key === Qt.Key_Super_L || key === Qt.Key_Super_R
                || key === Qt.Key_Hyper_L || key === Qt.Key_Hyper_R || key === Qt.Key_CapsLock
                || key === Qt.Key_NumLock || key === Qt.Key_ScrollLock || key === Qt.Key_unknown;
        }

        // The portable name of a key; "" when it has none.
        function keyName(key) {
            const names = {};
            names[Qt.Key_Space] = "Space";
            names[Qt.Key_Return] = "Return";
            names[Qt.Key_Enter] = "Enter";
            names[Qt.Key_Tab] = "Tab";
            names[Qt.Key_Backtab] = "Backtab";
            names[Qt.Key_Left] = "Left";
            names[Qt.Key_Right] = "Right";
            names[Qt.Key_Up] = "Up";
            names[Qt.Key_Down] = "Down";
            names[Qt.Key_Home] = "Home";
            names[Qt.Key_End] = "End";
            names[Qt.Key_PageUp] = "PgUp";
            names[Qt.Key_PageDown] = "PgDown";
            names[Qt.Key_Insert] = "Ins";
            // Recorded only with a modifier: on their own they cancel or clear.
            names[Qt.Key_Delete] = "Del";
            names[Qt.Key_Escape] = "Esc";
            names[Qt.Key_Backspace] = "Backspace";
            names[Qt.Key_Print] = "Print";
            names[Qt.Key_Pause] = "Pause";
            names[Qt.Key_Menu] = "Menu";
            if (names[key] !== undefined) {
                return names[key];
            }
            if (key >= Qt.Key_F1 && key <= Qt.Key_F35) {
                return "F" + (key - Qt.Key_F1 + 1);
            }
            // Letters (always upper case), digits and punctuation: their ASCII code.
            if (key > 0x20 && key < 0x7f) {
                return String.fromCharCode(key);
            }
            return "";
        }

        function record(event) {
            const name = keyName(event.key);
            if (name.length === 0) {
                return false;
            }
            let text = "";
            if (event.modifiers & Qt.ControlModifier) {
                text += "Ctrl+";
            }
            if (event.modifiers & Qt.AltModifier) {
                text += "Alt+";
            }
            if (event.modifiers & Qt.ShiftModifier) {
                text += "Shift+";
            }
            if (event.modifiers & Qt.MetaModifier) {
                text += "Meta+";
            }
            // Normalised by Qt; text Qt cannot read is no shortcut.
            const portable = TelamonShortcuts.portable(text + name);
            if (portable.length === 0) {
                return false;
            }
            control.sequence = portable;
            return true;
        }
    }

    implicitWidth: Kirigami.Units.gridUnit * 12
    implicitHeight: internals.fieldHeight + internals.messageHeight
    topPadding: 0
    leftPadding: TelamonStyle.spacingLarge + (mirrored ? internals.errorSpace : 0)
    rightPadding: TelamonStyle.spacingLarge + (mirrored ? 0 : internals.errorSpace)
    bottomPadding: internals.messageHeight
    hoverEnabled: true
    focusPolicy: Qt.StrongFocus

    Accessible.role: Accessible.Button
    Accessible.name: internals.recording ? qsTr("Press keys…") : control.sequence.length > 0 ? TelamonShortcuts.readable(control.sequence) : control.placeholderText
    Accessible.description: internals.conflictText
    Accessible.onPressAction: control.startRecording()

    onActiveFocusChanged: {
        if (!activeFocus) {
            internals.recording = false;
        }
    }
    onEnabledChanged: {
        if (!enabled) {
            internals.recording = false;
        }
    }

    // While recording, the window's shortcuts must not take the keys.
    Keys.onShortcutOverride: event => {
        if (internals.recording) {
            event.accepted = true;
        }
    }
    Keys.onPressed: event => {
        // A held key repeats: it neither starts a recording nor ends one.
        if (event.isAutoRepeat) {
            event.accepted = internals.recording || event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter;
            return;
        }
        if (!internals.recording) {
            if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                control.startRecording();
                event.accepted = true;
            }
            return;
        }
        if (internals.isModifier(event.key)) {
            event.accepted = true;
            return;
        }
        // Escape, Backspace and Delete cancel or clear only on their own; with
        // Ctrl, Shift, Alt or Meta held they are recorded like any key.
        const bare = !(event.modifiers & ~Qt.KeypadModifier);
        if (event.key === Qt.Key_Escape && bare) {
            internals.recording = false;
        } else if ((event.key === Qt.Key_Backspace || event.key === Qt.Key_Delete) && bare) {
            internals.recording = false;
            control.sequence = "";
            control.edited();
        } else if ((event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) && !(event.modifiers & ~Qt.ShiftModifier)) {
            // Plain Tab still leaves the field.
            return;
        } else if (internals.record(event)) {
            internals.recording = false;
            control.edited();
        }
        event.accepted = true;
    }

    TapHandler {
        enabled: control.enabled
        gesturePolicy: TapHandler.ReleaseWithinBounds
        onTapped: {
            if (internals.recording) {
                internals.recording = false;
            } else {
                control.startRecording();
            }
        }
    }

    background: Item {
        Rectangle {
            width: parent.width
            height: internals.fieldHeight
            radius: TelamonStyle.radiusSmall
            color: internals.hasConflict ? TelamonStyle.errorFill : control.hovered && !control.activeFocus && control.enabled ? Qt.tint(TelamonStyle.control, TelamonStyle.hover) : TelamonStyle.control
            border.width: 1
            border.color: internals.hasConflict ? TelamonStyle.error
                : internals.recording ? TelamonStyle.accent
                : control.activeFocus ? TelamonStyle.focus
                : TelamonStyle.controlBorder
            opacity: control.enabled ? 1 : 0.6
            TelamonFocusRing {
                radius: parent.radius + gap
                shown: control.visualFocus
            }
        }
    }

    contentItem: Item {
        Text {
            anchors.verticalCenter: parent.verticalCenter
            x: control.mirrored ? parent.width - width : 0
            width: Math.min(implicitWidth, parent.width - (internals.showClear ? clearButton.width : 0))
            visible: internals.recording || control.sequence.length === 0
            text: internals.recording ? qsTr("Press keys…") : control.placeholderText
            font.family: TelamonStyle.fontFamily
            font.pointSize: TelamonStyle.fontSizeBody
            color: !control.enabled ? TelamonStyle.textDisabled : internals.recording ? TelamonStyle.accent : TelamonStyle.textMuted
            elide: Text.ElideRight
            textFormat: Text.PlainText
            Accessible.ignored: true
        }
        TelamonShortcutLabel {
            id: label
            anchors.verticalCenter: parent.verticalCenter
            x: control.mirrored ? parent.width - width : 0
            visible: !internals.recording && control.sequence.length > 0
            sequence: control.sequence
            Accessible.ignored: true
        }
        T.AbstractButton {
            id: clearButton
            x: control.mirrored ? 0 : parent.width - width
            y: Math.round((parent.height - height) / 2)
            width: Kirigami.Units.iconSizes.small + TelamonStyle.spacingSmall * 2
            height: width
            visible: internals.showClear
            focusPolicy: Qt.NoFocus
            hoverEnabled: true
            //: Spoken name of the button that removes a recorded shortcut
            Accessible.name: qsTr("Clear")
            onClicked: {
                control.sequence = "";
                control.edited();
            }
            background: Rectangle {
                radius: width / 2
                color: TelamonStyle.alpha(Kirigami.Theme.textColor, clearButton.down ? 0.15 : clearButton.hovered ? 0.08 : 0)
            }
            contentItem: Symbol {
                icon: Symbols.Cancel
                size: Kirigami.Units.iconSizes.small
                color: TelamonStyle.textMuted
            }
        }
    }

    // The error symbol, at the trailing edge (mirrored in RTL).
    Symbol {
        x: control.mirrored ? TelamonStyle.spacingLarge : control.width - width - TelamonStyle.spacingLarge
        y: Math.round((internals.fieldHeight - height) / 2)
        visible: internals.hasConflict
        icon: Symbols.Error
        size: internals.iconSize
        color: TelamonStyle.error
    }

    Text {
        id: message
        x: TelamonStyle.spacingLarge
        y: internals.fieldHeight + TelamonStyle.spacing
        width: control.width - TelamonStyle.spacingLarge * 2
        visible: internals.hasConflict
        text: internals.conflictText
        font.family: TelamonStyle.fontFamily
        font.pointSize: TelamonStyle.fontSizeCaption
        color: TelamonStyle.error
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
        horizontalAlignment: control.mirrored ? Text.AlignRight : Text.AlignLeft
        Accessible.ignored: true
    }
}
