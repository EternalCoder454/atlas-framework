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
    readonly property bool collapsed: control.collapsible && control.orientation === Qt.Horizontal && control.width < control.collapseWidth
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
    // The panes this view hid, to show them again.
    property var _hidden: []
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

    // Hides every pane but the shown one while collapsed, and shows them all
    // otherwise.
    function _syncPanes(): void {
        if (!control._ready) {
            return;
        }
        const hidden = control._hidden.slice();
        for (let i = 0; i < control.count; ++i) {
            const pane = control.itemAt(i);
            if (!pane) {
                continue;
            }
            const at = hidden.indexOf(pane);
            if (control.collapsed && i !== control._paneShown()) {
                if (pane.visible) {
                    pane.visible = false;
                    hidden.push(pane);
                }
            } else if (at >= 0) {
                pane.visible = true;
                hidden.splice(at, 1);
            }
        }
        control._hidden = hidden.filter(p => p !== null && p !== undefined);
    }

    // Back one pane: the one before in the history, else the one before in order.
    function _back(): void {
        if (!control.collapsed || control._paneShown() <= 0) {
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
            h.push(control._previous);
            control._history = h;
        }
        control._slide(control._goingBack);
        control._previous = control.currentPane;
        control._syncPanes();
    }
    onCountChanged: control._syncPanes()
    onCollapsedChanged: {
        if (control.collapsed) {
            // Keep a drag the timer has not written yet, then the sizes.
            if (saveTimer.running) {
                control._saveNowForce();
            }
            control._expandedSizes = control.saveSizes();
        } else {
            control._history = [];
        }
        control._syncPanes();
        if (!control.collapsed && control._expandedSizes.length > 0) {
            const sizes = control._expandedSizes;
            control._expandedSizes = "";
            Qt.callLater(() => control.restoreSizes(sizes));
        }
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
    topPadding: backRow.visible ? backRow.height : 0
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
    Shortcut {
        sequence: "Alt+Left"
        enabled: control.collapsed && control._shown > 0 && control.visible
        onActivated: control._back()
    }
    TapHandler {
        acceptedButtons: Qt.BackButton
        grabPermissions: PointerHandler.ApprovesTakeOverByAnything
        enabled: control.collapsed && control._shown > 0
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
