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
// names the registered AtlasAction that already has the same shortcut (not
// `ignoreAction`, the one being edited), and shows under the field; it is
// empty when there is none. The field only reports: the app decides whether to
// accept the shortcut, in `onEdited`.
//
//   AtlasShortcutField {
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
    // Set when another registered AtlasAction already uses `sequence`.
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
        readonly property real fieldHeight: Math.round(Kirigami.Units.gridUnit * 1.9)
        readonly property string wanted: AtlasShortcuts.portable(control.sequence)
        readonly property string conflictText: {
            if (wanted.length === 0) {
                return "";
            }
            const actions = AtlasShortcuts.actions;
            for (let i = 0; i < actions.length; ++i) {
                const action = actions[i];
                if (action === control.ignoreAction || AtlasShortcuts.portable(action.shortcut) !== wanted) {
                    continue;
                }
                //: Under a shortcut field: %1 is the name of the action that already has that shortcut
                return qsTr("Already used by “%1”").arg(AtlasShortcuts.plainText(action.text));
            }
            return "";
        }
        readonly property bool hasConflict: conflictText.length > 0
        readonly property bool showClear: control.sequence.length > 0 && !recording && control.enabled
        readonly property real messageHeight: hasConflict ? message.implicitHeight + Kirigami.Units.smallSpacing : 0

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
            const portable = AtlasShortcuts.portable(text + name);
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
    leftPadding: Kirigami.Units.largeSpacing
    rightPadding: Kirigami.Units.largeSpacing
    bottomPadding: internals.messageHeight
    hoverEnabled: true
    focusPolicy: Qt.StrongFocus
    opacity: enabled ? 1 : 0.5

    Accessible.role: Accessible.Button
    Accessible.name: internals.recording ? qsTr("Press keys…") : control.sequence.length > 0 ? AtlasShortcuts.readable(control.sequence) : control.placeholderText
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
        if (event.key === Qt.Key_Escape) {
            internals.recording = false;
        } else if (event.key === Qt.Key_Backspace || event.key === Qt.Key_Delete) {
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
            radius: height / 2
            color: Qt.alpha(Kirigami.Theme.textColor, control.hovered && !control.activeFocus ? 0.09 : 0.06)
            border.width: internals.recording || control.activeFocus || internals.hasConflict ? 2 : 1
            border.color: internals.hasConflict ? Kirigami.Theme.negativeTextColor
                : internals.recording ? Kirigami.Theme.highlightColor
                : control.activeFocus ? Qt.alpha(Kirigami.Theme.highlightColor, 0.7)
                : Qt.alpha(Kirigami.Theme.textColor, 0.1)
            AtlasFocusRing {
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
            font: Kirigami.Theme.defaultFont
            color: internals.recording ? Kirigami.Theme.highlightColor : Qt.alpha(Kirigami.Theme.textColor, 0.5)
            elide: Text.ElideRight
            textFormat: Text.PlainText
            Accessible.ignored: true
        }
        AtlasShortcutLabel {
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
            width: Kirigami.Units.iconSizes.small + Kirigami.Units.smallSpacing * 2
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

    Text {
        id: message
        x: Kirigami.Units.largeSpacing
        y: internals.fieldHeight + Kirigami.Units.smallSpacing
        width: control.width - Kirigami.Units.largeSpacing * 2
        visible: internals.hasConflict
        text: internals.conflictText
        font: Kirigami.Theme.smallFont
        color: Kirigami.Theme.negativeTextColor
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
        horizontalAlignment: control.mirrored ? Text.AlignRight : Text.AlignLeft
        Accessible.ignored: true
    }
}
