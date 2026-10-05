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
// With a `collection` (AtlasActionCollection) the list shows its actions, by
// `category`. When the collection's `shortcutsEditable` is set, each row has a
// Change button that records a new shortcut (a shortcut another action has is
// refused, saying which), a Reset button for a changed one, and the dialog has
// Reset all.
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
    // The app's AtlasActionCollection: its actions are listed instead of every
    // registered action, and the user can change shortcuts when its
    // `shortcutsEditable` is set.
    property AtlasActionCollection collection: null
    readonly property bool _editable: dialog.collection !== null && dialog.collection.shortcutsEditable

    QtObject {
        id: priv
        // [{ section, text, sequence, readable }] for what the dialog shows now.
        readonly property var entries: dialog.visible ? priv.build(dialog.collection ? dialog.collection._all : AtlasShortcuts.actions, search.query, AtlasShortcuts.conflicts, dialog.collection ? dialog.collection._overrides : null) : []
        // The action being given a new shortcut, and what went wrong last.
        property var editing: null
        property string message
        // Edit mode stays until the Escape release was seen after a cancel (or
        // 2 s), so that release does not close the dialog.
        property bool escDown: false
        readonly property Timer idle: Timer {
            // Only a fallback for a cancel that sends no Escape release; an
            // Escape release ends edit mode at once.
            interval: 2000
            onTriggered: priv.stop()
        }

        // `conflicts` and `overrides` are only dependencies: `conflicts` changes
        // (after each change of an action's shortcut, text or enabled) so the
        // list is rebuilt, and `overrides` when the user changed a shortcut.
        function build(actions: var, query: string, conflicts: var, overrides: var): var {
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
                const category = a.category !== undefined ? a.category : a.section;
                const section = category && category.length > 0 ? category : general;
                if (!(section in index)) {
                    index[section] = groups.length;
                    groups.push([]);
                }
                groups[index[section]].push({
                    "section": section,
                    "text": text,
                    "sequence": a.shortcut,
                    "readable": readable,
                    "action": a,
                    "name": a.objectName ?? ""
                });
            }
            // Sections by name with the general one first, rows by text: the
            // order the actions registered in follows nothing the user can see.
            const byText = (x, y) => x.text.localeCompare(y.text);
            const names = Object.keys(index).sort((x, y) => x === general ? -1 : y === general ? 1 : x.localeCompare(y));
            return names.reduce((all, name) => all.concat(groups[index[name]].sort(byText)), []);
        }

        // Whether the row's action can be given a shortcut: it is in the
        // editable collection and has an objectName to keep it under.
        function canEdit(row: var): bool {
            return dialog._editable && row.name.length > 0 && dialog.collection.action(row.name) === row.action;
        }
        function stop(): void {
            priv.idle.stop();
            priv.escDown = false;
            priv.editing = null;
            priv.message = "";
        }
        // The user recorded `text` for the row's action: refuse what another
        // action has, keep anything else.
        function accept(row: var, text: string, conflict: string): bool {
            if (text.length === 0) {
                priv.message = qsTr("A shortcut cannot be empty. Press keys, or use Reset.");
                return false;
            }
            if (conflict.length > 0) {
                //: Under the shortcut list: %1 is "Already used by “Save”"
                priv.message = qsTr("%1. Choose another shortcut.").arg(conflict);
                return false;
            }
            if (!dialog.collection.setShortcut(row.name, text)) {
                priv.message = qsTr("That shortcut cannot be used or saved. Use Ctrl, Alt or Meta with a key, or an F key.");
                return false;
            }
            priv.stop();
            return true;
        }
        // Back to the declared shortcut, unless another action has it now.
        function reset(row: var): void {
            const other = dialog.collection.declaredConflict(row.name);
            if (other.length > 0) {
                //: %1 is the name of the action that has the shortcut this one would go back to
                priv.message = qsTr("Already used by “%1”. Change that shortcut first.").arg(other);
                return;
            }
            if (dialog.collection.resetShortcut(row.name)) {
                priv.stop();
            } else {
                priv.message = qsTr("The shortcut could not be reset.");
            }
        }
    }

    parent: QQC2.Overlay.overlay
    anchors.centerIn: parent
    modal: true
    focus: true
    // Escape while a shortcut is being recorded cancels the recording only.
    closePolicy: priv.editing !== null ? QQC2.Popup.CloseOnPressOutside : (QQC2.Popup.CloseOnEscape | QQC2.Popup.CloseOnPressOutside)
    width: Math.min(parent ? parent.width - Kirigami.Units.gridUnit * 2 : 0, Kirigami.Units.gridUnit * 30)
    padding: Math.round(Kirigami.Units.gridUnit * 1.3)
    height: Math.min(implicitHeight, parent ? parent.height - Kirigami.Units.gridUnit * 2 : implicitHeight)
    onOpened: search.forceActiveFocus()
    onClosed: {
        search.clear();
        priv.stop();
    }

    enter: Transition {
        NumberAnimation {
            property: "opacity"
            from: 0
            to: 1
            duration: AtlasStyle.durationShort
        }
    }
    exit: Transition {
        NumberAnimation {
            property: "opacity"
            from: 1
            to: 0
            duration: AtlasStyle.durationShort
        }
    }

    QQC2.Overlay.modal: Rectangle {
        color: Qt.rgba(0, 0, 0, 0.35)
    }

    background: Rectangle {
        radius: AtlasStyle.radiusLarge
        // Raised, strongly tinted over the blur; solid without it (floatingBackground switches).
        color: AtlasStyle.floatingBackground
        border.width: 1
        border.color: AtlasStyle.separator
    }

    contentItem: ColumnLayout {
        Accessible.role: Accessible.Dialog
        Accessible.name: dialog.title
        spacing: AtlasStyle.spacingLarge

        QQC2.Label {
            Layout.fillWidth: true
            text: dialog.title
            font.bold: true
            font.pointSize: AtlasStyle.fontSizeHeading
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
                // The model is rebuilt after every change; the scroll position
                // is kept unless the search changed.
                property real _y: 0
                property string _yQuery: ""
                property bool _restoring: false
                // Only the user's own movement (flick, wheel, drag, scroll bar)
                // is remembered: not what a model reset does to contentY.
                onContentYChanged: {
                    if (!list._restoring && (list.moving || bar.pressed)) {
                        list._y = list.contentY;
                        list._yQuery = search.query;
                    }
                }
                onMovementEnded: {
                    list._y = list.contentY;
                    list._yQuery = search.query;
                }
                onModelChanged: {
                    if (search.query !== list._yQuery) {
                        // A new search starts at the top.
                        list._y = 0;
                        list._yQuery = search.query;
                    } else if (list._y > 0) {
                        list._restoring = true;
                        Qt.callLater(list._restore);
                    }
                }
                function _restore(): void {
                    list.forceLayout();
                    list.contentY = Math.min(list._y, Math.max(0, list.contentHeight - list.height));
                    list._restoring = false;
                }
                // A row's button or field that takes the focus (Tab) is
                // scrolled into view, and that position is kept.
                function _follow(): void {
                    const f = list.Window.activeFocusItem;
                    let p = f;
                    while (p && p !== list.contentItem) {
                        p = p.parent;
                    }
                    if (!p) {
                        return;
                    }
                    const at = f.mapToItem(list, 0, 0);
                    const max = Math.max(0, list.contentHeight - list.height);
                    let y = list.contentY;
                    if (at.y < 0) {
                        y += at.y;
                    } else if (at.y + f.height > list.height) {
                        y += at.y + f.height - list.height;
                    }
                    y = Math.max(0, Math.min(max, y));
                    if (y !== list.contentY) {
                        list.contentY = y;
                        list._y = y;
                        list._yQuery = search.query;
                    }
                }
                readonly property Connections _focusWatch: Connections {
                    target: list.Window.window
                    function onActiveFocusItemChanged(): void {
                        list._follow();
                    }
                }
                spacing: 0
                QQC2.ScrollBar.vertical: QQC2.ScrollBar {
                    id: bar
                }

                section.property: "section"
                section.criteria: ViewSection.FullString
                section.delegate: QQC2.Label {
                    required property string section
                    width: ListView.view.width
                    topPadding: AtlasStyle.spacingLarge
                    bottomPadding: AtlasStyle.spacingSmall
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
                    readonly property bool editable: priv.canEdit(row.modelData)
                    readonly property bool isEditing: row.editable && priv.editing === row.modelData.action
                    height: rowLayout.implicitHeight + AtlasStyle.spacingSmall * 2

                    Accessible.role: Accessible.ListItem
                    Accessible.name: row.modelData.text + ", " + row.modelData.readable

                    RowLayout {
                        id: rowLayout
                        anchors.fill: parent
                        anchors.rightMargin: AtlasStyle.spacingLarge + (bar.visible ? bar.width : 0)
                        spacing: AtlasStyle.spacingLarge
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
                            visible: !row.isEditing
                            sequence: row.modelData.sequence
                            Accessible.ignored: true
                        }
                        AtlasShortcutField {
                            id: field
                            visible: row.isEditing
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 9
                            ignoreAction: row.modelData.action
                            Accessible.name: qsTr("New shortcut for %1").arg(row.modelData.text)
                            // Set when onEdited ran, so the end of the recording that
                            // caused it is not taken for a cancel.
                            property bool _handled: false
                            function _checkIdle(): void {
                                if (!field._handled && !field.recording && row.isEditing) {
                                    if (field.activeFocus) {
                                        // Escape (still held, perhaps): wait for its release.
                                        priv.escDown = true;
                                        priv.idle.restart();
                                    } else {
                                        priv.stop();
                                    }
                                }
                                field._handled = false;
                            }
                            onRecordingChanged: if (!field.recording) Qt.callLater(field._checkIdle)
                            Keys.onReleased: event => {
                                if (event.key === Qt.Key_Escape && row.isEditing) {
                                    event.accepted = true;
                                    if (priv.escDown) {
                                        priv.stop();
                                    }
                                }
                            }
                            sequence: AtlasShortcuts.portable(row.modelData.sequence)
                            onVisibleChanged: if (visible) startRecording()
                            Component.onCompleted: if (visible) startRecording()
                            onEdited: {
                                field._handled = true;
                                const wanted = field.sequence;
                                if (!priv.accept(row.modelData, wanted, field.conflictText)) {
                                    // Back to the action's own shortcut, and record again.
                                    field.sequence = AtlasShortcuts.portable(row.modelData.sequence);
                                    Qt.callLater(field.startRecording);
                                }
                            }
                        }
                        TextButton {
                            visible: row.editable && !row.isEditing
                            text: qsTr("Change")
                            Accessible.name: qsTr("Change shortcut for %1").arg(row.modelData.text)
                            onClicked: {
                                priv.message = "";
                                priv.editing = row.modelData.action;
                            }
                        }
                        TextButton {
                            visible: row.editable && !row.isEditing && dialog.collection.hasCustomShortcut(row.modelData.name)
                            text: qsTr("Reset")
                            Accessible.name: qsTr("Reset shortcut for %1").arg(row.modelData.text)
                            onClicked: {
                                priv.reset(row.modelData);
                            }
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

        QQC2.Label {
            Layout.fillWidth: true
            visible: priv.message.length > 0
            text: priv.message
            color: AtlasStyle.error
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
            Accessible.role: Accessible.AlertMessage
            Accessible.name: priv.message
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: AtlasStyle.spacingSmall
            SecondaryButton {
                visible: dialog._editable
                text: qsTr("Reset all")
                onClicked: {
                    priv.stop();
                    if (!dialog.collection.resetShortcuts()) {
                        priv.message = qsTr("Some shortcuts could not be reset.");
                    }
                }
            }
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
