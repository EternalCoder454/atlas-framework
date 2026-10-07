pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

// SecondaryButton with a chevron that opens a menu. Put QQC2.MenuItem children inside.
// With an `action` it shows the action's text and, when it has one, its symbol.
SecondaryButton {
    id: control

    // Read duck-typed, so a plain Qt Action works too.
    readonly property var _actionObject: control.action
    symbol: _actionObject && _actionObject.symbol !== undefined ? _actionObject.symbol : 0

    // The menu's items. The menu itself is made on the first open (most
    // menus are never opened, and a menu costs a popup, a list and their
    // theme objects); it takes these as its content then.
    default property list<QtObject> items
    property QQC2.Menu _menu: null
    function _ensureMenu(): QQC2.Menu {
        if (!_menu) {
            _menu = menuComponent.createObject(control) as QQC2.Menu;
        }
        return _menu;
    }

    rightPadding: control.mirrored ? leftPadding : leftPadding + Kirigami.Units.iconSizes.small
    leftPadding: control.mirrored ? TelamonStyle.spacingLarge + TelamonStyle.spacingSmall + Kirigami.Units.iconSizes.small : TelamonStyle.spacingLarge + TelamonStyle.spacingSmall
    Accessible.role: Accessible.ButtonMenu
    // Qt has no Accessible.expanded for QML: the state is the description,
    // and a change of it is announced (see the menu below).
    Accessible.description: control._menu && control._menu.visible ? qsTr("Expanded") : qsTr("Collapsed")
    QtObject {
        id: priv
        // When the menu last began to close, and whether it was open when the
        // current press began.
        property real hiddenAt: 0
        property bool openAtPress: false
        function announceState() {
            control.Accessible.announce(control._menu && control._menu.visible ? qsTr("Expanded") : qsTr("Collapsed"));
        }
    }
    // A second click on the button closes the menu. Before, the press closed
    // it (CloseOnPressOutside) and the click that followed opened it again,
    // so the menu could only be closed from somewhere else. The press that
    // closes the menu runs just before the button sees it, hence the short
    // window on hiddenAt.
    onPressed: priv.openAtPress = (control._menu !== null && control._menu.opened) || Date.now() - priv.hiddenAt < 150
    onClicked: {
        if (priv.openAtPress) {
            priv.openAtPress = false;
            control._menu?.close();
            return;
        }
        const menu = control._ensureMenu();
        // The menu opens under the end the label starts from: mirrored, flush right.
        menu.popup(control, control.mirrored ? control.width - menu.implicitWidth : 0, control.height + 4);
    }

    Kirigami.Icon {
        x: control.mirrored ? TelamonStyle.spacingSmall + 2 : parent.width - width - TelamonStyle.spacingSmall - 2
        anchors.verticalCenter: parent.verticalCenter
        source: "arrow-down"
        isMask: true
        color: control.textTint
        width: Kirigami.Units.iconSizes.small
        height: width
        opacity: control.enabled ? 0.8 : 0.4
        Accessible.ignored: true
    }

    Component {
        id: menuComponent
        QQC2.Menu {
            contentData: control.items
            onVisibleChanged: priv.announceState()
            onAboutToHide: priv.hiddenAt = Date.now()
            delegate: QQC2.MenuItem {
                Kirigami.MnemonicData.enabled: false
            }
        }
    }
}
