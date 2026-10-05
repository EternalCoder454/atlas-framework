pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import Atlas.Ui

// A preferences dialog: AtlasPreferencesPage children, each a page of
// AtlasFormEntry rows. One page shows alone; two or more get a sidebar of the
// page titles. A search field over every entry's `label` and `help` lists the
// matches as "label, page title"; choosing one shows its page, focuses its
// control and flashes the row. Escape clears the search first, then closes.
// Entries with a `settingKey` save to `settings`. The members and the rules:
// docs/reference/atlas-ui/atlas-preferences-dialog.md.
//
//   AtlasPreferencesDialog {
//       title: qsTr("Preferences")
//       settings: AtlasSettings { group: "General" }
//       AtlasPreferencesPage {
//           title: qsTr("General"); symbol: Symbols.Settings
//           Section {
//               AtlasFormEntry {
//                   label: qsTr("Show hidden files"); settingKey: "ShowHidden"
//                   AtlasSwitch { }
//               }
//           }
//       }
//   }
AtlasDialog {
    id: control

    // The pages. They are made once, when the dialog is created.
    default property list<AtlasPreferencesPage> pages
    // Where the entries with a `settingKey` save.
    property AtlasSettings settings: null
    // Show the search field.
    property bool searchable: true
    // The page shown.
    property int currentIndex: 0
    // Names what the dialog remembers between runs (the page shown); empty:
    // nothing is saved.
    property string stateKey

    // A page chosen by the user is held on currentIndex for one turn of the
    // event loop, so an app binding to it stays bound (Part 1 of
    // docs/api-1.5.0.md).
    property int _edit: 0
    property bool _editing: false
    readonly property Binding _hold: Binding {
        target: control
        property: "currentIndex"
        value: control._edit
        when: control._editing
        restoreMode: Binding.RestoreBinding
    }
    function _release(): void {
        control._editing = false;
    }
    function _choose(i: int): void {
        if (i < 0 || i >= control.pages.length || i === control.currentIndex) {
            return;
        }
        control._edit = i;
        control._editing = true;
        Qt.callLater(control._release);
    }

    property bool _ready: false
    property var _pending: null
    readonly property bool _narrow: control.width < Kirigami.Units.gridUnit * 36
    readonly property string _query: search.query.trim().toLowerCase()
    readonly property bool _searching: control._query.length > 0
    // Entries whose label or help contains the query: {entry, page, text, pageTitle}.
    readonly property var _results: {
        const out = [];
        const q = control._query;
        if (q.length === 0) {
            return out;
        }
        for (let i = 0; i < control.pages.length; ++i) {
            const page = control.pages[i];
            for (const e of page.entries) {
                if (e.label.toLowerCase().includes(q) || e.help.toLowerCase().includes(q)) {
                    out.push({
                        entry: e,
                        page: i,
                        text: e.label,
                        pageTitle: page.title
                    });
                }
            }
        }
        return out;
    }

    // Leaves the search and shows the entry of a result.
    function _goto(result: var): void {
        search.clear();
        control._choose(result.page);
        control._pending = result.entry;
        settle.restart();
    }

    //: Title of the preferences dialog
    title: qsTr("Preferences")
    preferredWidth: Kirigami.Units.gridUnit * 50

    Component.onCompleted: {
        for (let i = 0; i < control.pages.length; ++i) {
            const page = control.pages[i];
            const index = i;
            page._owner = control;
            page.parent = stack;
            page.visible = Qt.binding(() => control.currentIndex === index);
        }
        if (control.stateKey.length > 0) {
            const saved = control._store.value("Page", 0);
            if (typeof saved === "number") {
                control._choose(saved);
            }
        }
        control._ready = true;
    }
    onCurrentIndexChanged: {
        if (control._ready && control.stateKey.length > 0) {
            control._store.setValue("Page", control.currentIndex);
        }
    }

    // Only read and written when stateKey is set.
    readonly property AtlasSettings _store: AtlasSettings {
        group: control.stateKey.length > 0 ? "AtlasPreferencesDialog-" + control.stateKey : ""
    }

    // The page has to be laid out before the entry can be scrolled to.
    Timer {
        id: settle
        interval: 50
        onTriggered: {
            if (control._pending) {
                control._pending._show();
                control._pending = null;
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: AtlasStyle.spacingLarge
        // Escape from anywhere in the dialog but the search field itself.
        Keys.onEscapePressed: event => {
            if (search.text.length > 0) {
                search.clear();
                search.forceActiveFocus();
                event.accepted = true;
            } else {
                event.accepted = false;
            }
        }

        AtlasSidebar {
            id: nav
            objectName: "atlasPreferencesSidebar"
            visible: control.pages.length > 1
            compact: control._narrow
            Layout.preferredWidth: compact ? Kirigami.Units.gridUnit * 4 : Kirigami.Units.gridUnit * 11
            Layout.fillHeight: true
            Layout.alignment: Qt.AlignTop
            Accessible.name: qsTr("Pages")
            model: control.pages.length
            delegate: SidebarItem {
                required property int index
                Layout.fillWidth: true
                text: control.pages[index].title
                symbol: control.pages[index].symbol
                selected: index === control.currentIndex
                onClicked: control._choose(index)
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignTop
            spacing: AtlasStyle.spacing

            SearchField {
                id: search
                objectName: "atlasPreferencesSearch"
                visible: control.searchable
                Layout.fillWidth: true
                placeholderText: qsTr("Search settings")
            }

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: Kirigami.Units.gridUnit * 24

                Flickable {
                    anchors.fill: parent
                    visible: !control._searching
                    clip: true
                    contentWidth: width
                    contentHeight: stack.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds
                    QQC2.ScrollBar.vertical: AtlasScrollBar {}
                    ColumnLayout {
                        id: stack
                        width: parent.width
                        spacing: AtlasStyle.spacing
                    }
                }

                Flickable {
                    anchors.fill: parent
                    visible: control._searching && control._results.length > 0
                    clip: true
                    contentWidth: width
                    contentHeight: found.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds
                    QQC2.ScrollBar.vertical: AtlasScrollBar {}
                    Section {
                        id: found
                        width: parent.width
                        Repeater {
                            model: control._results
                            SectionRow {
                                id: hit
                                required property var modelData
                                title: hit.modelData.text
                                subtitle: hit.modelData.pageTitle
                                clickable: true
                                chevron: true
                                onClicked: control._goto(hit.modelData)
                            }
                        }
                    }
                }

                AtlasEmptyState {
                    anchors.fill: parent
                    visible: control._searching && control._results.length === 0
                    symbol: Symbols.SearchOff
                    title: qsTr("No settings found")
                    text: qsTr("Try another word.")
                }
            }
        }
    }
}
