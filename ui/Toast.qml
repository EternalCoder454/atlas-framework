import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// A short message that appears at the bottom centre of its parent and goes
// by itself: "Copied", "Saved". Call show("text"). It stays while the
// pointer is over it or its button has focus. For "Deleted" with an "Undo", call
// showAction("Deleted", "Undo") and handle actionTriggered(): the button is
// reached with Tab, and clicking it hides the toast. Place it as the last child of the window's content so
// that it draws above the rest.
Item {
    id: control

    // How long it stays, in ms.
    property int interval: 2500
    property alias text: label.text
    // The label of the action button (Undo); empty for none. show() clears it.
    property string actionText

    // The action button was clicked; the toast has already hidden itself.
    signal actionTriggered

    function show(message) {
        control.actionText = "";
        priv.display(message);
    }
    // Shows `message` with an action button labelled `actionText`.
    function showAction(message, actionText) {
        control.actionText = actionText;
        priv.display(message);
    }
    function hide() {
        timer.stop();
        timer.showing = false;
    }

    QtObject {
        id: priv
        function display(message) {
            label.text = message;
            control.Accessible.announce(control.actionText.length > 0 ? message + ", " + control.actionText : message);
            timer.showing = true;
            timer.restart();
        }
    }

    anchors.horizontalCenter: parent ? parent.horizontalCenter : undefined
    anchors.bottom: parent ? parent.bottom : undefined
    anchors.bottomMargin: Kirigami.Units.gridUnit * 2
    width: pill.width
    height: pill.height
    visible: opacity > 0
    opacity: timer.showing ? 1 : 0
    z: 100
    Accessible.role: Accessible.AlertMessage
    Accessible.name: label.text

    Behavior on opacity {
        NumberAnimation {
            duration: AtlasStyle.durationShort
        }
    }

    Timer {
        id: timer
        // Whether the toast is up (internal: not part of the API).
        property bool showing: false
        interval: control.interval
        // Hovering holds it: the timer starts over when the pointer leaves.
        running: false
        onTriggered: {
            if (hoverHandler.hovered || actionButton.visualFocus || actionButton.activeFocus) {
                timer.restart();
            } else {
                timer.showing = false;
            }
        }
    }

    HoverHandler {
        id: hoverHandler
    }

    // A soft shadow, then the pill.
    Rectangle {
        anchors.fill: pill
        anchors.topMargin: 2
        anchors.bottomMargin: -3
        anchors.leftMargin: -1
        anchors.rightMargin: -1
        radius: AtlasStyle.radiusPill
        color: Qt.rgba(0, 0, 0, 0.18)
    }
    Rectangle {
        id: pill
        readonly property real pad: Kirigami.Units.gridUnit
        width: Math.min(row.implicitWidth + pad + (actionButton.visible ? AtlasStyle.spacingSmall : pad), Math.max(0, (control.parent ? control.parent.width : 0) - Kirigami.Units.gridUnit * 2))
        height: Math.max(label.implicitHeight, actionButton.visible ? actionButton.implicitHeight : 0) + AtlasStyle.spacingLarge * 2
        radius: AtlasStyle.radiusPill
        color: Kirigami.Theme.backgroundColor.hslLightness > 0.5 ? Qt.lighter(Kirigami.Theme.backgroundColor, 1.5) : Qt.tint(Kirigami.Theme.backgroundColor, Qt.rgba(1, 1, 1, 0.1))
        border.width: 1
        border.color: Qt.alpha(Kirigami.Theme.textColor, 0.16)

        RowLayout {
            id: row
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: pill.pad
            anchors.rightMargin: actionButton.visible ? AtlasStyle.spacingSmall : pill.pad
            spacing: AtlasStyle.spacingLarge

            QQC2.Label {
                id: label
                Layout.fillWidth: true
                horizontalAlignment: actionButton.visible ? Text.AlignLeft : Text.AlignHCenter
                elide: Text.ElideRight
                textFormat: Text.PlainText
                color: Kirigami.Theme.textColor
            }
            TextButton {
                id: actionButton
                visible: control.actionText.length > 0
                text: control.actionText
                Accessible.name: control.actionText
                onClicked: {
                    control.hide();
                    control.actionTriggered();
                }
            }
        }
    }
}
