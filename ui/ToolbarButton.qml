import QtQuick
import QtQuick.Templates as T
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

// A small icon button for formatting toolbars (Bold, Italic, ...). It never
// takes the keyboard focus from the editor. `checkable` makes it a toggle,
// drawn with the accent tint while checked. The tooltip is the text plus the
// optional `shortcutText`: "Bold (Ctrl+B)".
T.AbstractButton {
    id: control

    // The shortcut as shown to people, such as "Ctrl+B".
    property string shortcutText
    // Turns the icon, for a chevron that points down once opened.
    property real iconRotation: 0

    implicitWidth: Math.max(implicitHeight, contentItem.implicitWidth + leftPadding + rightPadding)
    implicitHeight: Math.round(Kirigami.Units.gridUnit * 1.7)
    padding: Kirigami.Units.smallSpacing + 1
    display: T.AbstractButton.IconOnly
    hoverEnabled: true
    focusPolicy: Qt.NoFocus
    Accessible.name: control.text
    Accessible.description: control.shortcutText
    Accessible.checkable: control.checkable
    Accessible.checked: control.checked

    QQC2.ToolTip.visible: control.hovered && control.text.length > 0
    QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
    QQC2.ToolTip.text: control.shortcutText.length > 0 ? qsTr("%1 (%2)").arg(control.text).arg(control.shortcutText) : control.text

    background: Rectangle {
        radius: 6
        color: control.checked ? Qt.alpha(Kirigami.Theme.highlightColor, control.down ? 0.28 : 0.18) : Qt.alpha(Kirigami.Theme.textColor, control.down ? 0.12 : control.hovered ? 0.07 : 0)
        Behavior on color {
            ColorAnimation {
                duration: Kirigami.Units.shortDuration
            }
        }
    }

    contentItem: Item {
        implicitWidth: row.implicitWidth
        implicitHeight: row.implicitHeight
        Row {
            id: row
            anchors.centerIn: parent
            spacing: Kirigami.Units.smallSpacing
            Kirigami.Icon {
                visible: control.display !== T.AbstractButton.TextOnly && (control.icon.name.length > 0 || control.icon.source.toString().length > 0)
                source: control.icon.name.length > 0 ? control.icon.name : control.icon.source
                isMask: true
                color: Kirigami.Theme.textColor
                opacity: control.enabled ? 1 : 0.4
                width: Kirigami.Units.iconSizes.small
                height: width
                rotation: control.iconRotation
                anchors.verticalCenter: parent.verticalCenter
                Behavior on rotation {
                    NumberAnimation {
                        duration: Kirigami.Units.shortDuration
                    }
                }
            }
            Text {
                visible: control.display !== T.AbstractButton.IconOnly
                anchors.verticalCenter: parent.verticalCenter
                text: control.text
                font: Kirigami.Theme.defaultFont
                color: Kirigami.Theme.textColor
                opacity: control.enabled ? 1 : 0.4
                textFormat: Text.PlainText
            }
        }
    }
}
