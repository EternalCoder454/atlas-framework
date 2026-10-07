import QtQuick
import QtQuick.Layouts
import Telamon.Ui

// A form: Sections of TelamonFormEntry rows. It knows when every entry is valid,
// shows all their errors at once with `validate()`, and gives the entries the
// TelamonSettings that their `settingKey` saves to. The members and the rules for
// errors: docs/reference/telamon-ui/telamon-form.md.
//
//   TelamonForm {
//       id: form
//       settings: TelamonSettings { group: "Account" }
//       onAccepted: save()
//       Section {
//           title: qsTr("Account")
//           TelamonFormEntry {
//               label: qsTr("Name")
//               required: true
//               settingKey: "Name"
//               TelamonTextField { }
//           }
//       }
//       PrimaryButton { text: qsTr("Save"); enabled: form.valid; onClicked: save() }
//   }
ColumnLayout {
    id: form

    // Where the entries with a `settingKey` save. Null: the nearest
    // TelamonPreferencesDialog's, if the form is a page of one.
    property TelamonSettings settings: null
    // True when every entry that is enabled has no error of any kind.
    readonly property bool valid: form._entries.every(e => e.valid)
    // The entries inside, in reading order (their order in the item tree).
    readonly property var entries: form._entries

    // Return was pressed in a single-line field while the form is valid.
    signal accepted

    readonly property bool _isTelamonForm: true
    property var _entries: []
    // The TelamonPreferencesDialog this page belongs to (set by the dialog).
    property var _owner: null
    readonly property var _settings: form.settings ?? (form._owner ? form._owner.settings : null)

    Layout.fillWidth: true
    spacing: TelamonStyle.spacing

    // Shows every error, moves the focus to the first entry that is invalid
    // (in reading order) and returns `valid`.
    function validate(): bool {
        const list = form._entries.slice();
        for (const e of list) {
            e._reveal();
        }
        const bad = list.filter(e => !e.valid);
        if (bad.length === 0) {
            return true;
        }
        const pos = e => e.mapToItem(form, 0, 0);
        bad.sort((a, b) => {
            const pa = pos(a);
            const pb = pos(b);
            return pa.y !== pb.y ? pa.y - pb.y : pa.x - pb.x;
        });
        bad[0]._focusControl(Qt.ShortcutFocusReason);
        return false;
    }

    // Called by an entry when it is created and when it is destroyed.
    function _register(entry: var): void {
        if (form._entries.indexOf(entry) < 0) {
            // Entries complete in no fixed order, so sort by place in the tree.
            form._entries = form._entries.concat([entry]).sort((a, b) => form._compare(form._path(a), form._path(b)));
        }
    }
    // The child index at each level from the form down to `item`.
    function _path(item: var): var {
        const path = [];
        for (let i = item; i && i !== form; i = i.parent) {
            const kids = i.parent ? i.parent.children : [];
            let at = -1;
            for (let k = 0; k < kids.length; ++k) {
                if (kids[k] === i) {
                    at = k;
                    break;
                }
            }
            path.unshift(at);
        }
        return path;
    }
    function _compare(a: var, b: var): int {
        const n = Math.min(a.length, b.length);
        for (let k = 0; k < n; ++k) {
            if (a[k] !== b[k]) {
                return a[k] - b[k];
            }
        }
        return a.length - b.length;
    }
    function _unregister(entry: var): void {
        form._entries = form._entries.filter(e => e !== entry);
    }
}
