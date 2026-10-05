import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami

// A strip of document tabs in the Atlas look, after Windows 11 Notepad: each
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

    // AtlasStyle.Normal or AtlasStyle.Compact; Compact shrinks the height and
    // the vertical padding to about 75%. Follows the app-wide AtlasStyle.density
    // unless set here.
    property int density: AtlasStyle.density
    readonly property real _k: density === AtlasStyle.Compact ? 0.75 : 1

    implicitWidth: Kirigami.Units.gridUnit * 30
    implicitHeight: Math.round(Kirigami.Units.gridUnit * 1.9 * _k) + Math.round(AtlasStyle.spacingSmall * 2 * _k)
    Accessible.role: Accessible.PageTabList
    Accessible.name: qsTr("Tabs")

    // A new tab's index usually arrives after the count changed, and the list
    // no longer follows its current item (the highlight slides on its own).
    onCurrentIndexChanged: Qt.callLater(control.ensureCurrentVisible)

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
        anchors.leftMargin: AtlasStyle.spacingSmall
        anchors.rightMargin: AtlasStyle.spacingSmall
        spacing: AtlasStyle.spacingSmall

        ListView {
            id: list

            // Where a dragged tab would land, or -1.
            property int dragFrom: -1
            property int dropAt: -1

            Layout.fillHeight: true
            // Hugs its tabs while they fit and shrinks to the bar (then
            // scrolls) when they don't, so the New Tab button stays in view.
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.preferredWidth: contentWidth
            Layout.maximumWidth: contentWidth
            orientation: ListView.Horizontal
            spacing: AtlasStyle.spacingXSmall
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
                z: -1
                visible: list.currentItem !== null
                radius: AtlasStyle.radiusSmall
                color: AtlasStyle.selection
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
                x: _baseX + _slideX
                y: _baseY
                width: Math.max(0, _baseW + _slideW)
                height: _baseH
                Behavior on _slideX {
                    enabled: _springing && !AtlasStyle.reducedMotion
                    AtlasSpringAnimation {
                        expressive: true
                    }
                }
                Behavior on _slideW {
                    enabled: _springing && !AtlasStyle.reducedMotion
                    AtlasSpringAnimation {
                        expressive: true
                    }
                }
                function _sync() {
                    _baseX = _item ? _item.x + 0 : 0;
                    _baseY = _item ? _item.y + 0 : 0;
                    _baseW = _item ? _item.width : 0;
                    _baseH = _item ? _item.height : 0;
                }
                // Only a selection change slides, and only from a tint that was showing.
                Component.onCompleted: {
                    _sync();
                    _shown = _item;
                }
                on_ItemChanged: {
                    const oldX = x;
                    const oldW = width;
                    const from = _shown !== null && _item !== null;
                    _springing = false;
                    _slideX = 0;
                    _slideW = 0;
                    _sync();
                    _shown = _item;
                    if (from) {
                        _slideX = oldX - _baseX;
                        _slideW = oldW - _baseW;
                        _springing = true;
                        _slideX = 0;
                        _slideW = 0;
                    }
                }
                Connections {
                    target: _item
                    function onXChanged() { _sync(); }
                    function onYChanged() { _sync(); }
                    function onWidthChanged() { _sync(); }
                    function onHeightChanged() { _sync(); }
                }
            }
            onCountChanged: Qt.callLater(control.ensureCurrentVisible)
            // The current tab's title turns medium weight, so it grows a
            // little after it was scrolled to.
            Connections {
                target: list.currentItem
                function onWidthChanged() { Qt.callLater(control.ensureCurrentVisible); }
            }
            onWidthChanged: Qt.callLater(control.ensureCurrentVisible)

            WheelHandler {
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: event => {
                    const d = event.angleDelta.x !== 0 ? event.angleDelta.x : event.angleDelta.y;
                    // The content starts at originX, not 0, once tabs of
                    // different widths came and went.
                    const max = list.originX + Math.max(0, list.contentWidth - list.width);
                    list.contentX = Math.max(list.originX, Math.min(max, list.contentX - d * (list.mirrored ? -1 : 1)));
                }
            }

            readonly property bool mirrored: LayoutMirroring.enabled

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
                leftPadding: AtlasStyle.spacingLarge
                rightPadding: AtlasStyle.spacingSmall
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

                onPressed: {
                    if (!tab.current) {
                        control.activated(tab.index);
                    }
                }

                QQC2.ToolTip.visible: tab.hovered && tab.toolTipText.length > 0 && !dragHandler.active && !closeButton.hovered
                QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                QQC2.ToolTip.text: tab.toolTipText

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
                            tab.dragX = 0;
                            if (from >= 0 && to >= 0 && from !== to) {
                                control.moved(from, to);
                            }
                        }
                    }
                    onTranslationChanged: {
                        if (!active) {
                            return;
                        }
                        tab.dragX = translation.x;
                        const at = list.indexAt(tab.x + tab.width / 2 + translation.x, list.height / 2);
                        if (at >= 0) {
                            list.dropAt = at;
                        } else {
                            // Past either end: the first or last tab.
                            const centre = tab.x + tab.width / 2 + translation.x;
                            list.dropAt = centre < 0 ? (list.mirrored ? list.count - 1 : 0) : (list.mirrored ? 0 : list.count - 1);
                        }
                    }
                }

                background: Rectangle {
                    radius: AtlasStyle.radiusSmall
                    // The current tab is tinted by the list's sliding highlight,
                    // except while it is dragged away from it.
                    color: tab.current ? (dragHandler.active ? AtlasStyle.selection : "transparent") : tab.down ? AtlasStyle.pressed : tab.hovered ? AtlasStyle.hover : "transparent"
                    Behavior on color {
                        ColorAnimation {
                            duration: AtlasStyle.durationShort
                        }
                    }

                    // Inside the tab: the list clips what lies outside.
                    AtlasFocusRing {
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
                        color: AtlasStyle.accent
                    }
                }

                contentItem: RowLayout {
                    spacing: AtlasStyle.spacingSmall
                    Rectangle {
                        visible: tab.modified
                        Layout.preferredWidth: 7
                        Layout.preferredHeight: 7
                        radius: 3.5
                        color: AtlasStyle.textMuted
                    }
                    Text {
                        Accessible.ignored: true
                        Layout.fillWidth: true
                        text: tab.title
                        font.family: AtlasStyle.fontFamily
                        font.pointSize: AtlasStyle.fontSizeBody
                        font.weight: tab.current ? Font.Medium : Font.Normal
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        color: tab.current ? AtlasStyle.text : AtlasStyle.textMuted
                    }
                    T.AbstractButton {
                        id: closeButton
                        Layout.preferredWidth: Kirigami.Units.iconSizes.small + AtlasStyle.spacingSmall * 2
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
                            color: closeButton.down ? AtlasStyle.pressed : closeButton.hovered ? AtlasStyle.hover : "transparent"
                        }
                        contentItem: Kirigami.Icon {
                            source: "window-close"
                            isMask: true
                            color: AtlasStyle.textMuted
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
            spacing: AtlasStyle.spacingSmall
        }
    }
}
