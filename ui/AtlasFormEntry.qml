import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import Atlas.Ui

// One labelled row of an AtlasForm: the label and help text on the leading
// side, the control (one item, the default property) on the trailing side. It
// checks `required`, the control's `acceptableInput` and the app's `errorText`,
// shows the error under the row once the user has left the control (or
// `AtlasForm.validate()` was called) and announces it. Clicking the label
// focuses the control. With a `settingKey` the control loads from and saves to
// the form's AtlasSettings. The rules: docs/reference/atlas-ui/atlas-form-entry.md.
//
//   AtlasFormEntry {
//       label: qsTr("Port")
//       help: qsTr("1 to 65535")
//       required: true
//       settingKey: "Port"
//       AtlasSpinBox { from: 1; to: 65535 }
//   }
FocusScope {
    id: entry

    default property alias content: host.data

    property string label
    property string help
    // The app's own error; shown at once, like AtlasTextField.errorText.
    property string errorText
    property bool required: false
    property string requiredText: qsTr("Required")
    property string invalidText: qsTr("Check this value")
    // The AtlasSettings key the control is bound to; empty for none.
    property string settingKey
    // The control's property to save, for a control the table in the
    // reference does not list.
    property string settingProperty
    // The control under the label. On by default in a narrow row and for a tall
    // control (a text area, a list).
    property bool stacked: entry._autoStacked

    // No error of any kind (an entry that is disabled has none).
    readonly property bool valid: !entry.enabled || (entry.errorText.length === 0 && !entry._missing && !entry._unacceptable)
    // The error on screen, or "".
    readonly property string shownError: {
        if (entry.errorText.length > 0) {
            return entry.errorText;
        }
        if (!entry._leftOnce && !entry._revealed) {
            return "";
        }
        return entry._missing ? entry.requiredText : entry._unacceptable ? entry.invalidText : "";
    }

    readonly property bool atlasRow: true
    readonly property Item _control: host.children.length > 0 ? host.children[0] : null
    readonly property bool _isEmpty: entry._emptyOf(entry._control)
    readonly property bool _missing: entry.required && entry._isEmpty
    readonly property bool _unacceptable: !entry._isEmpty && entry._control !== null && entry._control["acceptableInput"] === false
    readonly property bool _autoStacked: (entry.width > 0 && entry.width < Kirigami.Units.gridUnit * 22) || (entry._control !== null && entry._control.implicitHeight > AtlasStyle.controlHeight * 2.5)
    // The user has left the control once / validate() asked to show errors.
    property bool _leftOnce: false
    property bool _revealed: false
    property bool _hadFocus: false
    property var _form: null
    // Test hook: replaces Accessible.announce().
    property var _announceHook: null
    readonly property bool _flashing: flashAnim.running
    // The first visible row in a Section draws no separator above itself.
    readonly property bool isFirst: {
        const v = entry.parent ? entry.parent.visibleChildren : [];
        for (let i = 0; i < v.length; ++i) {
            if (v[i].atlasRow === true) {
                return v[i] === entry;
            }
        }
        return true;
    }

    // Settings: what is saved, where, and the one-turn hold that loads a
    // stored value without ending an app's binding on the control (the same
    // rule as a user edit, docs/api-1.5.0.md Part 1).
    readonly property var _store: entry._form ? entry._form._settings : null
    readonly property string _prop: entry._propOf(entry._control, entry.settingProperty)
    readonly property bool _keyed: entry.settingKey.length > 0 && entry._prop.length > 0 && entry._prop !== "password"
    property bool _ready: false
    property var _wiredTo: null
    property string _warnedKey: ""
    property var _applyValue: null
    property bool _applying: false
    property bool _guard: false
    readonly property Binding _hold: Binding {
        target: entry._keyed ? entry._control : null
        property: entry._prop
        value: entry._applyValue
        when: entry._applying
        restoreMode: Binding.RestoreBinding
    }

    Layout.fillWidth: true
    Layout.minimumHeight: entry.implicitHeight
    implicitHeight: Math.max(Math.round(Kirigami.Units.gridUnit * 2.5), grid.implicitHeight + Math.round(AtlasStyle.spacingLarge * 1.6))

    onActiveFocusChanged: {
        if (entry.activeFocus) {
            entry._hadFocus = true;
        } else if (entry._hadFocus && !entry._popupOpen()) {
            entry._leftOnce = true;
        }
    }
    onShownErrorChanged: {
        if (entry.shownError.length > 0) {
            entry._announce(entry.shownError);
        }
    }
    on_ControlChanged: if (entry._ready) {
        entry._attach();
    }
    on_StoreChanged: if (entry._ready) {
        entry._load();
    }
    onSettingKeyChanged: if (entry._ready) {
        entry._load();
    }
    Keys.onReturnPressed: event => entry._returnKey(event)
    Keys.onEnterPressed: event => entry._returnKey(event)
    Component.onCompleted: {
        entry._form = entry._findForm();
        if (entry._form) {
            entry._form._register(entry);
        }
        entry._attach();
        entry._ready = true;
        entry._load();
    }
    Component.onDestruction: {
        if (entry._form) {
            entry._form._unregister(entry);
        }
    }

    // What AtlasForm.validate() does to each entry.
    function _reveal(): void {
        entry._revealed = true;
    }

    // Moves the keyboard focus to the control (to the first thing in it that
    // takes focus, for a composite such as AtlasFileField).
    function _focusControl(reason: int): void {
        const c = entry._control;
        if (!c) {
            entry.forceActiveFocus(reason);
            return;
        }
        let target = c;
        if (!c.activeFocusOnTab) {
            const next = c.nextItemInFocusChain(true);
            if (next && entry._inside(next)) {
                target = next;
            }
        }
        target.forceActiveFocus(reason);
    }

    // Moves the focus to the control, scrolls the row into view and flashes it
    // (not under reduced motion). Used by the preferences search.
    function _show(): void {
        entry._focusControl(Qt.ShortcutFocusReason);
        entry._ensureVisible();
        if (!AtlasStyle.reducedMotion) {
            flashAnim.restart();
        }
    }

    function _ensureVisible(): void {
        let f = entry.parent;
        while (f && !(f.contentY !== undefined && f.contentHeight !== undefined && f.flickableDirection !== undefined)) {
            f = f.parent;
        }
        if (!f) {
            return;
        }
        const p = entry.mapToItem(f.contentItem, 0, 0);
        const m = AtlasStyle.spacingSmall;
        if (p.y < f.contentY) {
            f.contentY = Math.max(0, p.y - m);
        } else if (p.y + entry.height > f.contentY + f.height) {
            f.contentY = Math.max(0, p.y + entry.height - f.height + m);
        }
    }

    function _inside(item: Item): bool {
        for (let i = item; i; i = i.parent) {
            if (i === entry) {
                return true;
            }
        }
        return false;
    }

    function _findForm(): var {
        for (let p = entry.parent; p; p = p.parent) {
            if (p._isAtlasForm === true) {
                return p;
            }
        }
        return null;
    }

    // A combo box's list takes the focus while it is open; that is not leaving.
    function _popupOpen(): bool {
        const c = entry._control;
        return c !== null && c["popup"] !== undefined && c["popup"] !== null && c["popup"].visible === true;
    }

    function _announce(text: string): void {
        if (entry._announceHook) {
            entry._announceHook(text);
        } else if (entry._control) {
            entry._control.Accessible.announce(text);
        } else {
            entry.Accessible.announce(text);
        }
    }

    // Empty: no text, not checked, index -1 (and no path or shortcut). A colour
    // is never empty.
    function _emptyOf(c: var): bool {
        if (!c) {
            return false;
        }
        if (c["sequence"] !== undefined) {
            return String(c["sequence"]).length === 0;
        }
        if (c["path"] !== undefined) {
            return String(c["path"]).length === 0;
        }
        if (c["showAlpha"] !== undefined) {
            return false;
        }
        if (typeof c["checked"] === "boolean") {
            return !c["checked"];
        }
        if (typeof c["currentIndex"] === "number") {
            return c["currentIndex"] < 0;
        }
        if (typeof c["text"] === "string") {
            return c["text"].length === 0;
        }
        return false;
    }

    // The property a settingKey saves ("password" marks one that never is).
    function _propOf(c: var, custom: string): string {
        if (custom.length > 0) {
            return custom;
        }
        if (!c) {
            return "";
        }
        if (c["sequence"] !== undefined) {
            return "sequence";
        }
        if (c["path"] !== undefined) {
            return "path";
        }
        if (c["showAlpha"] !== undefined) {
            return "color";
        }
        if (c["revealed"] !== undefined || c["echoMode"] === TextInput.Password) {
            return "password";
        }
        if (typeof c["checked"] === "boolean") {
            return "checked";
        }
        if (typeof c["currentIndex"] === "number") {
            return "currentIndex";
        }
        if (typeof c["value"] === "number") {
            return "value";
        }
        if (typeof c["text"] === "string") {
            return "text";
        }
        return "";
    }

    // Names the control for a screen reader, and connects what saves its edits.
    function _attach(): void {
        const c = entry._control;
        if (!c || entry._wiredTo === c) {
            return;
        }
        entry._wiredTo = c;
        // The control's own name stays when the entry has no label.
        const own = c.Accessible.name;
        c.Accessible.name = Qt.binding(() => entry.label.length > 0 ? entry.label : own);
        c.Accessible.description = Qt.binding(() => [entry.help, entry.shownError].filter(t => t.length > 0).join(", "));
        const p = entry._prop;
        if (c["echoMode"] !== undefined && c["accepted"] !== undefined) {
            c["accepted"].connect(entry, entry._returned);
        }
        if (p.length === 0 || p === "password") {
            return;
        }
        let names = ["edited"];
        if (entry.settingProperty.length > 0) {
            names = [p + "Changed"];
        } else if (p === "checked") {
            names = ["toggled"];
        } else if (p === "currentIndex") {
            names = ["activated"];
        } else if (p === "value") {
            names = ["moved", "valueModified", "edited"];
        } else if (p === "text") {
            names = [c["textEdited"] !== undefined ? "textEdited" : "textChanged"];
        }
        for (const n of names) {
            const s = c[n];
            if (s && typeof s.connect === "function") {
                s.connect(entry, entry._userEdited);
            }
        }
    }

    function _returned(): void {
        if (!entry._form) {
            return;
        }
        if (entry._form.valid) {
            entry._form.accepted();
        } else {
            entry._form.validate();
        }
    }

    // Return in a field whose text is not acceptable never reaches its
    // `accepted`, so show the errors from here.
    function _returnKey(event: var): void {
        const c = entry._control;
        if (c && c["echoMode"] !== undefined && c["acceptableInput"] === false && !event.isAutoRepeat) {
            entry._returned();
        }
        event.accepted = false;
    }

    function _warn(text: string): void {
        console.warn("AtlasFormEntry: settingKey \"" + entry.settingKey + "\": " + text);
    }

    // The stored value as the control's property takes it, or {ok: false}.
    // AtlasSettings.value() gives its default for a stored value of another
    // shape, so two different defaults that both come back mean it is not
    // that shape.
    function _parse(s: var, key: string, cur: var, p: string): var {
        if (typeof cur === "boolean") {
            const a = s.value(key, false);
            return a === s.value(key, true) ? {ok: true, value: a} : {ok: false};
        }
        if (typeof cur === "number") {
            const whole = p === "currentIndex";
            const a = s.value(key, whole ? 0 : 0.25);
            const b = s.value(key, whole ? 1 : 0.75);
            return a === b && typeof a === "number" && isFinite(a) ? {ok: true, value: a} : {ok: false};
        }
        if (p === "color") {
            const raw = s.value(key, "");
            return /^#([0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/.test(raw) ? {ok: true, value: raw} : {ok: false};
        }
        if (typeof cur === "string") {
            return {ok: true, value: s.value(key, "")};
        }
        return {ok: false};
    }

    function _hex(col: color): string {
        const h = n => ("0" + Math.round(n * 255).toString(16)).slice(-2);
        return "#" + (col.a < 1 ? h(col.a) : "") + h(col.r) + h(col.g) + h(col.b);
    }

    // Takes the stored value into the control, if there is one that fits.
    function _load(): void {
        const key = entry.settingKey;
        const c = entry._control;
        if (key.length === 0 || !c) {
            return;
        }
        const p = entry._prop;
        if (p === "password") {
            if (entry._warnedKey !== key) {
                entry._warnedKey = key;
                entry._warn("a password is not a setting, so it is neither loaded nor saved");
            }
            return;
        }
        if (p.length === 0) {
            entry._warn("the control has no property to save; set settingProperty");
            return;
        }
        const s = entry._store;
        if (!s) {
            // A page's dialog is known only once the dialog is complete.
            Qt.callLater(entry._checkStore);
            return;
        }
        if (!s.contains(key)) {
            return;
        }
        const r = entry._parse(s, key, c[p], p);
        if (!r.ok) {
            entry._warn("the stored value does not fit " + p + " and is ignored");
            return;
        }
        entry._applyValue = r.value;
        entry._applying = true;
        Qt.callLater(entry._endApply);
    }

    function _checkStore(): void {
        if (entry._keyed && !entry._store) {
            entry._warn("there is no AtlasSettings; set AtlasForm.settings or AtlasPreferencesDialog.settings");
        }
    }

    function _endApply(): void {
        entry._guard = true;
        entry._applying = false;
        entry._guard = false;
    }

    // The control's edit signal: write the new value.
    function _userEdited(): void {
        if (entry._applying || entry._guard || !entry._keyed) {
            return;
        }
        const s = entry._store;
        const c = entry._control;
        if (!s || !c) {
            return;
        }
        const p = entry._prop;
        let v = c[p];
        if (p === "color") {
            v = entry._hex(v);
        } else if (p === "sequence") {
            v = AtlasShortcuts.portable(v);
        } else if (typeof v === "number") {
            if (!isFinite(v)) {
                return;
            }
        } else if (typeof v !== "boolean" && typeof v !== "string") {
            entry._warn("the value of " + p + " cannot be stored");
            return;
        }
        s.setValue(entry.settingKey, v);
    }

    Connections {
        target: entry._store
        function onChanged(key: string): void {
            if (entry._ready && key === entry.settingKey) {
                entry._load();
            }
        }
    }

    Rectangle {
        id: flash
        anchors.fill: parent
        anchors.margins: 3
        radius: 7
        color: Qt.alpha(AtlasStyle.accent, 0.3)
        opacity: 0
        Accessible.ignored: true
    }
    SequentialAnimation {
        id: flashAnim
        NumberAnimation {
            target: flash
            property: "opacity"
            to: 1
            duration: AtlasStyle.durationShort
        }
        NumberAnimation {
            target: flash
            property: "opacity"
            to: 0
            duration: AtlasStyle.durationLong
        }
    }

    Rectangle {
        visible: !entry.isFirst
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: AtlasStyle.spacingLarge
        height: 1
        color: Qt.alpha(Kirigami.Theme.textColor, 0.1)
    }

    GridLayout {
        id: grid
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: AtlasStyle.spacingLarge
        anchors.rightMargin: AtlasStyle.spacingLarge
        columns: entry.stacked ? 1 : 2
        columnSpacing: AtlasStyle.spacingLarge
        rowSpacing: AtlasStyle.spacingSmall

        QQC2.Label {
            objectName: "atlasFormEntryLabel"
            Layout.fillWidth: true
            Layout.minimumWidth: entry.stacked ? 0 : Kirigami.Units.gridUnit * 6
            Layout.alignment: Qt.AlignVCenter
            text: entry.label
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
            Accessible.ignored: true
            TapHandler {
                onTapped: entry._focusControl(Qt.MouseFocusReason)
            }
        }
        RowLayout {
            id: host
            Layout.fillWidth: entry.stacked
            Layout.alignment: Qt.AlignVCenter | (entry.stacked ? Qt.AlignLeft : Qt.AlignRight)
            spacing: AtlasStyle.spacingSmall
        }
        Text {
            Layout.fillWidth: true
            Layout.columnSpan: grid.columns
            visible: entry.help.length > 0
            text: entry.help
            wrapMode: Text.Wrap
            font.family: AtlasStyle.fontFamily
            font.pointSize: AtlasStyle.fontSizeCaption
            color: AtlasStyle.textMuted
            textFormat: Text.PlainText
            Accessible.ignored: true
        }
        RowLayout {
            Layout.fillWidth: true
            Layout.columnSpan: grid.columns
            visible: entry.shownError.length > 0
            spacing: AtlasStyle.spacingSmall
            Symbol {
                icon: Symbols.Error
                size: Kirigami.Units.iconSizes.small
                color: AtlasStyle.error
                Layout.alignment: Qt.AlignTop
            }
            Text {
                Layout.fillWidth: true
                text: entry.shownError
                wrapMode: Text.Wrap
                font.family: AtlasStyle.fontFamily
                font.pointSize: AtlasStyle.fontSizeCaption
                color: AtlasStyle.error
                textFormat: Text.PlainText
                Accessible.ignored: true
            }
        }
    }

    // The control's outline turns red, for a control that draws no error of its own.
    Rectangle {
        parent: entry._control
        z: 10
        width: parent ? parent.width : 0
        height: parent ? parent.height : 0
        visible: entry.shownError.length > 0 && entry._control !== null && entry._control["hasError"] !== true
        radius: AtlasStyle.radiusSmall
        color: "transparent"
        border.width: 1
        border.color: AtlasStyle.error
        enabled: false
        Accessible.ignored: true
    }
}
