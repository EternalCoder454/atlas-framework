pragma ComponentBehavior: Bound

import QtQuick
import QtQml.Models
import Qt.labs.platform as Platform

// The app's menus, for the header (put it in AtlasHeaderBar.leading). With a
// global menu on the desktop (Plasma's app menu widget; see
// AtlasWindowChrome.globalMenu) the menus are exported through DBusMenu and
// this item shows nothing. Without one, it is a menu button in the header
// that opens the same menus as submenus.
//
// `menus` is a list of groups, each `{title, actions}`; `actions` holds
// AtlasAction or Qt Action items, and `null` for a separator:
//
//   AtlasHeaderBar {
//       leading: AtlasAppMenu {
//           menus: [
//               { title: qsTr("File"), actions: [openAction, null, quitAction] },
//               { title: qsTr("Edit"), actions: [undoAction, redoAction] }
//           ]
//       }
//   }
//
// The native export is made only when a global menu is there, so a desktop
// without one never creates a menu bar of its own. Detection is an
// asynchronous D-Bus check with a timeout: until it answers, the button shows.
Item {
    id: root

    // [{title: string, actions: [Action | null]}]
    property var menus: []
    // The name of the menu button for screen readers and its tooltip.
    property string accessibleName: qsTr("Main menu")

    readonly property bool _native: AtlasWindowChrome.globalMenu
    // Tests: true shows the button whatever the desktop has.
    property bool _forceButton: false
    readonly property bool _showButton: _forceButton || !_native

    // Opens the button's menu (no effect with a global menu).
    function open() {
        if (root._showButton) {
            button.clicked();
        }
    }

    visible: _showButton && menus.length > 0
    implicitWidth: visible ? button.implicitWidth : 0
    implicitHeight: visible ? button.implicitHeight : 0

    ToolbarButton {
        id: button
        anchors.fill: parent
        visible: root.visible
        focusable: true
        symbol: Symbols.Menu
        text: root.accessibleName
        Accessible.role: Accessible.ButtonMenu
        Accessible.name: root.accessibleName
        onClicked: popup.popup(button, 0, button.height)
    }

    ContextMenu {
        id: popup

        Instantiator {
            model: root._showButton ? root.menus : []
            delegate: ContextMenu {
                id: sub

                required property var modelData
                title: modelData.title
                Instantiator {
                    model: sub.modelData.actions
                    delegate: QtObject {
                        id: entry

                        required property var modelData
                        property Item item
                        Component.onCompleted: {
                            item = (entry.modelData ? itemComponent : separatorComponent).createObject(null, entry.modelData ? {
                                action: entry.modelData
                            } : {});
                            sub.addItem(item);
                        }
                        Component.onDestruction: {
                            if (item) {
                                sub.removeItem(item);
                                item.destroy();
                            }
                        }
                    }
                }
            }
            onObjectAdded: (index, object) => popup.insertMenu(index, object)
            onObjectRemoved: (index, object) => popup.removeMenu(object)
        }
    }
    Component {
        id: itemComponent
        ContextMenuItem {}
    }
    Component {
        id: separatorComponent
        ContextMenuSeparator {}
    }

    // The native export, only when the desktop has a global menu.
    Loader {
        active: root._native && root.menus.length > 0
        sourceComponent: Platform.MenuBar {
            id: menuBar
            window: root.Window.window
            Instantiator {
                model: root.menus
                delegate: Platform.Menu {
                    id: nativeMenu

                    required property var modelData
                    title: modelData.title
                    Instantiator {
                        model: nativeMenu.modelData.actions
                        delegate: Platform.MenuItem {
                            required property var modelData
                            separator: !modelData
                            text: modelData ? modelData.text : ""
                            enabled: modelData ? modelData.enabled : true
                            checkable: modelData ? modelData.checkable === true : false
                            checked: modelData ? modelData.checked === true : false
                            onTriggered: if (modelData) {
                                modelData.trigger()
                            }
                        }
                        onObjectAdded: (index, object) => nativeMenu.insertItem(index, object)
                        onObjectRemoved: (index, object) => nativeMenu.removeItem(object)
                    }
                }
                onObjectAdded: (index, object) => menuBar.insertMenu(index, object)
                onObjectRemoved: (index, object) => menuBar.removeMenu(object)
            }
        }
    }
}
