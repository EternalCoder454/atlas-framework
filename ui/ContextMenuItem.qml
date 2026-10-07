pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami

// One row of a ContextMenu: an icon, the text, and a shortcut hint on the
// right. A `destructive` row (Kill, Delete) is drawn in the negative colour.
// A checked `checkable` row shows a check mark in the icon's place, a row
// that opens a submenu an arrow at the end. A hidden row takes no room.
//
// A `radio` row is checkable and draws a dot (instead of the check mark) when
// checked. Rows of one choice share a Qt group, and the group makes them
// exclusive and keeps the checked one from being unchecked by a second click:
// either an exclusive ActionGroup (the rows' `action`s) or a ButtonGroup
// (`ButtonGroup.group: group` on each row, from QtQuick.Controls; it works
// with T.MenuItem):
//
//   ButtonGroup { id: sortGroup }
//   ContextMenuItem { text: qsTr("Name"); radio: true; checked: true; ButtonGroup.group: sortGroup }
//   ContextMenuItem { text: qsTr("Size"); radio: true; ButtonGroup.group: sortGroup }
//
// With an `action` (TelamonAction or a plain Qt Action) the row shows its
// `symbol` and, when `shortcutText` is empty, its shortcut.
T.MenuItem {
    id: control

    property bool destructive: false
    // A Material Symbol (Symbols.<Name>) to draw instead of icon.name.
    property int symbol: _actionObject && _actionObject.symbol !== undefined ? _actionObject.symbol : 0
    // The action, read duck-typed so a plain Qt Action works too.
    readonly property var _actionObject: control.action
    // Shown dimmed on the right ("Del"); it only describes, it doesn't bind.
    property string shortcutText
    // A choice among several: a dot instead of the check mark. Implies checkable.
    property bool radio: false

    checkable: control.radio || (_actionObject ? _actionObject.checkable === true : false)

    // shortcutText, else the action's shortcut.
    readonly property string _effectiveShortcut: {
        if (control.shortcutText.length > 0) {
            return control.shortcutText;
        }
        const seq = _actionObject ? _actionObject.shortcut : undefined;
        return seq !== undefined && seq !== null ? TelamonShortcuts.readable(seq) : "";
    }
    readonly property bool showsCheck: checkable && checked && !radio
    readonly property bool _showsDot: radio && checked
    readonly property color tint: !enabled ? TelamonStyle.textDisabled : destructive ? TelamonStyle.error : TelamonStyle.text

    implicitWidth: contentItem.implicitWidth + leftPadding + rightPadding
    implicitHeight: visible ? Math.round(Kirigami.Units.gridUnit * 1.8) : 0
    leftPadding: TelamonStyle.spacingLarge
    rightPadding: TelamonStyle.spacingLarge
    hoverEnabled: true
    icon.width: Kirigami.Units.iconSizes.small
    icon.height: Kirigami.Units.iconSizes.small

    // The text without an action's "&" mnemonic marker ("&&" is one "&").
    readonly property string _plainText: control.text.replace(/&(&|.)/g, "$1")

    Accessible.name: control._plainText
    Accessible.description: _effectiveShortcut
    Accessible.checkable: checkable
    Accessible.checked: checked

    background: Rectangle {
        radius: TelamonStyle.radiusSmall
        color: control.highlighted ? (control.destructive ? TelamonStyle.errorFill : control.down ? TelamonStyle.pressed : TelamonStyle.hover) : "transparent"
    }

    contentItem: RowLayout {
        spacing: TelamonStyle.spacingLarge

        Item {
            Layout.preferredWidth: control.icon.width
            Layout.preferredHeight: control.icon.height
            // Rows with and without icons line up.
            Kirigami.Icon {
                anchors.fill: parent
                visible: control.showsCheck || (!control._showsDot && control.symbol === 0 && source.toString().length > 0)
                source: control.showsCheck ? "checkmark" : control.icon.name.length > 0 ? control.icon.name : control.icon.source
                isMask: true
                color: control.tint
            }
            Rectangle {
                anchors.centerIn: parent
                visible: control._showsDot
                width: Math.round(parent.width * 0.5)
                height: width
                radius: width / 2
                color: control.tint
            }
            // Made only when used, so rows without one never load the fonts.
            Loader {
                anchors.centerIn: parent
                active: control.symbol !== 0 && !control.showsCheck && !control._showsDot
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
            text: control._plainText
            font.family: TelamonStyle.fontFamily
            font.pointSize: TelamonStyle.fontSizeBody
            color: control.tint
            textFormat: Text.PlainText
            elide: Text.ElideRight
        }
        Text {
            visible: control._effectiveShortcut.length > 0
            Layout.leftMargin: Kirigami.Units.gridUnit
            text: control._effectiveShortcut
            font.family: TelamonStyle.fontFamily
            font.pointSize: TelamonStyle.fontSizeCaption
            color: control.enabled ? TelamonStyle.textMuted : TelamonStyle.textDisabled
            textFormat: Text.PlainText
        }
        Kirigami.Icon {
            visible: control.subMenu !== null
            Layout.preferredWidth: Kirigami.Units.iconSizes.small
            Layout.preferredHeight: Layout.preferredWidth
            source: control.mirrored ? "go-previous" : "go-next"
            isMask: true
            color: control.enabled ? TelamonStyle.textMuted : TelamonStyle.textDisabled
        }
    }
}
