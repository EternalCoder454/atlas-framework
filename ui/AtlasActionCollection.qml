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
// is read once, and so is each action's declared shortcut (what Reset goes back to).
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
    // A user shortcut is one chord.
    readonly property int _maxChords: 1

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
    // objectName -> portable declared shortcut, read before any override applies.
    property var _declared: ({})
    // Conflicts already warned about, so each is logged once.
    property var _warned: ({})
    property bool _ready: false

    // The action whose objectName is `name`; null when there is none.
    function action(name: string): var {
        if (typeof name !== "string" || name.length === 0) {
            return null;
        }
        for (let i = 0; i < root._all.length; ++i) {
            const a = root._all[i];
            if (a && a.objectName === name) {
                return a;
            }
        }
        return null;
    }
    // The text of another enabled action (of the app, not only this
    // collection) that has the shortcut `name` goes back to on reset; "" when
    // none does, so a reset is safe.
    function declaredConflict(name: string): string {
        const declared = root._declared[name];
        const self = root.action(name);
        if (declared === undefined || declared.length === 0 || self === null) {
            return "";
        }
        const all = AtlasShortcuts.actions;
        for (let i = 0; i < all.length; ++i) {
            const b = all[i];
            if (b && b !== self && b.enabled !== false && AtlasShortcuts.portable(b.shortcut) === declared) {
                return AtlasShortcuts.plainText(String(b.text ?? ""));
            }
        }
        return "";
    }
    // True when the user changed the shortcut of the action called `name`.
    function hasCustomShortcut(name: string): bool {
        return Object.prototype.hasOwnProperty.call(root._overrides, name);
    }
    // Makes `sequence` (portable text such as "Ctrl+Shift+K": one chord with
    // Ctrl, Alt or Meta, or an F key) the shortcut of the action called
    // `name`, and keeps it in `settings`. The declared shortcut as `sequence`
    // removes the change. False, with nothing changed, for an unknown action,
    // text that is no such shortcut, or a settings file that refuses the
    // value. It does not check for conflicts: AtlasShortcutsDialog does.
    function setShortcut(name: string, sequence: string): bool {
        const clean = root._clean(sequence);
        if (clean.length === 0 || root.action(name) === null) {
            return false;
        }
        if (clean === root._declared[name]) {
            return root.hasCustomShortcut(name) ? root._drop(name) : true;
        }
        // Kept first: when it cannot be saved, nothing changed.
        if (root.settings && !root.settings.setValue(root._key(name), clean)) {
            console.warn("AtlasActionCollection: the shortcut of \"" + root._safe(name) + "\" could not be saved");
            return false;
        }
        const next = Object.assign({}, root._overrides);
        next[name] = clean;
        root._overrides = next;
        return true;
    }
    // Back to the declared shortcut of one action. False, with nothing
    // changed, when another action has that shortcut now (declaredConflict())
    // or the settings file refuses the change.
    function resetShortcut(name: string): bool {
        if (!root.hasCustomShortcut(name)) {
            return true;
        }
        if (root.declaredConflict(name).length > 0) {
            return false;
        }
        return root._drop(name);
    }
    // Back to the declared shortcuts. False when a change could not be saved;
    // that one stays.
    function resetShortcuts(): bool {
        let ok = true;
        for (const name of Object.keys(root._overrides)) {
            ok = root._drop(name) && ok;
        }
        return ok;
    }

    function _drop(name: string): bool {
        if (root.settings && !root.settings.remove(root._key(name))) {
            console.warn("AtlasActionCollection: the shortcut of \"" + root._safe(name) + "\" could not be reset in the settings");
            return false;
        }
        const next = Object.assign({}, root._overrides);
        delete next[name];
        root._overrides = next;
        return true;
    }
    // Text from outside, safe for a log line.
    function _safe(text): string {
        return String(text).slice(0, 80).replace(/[^\x20-\x7e]/g, "?");
    }
    // Whether one portable chord is allowed as a user shortcut: with Ctrl, Alt
    // or Meta, or an F key alone; never only modifiers or Shift and a key.
    function _chordOk(chord: string): bool {
        let rest = chord;
        let held = false;
        for (;;) {
            const m = /^(Ctrl|Alt|Shift|Meta)\+(.+)$/.exec(rest);
            if (!m) {
                break;
            }
            held = held || m[1] !== "Shift";
            rest = m[2];
        }
        if (rest.length === 0 || /^(Ctrl|Alt|Shift|Meta)$/.test(rest)) {
            return false;
        }
        return held || /^F([1-9]|[12][0-9]|3[0-5])$/.test(rest);
    }

    function _key(name: string): string {
        return "shortcuts/" + name;
    }
    // The portable form of `text`; "" when it is not one chord QKeySequence
    // reads, is longer than _maxLength, has a control, bidi or other format
    // character, or is not allowed by _chordOk().
    function _clean(text): string {
        const bad = /[\u0000-\u001f\u007f-\u009f\u00ad\u061c\u180e\u200b-\u200f\u2028-\u202e\u2060-\u206f\ufeff\ufff9-\ufffb]/;
        if (typeof text !== "string" || text.length === 0 || text.length > root._maxLength || bad.test(text)) {
            return "";
        }
        const portable = AtlasShortcuts.portable(text);
        const chords = AtlasShortcuts.keys(portable).length;
        if (portable.length === 0 || portable.length > root._maxLength || bad.test(portable) || chords < 1 || chords > root._maxChords) {
            return "";
        }
        return root._chordOk(portable) ? portable : "";
    }
    // What `b` has now: the user's shortcut, or the declared one.
    function _effective(b, map): string {
        const name = b.objectName ?? "";
        if (name.length > 0 && Object.prototype.hasOwnProperty.call(map, name)) {
            return map[name];
        }
        if (name.length > 0 && root._declared[name] !== undefined) {
            return root._declared[name];
        }
        return AtlasShortcuts.portable(b.shortcut);
    }
    // Reads the user's shortcuts from the settings. What is not a usable
    // shortcut, or is one that another enabled action of the collection has,
    // is ignored (a conflict is warned about once).
    function _load(): void {
        const map = {};
        if (root.settings) {
            for (const a of root._all) {
                const name = a ? (a.objectName ?? "") : "";
                if (name.length === 0) {
                    continue;
                }
                const clean = root._clean(root.settings.value(root._key(name), ""));
                if (clean.length === 0 || clean === root._declared[name]) {
                    continue;
                }
                let holder = null;
                for (const b of root._all) {
                    if (b && b !== a && b.enabled !== false && root._effective(b, map) === clean) {
                        holder = b;
                        break;
                    }
                }
                if (holder) {
                    const id = name + "\n" + clean;
                    if (!root._warned[id]) {
                        root._warned[id] = true;
                        console.warn("AtlasActionCollection: the saved shortcut " + clean + " of \"" + root._safe(name) + "\" is used by \"" + root._safe(AtlasShortcuts.plainText(String(holder.text ?? ""))) + "\" and is ignored");
                    }
                    continue;
                }
                map[name] = clean;
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
            value: root._overrides[modelData?.objectName ?? ""]
            when: modelData !== null && modelData !== undefined && (modelData.objectName ?? "").length > 0 && Object.prototype.hasOwnProperty.call(root._overrides, modelData.objectName)
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
                console.warn("AtlasActionCollection: the action \"" + root._safe(AtlasShortcuts.plainText(a.text)) + "\" has no objectName, so a shortcut the user changes is not kept");
            } else {
                root._declared[a.objectName] = AtlasShortcuts.portable(a.shortcut);
            }
            AtlasShortcuts.add(a);
            list.push(a);
        }
        root._all = list;
        root._ready = true;
        root._load();
    }
}
