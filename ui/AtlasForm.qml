import QtQuick
import QtQuick.Layouts
import Atlas.Ui

// A form: Sections of AtlasFormEntry rows. It knows when every entry is valid,
// shows all their errors at once with `validate()`, and gives the entries the
// AtlasSettings that their `settingKey` saves to. The members and the rules for
// errors: docs/reference/atlas-ui/atlas-form.md.
//
//   AtlasForm {
//       id: form
//       settings: AtlasSettings { group: "Account" }
//       onAccepted: save()
//       Section {
//           title: qsTr("Account")
//           AtlasFormEntry {
//               label: qsTr("Name")
//               required: true
//               settingKey: "Name"
//               AtlasTextField { }
//           }
//       }
//       PrimaryButton { text: qsTr("Save"); enabled: form.valid; onClicked: save() }
//   }
ColumnLayout {
    id: form

    // Where the entries with a `settingKey` save. Null: the nearest
    // AtlasPreferencesDialog's, if the form is a page of one.
    property AtlasSettings settings: null
    // True when every entry that is enabled has no error of any kind.
    readonly property bool valid: form._entries.every(e => e.valid)
    // The entries inside, in the order they were created.
    readonly property var entries: form._entries

    // Return was pressed in a single-line field while the form is valid.
    signal accepted

    readonly property bool _isAtlasForm: true
    property var _entries: []
    // The AtlasPreferencesDialog this page belongs to (set by the dialog).
    property var _owner: null
    readonly property var _settings: form.settings ?? (form._owner ? form._owner.settings : null)

    Layout.fillWidth: true
    spacing: AtlasStyle.spacing

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
            form._entries = form._entries.concat([entry]);
        }
    }
    function _unregister(entry: var): void {
        form._entries = form._entries.filter(e => e !== entry);
    }
}
