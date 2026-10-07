pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami

// A small chip for a tag, a filter or a value. Plain (just `text`), checkable
// (a filter: the checked chip has the selection fill, an accent border and a
// check mark instead of its symbol, and is a full pill, while an unchecked one
// is a rounded rectangle of radiusLarge, 8 px) and/or `closable` (an x button, or Delete/Backspace while the
// chip has focus, emits `closeRequested()`; the app removes the chip).
//
//   TelamonChip { text: qsTr("Unread"); checkable: true; onToggled: app.filterUnread = checked }
//   TelamonChip { text: tag; closable: true; onCloseRequested: tags.remove(index) }
//
// Accessible name: the text; the close button's is "Remove <text>". Put chips
// that belong together in a TelamonChipGroup.
T.AbstractButton {
    id: control

    // A Material Symbol (Symbols.<Name>); 0 for none.
    property int symbol: 0
    property bool closable: false
    // The widest the chip asks for (its implicit width); a longer text is
    // elided. 0 means no limit. Since 1.5.0.
    property real maximumWidth: 0
    signal closeRequested

    // The TelamonChipGroup that holds the chip, set by the group; it is told when
    // the chip is shown, hidden, enabled or disabled (the roving Tab stop).
    // var, not Item: the group's _chipStateChanged() is not on Item (qmllint).
    property var _tabOwner: null
    onVisibleChanged: _tabOwner?._chipStateChanged()
    onEnabledChanged: _tabOwner?._chipStateChanged()
    // A chip moved out of its group stops telling the group, and is a Tab stop again.
    onParentChanged: {
        const owner = _tabOwner;
        if (!owner) {
            return;
        }
        let p = parent;
        while (p && p !== owner) {
            p = p.parent;
        }
        if (!p) {
            _tabOwner = null;
            focusPolicy = Qt.StrongFocus;
            owner._chipStateChanged();
        }
    }

    readonly property color tint: Kirigami.Theme.textColor
    readonly property bool showsCheck: checkable && checked

    implicitWidth: contentItem.implicitWidth + leftPadding + rightPadding
    implicitHeight: Math.round(Kirigami.Units.gridUnit * 1.5)
    leftPadding: mirrored ? _endPadding : TelamonStyle.spacingLarge
    rightPadding: mirrored ? TelamonStyle.spacingLarge : _endPadding
    readonly property real _endPadding: closable ? TelamonStyle.spacingSmall : TelamonStyle.spacingLarge
    hoverEnabled: true
    focusPolicy: Qt.StrongFocus
    scale: control.down && control.enabled ? 0.97 : 1

    Accessible.role: checkable ? Accessible.CheckBox : Accessible.Button
    Accessible.name: control.text
    Accessible.checkable: checkable
    Accessible.checked: checked

    // Return and Enter press the chip like Space: click() toggles a checkable
    // chip and runs its action, where emitting clicked() would not.
    Keys.onReturnPressed: event => {
        if (enabled && !event.isAutoRepeat) {
            control.click();
        }
    }
    Keys.onEnterPressed: event => {
        if (enabled && !event.isAutoRepeat) {
            control.click();
        }
    }
    Keys.onPressed: event => {
        if (control.closable && control.enabled && (event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace)) {
            event.accepted = true;
            control.closeRequested();
        }
    }

    Behavior on scale {
        NumberAnimation {
            duration: TelamonStyle.durationShort
            easing.type: Easing.OutCubic
        }
    }

    contentItem: Row {
        spacing: TelamonStyle.spacingSmall
        Loader {
            id: symbolSlot
            active: control.symbol !== 0 || control.showsCheck
            visible: active
            anchors.verticalCenter: parent.verticalCenter
            sourceComponent: Symbol {
                icon: control.showsCheck ? Symbols.Check : control.symbol
                size: Math.round(Kirigami.Units.iconSizes.small * 1.1)
                color: label.color
            }
        }
        Text {
            id: label
            Accessible.ignored: true
            anchors.verticalCenter: parent.verticalCenter
            text: control.text
            font.family: TelamonStyle.fontFamily
            font.pointSize: TelamonStyle.fontSizeBody
            color: !control.enabled ? TelamonStyle.textDisabled : control.showsCheck ? TelamonStyle.accent : control.tint
            textFormat: Text.PlainText
            elide: Text.ElideRight
            // With maximumWidth the text gives way; else it keeps its own width.
            width: control.maximumWidth > 0 ? Math.min(implicitWidth, Math.max(0, control.maximumWidth - control.leftPadding - control.rightPadding - (symbolSlot.visible ? symbolSlot.width + TelamonStyle.spacingSmall : 0) - (closeSpace.visible ? closeSpace.width + TelamonStyle.spacingSmall : 0))) : implicitWidth
        }
        // Room for the close button, which sits over it.
        Item {
            id: closeSpace
            visible: control.closable
            width: closeButton.width
            height: 1
        }
    }

    background: Rectangle {
        // Checkable chips: the checked one is a full pill, an unchecked one a rounded rectangle (radiusLarge).
        radius: control.checkable && !control.checked ? TelamonStyle.radiusLarge : height / 2
        color: control.showsCheck ? TelamonStyle.selection : TelamonStyle.control
        border.width: 1
        border.color: control.showsCheck && control.enabled ? TelamonStyle.accent : TelamonStyle.controlBorder
        Behavior on color {
            ColorAnimation {
                duration: TelamonStyle.durationShort
            }
        }
        Behavior on radius {
            NumberAnimation {
                duration: TelamonStyle.durationShort
            }
        }
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: !control.enabled ? "transparent" : control.down ? TelamonStyle.pressed : control.hovered ? TelamonStyle.hover : "transparent"
            Behavior on color {
                ColorAnimation {
                    duration: TelamonStyle.durationShort
                }
            }
        }
        TelamonFocusRing {
            radius: parent.radius + gap
            shown: control.visualFocus
        }
    }

    T.AbstractButton {
        id: closeButton
        visible: control.closable
        enabled: control.enabled
        width: Math.round(control.height * 0.72)
        height: width
        x: control.mirrored ? TelamonStyle.spacingSmall : control.width - width - TelamonStyle.spacingSmall
        anchors.verticalCenter: parent.verticalCenter
        hoverEnabled: true
        focusPolicy: Qt.NoFocus
        Accessible.role: Accessible.Button
        Accessible.name: qsTr("Remove %1").arg(control.text)
        onClicked: control.closeRequested()
        background: Rectangle {
            radius: height / 2
            color: closeButton.down ? TelamonStyle.pressed : closeButton.hovered ? TelamonStyle.hover : "transparent"
        }
        contentItem: Symbol {
            icon: Symbols.Close
            size: Math.round(Kirigami.Units.iconSizes.small * 0.9)
            color: control.enabled ? control.tint : TelamonStyle.textDisabled
            anchors.centerIn: parent
        }
    }
}
