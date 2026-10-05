import QtQuick
import QtQuick.Templates as T

// An action: one thing the user can do, with its text, icon, shortcut and
// tooltip in one place, so a toolbar button, a menu item and the keyboard all
// run the same code and stay in step. It is Qt Quick Controls' Action (`text`,
// `shortcut`, `enabled`, `checkable`, `checked`, `triggered()`) plus a symbol,
// a tooltip and a section. Every action registers with AtlasShortcuts, which
// warns when two enabled actions share a shortcut and feeds
// AtlasShortcutsDialog. Declare it inside an Item (the window it works in is
// then known): shortcuts in the same window conflict, others do not.
//
//   AtlasAction {
//       id: saveAction
//       text: qsTr("&Save")
//       symbol: Symbols.Save
//       shortcut: StandardKey.Save
//       section: qsTr("File")
//       onTriggered: document.save()
//   }
T.Action {
    id: action

    // Symbols.<Name>; 0 for none. ToolbarButton, ContextMenuItem and
    // MenuButton show it when given this action.
    property int symbol: 0
    // The tooltip of a button that shows this action; the text without its
    // "&" mnemonic marker unless set.
    property string toolTip: text.replace(/&(&|.)/g, "$1")
    // The group the action shows under in AtlasShortcutsDialog; empty for the
    // general group.
    property string section
    // A ContextMenu that the action's toolbar button opens instead of
    // triggering; in an AtlasAppMenu it shows as a submenu. If both this and
    // `popover` are set, `menu` wins.
    property T.Menu menu: null
    // An AtlasPopover that the action's toolbar button opens instead of
    // triggering. Its `target` is set to the button.
    property T.Popup popover: null

    Component.onCompleted: AtlasShortcuts.add(action)
    Component.onDestruction: AtlasShortcuts.remove(action)
}
