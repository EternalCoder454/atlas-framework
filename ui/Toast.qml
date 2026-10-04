import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

// A short message that appears at the bottom centre of its parent and goes
// by itself: "Copied", "Saved". Call show("text"). It stays while the
// pointer is over it. Place it as the last child of the window's content so
// that it draws above the rest.
Item {
    id: control

    // How long it stays, in ms.
    property int interval: 2500
    property alias text: label.text

    function show(message) {
        label.text = message;
        timer.showing = true;
        timer.restart();
    }
    function hide() {
        timer.stop();
        timer.showing = false;
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
            duration: Kirigami.Units.shortDuration
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
            if (hoverHandler.hovered) {
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
        radius: height / 2
        color: Qt.rgba(0, 0, 0, 0.18)
    }
    Rectangle {
        id: pill
        width: Math.min(label.implicitWidth + Kirigami.Units.gridUnit * 2, (control.parent ? control.parent.width : 0) - Kirigami.Units.gridUnit * 2)
        height: label.implicitHeight + Kirigami.Units.largeSpacing * 2
        radius: height / 2
        color: Kirigami.Theme.backgroundColor.hslLightness > 0.5 ? Qt.lighter(Kirigami.Theme.backgroundColor, 1.5) : Qt.tint(Kirigami.Theme.backgroundColor, Qt.rgba(1, 1, 1, 0.1))
        border.width: 1
        border.color: Qt.alpha(Kirigami.Theme.textColor, 0.16)

        QQC2.Label {
            id: label
            anchors.centerIn: parent
            width: parent.width - Kirigami.Units.gridUnit * 2
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            textFormat: Text.PlainText
            color: Kirigami.Theme.textColor
        }
    }
}
