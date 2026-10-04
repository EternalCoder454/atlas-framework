import QtQuick
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami

// A small rounded hint on a raised card. Declare it inside the item it
// describes and set `text`. Bind `shown` to the hover state: the tip opens
// after the hover delay, closes at once when `shown` ends, and goes by itself
// after a while. (Setting `visible` opens it at once.)
//
//   AtlasButton {
//       text: qsTr("Refresh")
//       AtlasToolTip { text: qsTr("Check for updates"); shown: parent.hovered }
//   }
T.ToolTip {
    id: control

    // Usually the hover state of the parent.
    property bool shown: false

    onShownChanged: {
        if (shown) {
            wait.restart();
        } else {
            wait.stop();
            close();
        }
    }

    Timer {
        id: wait
        interval: control.delay
        onTriggered: control.open()
    }

    x: parent ? Math.round((parent.width - implicitWidth) / 2) : 0
    y: -implicitHeight - Kirigami.Units.smallSpacing
    implicitWidth: Math.min(Kirigami.Units.gridUnit * 20, implicitContentWidth + leftPadding + rightPadding)
    implicitHeight: implicitContentHeight + topPadding + bottomPadding
    leftPadding: Kirigami.Units.largeSpacing
    rightPadding: Kirigami.Units.largeSpacing
    topPadding: Kirigami.Units.smallSpacing + 2
    bottomPadding: Kirigami.Units.smallSpacing + 2
    margins: Kirigami.Units.smallSpacing
    delay: Kirigami.Units.toolTipDelay
    timeout: Kirigami.Units.toolTipDelay * 10
    closePolicy: T.Popup.CloseOnEscape | T.Popup.CloseOnPressOutsideParent | T.Popup.CloseOnReleaseOutsideParent

    contentItem: Text {
        text: control.text
        font: Kirigami.Theme.smallFont
        color: Kirigami.Theme.textColor
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
    }

    background: Rectangle {
        radius: 8
        color: Kirigami.Theme.backgroundColor.hslLightness > 0.5 ? Qt.lighter(Kirigami.Theme.backgroundColor, 1.5) : Qt.tint(Kirigami.Theme.backgroundColor, Qt.rgba(1, 1, 1, 0.08))
        border.width: 1
        border.color: Qt.alpha(Kirigami.Theme.textColor, 0.16)
    }

    enter: Transition {
        NumberAnimation {
            property: "opacity"
            from: 0
            to: 1
            duration: Kirigami.Units.shortDuration
        }
    }
    exit: Transition {
        NumberAnimation {
            property: "opacity"
            from: 1
            to: 0
            duration: Kirigami.Units.shortDuration
        }
    }
}
