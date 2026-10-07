pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import Telamon.Ui

// A preferences dialog: TelamonPreferencesPage children, each a page of
// TelamonFormEntry rows. One page shows alone; two or more get a sidebar of the
// page titles. A search field over every entry's `label` and `help` lists the
// matches as "label, page title"; choosing one shows its page, focuses its
// control and flashes the row. Escape clears the search first, then closes.
// Entries with a `settingKey` save to `settings`. The members and the rules:
// docs/reference/telamon-ui/telamon-preferences-dialog.md.
//
//   TelamonPreferencesDialog {
//       title: qsTr("Preferences")
//       settings: TelamonSettings { group: "General" }
//       TelamonPreferencesPage {
//           title: qsTr("General"); symbol: Symbols.Settings
//           Section {
//               TelamonFormEntry {
//                   label: qsTr("Show hidden files"); settingKey: "ShowHidden"
//                   TelamonSwitch { }
//               }
//           }
//       }
//   }
TelamonDialog {
    id: control

    // The pages. They are made once, when the dialog is created.
    default property list<TelamonPreferencesPage> pages
    // Where the entries with a `settingKey` save.
    property TelamonSettings settings: null
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
    property int _tries: 0
    // Only made when stateKey is set.
    property var _store: null
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
                // Not an entry that is disabled or that the app hid.
                if (!e.enabled || e._selfHidden) {
                    continue;
                }
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
        control._tries = 0;
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
            control._store = storeComp.createObject(control, {
                "group": "TelamonPreferencesDialog-" + control.stateKey
            });
            const saved = control._store ? control._store.value("Page", 0) : 0;
            if (typeof saved === "number") {
                control._choose(saved);
            }
        }
        control._ready = true;
    }
    onCurrentIndexChanged: {
        if (control._ready && control._store) {
            control._store.setValue("Page", control.currentIndex);
        }
    }

    Component {
        id: storeComp
        TelamonSettings {
        }
    }

    // The page has to be laid out before the entry can be scrolled to: look
    // every 30 ms (at most 10 times) until the entry is on screen.
    Timer {
        id: settle
        interval: 30
        repeat: true
        onTriggered: {
            const e = control._pending;
            control._tries += 1;
            if (!e) {
                settle.stop();
            } else if ((e.visible && e.width > 0 && e.height > 0) || control._tries >= 10) {
                settle.stop();
                control._pending = null;
                e._show();
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: TelamonStyle.spacingLarge
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

        TelamonSidebar {
            id: nav
            objectName: "telamonPreferencesSidebar"
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
            spacing: TelamonStyle.spacing

            SearchField {
                id: search
                objectName: "telamonPreferencesSearch"
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
                    QQC2.ScrollBar.vertical: TelamonScrollBar {}
                    ColumnLayout {
                        id: stack
                        width: parent.width
                        spacing: TelamonStyle.spacing
                    }
                }

                Flickable {
                    anchors.fill: parent
                    visible: control._searching && control._results.length > 0
                    clip: true
                    contentWidth: width
                    contentHeight: found.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds
                    QQC2.ScrollBar.vertical: TelamonScrollBar {}
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

                TelamonEmptyState {
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
