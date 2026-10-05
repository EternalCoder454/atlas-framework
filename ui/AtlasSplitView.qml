import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

// Panes side by side (or stacked) with a draggable divider in the Atlas look:
// a thin separator line inside a wider invisible grab area, tinted on hover
// and while dragged. Put the panes inside as children and size them with
// SplitView.preferredWidth / minimumWidth / fillWidth (SplitView.* attached
// properties, as on Qt's own SplitView).
//
//   AtlasSplitView {
//       stateKey: "main"          // remember the sizes between runs
//       Sidebar { SplitView.preferredWidth: 220; SplitView.minimumWidth: 140 }
//       Content { SplitView.fillWidth: true }
//   }
//
// `stateKey` (empty by default): when set, the sizes are saved under
// "AtlasSplitView-<stateKey>" in the app's settings file (AtlasSettings) a
// moment after a drag, and
// restored when the view is created. Apps with their own storage use
// saveSizes() (a base64 string) and restoreSizes(string) instead.
//
// With `collapsible`, a horizontal view narrower than `collapseWidth` shows
// one pane at a time (`currentPane`; move with showPane()), and a pane other
// than the first gets a Back row; see docs/reference/atlas-ui/atlas-split-view.md.
QQC2.SplitView {
    id: control

    // Names the saved sizes; empty keeps them for this run only.
    property string stateKey
    // Below `collapseWidth` show one pane at a time (horizontal views only).
    property bool collapsible: false
    property real collapseWidth: Kirigami.Units.gridUnit * 40
    // One pane at a time now.
    readonly property bool collapsed: control.collapsible && control.orientation === Qt.Horizontal && control.width > 0 && control.width < control.collapseWidth
    // The pane shown while collapsed; kept across a resize.
    property int currentPane: 0

    // Moves to pane `i` (an index into the panes; one out of range is
    // ignored). The pane slides in, instantly under reduced motion.
    function showPane(i: int): void {
        if (i >= 0 && i < control.count) {
            control.currentPane = i;
        }
    }

    // The pane sizes as a base64 string, for the app's own storage.
    function saveSizes(): string {
        const buf = control.saveState();
        if (!buf) {
            return "";
        }
        const bytes = new Uint8Array(buf);
        let bin = "";
        for (let i = 0; i < bytes.length; ++i) {
            bin += String.fromCharCode(bytes[i]);
        }
        return Qt.btoa(bin);
    }

    // Applies sizes from saveSizes(); returns false for a string that is
    // empty or does not fit this view (nothing changes then).
    function restoreSizes(sizes: string): bool {
        if (typeof sizes !== "string" || sizes.length === 0) {
            return false;
        }
        let bin = "";
        try {
            bin = Qt.atob(sizes);
        } catch (e) {
            return false;
        }
        const bytes = new Uint8Array(bin.length);
        for (let i = 0; i < bin.length; ++i) {
            bytes[i] = bin.charCodeAt(i);
        }
        return control.restoreState(bytes.buffer);
    }

    function _scheduleSave() {
        if (control.stateKey.length > 0 && _ready) {
            saveTimer.restart();
        }
    }
    // The sizes are not written while collapsed (one pane fills the view);
    // the ones from before are kept for when it expands.
    function _saveNow() {
        saveTimer.stop();
        if (control.stateKey.length > 0 && !control.collapsed) {
            control._store.setValue("Sizes", control.saveSizes());
        }
    }
    property bool _ready: false
    // The sizes as they were when the view collapsed.
    property string _expandedSizes: ""
    // The panes that already carry the Binding that hides them.
    property var _hooked: null
    // Whether focus was inside the view when it last moved.
    property bool _hadFocus: false
    // The panes shown before this one, for Back.
    property var _history: []
    property int _previous: 0
    property bool _goingBack: false
    // The pane shown while collapsed, in range.
    readonly property int _shown: control._paneShown()
    function _paneShown(): int {
        return Math.max(0, Math.min(control.currentPane, control.count - 1));
    }
    // Test hook: the push's length.
    property int _pushDuration: AtlasStyle.duration
    readonly property bool _sliding: pushAnim.running

    // Whether collapsing hides `pane` now.
    function _hides(pane: Item): bool {
        if (!control._ready || !control.collapsed) {
            return false;
        }
        const shown = control._paneShown();
        for (let i = 0; i < control.count; ++i) {
            if (control.itemAt(i) === pane) {
                return i !== shown;
            }
        }
        return false;
    }
    // Every pane gets a Binding on its `visible` that hides it while collapsed
    // and is off otherwise, so a pane's own `visible` binding is kept.
    Component {
        id: hiderComp
        Binding {
            property: "visible"
            value: false
            restoreMode: Binding.RestoreBindingOrValue
        }
    }
    function _syncPanes(): void {
        if (!control._ready) {
            return;
        }
        if (control._hooked === null) {
            control._hooked = new WeakSet();
        }
        for (let i = 0; i < control.count; ++i) {
            const pane = control.itemAt(i);
            if (pane && !control._hooked.has(pane)) {
                control._hooked.add(pane);
                hiderComp.createObject(pane, {
                    "target": pane,
                    "when": Qt.binding(() => control._hides(pane))
                });
            }
        }
        Qt.callLater(control._restoreFocus);
    }

    function _contains(item: Item): bool {
        for (let p = item; p; p = p.parent) {
            if (p === control) {
                return true;
            }
        }
        return false;
    }
    function _firstFocusable(item: Item, depth: int): Item {
        if (item.activeFocusOnTab && item.visible && item.enabled) {
            return item;
        }
        if (depth < 12) {
            for (let i = 0; i < item.children.length; ++i) {
                const r = control._firstFocusable(item.children[i], depth + 1);
                if (r) {
                    return r;
                }
            }
        }
        return null;
    }
    // Focus that was in a pane or the Back row when it hid moves to the
    // shown pane.
    function _restoreFocus(): void {
        const win = control.Window.window;
        if (!control._hadFocus || !win) {
            return;
        }
        const f = win.activeFocusItem;
        if (f && f !== win.contentItem) {
            return;
        }
        const pane = control.itemAt(control._paneShown());
        if (!pane || !pane.visible) {
            return;
        }
        const target = control._firstFocusable(pane, 0) ?? pane;
        target.forceActiveFocus();
    }
    Connections {
        target: control.Window.window
        function onActiveFocusItemChanged() {
            const f = control.Window.window.activeFocusItem;
            if (f && f !== control.Window.window.contentItem) {
                control._hadFocus = control._contains(f);
            }
        }
    }

    // Whether Back would go somewhere.
    function _canBack(): bool {
        return control.collapsed && control._paneShown() > 0;
    }

    // Back one pane: the one before in the history, else the one before in order.
    function _back(): void {
        if (!control._canBack()) {
            return;
        }
        const h = control._history.slice();
        let to = control._paneShown() - 1;
        while (h.length > 0) {
            const t = h.pop();
            if (t !== control._paneShown() && t >= 0 && t < control.count) {
                to = t;
                break;
            }
        }
        control._history = h;
        control._goingBack = true;
        control.currentPane = to;
        control._goingBack = false;
    }

    onCurrentPaneChanged: {
        if (control.collapsed && !control._goingBack && control._previous !== control.currentPane) {
            const h = control._history.slice();
            if (h[h.length - 1] !== control._previous) {
                h.push(control._previous);
            }
            // The oldest steps go first.
            control._history = h.length > 64 ? h.slice(h.length - 64) : h;
        }
        control._slide(control._goingBack);
        control._previous = control.currentPane;
        control._syncPanes();
    }
    onCountChanged: control._syncPanes()
    onCollapsedChanged: {
        if (control.collapsed) {
            // Keep a drag the timer has not written yet. The sizes are taken
            // once: a drag back and forth over the width keeps the first.
            if (saveTimer.running) {
                control._saveNowForce();
            }
            if (control._expandedSizes.length === 0) {
                control._expandedSizes = control.saveSizes();
            }
        } else {
            control._history = [];
            Qt.callLater(control._restoreExpanded);
        }
        control._syncPanes();
    }
    // The sizes from before the collapse, once the panes are back.
    function _restoreExpanded(): void {
        if (control.collapsed || control._expandedSizes.length === 0) {
            return;
        }
        const sizes = control._expandedSizes;
        control._expandedSizes = "";
        control.restoreSizes(sizes);
    }
    function _saveNowForce() {
        saveTimer.stop();
        if (control.stateKey.length > 0) {
            control._store.setValue("Sizes", control.saveSizes());
        }
    }

    // The incoming pane slides in from the end (from a little way back when
    // going back); the end state is the same with no motion.
    function _slide(back: bool): void {
        pushAnim.stop();
        slide.x = 0;
        if (control._ready && control.collapsed && control._pushDuration > 0 && control.width > 0) {
            const dir = control.mirrored ? -1 : 1;
            pushAnim.from = back ? -dir * control.width * 0.3 : dir * control.width;
            pushAnim.restart();
        }
    }

    // The back row: shown over the top while collapsed on any pane after the
    // first. The panes start below it.
    // (`padding` still counts; set it rather than `topPadding`.)
    topPadding: control.padding + (backRow.visible ? backRow.height : 0)
    // A pane sliding in stays inside the view.
    clip: control.collapsed
    Item {
        id: backRow
        parent: control
        x: 0
        y: 0
        width: control.width
        height: backButton.implicitHeight + AtlasStyle.spacing * 2
        visible: control.collapsed && control._shown > 0
        z: 2
        ToolbarButton {
            id: backButton
            x: control.mirrored ? parent.width - width - AtlasStyle.spacing : AtlasStyle.spacing
            anchors.verticalCenter: parent.verticalCenter
            symbol: Symbols.ArrowBack
            text: qsTr("Back")
            focusable: true
            // The arrow points the other way in a right-to-left layout.
            transform: Scale {
                origin.x: backButton.width / 2
                xScale: control.mirrored ? -1 : 1
            }
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Back")
            onClicked: control._back()
        }
    }
    // Alt+Left goes back a pane while focus is inside and there is a pane to
    // go back to; otherwise an enclosing AtlasNavigationStack gets it. The
    // override keeps a stack's window-wide shortcut from firing first.
    Keys.onShortcutOverride: event => {
        if (event.key === Qt.Key_Left && (event.modifiers & Qt.AltModifier) && control._canBack()) {
            event.accepted = true;
        }
    }
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Left && (event.modifiers & Qt.AltModifier) && control._canBack()) {
            control._back();
            event.accepted = true;
        }
    }
    // The mouse Back button takes the click exclusively while there is a pane
    // to go back to, so an enclosing stack does not pop as well.
    TapHandler {
        acceptedButtons: Qt.BackButton
        gesturePolicy: TapHandler.WithinBounds
        grabPermissions: PointerHandler.CanTakeOverFromAnything
        enabled: control._canBack()
        onTapped: control._back()
    }
    Translate {
        id: slide
    }
    NumberAnimation {
        id: pushAnim
        target: slide
        property: "x"
        to: 0
        duration: control._pushDuration
        easing.type: Easing.OutCubic
    }

    onResizingChanged: if (!resizing) {
        _scheduleSave();
    }
    onWidthChanged: _scheduleSave()
    onHeightChanged: _scheduleSave()

    Component.onCompleted: {
        if (control.stateKey.length > 0) {
            control.restoreSizes(control._store.value("Sizes", ""));
        }
        _ready = true;
        // The panes slide as one: the content item carries the offset.
        if (control.contentItem) {
            control.contentItem.transform = slide;
        }
        control._previous = control.currentPane;
        control._syncPanes();
    }
    Component.onDestruction: if (saveTimer.running) {
        _saveNow();
    }

    Timer {
        id: saveTimer
        interval: 500
        onTriggered: control._saveNow()
    }

    // Only read and written when stateKey is set.
    readonly property AtlasSettings _store: AtlasSettings {
        group: control.stateKey.length > 0 ? "AtlasSplitView-" + control.stateKey : ""
    }

    handle: Item {
        id: handle

        readonly property bool _vertical: control.orientation === Qt.Vertical
        readonly property bool _active: QQC2.SplitHandle.hovered || QQC2.SplitHandle.pressed

        // The line is 1 px; the rest is the grab area.
        implicitWidth: _vertical ? control.width : 7
        implicitHeight: _vertical ? 7 : control.height

        Accessible.role: Accessible.Separator
        Accessible.name: qsTr("Pane divider")

        Rectangle {
            anchors.centerIn: parent
            width: handle._vertical ? parent.width : (handle._active ? 3 : 1)
            height: handle._vertical ? (handle._active ? 3 : 1) : parent.height
            radius: handle._active ? width / 2 : 0
            color: handle.QQC2.SplitHandle.pressed ? AtlasStyle.accent : handle.QQC2.SplitHandle.hovered ? Qt.alpha(AtlasStyle.accent, 0.6) : AtlasStyle.controlBorder
        }
        HoverHandler {
            cursorShape: handle._vertical ? Qt.SplitVCursor : Qt.SplitHCursor
        }
    }
}
