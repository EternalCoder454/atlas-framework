pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami

// A text field that suggests completions while you type. `model` is a list of
// strings or a model with `textRole`. The popup lists up to `maxSuggestions`
// choices that contain what was typed (`filter: "contains"`, the default) or
// start with it (`"startsWith"`), any case, with the matching part in bold.
// Up and Down move among them, Return or Tab takes the highlighted one, Escape
// closes the list (a second Escape goes on to whoever is behind). The focus
// stays in the field. `accepted(text)` is emitted when a suggestion is taken, or
// when Return is pressed with no list open. A model of ten thousand strings
// works: filtering waits 60 ms after the last key and stops at `maxSuggestions`.
// The field's own properties are `text`, `placeholderText`, `clearable`,
// `errorText` and `readOnly`.
//
//   AtlasAutocompleteField {
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
            current = found.length > 0 ? 0 : -1;
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
            const at = n.length > 0 ? s.toLowerCase().indexOf(n) : -1;
            if (at < 0) {
                return esc(s);
            }
            return esc(s.slice(0, at)) + "<b>" + esc(s.slice(at, at + n.length)) + "</b>" + esc(s.slice(at + n.length));
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

    AtlasTextField {
        id: field
        anchors.fill: parent
        focus: true

        onTextEdited: {
            internals.forceAll = false;
            debounce.restart();
        }
        onActiveFocusChanged: {
            if (!activeFocus) {
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
            } else if (event.key === Qt.Key_Tab && popup.visible && internals.current >= 0) {
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
                    radius: AtlasStyle.radiusSmall
                    color: row.highlighted ? Qt.alpha(Kirigami.Theme.highlightColor, row.down ? 0.28 : 0.18) : "transparent"
                }
                contentItem: Text {
                    text: internals.mark(row.modelData)
                    textFormat: Text.StyledText
                    font: Kirigami.Theme.defaultFont
                    color: Kirigami.Theme.textColor
                    verticalAlignment: Text.AlignVCenter
                    horizontalAlignment: field.rtl ? Text.AlignRight : Text.AlignLeft
                    elide: Text.ElideRight
                }
            }
        }

        background: Rectangle {
            radius: AtlasStyle.radiusLarge
            color: Kirigami.Theme.backgroundColor.hslLightness > 0.5 ? Qt.lighter(Kirigami.Theme.backgroundColor, 1.5) : Qt.tint(Kirigami.Theme.backgroundColor, Qt.rgba(1, 1, 1, 0.08))
            border.width: 1
            border.color: Qt.alpha(Kirigami.Theme.textColor, 0.16)
        }
    }
}
