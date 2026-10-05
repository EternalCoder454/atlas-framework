pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

// A modal list of the app's keyboard shortcuts: every AtlasAction that has
// one (AtlasShortcuts.actions), grouped by the action's `section`, each with
// its text and an AtlasShortcutLabel. The search field filters by action text
// or shortcut; the list scrolls when it is long. Escape clears the search,
// then closes; so does the Close button. Open it from a menu or a shortcut of
// its own.
//
//   AtlasShortcutsDialog { id: shortcutsDialog }
//   AtlasAction {
//       text: qsTr("Keyboard Shortcuts")
//       shortcut: StandardKey.HelpContents
//       onTriggered: shortcutsDialog.open()
//   }
QQC2.Popup {
    id: dialog

    property string title: qsTr("Keyboard Shortcuts")

    QtObject {
        id: priv
        // [{ section, text, sequence, readable }] for what the dialog shows now.
        readonly property var entries: dialog.visible ? priv.build(AtlasShortcuts.actions, search.query) : []

        function build(actions: var, query: string): var {
            const q = query.trim().toLowerCase();
            const general = qsTr("General");
            const groups = [];
            const index = {};
            for (let i = 0; i < actions.length; ++i) {
                const a = actions[i];
                if (!a) {
                    continue;
                }
                const readable = AtlasShortcuts.readable(a.shortcut);
                if (readable.length === 0) {
                    continue;
                }
                const text = AtlasShortcuts.plainText(a.text);
                if (q.length > 0 && text.toLowerCase().indexOf(q) < 0 && readable.toLowerCase().indexOf(q) < 0) {
                    continue;
                }
                const section = a.section && a.section.length > 0 ? a.section : general;
                if (!(section in index)) {
                    index[section] = groups.length;
                    groups.push([]);
                }
                groups[index[section]].push({
                    "section": section,
                    "text": text,
                    "sequence": a.shortcut,
                    "readable": readable
                });
            }
            // Sections by name with the general one first, rows by text: the
            // order the actions registered in follows nothing the user can see.
            const byText = (x, y) => x.text.localeCompare(y.text);
            const names = Object.keys(index).sort((x, y) => x === general ? -1 : y === general ? 1 : x.localeCompare(y));
            return names.reduce((all, name) => all.concat(groups[index[name]].sort(byText)), []);
        }
    }

    parent: QQC2.Overlay.overlay
    anchors.centerIn: parent
    modal: true
    focus: true
    closePolicy: QQC2.Popup.CloseOnEscape | QQC2.Popup.CloseOnPressOutside
    width: Math.min(parent ? parent.width - Kirigami.Units.gridUnit * 2 : 0, Kirigami.Units.gridUnit * 30)
    padding: Math.round(Kirigami.Units.gridUnit * 1.3)
    height: Math.min(implicitHeight, parent ? parent.height - Kirigami.Units.gridUnit * 2 : implicitHeight)
    onOpened: search.forceActiveFocus()
    onClosed: search.clear()

    enter: Transition {
        NumberAnimation {
            property: "opacity"
            from: 0
            to: 1
            duration: Kirigami.Units.shortDuration
        }
    }
    exit: Transition {
        NumberAnimation {
            property: "opacity"
            from: 1
            to: 0
            duration: Kirigami.Units.shortDuration
        }
    }

    QQC2.Overlay.modal: Rectangle {
        color: Qt.rgba(0, 0, 0, 0.35)
    }

    background: Rectangle {
        radius: 14
        color: Kirigami.Theme.backgroundColor
        border.width: 1
        border.color: Qt.alpha(Kirigami.Theme.textColor, 0.16)
    }

    contentItem: ColumnLayout {
        Accessible.role: Accessible.Dialog
        Accessible.name: dialog.title
        spacing: Kirigami.Units.largeSpacing

        QQC2.Label {
            Layout.fillWidth: true
            text: dialog.title
            font.bold: true
            font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.15
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
            Accessible.role: Accessible.Heading
        }

        SearchField {
            id: search
            Layout.fillWidth: true
            placeholderText: qsTr("Search shortcuts")
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredHeight: Kirigami.Units.gridUnit * 18
            Layout.minimumHeight: Kirigami.Units.gridUnit * 6

            ListView {
                id: list
                anchors.fill: parent
                clip: true
                visible: priv.entries.length > 0
                model: priv.entries
                boundsBehavior: Flickable.StopAtBounds
                activeFocusOnTab: false
                spacing: 0
                QQC2.ScrollBar.vertical: QQC2.ScrollBar {
                    id: bar
                }

                section.property: "section"
                section.criteria: ViewSection.FullString
                section.delegate: QQC2.Label {
                    required property string section
                    width: ListView.view.width
                    topPadding: Kirigami.Units.largeSpacing
                    bottomPadding: Kirigami.Units.smallSpacing
                    text: section
                    font.bold: true
                    opacity: 0.7
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                    Accessible.role: Accessible.Heading
                }

                delegate: Item {
                    id: row
                    required property var modelData
                    width: ListView.view.width
                    height: Math.max(label.implicitHeight, keys.implicitHeight) + Kirigami.Units.smallSpacing * 2

                    Accessible.role: Accessible.ListItem
                    Accessible.name: row.modelData.text + ", " + row.modelData.readable

                    RowLayout {
                        anchors.fill: parent
                        anchors.rightMargin: Kirigami.Units.largeSpacing + (bar.visible ? bar.width : 0)
                        spacing: Kirigami.Units.largeSpacing
                        QQC2.Label {
                            id: label
                            Layout.fillWidth: true
                            text: row.modelData.text
                            elide: Text.ElideRight
                            textFormat: Text.PlainText
                            Accessible.ignored: true
                        }
                        AtlasShortcutLabel {
                            id: keys
                            sequence: row.modelData.sequence
                            Accessible.ignored: true
                        }
                    }
                }
            }

            AtlasEmptyState {
                anchors.centerIn: parent
                width: parent.width
                visible: priv.entries.length === 0
                symbol: Symbols.Keyboard
                title: search.query.length > 0 ? qsTr("No matching shortcuts") : qsTr("No shortcuts")
                text: search.query.length > 0 ? qsTr("Try another word or key.") : ""
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Kirigami.Units.smallSpacing
            Item {
                Layout.fillWidth: true
            }
            PrimaryButton {
                id: closeButton
                text: qsTr("Close")
                onClicked: dialog.close()
            }
        }
    }
}
