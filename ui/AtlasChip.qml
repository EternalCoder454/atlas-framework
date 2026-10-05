import QtQuick
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami

// A small pill for a tag, a filter or a value. Plain (just `text`), checkable
// (a filter: the checked chip has the selection fill, an accent border and a
// check mark instead of its symbol, and is a full pill while an unchecked one
// is a little less round) and/or `closable` (an x button, or Delete/Backspace while the
// chip has focus, emits `closeRequested()`; the app removes the chip).
//
//   AtlasChip { text: qsTr("Unread"); checkable: true; onToggled: app.filterUnread = checked }
//   AtlasChip { text: tag; closable: true; onCloseRequested: tags.remove(index) }
//
// Accessible name: the text; the close button's is "Remove <text>". Put chips
// that belong together in an AtlasChipGroup.
T.AbstractButton {
    id: control

    // A Material Symbol (Symbols.<Name>); 0 for none.
    property int symbol: 0
    property bool closable: false
    signal closeRequested

    readonly property color tint: Kirigami.Theme.textColor
    readonly property bool showsCheck: checkable && checked

    implicitWidth: contentItem.implicitWidth + leftPadding + rightPadding
    implicitHeight: Math.round(Kirigami.Units.gridUnit * 1.5)
    leftPadding: mirrored ? _endPadding : AtlasStyle.spacingLarge
    rightPadding: mirrored ? AtlasStyle.spacingLarge : _endPadding
    readonly property real _endPadding: closable ? AtlasStyle.spacingSmall : AtlasStyle.spacingLarge
    hoverEnabled: true
    focusPolicy: Qt.StrongFocus
    scale: control.down && control.enabled ? 0.97 : 1

    Accessible.role: checkable ? Accessible.CheckBox : Accessible.Button
    Accessible.name: control.text
    Accessible.checkable: checkable
    Accessible.checked: checked

    Keys.onPressed: event => {
        if (control.closable && control.enabled && (event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace)) {
            event.accepted = true;
            control.closeRequested();
        }
    }

    Behavior on scale {
        NumberAnimation {
            duration: AtlasStyle.durationShort
            easing.type: Easing.OutCubic
        }
    }

    contentItem: Row {
        spacing: AtlasStyle.spacingSmall
        Loader {
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
            font: Kirigami.Theme.defaultFont
            color: !control.enabled ? AtlasStyle.textDisabled : control.showsCheck ? AtlasStyle.accent : control.tint
            textFormat: Text.PlainText
        }
        // Room for the close button, which sits over it.
        Item {
            visible: control.closable
            width: closeButton.width
            height: 1
        }
    }

    background: Rectangle {
        // Checkable chips: the checked one is a full pill, the others a little less round.
        radius: control.checkable && !control.checked ? AtlasStyle.radiusLarge : height / 2
        color: control.showsCheck ? AtlasStyle.selection : AtlasStyle.control
        border.width: 1
        border.color: control.showsCheck && control.enabled ? AtlasStyle.accent : AtlasStyle.controlBorder
        Behavior on color {
            ColorAnimation {
                duration: AtlasStyle.durationShort
            }
        }
        Behavior on radius {
            NumberAnimation {
                duration: AtlasStyle.durationShort
            }
        }
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: !control.enabled ? "transparent" : control.down ? AtlasStyle.pressed : control.hovered ? AtlasStyle.hover : "transparent"
            Behavior on color {
                ColorAnimation {
                    duration: AtlasStyle.durationShort
                }
            }
        }
        AtlasFocusRing {
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
        x: control.mirrored ? AtlasStyle.spacingSmall : control.width - width - AtlasStyle.spacingSmall
        anchors.verticalCenter: parent.verticalCenter
        hoverEnabled: true
        focusPolicy: Qt.NoFocus
        Accessible.role: Accessible.Button
        Accessible.name: qsTr("Remove %1").arg(control.text)
        onClicked: control.closeRequested()
        background: Rectangle {
            radius: height / 2
            color: closeButton.down ? AtlasStyle.pressed : closeButton.hovered ? AtlasStyle.hover : "transparent"
        }
        contentItem: Symbol {
            icon: Symbols.Close
            size: Math.round(Kirigami.Units.iconSizes.small * 0.9)
            color: control.enabled ? control.tint : AtlasStyle.textDisabled
            anchors.centerIn: parent
        }
    }
}
