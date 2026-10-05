pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Templates as T
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

// A small icon button for formatting toolbars (Bold, Italic, ...). It never
// takes the keyboard focus from the editor. `checkable` makes it a toggle,
// drawn with the selection fill, an accent border and an accent icon while
// checked. The tooltip is the text plus the optional `shortcutText`: "Bold (Ctrl+B)".
// The tooltip hides while the button is pressed and after it was used (a menu
// it opened must not sit under it); it returns once the pointer has left.
//
// With an `action` (an AtlasAction or a plain Qt Action) the button follows
// it: the tooltip is `action.toolTip`, else `action.text`, else `text`; the
// `action.symbol` is the symbol when it has one; and the action's shortcut is
// shown when `shortcutText` is empty. `symbol` (a Material Symbol) is drawn
// instead of the icon. `focusable` lets Tab reach the button (with the focus
// ring; Space and Return press it); by default it never takes the focus.
// `focusOnClick: false` keeps Tab but a click does not take the focus.
//
// `round` draws a circle, `tipSide` puts the tooltip beside the button, and
// `toolTipText` sets the tooltip's name without changing the spoken name. An
// action with a `menu` or a `popover` (AtlasAction) makes a button that opens
// it instead of triggering: it is a ButtonMenu for screen readers and looks
// checked while the menu or popover is open.
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
    readonly property var _actionObject: control.action ? control.action : control._source
    readonly property var _menu: _actionObject && _actionObject.menu ? _actionObject.menu : null
    readonly property var _popover: _actionObject && _actionObject.popover ? _actionObject.popover : null
    // What a click opens; the menu wins.
    readonly property var _opener: control._menu ? control._menu : control._popover
    readonly property bool _opened: control._opener ? control._opener.visible : false
    onActionChanged: {
        const a = control._actionObject;
        if (control.action && a && (a.menu || a.popover)) {
            // Opening is not triggering: keep the action out of the click.
            control._source = a;
            control.action = null;
        } else if (control.action) {
            control._source = null;
        }
    }
    // True lets Tab reach the button; false (the default) keeps the editor's focus.
    property bool focusable: false
    // False with `focusable` keeps Tab but a click does not take the focus.
    property bool focusOnClick: true
    // A circle: width equals height and the corners are half of it.
    property bool round: false
    // Where the tooltip opens: below the button, or beside it (Start and End
    // flip when there is no room, and swap under a right-to-left layout).
    enum TipSide {
        Below = 0,
        Start = 1,
        End = 2
    }
    property int tipSide: ToolbarButton.Below
    // The tooltip's name part, in place of the action's or the button's text.
    property string toolTipText
    // An action with a menu or popover, which has no `action` of its own (a
    // click must not trigger it).
    property var _source: null

    // The shortcut shown: shortcutText, else the action's.
    readonly property string _effectiveShortcut: {
        if (control.shortcutText.length > 0) {
            return control.shortcutText;
        }
        const seq = _actionObject ? _actionObject.shortcut : undefined;
        return seq !== undefined && seq !== null ? AtlasShortcuts.readable(seq) : "";
    }
    // The tooltip's name: action.toolTip, else action.text, else text, without mnemonics.
    readonly property string _spokenName: {
        const a = _actionObject;
        const raw = a && a.toolTip !== undefined && String(a.toolTip).length > 0 ? String(a.toolTip) : a && a.text ? String(a.text) : control.text;
        return raw.replace(/&(.)/g, "$1");
    }
    // The tooltip's name: toolTipText when set, else the spoken name.
    readonly property string _tipName: control.toolTipText.length > 0 ? control.toolTipText.replace(/&(.)/g, "$1") : control._spokenName
    readonly property color _iconColor: !control.enabled ? AtlasStyle.textDisabled : control.checked ? AtlasStyle.accent : Kirigami.Theme.textColor

    implicitWidth: control.round ? control.height : Math.max(implicitHeight, contentItem.implicitWidth + leftPadding + rightPadding)
    implicitHeight: AtlasStyle.controlHeight
    padding: AtlasStyle.spacingSmall + 1
    display: T.AbstractButton.IconOnly
    hoverEnabled: true
    focusPolicy: control.focusable ? (control.focusOnClick ? Qt.StrongFocus : Qt.TabFocus) : Qt.NoFocus
    // Not the tooltip's text: a long tip must not become the spoken name.
    Accessible.name: control._spokenName
    Accessible.role: control._opener ? Accessible.ButtonMenu : Accessible.Button
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

    // Set by a press or a click, cleared when the pointer leaves: the button
    // may have opened a menu or popup (the app calls popup() in onClicked),
    // and the tooltip must not sit on top of it.
    property bool _used: false
    // The tooltip shows while hovered, but not while pressed or after use.
    readonly property bool _tipShown: control.hovered && !control.down && !control._used && control._tipName.length > 0
    onPressed: {
        control._used = true;
        control._pressedAt = Date.now();
    }
    onClicked: {
        control._used = true;
        control._open();
    }

    // A click that only closed the menu (a press outside closes it first) must not reopen it.
    property double _closedAt: 0
    property double _pressedAt: 0
    property bool _hadFocus: false
    Connections {
        target: control._opener
        ignoreUnknownSignals: true
        function onClosed() {
            control._closedAt = Date.now();
            // The keyboard user gets the focus back, unless a click went elsewhere.
            const o = control._opener;
            const focused = control.Window.window?.activeFocusItem;
            let free = !focused || focused === control.Window.window.contentItem;
            for (let i = focused; i && !free; i = i.parent) {
                free = i === o.contentItem || i === o.background;
            }
            if (control._hadFocus && control.visible && control.enabled && free) {
                control.forceActiveFocus(Qt.PopupFocusReason);
            }
        }
    }
    Binding on checked {
        when: control._opener !== null
        value: control._opened
    }
    function _open(): void {
        const o = control._opener;
        if (!o || control._pressedAt - control._closedAt < 150 && control._closedAt > 0 && control._pressedAt >= control._closedAt) {
            return;
        }
        control._hadFocus = control.activeFocus;
        if (control._menu) {
            control._menu.popup(control, 0, control.height + AtlasStyle.spacingSmall);
        } else {
            if (o.target !== undefined) {
                o.target = control;
            }
            o.open();
        }
    }

    // A tooltip beside the button, for Start and End.
    property var _tip: null
    // True when the tip is at the physical right of the button.
    property bool _tipRight: false
    readonly property bool _tipBeside: control.tipSide !== ToolbarButton.Below
    on_TipBesideChanged: control._syncTip()
    Component.onCompleted: control._syncTip()
    function _syncTip(): void {
        if (control._tipBeside && !control._tip) {
            control._tip = tipComponent.createObject(control);
        } else if (!control._tipBeside && control._tip) {
            control._tip.destroy();
            control._tip = null;
        }
    }
    Component {
        id: tipComponent
        AtlasToolTip {
            text: control._tipText
            shown: (control.hovered && !control.down && !control._used || control.visualFocus) && control._tipName.length > 0
            x: control._tipRight ? control.width + AtlasStyle.spacingSmall : -implicitWidth - AtlasStyle.spacingSmall
            y: Math.round((control.height - implicitHeight) / 2)
            onAboutToShow: {
                const w = control.Window.window ? control.Window.window.width : 0;
                const sx = control.mapToItem(null, 0, 0).x;
                const gap = AtlasStyle.spacingSmall;
                const wantRight = (control.tipSide === ToolbarButton.End) !== control.mirrored;
                const fitsRight = sx + control.width + gap + implicitWidth <= w;
                const fitsLeft = sx - gap - implicitWidth >= 0;
                control._tipRight = wantRight ? (fitsRight || !fitsLeft) : (!fitsLeft && fitsRight);
            }
        }
    }
    onHoveredChanged: if (!control.hovered) control._used = false

    QQC2.ToolTip.visible: control._tipShown && !control._tipBeside
    QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
    //: Tooltip: %1 is the action ("Bold"), %2 its keyboard shortcut ("Ctrl+B")
    readonly property string _tipText: control._effectiveShortcut.length > 0 ? qsTr("%1 (%2)").arg(control._tipName).arg(control._effectiveShortcut) : control._tipName
    QQC2.ToolTip.text: control._tipText

    background: Rectangle {
        radius: control.round ? Math.min(width, height) / 2 : AtlasStyle.radiusSmall
        // On: the selection fill with an accent border and icon; hover and
        // press are the grey overlay.
        color: control.checked ? AtlasStyle.selection : "transparent"
        border.width: control.checked ? 1 : 0
        border.color: control.enabled ? AtlasStyle.accent : AtlasStyle.controlBorder
        Behavior on color {
            ColorAnimation {
                duration: AtlasStyle.durationShort
            }
        }
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: !control.enabled ? "transparent" : control.down ? AtlasStyle.pressed : control.hovered ? AtlasStyle.hover : "transparent"
            Behavior on color {
                ColorAnimation {
                    duration: AtlasStyle.durationShort
                }
            }
        }
        AtlasFocusRing {
            radius: parent.radius + gap
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
                }
            }
            Kirigami.Icon {
                visible: control.symbol === 0 && control.display !== T.AbstractButton.TextOnly && (control.icon.name.length > 0 || control.icon.source.toString().length > 0)
                source: control.icon.name.length > 0 ? control.icon.name : control.icon.source
                isMask: true
                color: control._iconColor
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
                font.family: AtlasStyle.fontFamily
                font.pointSize: AtlasStyle.fontSizeBody
                color: Kirigami.Theme.textColor
                textFormat: Text.PlainText
            }
        }
    }
}
