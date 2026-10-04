import QtQuick
import QtQuick.Layouts
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami

// One row of a ContextMenu: an icon, the text, and a shortcut hint on the
// right. A `destructive` row (Kill, Delete) is drawn in the negative colour.
// A checked `checkable` row shows a check mark in the icon's place, a row
// that opens a submenu an arrow at the end. A hidden row takes no room.
T.MenuItem {
    id: control

    property bool destructive: false
    // A Material Symbol (Symbols.<Name>) to draw instead of icon.name.
    property int symbol: 0
    // Shown dimmed on the right ("Del"); it only describes, it doesn't bind.
    property string shortcutText

    readonly property bool showsCheck: checkable && checked
    readonly property color tint: destructive ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor

    implicitWidth: contentItem.implicitWidth + leftPadding + rightPadding
    implicitHeight: visible ? Math.round(Kirigami.Units.gridUnit * 1.8) : 0
    leftPadding: Kirigami.Units.largeSpacing
    rightPadding: Kirigami.Units.largeSpacing
    hoverEnabled: true
    icon.width: Kirigami.Units.iconSizes.small
    icon.height: Kirigami.Units.iconSizes.small
    opacity: enabled ? 1 : 0.45

    Accessible.name: text
    Accessible.description: shortcutText

    background: Rectangle {
        radius: 6
        color: control.highlighted ? Qt.alpha(control.destructive ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.highlightColor, control.down ? 0.28 : 0.18) : "transparent"
    }

    contentItem: RowLayout {
        spacing: Kirigami.Units.largeSpacing

        Item {
            Layout.preferredWidth: control.icon.width
            Layout.preferredHeight: control.icon.height
            // Rows with and without icons line up.
            Kirigami.Icon {
                anchors.fill: parent
                visible: control.showsCheck || (control.symbol === 0 && source.toString().length > 0)
                source: control.showsCheck ? "checkmark" : control.icon.name.length > 0 ? control.icon.name : control.icon.source
                isMask: true
                color: control.tint
            }
            // Made only when used, so rows without one never load the fonts.
            Loader {
                anchors.centerIn: parent
                active: control.symbol !== 0 && !control.showsCheck
                sourceComponent: Symbol {
                    icon: control.symbol
                    // A symbol fills about 5/6 of its square: a little larger
                    // matches a theme icon of the same slot.
                    size: Math.round(control.icon.width * 1.2)
                    color: control.tint
                }
            }
        }
        Text {
            Layout.fillWidth: true
            text: control.text
            font: Kirigami.Theme.defaultFont
            color: control.tint
            textFormat: Text.PlainText
            elide: Text.ElideRight
        }
        Text {
            visible: control.shortcutText.length > 0
            Layout.leftMargin: Kirigami.Units.gridUnit
            text: control.shortcutText
            font: Kirigami.Theme.smallFont
            color: Qt.alpha(Kirigami.Theme.textColor, 0.5)
            textFormat: Text.PlainText
        }
        Kirigami.Icon {
            visible: control.subMenu !== null
            Layout.preferredWidth: Kirigami.Units.iconSizes.small
            Layout.preferredHeight: Layout.preferredWidth
            source: control.mirrored ? "go-previous" : "go-next"
            isMask: true
            color: Qt.alpha(Kirigami.Theme.textColor, 0.6)
        }
    }
}
