pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

// The window of an Atlas app. With "Transparency and blur" on (and the
// compositor blurring), the window background is `AtlasStyle.base` at
// `blurAlpha` over a blurred desktop, Mica style; otherwise it is the plain
// opaque background, exactly as before. Put `sidebarColor(base)` on a sidebar
// so it is a little more see-through; Section cards stay nearly opaque.
//
// `widthClass` says how roomy the window is (Compact, Medium or Wide), and
// `sidebarCollapsed` is true in Compact, so every app folds its sidebar to
// icons at the same width:
//
//   AtlasWindow {
//       AtlasSidebar {
//           compact: window.sidebarCollapsed
//           ...
//       }
//   }
//
// `stateKey` (empty: off) remembers the window: its width, height and whether
// it was maximised are saved under "Window-<stateKey>" in the app's settings
// file (AtlasSettings, a moment after a change) and restored when the window
// first shows, clamped to the screen. A sidebar's or split view's size is
// saved the same way by the app (see AtlasSettings).
//
// A second launch of an app started with atlas_app_run raises this window
// (with the launcher's activation token, so Wayland lets it come up) and
// exits; nothing is needed here.
//
// Frameless mode is opt-in: give the window an AtlasHeaderBar as its `header`
// and the window draws its own title row (title, main tools and the window
// buttons, in one) instead of KWin's title bar:
//
//   AtlasWindow {
//       header: AtlasHeaderBar { actions: [saveAction, openAction] }
//   }
//
// Then the window has the Qt.FramelessWindowHint, a hairline border (none when
// maximised or full screen), and invisible handles along its edges (6 px deep,
// with 16 px L-shaped corners) that resize it through the compositor
// (startSystemResize), with the right cursors. The
// header moves the window and maximises it on a double click. The header sits
// above the content, as with any ApplicationWindow `header`, so it composes
// with Kirigami page stacks inside (their global toolbars are separate).
// Without an AtlasHeaderBar nothing changes: KWin decorates the window.
QQC2.ApplicationWindow {
    id: root

    enum WidthClass {
        Compact,
        Medium,
        Wide
    }

    // Width classes: see docs/reference/atlas-ui/atlas-window.md.
    property real compactBreakpoint: 30
    property real wideBreakpoint: 60
    readonly property real _compactAt: (Number.isFinite(root.compactBreakpoint) && root.compactBreakpoint > 0 ? root.compactBreakpoint : 30) * Kirigami.Units.gridUnit
    readonly property real _wideAt: (Number.isFinite(root.wideBreakpoint) && root.wideBreakpoint > 0 ? root.wideBreakpoint : 60) * Kirigami.Units.gridUnit
    readonly property int widthClass: root.width < root._compactAt ? AtlasWindow.WidthClass.Compact : root._compactAt >= root._wideAt || root.width >= root._wideAt ? AtlasWindow.WidthClass.Wide : AtlasWindow.WidthClass.Medium
    // True in Compact: show the sidebar as icons only (AtlasSidebar.compact).
    readonly property bool sidebarCollapsed: root.widthClass === AtlasWindow.WidthClass.Compact

    // Names the saved window state; empty keeps none.
    property string stateKey

    // True while the window is drawn over blur.
    readonly property bool blurred: Appearance.effective
    property real blurAlpha: 0.80
    // How much more see-through the sidebar is, as a factor on blurAlpha.
    property real sidebarFactor: 0.8

    // `base` with the window's alpha (times the sidebar's, for a sidebar), or
    // unchanged when there is no blur.
    function tinted(base: color, factor: real): color {
        return root.blurred ? Qt.alpha(base, root.blurAlpha * factor) : base;
    }
    function sidebarColor(base: color): color {
        return tinted(base, root.sidebarFactor);
    }

    // Queues a toast. See docs/reference/atlas-ui/atlas-window.md.
    function toast(text: var, options: var): void {
        const t = text === undefined || text === null ? "" : String(text);
        const o = options !== null && typeof options === "object" ? options : ({});
        if (t.length === 0) {
            return;
        }
        const error = o.kind === "error";
        const requested = typeof o.timeout === "number" && Number.isFinite(o.timeout) && o.timeout > 0 ? o.timeout : (error ? 5000 : 2500);
        const item = {
            text: t,
            actionText: typeof o.actionText === "string" ? o.actionText : "",
            onAction: typeof o.onAction === "function" ? o.onAction : null,
            timeout: Math.max(1, Math.min(60000, Math.round(requested)))
        };
        const last = root._toasts.length > 0 ? root._toasts[root._toasts.length - 1] : root._toastCur;
        if (last && last.text === item.text && last.actionText === item.actionText && last.onAction === item.onAction) {
            return;
        }
        root._toasts.push(item);
        // A bound on the queue: the oldest waiting toast goes first.
        while (root._toasts.length > root._maxToasts) {
            root._toasts.shift();
        }
        root._nextToast();
    }
    // Opens a ConfirmDialog. See docs/reference/atlas-ui/atlas-window.md.
    function confirm(options: var, done: var): var {
        const o = options !== null && typeof options === "object" ? options : ({});
        const cb = typeof done === "function" ? done : null;
        if (!root.visible) {
            // Nothing to open it in: answered at once.
            if (cb) {
                try {
                    cb(false);
                } catch (e) {
                    console.warn("AtlasWindow.confirm: done failed:", e);
                }
            }
            return null;
        }
        const raw = root._confirmComponent.createObject(root.contentItem);
        const dlg = raw as ConfirmDialog;
        if (!dlg) {
            if (cb) {
                cb(false);
            }
            return null;
        }
        if (typeof o.title === "string") {
            dlg.title = o.title;
        }
        if (typeof o.text === "string") {
            dlg.text = o.text;
        }
        if (typeof o.acceptText === "string") {
            dlg.acceptText = o.acceptText;
        }
        if (typeof o.rejectText === "string") {
            dlg.rejectText = o.rejectText;
        }
        dlg.destructive = o.destructive === true;
        dlg.focusReject = dlg.destructive;
        const entry = {
            dialog: dlg,
            done: cb,
            result: false,
            finished: false
        };
        root._confirms.push(entry);
        raw["_gone"] = () => root._finishConfirm(entry, true);
        dlg.accepted.connect(() => {
            entry.result = true;
        });
        dlg.closed.connect(() => root._finishConfirm(entry, false));
        dlg.open();
        if (!dlg.visible && !dlg.opened) {
            root._finishConfirm(entry, false);
            return null;
        }
        return dlg;
    }

    // Toast and confirm state; the host items are made on first use.
    readonly property int _maxToasts: 20
    property var _toasts: []
    property var _toastCur: null
    property var _toastItem: null
    property var _confirms: []
    readonly property Component _toastComponent: Component {
        Toast {
            id: host
            // The queue moves on when the toast itself says it is over, not
            // when it stops being visible (the window may be hidden).
            // One turn later: showing the next toast from inside the change
            // would loop on `_showing`.
            Component.onCompleted: host._showingChanged.connect(() => Qt.callLater(root._toastEnded))
            onActionTriggered: {
                const cb = root._toastCur ? root._toastCur.onAction : null;
                if (cb) {
                    try {
                        cb();
                    } catch (e) {
                        console.warn("AtlasWindow.toast: onAction failed:", e);
                    }
                }
            }
        }
    }
    readonly property Component _confirmComponent: Component {
        ConfirmDialog {
            // Set by confirm(): answers the caller when the dialog is destroyed.
            property var _gone: null
            Component.onDestruction: {
                if (_gone) {
                    _gone();
                }
            }
        }
    }
    function _toastEnded(): void {
        if (root._toastItem !== null && !root._toastItem._showing && root._toastCur !== null) {
            root._toastCur = null;
            root._nextToast();
        }
    }
    function _nextToast(): void {
        if (root._toastCur !== null || root._toasts.length === 0) {
            return;
        }
        if (root._toastItem === null) {
            root._toastItem = root._toastComponent.createObject(root.contentItem);
            if (root._toastItem === null) {
                root._toasts = [];
                return;
            }
        }
        const next = root._toasts.shift();
        root._toastCur = next;
        root._toastItem.interval = next.timeout;
        if (next.actionText.length > 0) {
            root._toastItem.showAction(next.text, next.actionText);
        } else {
            root._toastItem.show(next.text);
        }
    }
    // Answers a confirmation once. `destroying`: the dialog is already going.
    function _finishConfirm(entry: var, destroying: bool): void {
        if (entry.finished) {
            return;
        }
        entry.finished = true;
        const i = root._confirms.indexOf(entry);
        if (i >= 0) {
            root._confirms.splice(i, 1);
        }
        if (destroying) {
            entry.result = false;
        }
        if (entry.done) {
            try {
                entry.done(entry.result);
            } catch (e) {
                console.warn("AtlasWindow.confirm: done failed:", e);
            }
        }
        if (!destroying) {
            entry.dialog.destroy();
        }
    }
    // A window that hides or goes away answers every open confirmation with false.
    function _finishAllConfirms(destroying: bool): void {
        for (const e of root._confirms.slice()) {
            e.result = false;
            root._finishConfirm(e, destroying);
        }
    }

    // The header, when it is an AtlasHeaderBar: the window is then frameless.
    readonly property AtlasHeaderBar _atlasHeader: root.header as AtlasHeaderBar
    readonly property bool frameless: root._atlasHeader !== null
    // The window can be resized by the handles: frameless and in a normal state.
    readonly property bool _resizable: root.frameless && root.visibility !== Window.Maximized && root.visibility !== Window.FullScreen
    flags: root.frameless ? Qt.Window | Qt.FramelessWindowHint : Qt.Window

    // Test hook: replaces startSystemResize(edges).
    property var _resizeHook: null
    function _startResize(edges: int) {
        if (_resizeHook) {
            _resizeHook(edges);
        } else {
            root.startSystemResize(edges);
        }
    }
    // The handles: the edges each one resizes and its cursor. A corner is two
    // strips (`axis` "h" along the top or bottom edge, "v" along the side), an
    // L that is easy to grab without reaching into the header's buttons.
    readonly property var _handles: [
        { edges: Qt.TopEdge | Qt.LeftEdge, axis: "h", cursor: Qt.SizeFDiagCursor },
        { edges: Qt.TopEdge | Qt.LeftEdge, axis: "v", cursor: Qt.SizeFDiagCursor },
        { edges: Qt.TopEdge, axis: "", cursor: Qt.SizeVerCursor },
        { edges: Qt.TopEdge | Qt.RightEdge, axis: "h", cursor: Qt.SizeBDiagCursor },
        { edges: Qt.TopEdge | Qt.RightEdge, axis: "v", cursor: Qt.SizeBDiagCursor },
        { edges: Qt.LeftEdge, axis: "", cursor: Qt.SizeHorCursor },
        { edges: Qt.RightEdge, axis: "", cursor: Qt.SizeHorCursor },
        { edges: Qt.BottomEdge | Qt.LeftEdge, axis: "h", cursor: Qt.SizeBDiagCursor },
        { edges: Qt.BottomEdge | Qt.LeftEdge, axis: "v", cursor: Qt.SizeBDiagCursor },
        { edges: Qt.BottomEdge, axis: "", cursor: Qt.SizeVerCursor },
        { edges: Qt.BottomEdge | Qt.RightEdge, axis: "h", cursor: Qt.SizeFDiagCursor },
        { edges: Qt.BottomEdge | Qt.RightEdge, axis: "v", cursor: Qt.SizeFDiagCursor }
    ]
    // How deep the handles reach in from the edge, and how far a corner runs
    // along each edge.
    readonly property real _grip: 6
    readonly property real _cornerGrip: 16

    // An alpha surface only while blurred: an opaque window otherwise, as before.
    color: root.blurred ? "transparent" : AtlasStyle.base
    background: Rectangle {
        color: root.tinted(AtlasStyle.base, 1)
        border.width: root._resizable ? 1 : 0
        border.color: AtlasStyle.separator
    }

    Repeater {
        // The window's own root item, above the header (the content control
        // the header sits beside would put the handles below it).
        parent: Window.contentItem
        model: root._resizable ? root._handles : []

        MouseArea {
            id: handle

            required property var modelData
            readonly property int _edges: modelData.edges
            readonly property bool _left: (_edges & Qt.LeftEdge) !== 0
            readonly property bool _right: (_edges & Qt.RightEdge) !== 0
            readonly property bool _top: (_edges & Qt.TopEdge) !== 0
            readonly property bool _bottom: (_edges & Qt.BottomEdge) !== 0
            readonly property bool _corner: (_left || _right) && (_top || _bottom)

            // Sides run between the corners. The top side stops short of the
            // header's window buttons and menu button, and so do the top
            // corners' strips along the top edge (they stop at the group's
            // margin), so no handle covers the top pixels of a button.
            readonly property bool _alongTop: handle._corner ? handle.modelData.axis === "h" : handle._top || handle._bottom
            // A corner's length, at most half the window so the corners never overlap.
            readonly property real _len: Math.min(root._cornerGrip, root.width / 2, root.height / 2)
            readonly property var _header: root._atlasHeader
            readonly property real _arm: handle._corner && handle._top && handle._alongTop && handle._header ? (handle._left ? (handle._header._freeStart > handle._header._startMargin ? Math.min(_len, handle._header._startMargin) : _len) : (handle._header._freeEnd > handle._header._endMargin ? Math.min(_len, handle._header._endMargin) : _len)) : _len
            readonly property bool _topSide: handle._top && !handle._corner
            readonly property real _from: _topSide && handle._header ? Math.max(_len, handle._header._freeStart) : _len
            readonly property real _to: _topSide && handle._header ? Math.max(_from, root.width - Math.max(_len, handle._header._freeEnd)) : root.width - _len
            x: handle._left ? 0 : handle._right ? root.width - (handle._corner && handle._alongTop ? _arm : root._grip) : handle._from
            y: handle._top ? 0 : handle._bottom ? root.height - (handle._corner && !handle._alongTop ? _len : root._grip) : _len
            width: handle._corner ? (handle._alongTop ? _arm : root._grip) : handle._left || handle._right ? root._grip : Math.max(0, handle._to - handle._from)
            height: handle._corner ? (handle._alongTop ? root._grip : _len) : handle._top || handle._bottom ? root._grip : Math.max(0, root.height - 2 * _len)
            z: 1000
            acceptedButtons: Qt.LeftButton
            hoverEnabled: true
            cursorShape: modelData.cursor
            onPressed: root._startResize(handle._edges)
        }
    }

    function syncBlur() {
        Appearance.applyBlur(root);
    }
    onBlurredChanged: syncBlur()
    // Nothing tells us when KWin's blur effect is switched on or off:
    // check again when the window shows and when it gets focus.
    onVisibleChanged: if (visible) {
        Appearance.refresh();
        syncBlur();
        _firstShow();
    } else {
        root._finishAllConfirms(false);
    }
    onActiveChanged: if (active) {
        Appearance.refresh();
        syncBlur();
    }
    // The platform window (on Wayland, the surface) exists from here on.
    onSceneGraphInitialized: syncBlur()
    Component.onDestruction: root._finishAllConfirms(true)
    Component.onCompleted: {
        _restoreSize();
        if (visible) {
            syncBlur();
            _firstShow();
        }
    }

    // Window state (stateKey). Nothing is saved until the saved size has been
    // applied, so the defaults never overwrite it.
    property bool _stateReady: false
    property bool _shown: false
    readonly property AtlasSettings _state: AtlasSettings {
        group: root.stateKey.length > 0 ? "Window-" + root.stateKey : ""
    }
    function _restoreSize() {
        if (root.stateKey.length > 0) {
            const screen = root.screen;
            // 16384 when the screen is not known yet: a rewritten settings
            // file must not open a window of any size.
            const maxW = screen && screen.desktopAvailableWidth > 0 ? screen.desktopAvailableWidth : 16384;
            const maxH = screen && screen.desktopAvailableHeight > 0 ? screen.desktopAvailableHeight : 16384;
            const w = root._state.value("Width", 0);
            const h = root._state.value("Height", 0);
            if (w >= 100 && h >= 100) {
                // Clamped: a screen smaller than last time must not hide the window.
                root.width = Math.max(root.minimumWidth, Math.min(w, maxW));
                root.height = Math.max(root.minimumHeight, Math.min(h, maxH));
            }
        }
        root._stateReady = true;
    }
    function _firstShow() {
        if (root._shown) {
            return;
        }
        root._shown = true;
        if (root.stateKey.length > 0 && root._state.value("Maximized", false)) {
            root.visibility = Window.Maximized;
        }
    }
    function _saveState() {
        if (!root._stateReady || root.stateKey.length === 0 || !root._shown) {
            return;
        }
        if (root.visibility === Window.Windowed) {
            root._state.setValue("Width", Math.round(root.width));
            root._state.setValue("Height", Math.round(root.height));
            root._state.setValue("Maximized", false);
        } else if (root.visibility === Window.Maximized) {
            // The size stays what it was before: that is where un-maximising goes.
            root._state.setValue("Maximized", true);
        }
    }
    onWidthChanged: _saveState()
    onHeightChanged: _saveState()
    onVisibilityChanged: _saveState()
}
