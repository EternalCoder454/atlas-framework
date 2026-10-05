import QtQuick
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami

// A small pill for a tag, a filter or a value. Plain (just `text`), checkable
// (a filter: the checked chip is accent-tinted and shows a check mark instead
// of its symbol) and/or `closable` (an x button, or Delete/Backspace while the
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
    leftPadding: Kirigami.Units.largeSpacing
    rightPadding: closable ? Kirigami.Units.smallSpacing : Kirigami.Units.largeSpacing
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
        spacing: Kirigami.Units.smallSpacing
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
            color: control.tint
            opacity: control.enabled ? 1 : 0.6
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
        radius: height / 2
        color: {
            if (control.showsCheck) {
                return Qt.alpha(Kirigami.Theme.highlightColor, control.down ? 0.34 : control.hovered ? 0.28 : 0.22);
            }
            return Qt.alpha(control.tint, control.down ? 0.2 : control.hovered ? 0.12 : 0.07);
        }
        border.width: 1
        border.color: control.showsCheck ? Qt.alpha(Kirigami.Theme.highlightColor, 0.6) : Qt.alpha(control.tint, 0.14)
        opacity: control.enabled ? 1 : 0.6
        Behavior on color {
            ColorAnimation {
                duration: AtlasStyle.durationShort
            }
        }
        AtlasFocusRing {
            radius: parent.radius
            shown: control.visualFocus
        }
    }

    T.AbstractButton {
        id: closeButton
        visible: control.closable
        enabled: control.enabled
        width: Math.round(control.height * 0.72)
        height: width
        x: control.mirrored ? Kirigami.Units.smallSpacing : control.width - width - Kirigami.Units.smallSpacing
        anchors.verticalCenter: parent.verticalCenter
        hoverEnabled: true
        focusPolicy: Qt.NoFocus
        Accessible.role: Accessible.Button
        Accessible.name: qsTr("Remove %1").arg(control.text)
        onClicked: control.closeRequested()
        background: Rectangle {
            radius: height / 2
            color: Qt.alpha(control.tint, closeButton.down ? 0.25 : closeButton.hovered ? 0.15 : 0)
        }
        contentItem: Symbol {
            icon: Symbols.Close
            size: Math.round(Kirigami.Units.iconSizes.small * 0.9)
            color: control.tint
            opacity: control.enabled ? 0.8 : 0.5
            anchors.centerIn: parent
        }
    }
}
