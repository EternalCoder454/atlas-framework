import QtQuick
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami

// A round radio button with a label. Radio buttons with the same parent form
// a group: checking one unchecks the others.
//
//   Column {
//       AtlasRadioButton { text: qsTr("Light"); checked: true }
//       AtlasRadioButton { text: qsTr("Dark") }
//   }
T.RadioButton {
    id: control

    implicitWidth: Math.max(implicitBackgroundWidth + leftInset + rightInset, implicitContentWidth + leftPadding + rightPadding)
    implicitHeight: Math.max(Math.round(Kirigami.Units.gridUnit * 1.4), implicitContentHeight + topPadding + bottomPadding)
    spacing: Kirigami.Units.largeSpacing
    padding: 0
    leftPadding: indicator.width + spacing
    hoverEnabled: true
    focusPolicy: Qt.StrongFocus
    opacity: enabled ? 1 : 0.5

    Accessible.name: text
    Accessible.role: Accessible.RadioButton

    indicator: Rectangle {
        implicitWidth: Math.round(Kirigami.Units.gridUnit * 1.2)
        implicitHeight: implicitWidth
        x: control.mirrored ? control.width - width : 0
        y: Math.round((control.height - height) / 2)
        radius: height / 2
        color: control.checked ? (control.enabled ? Kirigami.Theme.highlightColor : control.palette.active.highlight) : Qt.alpha(Kirigami.Theme.textColor, control.hovered ? 0.12 : 0.07)
        border.width: 1
        border.color: control.checked ? "transparent" : Qt.alpha(Kirigami.Theme.textColor, 0.3)
        Behavior on color {
            ColorAnimation {
                duration: Kirigami.Units.shortDuration
            }
        }
        Rectangle {
            anchors.centerIn: parent
            width: Math.round(parent.width * 0.4)
            height: width
            radius: width / 2
            color: Kirigami.Theme.highlightedTextColor
            opacity: control.checked ? 1 : 0
            scale: control.checked ? 1 : 0.4
            Behavior on opacity {
                NumberAnimation {
                    duration: Kirigami.Units.shortDuration
                }
            }
            Behavior on scale {
                NumberAnimation {
                    duration: Kirigami.Units.shortDuration
                    easing.type: Easing.OutCubic
                }
            }
        }
        AtlasFocusRing {
            radius: parent.radius + gap
            shown: control.visualFocus
        }
    }

    contentItem: Text {
        text: control.text
        font: Kirigami.Theme.defaultFont
        color: Kirigami.Theme.textColor
        elide: Text.ElideRight
        verticalAlignment: Text.AlignVCenter
        horizontalAlignment: control.mirrored ? Text.AlignRight : Text.AlignLeft
        textFormat: Text.PlainText // no mnemonics
    }
}
