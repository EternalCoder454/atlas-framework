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

    // No error of any kind. An entry that is disabled or that the app hid
    // has none. (One on a page that is not shown still counts.)
    readonly property bool valid: !entry.enabled || entry._selfHidden || (entry.errorText.length === 0 && !entry._missing && !entry._unacceptable)
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
    readonly property bool _unacceptable: !entry._isEmpty && entry._control !== null && entry._untyped(entry._control)["acceptableInput"] === false
    readonly property bool _autoStacked: entry._narrow || (entry._control !== null && entry._control.implicitHeight > AtlasStyle.controlHeight * 2.5)
    // Narrow: below 22 grid units, and not wide again until 24 (no flapping at
    // the threshold).
    property bool _narrow: false
    // Hidden by the app (its own `visible`, or a container's), as opposed to
    // by a page that is not shown: it went invisible while the form was visible.
    property bool _selfHidden: false
    // Latched: a field that has been a password never saves, even when a
    // "show" toggle turns the text to Normal.
    property bool _wasSecret: false
    function _checkSecret(): bool {
        entry._secret = entry._isSecret(entry._control);
        if (entry._secret) {
            entry._wasSecret = true;
        }
        return entry._secret || entry._wasSecret;
    }
    onVisibleChanged: entry._noteVisible()
    function _noteVisible(): void {
        const ref = entry._form ? entry._form : entry.parent;
        if (entry.visible) {
            entry._selfHidden = false;
        } else if (ref && ref.visible) {
            entry._selfHidden = true;
        }
    }
    // An entry hidden while its page was not shown changes nothing visible
    // then; the form coming into view settles it (Qt updates the children
    // before the form's signal).
    Connections {
        target: entry._form ? entry._form : entry.parent
        function onVisibleChanged() {
            entry._noteVisible();
        }
    }
    onWidthChanged: {
        if (entry.width > 0 && entry.width < Kirigami.Units.gridUnit * 22) {
            entry._narrow = true;
        } else if (entry.width > Kirigami.Units.gridUnit * 24) {
            entry._narrow = false;
        }
    }
    // A password, or anything that holds one: never loaded, never saved.
    // Checked by _checkSecret() rather than bound: walking the control can
    // create its deferred parts, which would re-trigger a binding.
    property bool _secret: false
    property var _warned: ({})
    property var _links: []
    property bool _a11yTaken: false
    property string _ownName: ""
    property string _ownDesc: ""
    // Where the control is, in the entry's coordinates (for the error outline).
    readonly property rect _controlRect: {
        const c = entry._control;
        if (!c) {
            return Qt.rect(0, 0, 0, 0);
        }
        // Read so that the rectangle follows every layout change.
        // Every item between the control and the entry: any of them moving or
        // resizing moves the control.
        const follow = [entry.width, entry.height, grid.x, grid.y, grid.width, grid.height];
        for (let i = c; i && i !== entry; i = i.parent) {
            follow.push(i.x, i.y, i.width, i.height);
        }
        if (follow.length === 0) {
            return Qt.rect(0, 0, 0, 0);
        }
        const p = c.mapToItem(entry, 0, 0);
        return Qt.rect(p.x, p.y, c.width, c.height);
    }
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
    readonly property bool _keyed: entry.settingKey.length > 0 && entry._prop.length > 0 && !entry._secret && !entry._wasSecret
    property bool _ready: false
    property var _wiredTo: null
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

    // Leaving counts only while the window stays active and the entry stays
    // visible: not a window switch, a closing dialog or a page change.
    onActiveFocusChanged: {
        if (entry.activeFocus) {
            entry._hadFocus = true;
        } else if (entry._hadFocus && entry.visible && Window.window && Window.window.active && !entry._popupOpen()) {
            entry._leftOnce = true;
        }
    }
    onShownErrorChanged: {
        entry._syncA11y();
        if (entry.shownError.length > 0) {
            entry._announce(entry.shownError);
        }
    }
    onLabelChanged: entry._syncA11y()
    onHelpChanged: entry._syncA11y()
    on_ControlChanged: if (entry._ready) {
        entry._attach();
        entry._load();
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
        entry._checkSecret();
        entry._noteVisible();
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
        let f = entry._untyped(entry.parent);
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

    // The controls and views an entry meets are any type; their members are
    // looked up at run time.
    function _untyped(o: var): var {
        return o;
    }

    function _findForm(): var {
        for (let p = entry._untyped(entry.parent); p; p = p.parent) {
            if (p._isAtlasForm === true) {
                return p;
            }
        }
        return null;
    }

    // A combo box's list takes the focus while it is open; that is not leaving.
    function _popupOpen(): bool {
        const c = entry._untyped(entry._control);
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

    // The property a settingKey saves.
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

    function _link(c: var, name: string, fn: var): void {
        const sig = c[name];
        if (sig && typeof sig.connect === "function") {
            sig.connect(entry, fn);
            entry._links.push({sig: sig, fn: fn});
        }
    }

    function _detach(): void {
        for (const l of entry._links) {
            try {
                l.sig.disconnect(entry, l.fn);
            } catch (e) {
                console.debug("AtlasFormEntry: the old control was already gone");
            }
        }
        entry._links = [];
        entry._a11yTaken = false;
    }

    // Names the control for a screen reader, and connects what saves its edits.
    function _attach(): void {
        const c = entry._untyped(entry._control);
        if (entry._wiredTo === c) {
            return;
        }
        entry._detach();
        entry._wiredTo = c;
        if (!c) {
            return;
        }
        entry._checkSecret();
        entry._syncA11y();
        const p = entry._prop;
        if (c["echoMode"] !== undefined && c["accepted"] !== undefined) {
            entry._link(c, "accepted", entry._returned);
        }
        if (p.length === 0) {
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
            entry._link(c, n, entry._userEdited);
        }
    }

    // The control's name is the label (its own name stays without one); its
    // description is the help and the error, then the app's own.
    function _syncA11y(): void {
        const c = entry._control;
        if (!c || entry._wiredTo !== c) {
            return;
        }
        const parts = [entry.help, entry.shownError];
        if (!entry._a11yTaken) {
            if (entry.label.length === 0 && parts.every(t => t.length === 0)) {
                return;
            }
            entry._ownName = c.Accessible.name;
            entry._ownDesc = c.Accessible.description;
            entry._a11yTaken = true;
        }
        c.Accessible.name = entry.label.length > 0 ? entry.label : entry._ownName;
        parts.push(entry._ownDesc);
        c.Accessible.description = parts.filter((t, i) => t.length > 0 && parts.indexOf(t) === i).join(", ");
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
        const c = entry._untyped(entry._control);
        if (c && c["echoMode"] !== undefined && c["acceptableInput"] === false && !event.isAutoRepeat) {
            entry._returned();
        }
        event.accepted = false;
    }

    function _warn(text: string): void {
        console.warn("AtlasFormEntry: settingKey " + JSON.stringify(entry.settingKey.slice(0, 200)) + ": " + text);
    }

    function _warnOnce(text: string): void {
        const id = entry.settingKey + "\u0000" + text;
        if (entry._warned[id] !== true) {
            entry._warned[id] = true;
            entry._warn(text);
        }
    }

    // The same rule as AtlasSettings.validKey().
    function _validKey(k: string): bool {
        return k.length > 0 && k.length <= 200 && k === k.trim() && !/^[#;]/.test(k) && !/[\[\]=]/.test(k) && !/[\u0000-\u001f\u007f]/.test(k);
    }

    // A password, or something that holds one: the item or anything in it (a
    // bounded look) is a password field, hides what is typed, asks for no
    // prediction of it or says it is a password to a screen reader.
    function _isSecret(item: var): bool {
        return entry._secretIn(item, 0, {n: 0});
    }
    function _secretIn(item: var, depth: int, budget: var): bool {
        if (!item || depth > 4 || budget.n >= 64) {
            return false;
        }
        budget.n += 1;
        if (item["revealed"] !== undefined) {
            return true;
        }
        const mode = item["echoMode"];
        if (mode !== undefined && mode !== TextInput.Normal) {
            return true;
        }
        const hints = item["inputMethodHints"];
        if (typeof hints === "number" && (hints & Qt.ImhSensitiveData) !== 0) {
            return true;
        }
        if (item.Accessible.passwordEdit === true) {
            return true;
        }
        const kids = item.children;
        for (let i = 0; i < kids.length; ++i) {
            if (entry._secretIn(kids[i], depth + 1, budget)) {
                return true;
            }
        }
        const inner = item["contentItem"];
        return !!inner && inner !== item && entry._secretIn(inner, depth + 1, budget);
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
            const text = s.value(key, "");
            return text.length <= 65536 ? {ok: true, value: text} : {ok: false};
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
        if (!entry._validKey(key)) {
            entry._warnOnce("this is not a valid settings key");
            return;
        }
        if (entry._checkSecret()) {
            entry._warnOnce("a password is not a setting, so it is neither loaded nor saved");
            return;
        }
        const p = entry._prop;
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
        // A stored shortcut is untrusted text: only its portable form is used.
        entry._applyValue = p === "sequence" ? AtlasShortcuts.portable(r.value) : r.value;
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
        if (entry._applying || entry._guard || !entry._keyed || !entry._validKey(entry.settingKey)) {
            return;
        }
        if (entry._checkSecret()) {
            // Made a password after loading: say so once, as _load() does.
            entry._warnOnce("a password is not a setting, so it is neither loaded nor saved");
            return;
        }
        const s = entry._store;
        const c = entry._untyped(entry._control);
        // Read now, not through the bindings: a text field's edit signal
        // comes before its acceptableInput is updated.
        const empty = entry._emptyOf(c);
        if (!s || !c || (!empty && c["acceptableInput"] === false) || (entry.required && empty)) {
            // A value the entry calls invalid is not saved.
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
        if (typeof v === "string" && v.length > 65536) {
            entry._warnOnce("the text is over 64 KiB and is not saved");
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

    // The control's outline turns red, for a control that draws no error of its
    // own. It is drawn here, over the control, not inside it, so it never takes
    // part in the control's own layout.
    Rectangle {
        x: entry._controlRect.x
        y: entry._controlRect.y
        width: entry._controlRect.width
        height: entry._controlRect.height
        z: 10
        visible: entry.shownError.length > 0 && entry._control !== null && entry._control.visible && entry._control.width > 0 && entry._untyped(entry._control)["hasError"] !== true
        radius: AtlasStyle.radiusSmall
        color: "transparent"
        border.width: 1
        border.color: AtlasStyle.error
        enabled: false
        Accessible.ignored: true
    }
}
