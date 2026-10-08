pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami

// A strip of document tabs in the Telamon look, after Windows 11 Notepad: each
// tab is softly rounded like a SidebarItem, with an accent tint for the
// current one (one highlight that slides to the new tab), a dot when it holds unsaved changes and a close button on
// hover. A "+" after the last tab asks for a new one. The strip scrolls
// sideways with the wheel when the tabs overflow, and keeps the current tab
// in view.
//
// The bar owns no data. `model` (a ListModel or a QAbstractItemModel) has the
// roles `title`, `modified` and `toolTip`; the app changes `currentIndex` and
// the model in answer to the signals, including moved(), which reports a tab
// dragged to a new place. Items put inside the bar sit at its far end.
//
// contextMenuRequested(index, position) asks for the tab's context menu: on a
// right click on the tab, and on the Menu key or Shift+F10 while the tab has
// the keyboard focus (Tab reaches the current tab; clicking never takes the
// focus from the editor). `position` is in the bar's coordinates, ready for
// ContextMenu.popup(tabBar, position): the pointer for a click, the tab's
// bottom-left for a key. A middle click still emits closeRequested().
Item {
    id: control

    property var model
    property int currentIndex: -1
    default property alias trailing: trailingRow.data
    // Widest a tab grows before its title is elided.
    readonly property real maxTabWidth: Kirigami.Units.gridUnit * 14

    signal activated(int index)
    signal closeRequested(int index)
    signal newRequested
    signal moved(int from, int to)
    signal contextMenuRequested(int index, point position)

    // TelamonStyle.Normal or TelamonStyle.Compact; Compact shrinks the height and
    // the vertical padding to about 75%. Follows the app-wide TelamonStyle.density
    // unless set here.
    property int density: TelamonStyle.density
    readonly property real _k: density === TelamonStyle.Compact ? 0.75 : 1

    implicitWidth: Kirigami.Units.gridUnit * 30
    implicitHeight: Math.round(Kirigami.Units.gridUnit * 1.9 * _k) + Math.round(TelamonStyle.spacingSmall * 2 * _k)
    Accessible.role: Accessible.PageTabList
    Accessible.name: qsTr("Tabs")

    // The strip follows the current tab (a new tab's index usually arrives
    // after the count changed) until the wheel scrolls it; it doesn't move
    // under a pressed or dragged tab, and catches up on release.
    property bool _follow: true
    onCurrentIndexChanged: {
        control._follow = true;
        Qt.callLater(control._followCurrent);
    }
    function _followCurrent() {
        if (control._follow && list.held === 0 && list.dragFrom < 0) {
            control.ensureCurrentVisible();
        }
    }

    function ensureCurrentVisible() {
        if (control.currentIndex >= 0 && control.currentIndex < list.count) {
            // Lay out the new tabs first, or the list scrolls by estimated widths.
            list.forceLayout();
            list.positionViewAtIndex(control.currentIndex, ListView.Contain);
        }
    }

    // Double-click on the empty strip opens a new tab.
    MouseArea {
        anchors.fill: parent
        onDoubleClicked: control.newRequested()
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: TelamonStyle.spacingSmall
        anchors.rightMargin: TelamonStyle.spacingSmall
        spacing: TelamonStyle.spacingSmall

        ListView {
            id: list

            // Where a dragged tab would land, or -1.
            property int dragFrom: -1
            property int dropAt: -1
            // Tabs pressed now: the strip doesn't scroll under the pointer.
            property int held: 0
            // The count before the last change: only a new tab is followed.
            property int lastCount: 0

            Layout.fillHeight: true
            // Hugs its tabs while they fit and shrinks to the bar (then
            // scrolls) when they don't, so the New Tab button stays in view.
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.preferredWidth: contentWidth
            Layout.maximumWidth: contentWidth
            orientation: ListView.Horizontal
            spacing: TelamonStyle.spacingXSmall
            clip: true
            // Every tab is built, so the strip scrolls by real widths, not
            // estimates that are corrected (and clamp contentX) later.
            cacheBuffer: 100000
            // Dragging belongs to reordering; the wheel scrolls.
            interactive: false
            boundsBehavior: Flickable.StopAtBounds
            model: control.model
            currentIndex: control.currentIndex
            highlightFollowsCurrentItem: false
            // The current tab's tint, one rectangle that slides (a spring with
            // a small overshoot) to the tab that becomes current. It jumps on
            // the first layout.
            highlight: Rectangle {
                id: tint
                z: -1
                visible: list.currentItem !== null
                radius: TelamonStyle.radiusSmall
                color: TelamonStyle.selection
                property Item _item: list.currentItem
                // Where the tint sits (follows the item directly) and how far it still
                // lags behind after a selection change (springs back to 0).
                property real _baseX: 0
                property real _baseY: 0
                property real _baseW: 0
                property real _baseH: 0
                property real _slideX: 0
                property real _slideW: 0
                property bool _springing: false
                property Item _shown: null
                x: tint._baseX + tint._slideX
                y: tint._baseY
                width: Math.max(0, tint._baseW + tint._slideW)
                height: tint._baseH
                Behavior on _slideX {
                    enabled: tint._springing && !TelamonStyle.reducedMotion
                    TelamonSpringAnimation {
                        expressive: true
                    }
                }
                Behavior on _slideW {
                    enabled: tint._springing && !TelamonStyle.reducedMotion
                    TelamonSpringAnimation {
                        expressive: true
                    }
                }
                function _sync() {
                    tint._baseX = tint._item ? tint._item.x + 0 : 0;
                    tint._baseY = tint._item ? tint._item.y + 0 : 0;
                    tint._baseW = tint._item ? tint._item.width : 0;
                    tint._baseH = tint._item ? tint._item.height : 0;
                }
                // Only a selection change slides, and only from a tint that was showing.
                Component.onCompleted: {
                    tint._sync();
                    tint._shown = tint._item;
                }
                on_ItemChanged: {
                    const oldX = x;
                    const oldW = width;
                    const from = tint._shown !== null && tint._item !== null;
                    tint._springing = false;
                    tint._slideX = 0;
                    tint._slideW = 0;
                    tint._sync();
                    tint._shown = tint._item;
                    if (from) {
                        tint._slideX = oldX - tint._baseX;
                        tint._slideW = oldW - tint._baseW;
                        tint._springing = true;
                        tint._slideX = 0;
                        tint._slideW = 0;
                    }
                }
                Connections {
                    target: tint._item
                    function onXChanged() { tint._sync(); }
                    function onYChanged() { tint._sync(); }
                    function onWidthChanged() { tint._sync(); }
                    function onHeightChanged() { tint._sync(); }
                }
            }
            // A new model: follow its current tab.
            onModelChanged: {
                control._follow = true;
                list.lastCount = 0;
            }
            onCountChanged: {
                // A tab was added: follow again. A closed background tab
                // keeps the user's wheel scroll.
                if (list.count > list.lastCount) {
                    control._follow = true;
                }
                list.lastCount = list.count;
                Qt.callLater(control._followCurrent);
            }
            // The current tab's title turns medium weight, so it grows a
            // little after it was scrolled to.
            Connections {
                target: list.currentItem
                function onWidthChanged() { Qt.callLater(control._followCurrent); }
            }
            onWidthChanged: Qt.callLater(control._followCurrent)

            WheelHandler {
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: event => {
                    const d = event.angleDelta.x !== 0 ? event.angleDelta.x : event.angleDelta.y;
                    // The content starts at originX, not 0, once tabs of
                    // different widths came and went.
                    const max = list.originX + Math.max(0, list.contentWidth - list.width);
                    list.contentX = Math.max(list.originX, Math.min(max, list.contentX - d * (list.mirrored ? -1 : 1)));
                    control._follow = false;
                }
            }

            readonly property bool mirrored: LayoutMirroring.enabled

            // Where the dragged tab would land. Only the tabs in view can be
            // the target (the wheel scrolls during a drag); in the spacing
            // between two tabs, the nearer one; past either end, the first or
            // last.
            // How far the dragged tab has moved from its place.
            property real dragShift: 0
            function updateDrop() {
                const tab = list.itemAtIndex(list.dragFrom);
                if (!tab) {
                    return;
                }
                const centre = Math.max(list.contentX, Math.min(list.contentX + list.width - 1, tab.x + tab.width / 2 + list.dragShift));
                const y = list.height / 2;
                let at = list.indexAt(centre, y);
                if (at < 0) {
                    const before = list.indexAt(centre - list.spacing, y);
                    const after = list.indexAt(centre + list.spacing, y);
                    const a = list.itemAtIndex(before);
                    const b = list.itemAtIndex(after);
                    if (a && b) {
                        at = centre - (a.x + a.width) <= b.x - centre ? before : after;
                    } else {
                        at = a ? before : after;
                    }
                }
                if (at >= 0) {
                    list.dropAt = at;
                } else {
                    const start = centre < list.originX + list.contentWidth / 2;
                    list.dropAt = start !== list.mirrored ? 0 : list.count - 1;
                }
            }
            onContentXChanged: {
                if (list.dragFrom >= 0) {
                    list.updateDrop();
                }
            }

            delegate: T.AbstractButton {
                id: tab

                required property int index
                required property var model
                readonly property bool current: index === control.currentIndex
                readonly property string title: model.title ?? ""
                readonly property bool modified: model.modified ?? false
                readonly property string toolTipText: (model.toolTip ?? "").length > 0 ? model.toolTip : title
                readonly property bool showClose: hoverTracker.hovered || current
                property real dragX: 0

                implicitWidth: Math.min(control.maxTabWidth, contentItem.implicitWidth + leftPadding + rightPadding)
                implicitHeight: Math.round(Kirigami.Units.gridUnit * 1.9 * control._k)
                height: list.height
                leftPadding: TelamonStyle.spacingLarge
                rightPadding: TelamonStyle.spacingSmall
                hoverEnabled: true
                // Tab reaches the current tab only, and a click never takes the
                // focus (the editor keeps it).
                focusPolicy: tab.current ? Qt.TabFocus : Qt.NoFocus
                z: dragHandler.active ? 2 : 0
                opacity: dragHandler.active ? 0.85 : 1
                transform: Translate {
                    x: tab.dragX
                }

                Accessible.role: Accessible.PageTab
                //: Name of a tab with unsaved changes: %1 is the document title
                Accessible.name: tab.modified ? qsTr("%1, modified").arg(tab.title) : tab.title
                Accessible.selectable: true
                Accessible.selected: tab.current
                Accessible.onPressAction: control.activated(tab.index)

                function requestMenuFromKey() {
                    control.contextMenuRequested(tab.index, tab.mapToItem(control, 0, tab.height));
                }
                Keys.onMenuPressed: event => {
                    tab.requestMenuFromKey();
                    event.accepted = true;
                }
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_F10 && (event.modifiers & Qt.ShiftModifier)) {
                        tab.requestMenuFromKey();
                        event.accepted = true;
                    }
                }

                // Whether this tab counts in list.held, so a release during
                // teardown can't give the hold back twice.
                property bool _holding: false
                function _release() {
                    if (tab._holding) {
                        tab._holding = false;
                        list.held -= 1;
                    }
                }
                onPressedChanged: {
                    if (tab.pressed && !tab._holding) {
                        tab._holding = true;
                        list.held += 1;
                    } else if (!tab.pressed) {
                        tab._release();
                        Qt.callLater(control._followCurrent);
                    }
                }
                // Tabs removed before this one move it: the drag follows.
                onIndexChanged: {
                    if (dragHandler.active && tab.index >= 0) {
                        list.dragFrom = tab.index;
                        list.updateDrop();
                    }
                }
                // Removed mid-press or mid-drag (a model reset, a tab closed
                // by the app): give back what this tab held. Only the active
                // handler owns the drag state; the index may already be gone.
                Component.onDestruction: {
                    tab._release();
                    if (dragHandler.active) {
                        list.dragFrom = -1;
                        list.dropAt = -1;
                        list.dragShift = 0;
                    }
                    Qt.callLater(control._followCurrent);
                }
                onPressed: {
                    if (!tab.current) {
                        control.activated(tab.index);
                    }
                }

                // Made when the tab is first hovered, not for every tab.
                property var _tip: null
                onHoveredChanged: if (tab.hovered && !tab._tip) tab._tip = tipComponent.createObject(tab)
                Component {
                    id: tipComponent
                    TelamonToolTip {
                        text: tab.toolTipText
                        shown: tab.hovered && tab.toolTipText.length > 0 && !dragHandler.active && !closeButton.hovered
                    }
                }

                HoverHandler {
                    id: hoverTracker
                }

                // Middle click closes; right click asks for the context menu.
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.MiddleButton | Qt.RightButton
                    onClicked: mouse => {
                        if (mouse.button === Qt.RightButton) {
                            control.contextMenuRequested(tab.index, mapToItem(control, mouse.x, mouse.y));
                        } else {
                            control.closeRequested(tab.index);
                        }
                    }
                }

                DragHandler {
                    id: dragHandler
                    target: null
                    xAxis.enabled: true
                    yAxis.enabled: false
                    acceptedButtons: Qt.LeftButton
                    onActiveChanged: {
                        if (active) {
                            list.dragFrom = tab.index;
                            list.dropAt = tab.index;
                        } else {
                            const from = list.dragFrom;
                            const to = list.dropAt;
                            list.dragFrom = -1;
                            list.dropAt = -1;
                            list.dragShift = 0;
                            tab.dragX = 0;
                            if (from >= 0 && to >= 0 && from !== to) {
                                control.moved(from, to);
                            }
                            Qt.callLater(control._followCurrent);
                        }
                    }
                    onTranslationChanged: {
                        if (!active) {
                            return;
                        }
                        tab.dragX = translation.x;
                        list.dragShift = translation.x;
                        list.updateDrop();
                    }
                }

                background: Rectangle {
                    radius: TelamonStyle.radiusSmall
                    // The current tab is tinted by the list's sliding highlight,
                    // except while it is dragged away from it.
                    color: tab.current ? (dragHandler.active ? TelamonStyle.selection : "transparent") : tab.down ? TelamonStyle.pressed : tab.hovered ? TelamonStyle.hover : "transparent"
                    Behavior on color {
                        ColorAnimation {
                            duration: TelamonStyle.durationShort
                        }
                    }

                    // Inside the tab: the list clips what lies outside.
                    TelamonFocusRing {
                        gap: 0
                        radius: parent.radius
                        shown: tab.visualFocus && tab.current
                    }

                    // Where a dragged tab would land: a line on that side.
                    Rectangle {
                        visible: list.dropAt === tab.index && list.dragFrom !== tab.index && list.dragFrom >= 0
                        readonly property bool before: list.dropAt < list.dragFrom
                        x: (before !== list.mirrored) ? -2 : parent.width + 1
                        y: 4
                        width: 2
                        height: parent.height - 8
                        radius: 1
                        color: TelamonStyle.accent
                    }
                }

                contentItem: RowLayout {
                    spacing: TelamonStyle.spacingSmall
                    Rectangle {
                        visible: tab.modified
                        Layout.preferredWidth: 7
                        Layout.preferredHeight: 7
                        radius: 3.5
                        color: TelamonStyle.textMuted
                    }
                    Text {
                        Accessible.ignored: true
                        Layout.fillWidth: true
                        text: tab.title
                        font.family: TelamonStyle.fontFamily
                        font.pointSize: TelamonStyle.fontSizeBody
                        font.weight: tab.current ? Font.Medium : Font.Normal
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        color: tab.current ? TelamonStyle.text : TelamonStyle.textMuted
                    }
                    T.AbstractButton {
                        id: closeButton
                        Layout.preferredWidth: Kirigami.Units.iconSizes.small + TelamonStyle.spacingSmall * 2
                        Layout.preferredHeight: Layout.preferredWidth
                        // Always takes its room, so a tab keeps its width on hover.
                        opacity: tab.showClose ? 1 : 0
                        enabled: tab.showClose
                        hoverEnabled: true
                        focusPolicy: Qt.NoFocus
                        Accessible.name: qsTr("Close Tab")
                        onClicked: control.closeRequested(tab.index)
                        background: Rectangle {
                            radius: width / 2
                            color: closeButton.down ? TelamonStyle.pressed : closeButton.hovered ? TelamonStyle.hover : "transparent"
                        }
                        contentItem: TelamonIcon {
                            source: "window-close"
                            isMask: true
                            color: TelamonStyle.textMuted
                        }
                    }
                }
            }
        }

        ToolbarButton {
            icon.name: "list-add"
            text: qsTr("New Tab")
            onClicked: control.newRequested()
        }

        Item {
            Layout.fillWidth: true
        }

        RowLayout {
            id: trailingRow
            spacing: TelamonStyle.spacingSmall
        }
    }
}
