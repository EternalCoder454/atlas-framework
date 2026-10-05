import QtQuick
import Atlas.Ui

// One page of an AtlasPreferencesDialog: Sections of AtlasFormEntry, like any
// AtlasForm. `title` and `symbol` (a Symbols value) name it in the dialog's
// sidebar and in the search results. The dialog's `settings` are used by the
// entries that have a `settingKey`, unless the page has its own.
AtlasForm {
    property string title
    property int symbol: 0
}
