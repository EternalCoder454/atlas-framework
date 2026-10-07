import QtQuick
import Telamon.Ui

// One page of a TelamonPreferencesDialog: Sections of TelamonFormEntry, like any
// TelamonForm. `title` and `symbol` (a Symbols value) name it in the dialog's
// sidebar and in the search results. The dialog's `settings` are used by the
// entries that have a `settingKey`, unless the page has its own.
TelamonForm {
    property string title
    property int symbol: 0
}
