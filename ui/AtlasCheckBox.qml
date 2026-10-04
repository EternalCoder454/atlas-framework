pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami

// A rounded check box with a label. With `tristate: true` it also has a
// partly-checked state (`checkState === Qt.PartiallyChecked`), drawn as a
// dash; a click then cycles unchecked, partly, checked.
//
//   AtlasCheckBox { text: qsTr("Remember me"); checked: true }
//   AtlasCheckBox { text: qsTr("Select all"); tristate: true; checkState: Qt.PartiallyChecked }
T.CheckBox {
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
    Accessible.role: Accessible.CheckBox

    indicator: Rectangle {
        implicitWidth: Math.round(Kirigami.Units.gridUnit * 1.2)
        implicitHeight: implicitWidth
        x: control.mirrored ? control.width - width : 0
        y: Math.round((control.height - height) / 2)
        radius: 6
        color: control.checkState !== Qt.Unchecked ? (control.enabled ? Kirigami.Theme.highlightColor : control.palette.active.highlight) : Qt.alpha(Kirigami.Theme.textColor, control.hovered ? 0.12 : 0.07)
        border.width: 1
        border.color: control.checkState !== Qt.Unchecked ? "transparent" : Qt.alpha(Kirigami.Theme.textColor, 0.3)
        Behavior on color {
            ColorAnimation {
                duration: Kirigami.Units.shortDuration
            }
        }
        Loader {
            anchors.centerIn: parent
            active: control.checkState === Qt.Checked
            sourceComponent: Symbol {
                name: "check"
                weight: 600
                size: Math.round(Kirigami.Units.gridUnit * 1.2 * 0.9)
                color: Kirigami.Theme.highlightedTextColor
            }
        }
        Rectangle {
            anchors.centerIn: parent
            visible: control.checkState === Qt.PartiallyChecked
            width: Math.round(parent.width * 0.5)
            height: 2
            radius: 1
            color: Kirigami.Theme.highlightedTextColor
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
