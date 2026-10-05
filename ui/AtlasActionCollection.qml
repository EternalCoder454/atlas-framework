pragma ComponentBehavior: Bound
import QtQml

// The app's actions, declared once. Put every AtlasAction inside it; hand it
// to AtlasCommandPalette, AtlasShortcutsDialog and AtlasAppMenu as their
// `collection`, and they read the actions from it. The collection registers
// each action with AtlasShortcuts (so a conflict is reported once), and keeps
// the shortcuts the user changed: under the key `shortcuts/<objectName>` of
// `settings`, which is why every action needs an `objectName`. A changed
// shortcut replaces the declared one everywhere: menu text, tooltips, the
// palette and the shortcuts dialog. Declare the actions at creation; the list
// is read once.
//
//   AtlasActionCollection {
//       id: actions
//       settings: AtlasSettings { group: "Shortcuts" }
//       shortcutsEditable: true
//       AtlasAction { objectName: "save"; text: qsTr("&Save"); shortcut: StandardKey.Save }
//       AtlasAction { objectName: "quit"; text: qsTr("&Quit"); shortcut: StandardKey.Quit }
//   }
//   AtlasShortcutsDialog { collection: actions }
QtObject {
    id: root

    // The longest shortcut text read from the settings file or accepted from
    // setShortcut(): a file on disk is not trusted.
    readonly property int _maxLength: 64
    readonly property int _maxChords: 4

    default property list<AtlasAction> actions
    // Where the user's shortcuts are kept. Null: they last until the app quits.
    // Give it a group of its own, set as a literal.
    property AtlasSettings settings: null
    // AtlasShortcutsDialog lets the user change shortcuts.
    property bool shortcutsEditable: false

    // The actions as a plain array, read once on completion.
    property var _all: []
    // objectName -> portable shortcut text, the user's choices in force.
    property var _overrides: ({})
    property bool _ready: false

    // The action whose objectName is `name`; null when there is none.
    function action(name: string): var {
        if (typeof name !== "string" || name.length === 0) {
            return null;
        }
        for (let i = 0; i < root._all.length; ++i) {
            if (root._all[i].objectName === name) {
                return root._all[i];
            }
        }
        return null;
    }
    // True when the user changed the shortcut of the action called `name`.
    function hasCustomShortcut(name: string): bool {
        return Object.prototype.hasOwnProperty.call(root._overrides, name);
    }
    // Makes `sequence` (portable text such as "Ctrl+Shift+K") the shortcut of
    // the action called `name`, and keeps it in `settings`. False, with
    // nothing changed, for an unknown action or text that is no shortcut.
    // It does not check for conflicts: AtlasShortcutsDialog does.
    function setShortcut(name: string, sequence: string): bool {
        const clean = root._clean(sequence);
        if (clean.length === 0 || root.action(name) === null) {
            return false;
        }
        const next = Object.assign({}, root._overrides);
        next[name] = clean;
        root._overrides = next;
        if (root.settings) {
            root.settings.setValue(root._key(name), clean);
        }
        return true;
    }
    // Back to the declared shortcut of one action.
    function resetShortcut(name: string): void {
        if (!root.hasCustomShortcut(name)) {
            return;
        }
        const next = Object.assign({}, root._overrides);
        delete next[name];
        root._overrides = next;
        if (root.settings) {
            root.settings.remove(root._key(name));
        }
    }
    // Back to the declared shortcuts.
    function resetShortcuts(): void {
        for (const name of Object.keys(root._overrides)) {
            if (root.settings) {
                root.settings.remove(root._key(name));
            }
        }
        root._overrides = ({});
    }

    function _key(name: string): string {
        return "shortcuts/" + name;
    }
    // The portable form of `text`; "" when it is not a sequence QKeySequence
    // reads, is longer than _maxLength or has more than _maxChords chords.
    function _clean(text): string {
        if (typeof text !== "string" || text.length === 0 || text.length > root._maxLength) {
            return "";
        }
        const portable = AtlasShortcuts.portable(text);
        const chords = AtlasShortcuts.keys(portable).length;
        return portable.length > 0 && portable.length <= root._maxLength && chords >= 1 && chords <= root._maxChords ? portable : "";
    }
    // Reads the user's shortcuts from the settings; what is not a shortcut is ignored.
    function _load(): void {
        const map = {};
        if (root.settings) {
            for (const a of root._all) {
                const name = a.objectName;
                if (name.length === 0) {
                    continue;
                }
                const clean = root._clean(root.settings.value(root._key(name), ""));
                if (clean.length > 0) {
                    map[name] = clean;
                }
            }
        }
        root._overrides = map;
    }

    // The user's shortcut replaces the declared one while it is set; the
    // declared binding comes back when it is not.
    readonly property Instantiator _holders: Instantiator {
        model: root._all
        delegate: Binding {
            required property var modelData
            target: modelData
            property: "shortcut"
            value: root._overrides[modelData.objectName]
            when: modelData.objectName.length > 0 && Object.prototype.hasOwnProperty.call(root._overrides, modelData.objectName)
            restoreMode: Binding.RestoreBinding
        }
    }
    readonly property Connections _watch: Connections {
        target: root.settings
        function onChanged(key: string): void {
            if (key.startsWith("shortcuts/")) {
                root._load();
            }
        }
    }
    onSettingsChanged: if (_ready) _load()

    Component.onCompleted: {
        const list = [];
        for (let i = 0; i < root.actions.length; ++i) {
            const a = root.actions[i];
            if (!a) {
                continue;
            }
            if (a.objectName.length === 0) {
                console.warn("AtlasActionCollection: the action \"" + AtlasShortcuts.plainText(a.text) + "\" has no objectName, so a shortcut the user changes is not kept");
            }
            AtlasShortcuts.add(a);
            list.push(a);
        }
        root._all = list;
        root._ready = true;
        root._load();
    }
}
