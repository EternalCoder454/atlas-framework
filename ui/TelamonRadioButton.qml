import QtQuick
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami

// A round radio button with a label. Radio buttons with the same parent form
// a group: checking one unchecks the others. The arrow keys move the choice
// to the next or previous button of the group (wrapping round), as in any
// radio group.
//
//   Column {
//       TelamonRadioButton { text: qsTr("Light"); checked: true }
//       TelamonRadioButton { text: qsTr("Dark") }
//   }
T.RadioButton {
    id: control

    implicitWidth: Math.max(implicitBackgroundWidth + leftInset + rightInset, implicitContentWidth + leftPadding + rightPadding)
    implicitHeight: Math.max(Math.round(Kirigami.Units.gridUnit * 1.4), implicitContentHeight + topPadding + bottomPadding)
    spacing: TelamonStyle.spacingLarge
    padding: 0
    leftPadding: control.mirrored ? 0 : indicator.width + spacing
    rightPadding: control.mirrored ? indicator.width + spacing : 0
    hoverEnabled: true
    // Tab visits one radio of a group: the checked one, or the first if none is.
    focusPolicy: internals.tabStop ? Qt.StrongFocus : Qt.ClickFocus

    Accessible.name: text
    Accessible.role: Accessible.RadioButton
    Accessible.checkable: true
    Accessible.checked: control.checked

    QtObject {
        id: internals

        // The enabled, visible radio buttons of control's group, itself included.
        readonly property var group: {
            const list = [];
            if (!control.parent) {
                return [control];
            }
            for (const item of control.parent.children) {
                if (item === control || (item.autoExclusive === true && item.checkable === true && item.visible && item.enabled)) {
                    list.push(item);
                }
            }
            return list;
        }

        // Whether Tab stops here: when alone, when checked, or when it is the
        // first of a group in which none is checked.
        readonly property bool tabStop: {
            if (internals.group.length < 2 || control.checked) {
                return true;
            }
            for (const item of internals.group) {
                if (item.checked) {
                    return false;
                }
            }
            return internals.group[0] === control;
        }

        // Check the next (1) or previous (-1) button of the group; false when
        // there is none to move to (the key then goes on).
        function step(dir: int): bool {
            const group = internals.group;
            const at = group.indexOf(control);
            if (group.length < 2 || at < 0) {
                return false;
            }
            const target = group[(at + dir + group.length) % group.length];
            target.forceActiveFocus(Qt.TabFocusReason);
            if (!target.checked) {
                target.toggle();
            }
            return true;
        }
    }

    Keys.onDownPressed: event => event.accepted = internals.step(1)
    Keys.onUpPressed: event => event.accepted = internals.step(-1)
    Keys.onRightPressed: event => event.accepted = internals.step(control.mirrored ? -1 : 1)
    Keys.onLeftPressed: event => event.accepted = internals.step(control.mirrored ? 1 : -1)

    indicator: Rectangle {
        implicitWidth: Math.round(Kirigami.Units.gridUnit * 1.2)
        implicitHeight: implicitWidth
        x: control.mirrored ? control.width - width : 0
        y: Math.round((control.height - height) / 2)
        radius: TelamonStyle.radiusPill
        color: control.checked ? (control.enabled ? TelamonStyle.accent : TelamonStyle.alpha(TelamonStyle.accent, 0.4)) : control.enabled && control.hovered ? Qt.tint(TelamonStyle.control, TelamonStyle.hover) : TelamonStyle.control
        border.width: control.checked ? 0 : 1
        border.color: TelamonStyle.controlBorder
        Behavior on color {
            ColorAnimation {
                duration: TelamonStyle.durationShort
            }
        }
        Rectangle {
            anchors.centerIn: parent
            width: Math.round(parent.width * 0.4)
            height: width
            radius: width / 2
            color: TelamonStyle.accentText
            opacity: control.checked ? 1 : 0
            scale: control.checked ? 1 : 0.4
            Behavior on opacity {
                NumberAnimation {
                    duration: TelamonStyle.durationShort
                }
            }
            Behavior on scale {
                NumberAnimation {
                    duration: TelamonStyle.durationShort
                    easing.type: Easing.OutCubic
                }
            }
        }
        TelamonFocusRing {
            radius: parent.radius + gap
            shown: control.visualFocus
        }
    }

    contentItem: Text {
        text: control.text
        font.family: TelamonStyle.fontFamily
        font.pointSize: TelamonStyle.fontSizeBody
        color: control.enabled ? Kirigami.Theme.textColor : TelamonStyle.textDisabled
        elide: Text.ElideRight
        verticalAlignment: Text.AlignVCenter
        horizontalAlignment: control.mirrored ? Text.AlignRight : Text.AlignLeft
        textFormat: Text.PlainText // no mnemonics
    }
}
