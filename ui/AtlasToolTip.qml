import QtQuick
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami

// A small rounded hint on a raised card. Declare it inside the item it
// describes and set `text`; it shows after the hover delay and goes by
// itself.
//
//   AtlasButton {
//       text: qsTr("Refresh")
//       AtlasToolTip { text: qsTr("Check for updates"); visible: parent.hovered }
//   }
T.ToolTip {
    id: control

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
