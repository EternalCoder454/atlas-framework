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
//
// Without `text`, name it for screen readers with Accessible.name.
T.CheckBox {
    id: control

    implicitWidth: Math.max(implicitBackgroundWidth + leftInset + rightInset, implicitContentWidth + leftPadding + rightPadding)
    implicitHeight: Math.max(Math.round(Kirigami.Units.gridUnit * 1.4), implicitContentHeight + topPadding + bottomPadding)
    spacing: AtlasStyle.spacingLarge
    padding: 0
    leftPadding: control.mirrored ? 0 : indicator.width + spacing
    rightPadding: control.mirrored ? indicator.width + spacing : 0
    hoverEnabled: true
    focusPolicy: Qt.StrongFocus

    Accessible.name: text
    Accessible.role: Accessible.CheckBox
    Accessible.checkable: true
    Accessible.checked: control.checkState !== Qt.Unchecked
    Accessible.checkStateMixed: control.checkState === Qt.PartiallyChecked

    indicator: Rectangle {
        implicitWidth: Math.round(Kirigami.Units.gridUnit * 1.2)
        implicitHeight: implicitWidth
        x: control.mirrored ? control.width - width : 0
        y: Math.round((control.height - height) / 2)
        radius: AtlasStyle.radiusSmall
        color: control.checkState !== Qt.Unchecked ? (control.enabled ? AtlasStyle.accent : Qt.alpha(AtlasStyle.accent, 0.4)) : control.enabled && control.hovered ? Qt.tint(AtlasStyle.control, AtlasStyle.hover) : AtlasStyle.control
        border.width: control.checkState !== Qt.Unchecked ? 0 : 1
        border.color: AtlasStyle.controlBorder
        Behavior on color {
            ColorAnimation {
                duration: AtlasStyle.durationShort
            }
        }
        Loader {
            anchors.centerIn: parent
            active: control.checkState === Qt.Checked
            sourceComponent: Symbol {
                name: "check"
                weight: 600
                size: Math.round(Kirigami.Units.gridUnit * 1.2 * 0.9)
                color: AtlasStyle.accentText
            }
        }
        Rectangle {
            anchors.centerIn: parent
            visible: control.checkState === Qt.PartiallyChecked
            width: Math.round(parent.width * 0.5)
            height: 2
            radius: 1
            color: AtlasStyle.accentText
        }
        AtlasFocusRing {
            radius: parent.radius + gap
            shown: control.visualFocus
        }
    }

    contentItem: Text {
        text: control.text
        font.family: AtlasStyle.fontFamily
        font.pointSize: AtlasStyle.fontSizeBody
        color: control.enabled ? Kirigami.Theme.textColor : AtlasStyle.textDisabled
        elide: Text.ElideRight
        verticalAlignment: Text.AlignVCenter
        horizontalAlignment: control.mirrored ? Text.AlignRight : Text.AlignLeft
        textFormat: Text.PlainText // no mnemonics
    }
}
