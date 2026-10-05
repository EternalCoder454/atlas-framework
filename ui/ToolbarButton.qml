import QtQuick
import QtQuick.Templates as T
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

// A small icon button for formatting toolbars (Bold, Italic, ...). It never
// takes the keyboard focus from the editor. `checkable` makes it a toggle,
// drawn with an accent-tinted fill and an accent icon while checked. The
// tooltip is the text plus the optional `shortcutText`: "Bold (Ctrl+B)".
//
// With an `action` (an AtlasAction or a plain Qt Action) the button follows
// it: the tooltip is `action.toolTip`, else `action.text`, else `text`; the
// `action.symbol` is the symbol when it has one; and the action's shortcut is
// shown when `shortcutText` is empty. `symbol` (a Material Symbol) is drawn
// instead of the icon. `focusable` lets Tab reach the button (with the focus
// ring; Space and Return press it); by default it never takes the focus.
T.AbstractButton {
    id: control

    // The shortcut as shown to people, such as "Ctrl+B".
    property string shortcutText
    // Turns the icon, for a chevron that points down once opened.
    property real iconRotation: 0
    // A Material Symbol (Symbols.<Name>) to draw instead of icon.name; the
    // action's symbol when it has one.
    property int symbol: _actionObject && _actionObject.symbol !== undefined ? _actionObject.symbol : 0
    // The action, read duck-typed so a plain Qt Action works too.
    readonly property var _actionObject: control.action
    // True lets Tab reach the button; false (the default) keeps the editor's focus.
    property bool focusable: false

    // The shortcut shown: shortcutText, else the action's.
    readonly property string _effectiveShortcut: {
        if (control.shortcutText.length > 0) {
            return control.shortcutText;
        }
        const seq = _actionObject ? _actionObject.shortcut : undefined;
        return seq !== undefined && seq !== null ? AtlasShortcuts.readable(seq) : "";
    }
    // The tooltip's name: action.toolTip, else action.text, else text, without mnemonics.
    readonly property string _tipName: {
        const a = _actionObject;
        const raw = a && a.toolTip !== undefined && String(a.toolTip).length > 0 ? String(a.toolTip) : a && a.text ? String(a.text) : control.text;
        return raw.replace(/&(.)/g, "$1");
    }
    readonly property color _iconColor: control.checked ? AtlasStyle.accent : Kirigami.Theme.textColor

    implicitWidth: Math.max(implicitHeight, contentItem.implicitWidth + leftPadding + rightPadding)
    implicitHeight: Math.round(Kirigami.Units.gridUnit * 1.7)
    padding: AtlasStyle.spacingSmall + 1
    display: T.AbstractButton.IconOnly
    hoverEnabled: true
    focusPolicy: control.focusable ? Qt.StrongFocus : Qt.NoFocus
    Accessible.name: control._tipName
    Accessible.description: control._effectiveShortcut
    Accessible.checkable: control.checkable
    Accessible.checked: control.checked

    Keys.onReturnPressed: event => {
        if (control.focusable && control.enabled && !event.isAutoRepeat) {
            // The normal trigger path: toggles, fires a bound action, emits clicked().
            control.click();
        } else {
            event.accepted = false;
        }
    }
    Keys.onEnterPressed: event => {
        if (control.focusable && control.enabled && !event.isAutoRepeat) {
            // The normal trigger path: toggles, fires a bound action, emits clicked().
            control.click();
        } else {
            event.accepted = false;
        }
    }

    QQC2.ToolTip.visible: control.hovered && control._tipName.length > 0
    QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
    //: Tooltip: %1 is the action ("Bold"), %2 its keyboard shortcut ("Ctrl+B")
    QQC2.ToolTip.text: control._effectiveShortcut.length > 0 ? qsTr("%1 (%2)").arg(control._tipName).arg(control._effectiveShortcut) : control._tipName

    background: Rectangle {
        radius: AtlasStyle.radiusSmall
        color: control.checked ? Qt.alpha(AtlasStyle.accent, control.down ? 0.28 : 0.18) : Qt.alpha(Kirigami.Theme.textColor, control.down ? 0.12 : control.hovered ? 0.07 : 0)
        Behavior on color {
            ColorAnimation {
                duration: AtlasStyle.durationShort
            }
        }
        AtlasFocusRing {
            radius: parent.radius
            shown: control.visualFocus
        }
    }

    contentItem: Item {
        implicitWidth: row.implicitWidth
        implicitHeight: row.implicitHeight
        Row {
            id: row
            anchors.centerIn: parent
            spacing: AtlasStyle.spacingSmall
            // Made only when used, so buttons without one never load the fonts.
            Loader {
                active: control.symbol !== 0 && control.display !== T.AbstractButton.TextOnly
                visible: active
                anchors.verticalCenter: parent.verticalCenter
                rotation: control.iconRotation
                sourceComponent: Symbol {
                    icon: control.symbol
                    // A symbol fills about 5/6 of its square: a little larger
                    // matches a theme icon of the same slot.
                    size: Math.round(Kirigami.Units.iconSizes.small * 1.2)
                    color: control._iconColor
                    opacity: control.enabled ? 1 : 0.4
                }
            }
            Kirigami.Icon {
                visible: control.symbol === 0 && control.display !== T.AbstractButton.TextOnly && (control.icon.name.length > 0 || control.icon.source.toString().length > 0)
                source: control.icon.name.length > 0 ? control.icon.name : control.icon.source
                isMask: true
                color: control._iconColor
                opacity: control.enabled ? 1 : 0.4
                width: Kirigami.Units.iconSizes.small
                height: width
                rotation: control.iconRotation
                anchors.verticalCenter: parent.verticalCenter
                Behavior on rotation {
                    NumberAnimation {
                        duration: AtlasStyle.durationShort
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
