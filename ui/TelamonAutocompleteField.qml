pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami

// A text field that suggests completions while you type. `model` is a list of
// strings or a model with `textRole`. The popup lists up to `maxSuggestions`
// choices that contain what was typed (`filter: "contains"`, the default) or
// start with it (`"startsWith"`), any case, with the matching part in bold.
// Up and Down move among them (nothing is highlighted until you do), Return or Tab takes the highlighted one, Escape
// closes the list (a second Escape goes on to whoever is behind). The focus
// stays in the field. `accepted(text)` is emitted when a suggestion is taken, or
// when Return is pressed with no list open. A model of ten thousand strings
// works: filtering waits 60 ms after the last key and stops at `maxSuggestions`.
// The field's own properties are `text`, `placeholderText`, `clearable`,
// `errorText` and `readOnly`.
//
//   TelamonAutocompleteField {
//       model: ["Berlin", "Bern", "Bergen", "Paris"]
//       placeholderText: qsTr("City")
//       onAccepted: text => search(text)
//   }
FocusScope {
    id: control

    // A list of strings, or a model; with a model, `textRole` names the role.
    property var model: []
    property string textRole
    // "contains" (default) or "startsWith".
    property string filter: "contains"
    property int maxSuggestions: 8
    property alias text: field.text
    property alias placeholderText: field.placeholderText
    property alias clearable: field.clearable
    property alias errorText: field.errorText
    property alias readOnly: field.readOnly
    readonly property alias _field: field
    // The text with the part the user typed in bold (for the tests).
    function _mark(text: string): string {
        return internals.mark(text);
    }
    // True while the suggestion list is open.
    readonly property bool popupOpen: popup.visible

    signal accepted(string text)

    implicitWidth: field.implicitWidth
    implicitHeight: field.implicitHeight

    QtObject {
        id: internals

        // The strings of the model and their lower-case form, made again only
        // after the model changed.
        property var items: []
        property var lower: []
        property bool stale: true
        // The matching strings, at most maxSuggestions.
        property var matches: []
        // The highlighted row; -1 for none.
        property int current: -1

        function esc(s: string): string {
            return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
        }
        function needle(): string {
            return field.text.trim().toLowerCase();
        }
        function rebuild(): void {
            const m = control.model;
            const out = [];
            if (m && typeof m.rowCount !== "function" && typeof m.length === "number") {
                // A JS array, or a list a C++ side or a property assignment made of one.
                for (let i = 0; i < m.length; ++i) {
                    const v = control.textRole.length > 0 && typeof m[i] === "object" && m[i] !== null ? m[i][control.textRole] : m[i];
                    out.push(v === undefined || v === null ? "" : String(v));
                }
            } else if (m && typeof m.rowCount === "function") {
                const rows = m.rowCount();
                if (typeof m.get === "function") {
                    // A ListModel: a row is an object; without textRole, its first value.
                    for (let i = 0; i < rows; ++i) {
                        const row = m.get(i);
                        const key = control.textRole.length > 0 ? control.textRole : Object.keys(row)[0];
                        out.push(key === undefined || row[key] === undefined ? "" : String(row[key]));
                    }
                } else if (control.textRole.length === 0 || typeof m.roleNames === "function") {
                    // Another model: the display role, or the role textRole names.
                    let role = 0;
                    if (control.textRole.length > 0) {
                        const names = m.roleNames();
                        role = -1;
                        for (const k in names) {
                            if (String(names[k]) === control.textRole) {
                                role = Number(k);
                                break;
                            }
                        }
                    }
                    for (let i = 0; role >= 0 && i < rows; ++i) {
                        out.push(String(m.data(m.index(i, 0), role)));
                    }
                }
            }
            items = out;
            lower = out.map(s => s.toLowerCase());
            stale = false;
        }
        // Finds the matches for the text now; opens or closes the list.
        function refresh(): void {
            if (stale) {
                rebuild();
            }
            const n = needle();
            const found = [];
            const starts = control.filter === "startsWith";
            const max = Math.max(0, control.maxSuggestions);
            // Typing nothing suggests nothing; Down asks for the first rows.
            for (let i = 0; i < lower.length && found.length < max; ++i) {
                const at = lower[i].indexOf(n);
                if (n.length > 0 ? (starts ? at === 0 : at >= 0) : forceAll) {
                    // A string that is exactly what is typed is not a suggestion.
                    if (items[i] !== field.text) {
                        found.push(items[i]);
                    }
                }
            }
            matches = found;
            // The highlight starts on nothing: Return submits the typed text until
            // the user moves it (Down or the pointer). Down on a closed list starts on row 0.
            current = forceAll && found.length > 0 ? 0 : -1;
            if (found.length > 0 && field.activeFocus && !control.readOnly) {
                popup.open();
            } else {
                popup.close();
            }
        }
        property bool forceAll: false
        // The text with the matching part in bold, as rich text.
        function mark(s: string): string {
            const n = needle();
            if (n.length === 0) {
                return esc(s);
            }
            // toLowerCase can change the length (an "I" with a dot becomes two
            // characters), so the offsets are mapped back to s.
            const map = [];
            let lo = "";
            for (let i = 0; i < s.length;) {
                const ch = String.fromCodePoint(s.codePointAt(i));
                const l = ch.toLowerCase();
                for (let k = 0; k < l.length; ++k) {
                    map.push(i);
                }
                lo += l;
                i += ch.length;
            }
            const at = lo.indexOf(n);
            if (at < 0) {
                return esc(s);
            }
            let e = at + n.length;
            while (e < map.length && map[e] === map[e - 1]) {
                ++e;
            }
            const from = map[at];
            const to = e < map.length ? map[e] : s.length;
            return esc(s.slice(0, from)) + "<b>" + esc(s.slice(from, to)) + "</b>" + esc(s.slice(to));
        }
        // Applies a pending (debounced) filter now, so a fast Return or Tab acts
        // on what is typed, not on the list for the text before.
        function flush(): void {
            if (debounce.running) {
                debounce.stop();
                refresh();
            }
        }
        function take(index: int): void {
            if (index < 0 || index >= matches.length) {
                return;
            }
            const t = matches[index];
            debounce.stop();
            popup.close();
            field.text = t;
            field.cursorPosition = t.length;
            control.accepted(t);
        }
    }

    onModelChanged: internals.stale = true
    onTextRoleChanged: internals.stale = true
    onFilterChanged: debounce.restart()
    onMaxSuggestionsChanged: debounce.restart()

    // The model is read again when it changes.
    Connections {
        target: control.model && typeof control.model.rowCount === "function" ? control.model : null
        ignoreUnknownSignals: true
        function onModelReset() {
            internals.stale = true;
        }
        function onRowsInserted() {
            internals.stale = true;
        }
        function onRowsRemoved() {
            internals.stale = true;
        }
        function onRowsMoved() {
            internals.stale = true;
        }
        function onDataChanged() {
            internals.stale = true;
        }
        function onLayoutChanged() {
            internals.stale = true;
        }
    }

    Timer {
        id: debounce
        interval: 60
        onTriggered: internals.refresh()
    }

    TelamonTextField {
        id: field
        anchors.fill: parent
        focus: true

        onTextEdited: {
            internals.forceAll = false;
            debounce.restart();
        }
        // The clear button, or the app, emptied the field: no list for the old text.
        onTextChanged: {
            if (text.length === 0) {
                debounce.stop();
                internals.forceAll = false;
                internals.matches = [];
                internals.current = -1;
                popup.close();
            }
        }
        onActiveFocusChanged: {
            if (!activeFocus) {
                internals.forceAll = false;
                debounce.stop();
                popup.close();
            }
        }
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) {
                if (popup.visible) {
                    popup.close();
                    event.accepted = true;
                } else {
                    event.accepted = false;
                }
            } else if (event.key === Qt.Key_Tab && (debounce.running || popup.visible)) {
                internals.flush();
                if (!popup.visible || internals.current < 0) {
                    event.accepted = false;
                    return;
                }
                // Tab takes the suggestion instead of moving on.
                internals.take(internals.current);
                event.accepted = true;
            }
        }
        Keys.onDownPressed: event => {
            if (!popup.visible) {
                debounce.stop();
                internals.forceAll = true;
                internals.refresh();
            } else {
                internals.current = Math.min(internals.current + 1, internals.matches.length - 1);
            }
            event.accepted = true;
        }
        Keys.onUpPressed: event => {
            if (popup.visible) {
                internals.current = Math.max(internals.current - 1, 0);
                event.accepted = true;
            } else {
                event.accepted = false;
            }
        }
        Keys.onReturnPressed: event => handleReturn(event)
        Keys.onEnterPressed: event => handleReturn(event)

        function handleReturn(event: var): void {
            internals.flush();
            if (popup.visible && internals.current >= 0) {
                internals.take(internals.current);
            } else {
                control.accepted(text);
            }
            event.accepted = true;
        }
    }

    T.Popup {
        id: popup
        parent: field
        y: field.height + Kirigami.Units.smallSpacing
        x: 0
        width: field.width
        padding: Kirigami.Units.smallSpacing
        margins: Kirigami.Units.smallSpacing
        // The list is only a view of the field: it never takes the focus.
        focus: false
        modal: false
        closePolicy: T.Popup.CloseOnPressOutsideParent
        // Down's "show everything" ends with the list.
        onClosed: internals.forceAll = false

        contentItem: ListView {
            id: list
            implicitHeight: contentHeight
            model: popup.visible ? internals.matches : []
            currentIndex: internals.current
            interactive: false
            boundsBehavior: Flickable.StopAtBounds
            delegate: T.ItemDelegate {
                id: row
                required property string modelData
                required property int index
                width: ListView.view ? ListView.view.width : implicitWidth
                implicitHeight: Math.round(Kirigami.Units.gridUnit * 1.8)
                leftPadding: Kirigami.Units.largeSpacing
                rightPadding: Kirigami.Units.largeSpacing
                hoverEnabled: true
                focusPolicy: Qt.NoFocus
                highlighted: internals.current === index
                onHoveredChanged: {
                    if (hovered) {
                        internals.current = index;
                    }
                }
                onClicked: internals.take(index)
                Accessible.role: Accessible.ListItem
                Accessible.name: modelData
                background: Rectangle {
                    radius: TelamonStyle.radiusSmall
                    color: row.highlighted ? TelamonStyle.alpha(TelamonStyle.accent, row.down ? 0.28 : 0.18) : "transparent"
                }
                contentItem: Text {
                    text: internals.mark(row.modelData)
                    textFormat: Text.StyledText
                    font.family: TelamonStyle.fontFamily
                    font.pointSize: TelamonStyle.fontSizeBody
                    color: Kirigami.Theme.textColor
                    verticalAlignment: Text.AlignVCenter
                    horizontalAlignment: field.rtl ? Text.AlignRight : Text.AlignLeft
                    elide: Text.ElideRight
                }
            }
        }

        background: Item {
            // Same card as ContextMenu. Soft shadow: faint outlines, no shader, so it also draws with the software renderer.
            Rectangle {
                anchors.fill: parent
                anchors.margins: -1
                anchors.topMargin: 0
                anchors.bottomMargin: -3
                radius: TelamonStyle.radius + 1
                color: TelamonStyle.alpha("black", 0.04)
            }
            Rectangle {
                anchors.fill: parent
                anchors.margins: -2
                anchors.topMargin: -1
                anchors.bottomMargin: -5
                radius: TelamonStyle.radius + 2
                color: TelamonStyle.alpha("black", 0.025)
            }
            Rectangle {
                anchors.fill: parent
                radius: TelamonStyle.radius
                color: TelamonStyle.floatingBackground
                border.width: 1
                border.color: TelamonStyle.separator
            }
        }
    }
}
