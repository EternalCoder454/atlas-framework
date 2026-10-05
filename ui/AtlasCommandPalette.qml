import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

// A command palette: a search field over a list of the app's actions, opened
// with a shortcut such as Ctrl+K. Typing filters the actions (every word of
// the query must appear in the action's text or section, in any case; names
// that start with the query come first), Up and Down move, Return runs the
// highlighted action and closes the palette, Escape closes it. Only enabled
// actions are listed. With an empty query the actions run most recently come
// first. Each row shows the symbol, text, section and shortcut of the action.
//
// `actions` defaults to every AtlasAction of the app (AtlasShortcuts.actions),
// or the actions of `collection` when one is set; give it a list to offer
// fewer (a list that is not empty wins over the collection). The palette is a popup: declare it anywhere
// and call open().
//
//   AtlasCommandPalette { id: palette }
//   AtlasAction {
//       text: qsTr("Command Palette")
//       shortcut: "Ctrl+K"
//       onTriggered: palette.open()
//   }
QQC2.Popup {
    id: palette

    // The actions on offer: anything with `text`, `enabled`, `trigger()`, and
    // optionally `symbol`, `section` and `shortcut` (an AtlasAction does).
    property list<QtObject> actions: palette.collection ? palette.collection._all : AtlasShortcuts.actions
    // The app's AtlasActionCollection: its actions are offered when `actions`
    // is empty, with the user's shortcuts shown.
    property AtlasActionCollection collection: null
    property string placeholderText: qsTr("Type a command")
    // How many recently run actions lead the empty list.
    property int recentCount: 5
    // The text in the search field.
    property alias query: field.text

    // Emitted after the palette closed and the action ran.
    signal triggered(QtObject action)

    // Most recent first. In memory only.
    property var _recent: []
    readonly property var _source: palette.actions.length > 0 || !palette.collection ? palette.actions : palette.collection._all
    readonly property var _rows: palette._compute(palette._source, field.text, palette._recent, palette.recentCount)

    function _plain(a): string {
        return AtlasShortcuts.plainText(String(a.text ?? ""));
    }
    // The rows to list for `query`: the enabled actions that match, best first.
    function _compute(actions, query: string, recent, recentCount: int): var {
        const words = query.toLowerCase().split(/\s+/).filter(w => w.length > 0);
        const items = [];
        for (let i = 0; i < actions.length; ++i) {
            const a = actions[i];
            if (!a || a.enabled === false) {
                continue;
            }
            const title = palette._plain(a);
            if (title.length === 0) {
                continue;
            }
            const section = String(a.category ?? a.section ?? "");
            const hay = (title + " " + section).toLowerCase();
            if (!words.every(w => hay.includes(w))) {
                continue;
            }
            let rank = 2;
            if (words.length === 0) {
                const r = recent.indexOf(a);
                rank = r >= 0 && r < recentCount ? 0 : 2;
                items.push({
                    "action": a,
                    "title": title,
                    "section": section,
                    "order": i,
                    "rank": rank,
                    "recent": r
                });
                continue;
            }
            const low = title.toLowerCase();
            if (low.startsWith(words[0])) {
                rank = 0;
            } else if (low.split(/\s+/).some(t => t.startsWith(words[0]))) {
                rank = 1;
            }
            items.push({
                "action": a,
                "title": title,
                "section": section,
                "order": i,
                "rank": rank,
                "recent": -1
            });
        }
        items.sort((x, y) => x.rank !== y.rank ? x.rank - y.rank : x.rank === 0 && words.length === 0 ? x.recent - y.recent : x.order - y.order);
        return items.map(it => ({
                    "action": it.action,
                    "title": it.title,
                    "subtitle": it.section,
                    "symbol": it.action.symbol ?? 0,
                    "shortcut": it.action.shortcut !== undefined && it.action.shortcut !== null ? AtlasShortcuts.readable(it.action.shortcut) : ""
                }));
    }
    function _run(index: int): void {
        const row = palette._rows[index];
        const action = row ? row.action : null;
        if (!action || action.enabled === false) {
            return;
        }
        const recent = palette._recent.filter(a => a && a !== action);
        recent.unshift(action);
        palette._recent = recent.slice(0, Math.max(0, palette.recentCount));
        palette.close();
        action.trigger();
        palette.triggered(action);
    }

    parent: QQC2.Overlay.overlay
    x: parent ? Math.round((parent.width - width) / 2) : 0
    y: parent ? Math.round(parent.height * 0.12) : 0
    modal: true
    focus: true
    closePolicy: QQC2.Popup.CloseOnEscape | QQC2.Popup.CloseOnPressOutside
    width: Math.min(parent ? parent.width - Kirigami.Units.gridUnit * 2 : 0, Kirigami.Units.gridUnit * 32)
    height: Math.min(implicitHeight, parent ? parent.height - y - Kirigami.Units.gridUnit : implicitHeight)
    padding: AtlasStyle.spacing

    onClosed: field.clear()
    onOpened: field.forceActiveFocus()

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
        color: Qt.rgba(0, 0, 0, 0.25)
    }

    background: Rectangle {
        radius: AtlasStyle.radiusLarge
        color: AtlasStyle.floatingBackground
        border.width: 1
        border.color: AtlasStyle.separator
    }

    contentItem: ColumnLayout {
        spacing: AtlasStyle.spacing
        Accessible.role: Accessible.Dialog
        Accessible.name: qsTr("Command palette")

        SearchField {
            id: field
            Layout.fillWidth: true
            placeholderText: palette.placeholderText
            onTextChanged: results.currentIndex = 0
            Keys.onPressed: event => {
                if (event.key === Qt.Key_Escape) {
                    palette.close();
                    event.accepted = true;
                } else {
                    results.handleKey(event);
                }
            }
        }
        AtlasSearchResults {
            id: results
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(Kirigami.Units.gridUnit * 18, Math.max(Kirigami.Units.gridUnit * 6, results.count * Math.round(Kirigami.Units.gridUnit * 2.9)))
            Layout.fillHeight: true
            focusPolicy: Qt.NoFocus
            model: palette._rows
            textRole: "title"
            subtitleRole: "subtitle"
            symbolRole: "symbol"
            shortcutRole: "shortcut"
            placeholderText: qsTr("No matching commands")
            onActivated: index => palette._run(index)
        }
    }
}
