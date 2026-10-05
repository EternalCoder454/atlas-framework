import QtQuick
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami

// Page tabs for the top of a window, after libadwaita's ViewSwitcher: each tab
// is a symbol with its text beside it (or under it with `narrow`), the current
// one tinted with the accent (the tint slides to the new tab, and its symbol
// turns solid), and an optional count badge.
//
//   AtlasViewSwitcher {
//       model: [
//           { text: qsTr("Installed"), symbol: Symbols.CheckCircle },
//           { text: qsTr("Updates"), symbol: Symbols.Update, badge: 3 }
//       ]
//       currentIndex: pages.currentIndex
//       onActivated: index => pages.currentIndex = index
//   }
//
// `model` is a list of { text, symbol, badge }: `symbol` is a Symbols.<Name>
// (0 or missing: text only), `badge` a count (0 or missing: none). The switcher
// owns no state: change `currentIndex` in answer to activated(), as with
// TabBar. Tab reaches the switcher once; Left and Right (mirrored in a
// right-to-left layout), Home and End move between the tabs and activate them.
// Ctrl+PageUp and Ctrl+PageDown are left to the app.
T.Control {
    id: control

    property var model: []
    property int currentIndex: -1
    // Puts the text under the symbol.
    property bool narrow: false

    signal activated(int index)

    readonly property int count: model ? (model.length !== undefined ? model.length : 0) : 0

    implicitWidth: row.implicitWidth + leftPadding + rightPadding
    implicitHeight: row.implicitHeight + topPadding + bottomPadding
    padding: AtlasStyle.spacingXSmall
    focusPolicy: Qt.TabFocus

    Accessible.role: Accessible.PageTabList
    Accessible.name: qsTr("Views")

    // The current tab's item; the tint follows it.
    property Item _cur: null
    // One tint that slides (a spring with a small overshoot) to the current
    // tab, behind the tabs. It follows layout changes directly; only a change
    // of the current tab springs.
    Rectangle {
        id: tint
        z: -1
        visible: control.currentIndex >= 0 && control._cur !== null
        radius: AtlasStyle.radiusSmall
        color: AtlasStyle.selection
        property Item _item: control._cur
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
            enabled: tint._springing && !AtlasStyle.reducedMotion
            AtlasSpringAnimation {
                expressive: true
            }
        }
        Behavior on _slideW {
            enabled: tint._springing && !AtlasStyle.reducedMotion
            AtlasSpringAnimation {
                expressive: true
            }
        }
        function _sync() {
            _baseX = _item ? _item.x + row.x : 0;
            _baseY = _item ? _item.y + row.y : 0;
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
        // The Behaviors and Connections are objects of their own: tint's
        // members are reached through its id.
        Connections {
            target: tint._item
            function onXChanged() { tint._sync(); }
            function onYChanged() { tint._sync(); }
            function onWidthChanged() { tint._sync(); }
            function onHeightChanged() { tint._sync(); }
        }
    }

    function _step(delta) {
        if (control.count === 0) {
            return;
        }
        const cur = control.currentIndex < 0 ? 0 : control.currentIndex;
        control._go(Math.max(0, Math.min(control.count - 1, cur + delta)));
    }
    function _go(index) {
        if (index !== control.currentIndex) {
            control.activated(index);
        }
    }

    Keys.onPressed: event => {
        // Row mirrors by itself, so "right" is the next tab only when not mirrored.
        const next = control.LayoutMirroring.enabled ? Qt.Key_Left : Qt.Key_Right;
        const prev = control.LayoutMirroring.enabled ? Qt.Key_Right : Qt.Key_Left;
        if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) {
            return;
        }
        if (event.key === next) {
            control._step(1);
        } else if (event.key === prev) {
            control._step(-1);
        } else if (event.key === Qt.Key_Home) {
            control._go(0);
        } else if (event.key === Qt.Key_End) {
            control._go(control.count - 1);
        } else {
            return;
        }
        event.accepted = true;
    }

    contentItem: Row {
        id: row
        spacing: AtlasStyle.spacingXSmall

        Repeater {
            model: control.model

            delegate: Item {
                id: tab

                required property int index
                required property var modelData
                readonly property bool current: index === control.currentIndex
                readonly property string label: modelData.text ?? ""
                readonly property int glyph: modelData.symbol ?? 0
                readonly property int badge: modelData.badge ?? 0

                onCurrentChanged: {
                    if (current) {
                        control._cur = tab;
                    }
                }
                Component.onCompleted: {
                    if (current) {
                        control._cur = tab;
                    }
                }
                Component.onDestruction: {
                    if (control._cur === tab) {
                        control._cur = null;
                    }
                }

                implicitWidth: Math.max(Kirigami.Units.gridUnit * 3, flow.implicitWidth + Kirigami.Units.largeSpacing * 2)
                implicitHeight: control.narrow ? Math.round(Kirigami.Units.gridUnit * 3.2) : Math.round(Kirigami.Units.gridUnit * 2.2)

                Accessible.role: Accessible.PageTab
                //: Name of a view tab with a count: %1 is the tab text, %2 the count
                Accessible.name: tab.badge > 0 ? qsTr("%1, %2").arg(tab.label).arg(tab.badge) : tab.label
                Accessible.selectable: true
                Accessible.selected: tab.current
                Accessible.onPressAction: control.activated(tab.index)

                Rectangle {
                    anchors.fill: parent
                    radius: AtlasStyle.radiusSmall
                    // The current tab is tinted by the sliding highlight.
                    color: press.pressed ? AtlasStyle.pressed : !tab.current && hover.hovered ? AtlasStyle.hover : "transparent"
                    Behavior on color {
                        ColorAnimation {
                            duration: AtlasStyle.durationShort
                        }
                    }
                    AtlasFocusRing {
                        radius: parent.radius
                        shown: control.visualFocus && tab.current
                    }
                }

                Grid {
                    id: flow
                    anchors.centerIn: parent
                    // Under the symbol when narrow, beside it otherwise.
                    columns: control.narrow ? 1 : 2
                    horizontalItemAlignment: Grid.AlignHCenter
                    verticalItemAlignment: Grid.AlignVCenter
                    spacing: control.narrow ? AtlasStyle.spacingXSmall : AtlasStyle.spacingSmall

                    Item {
                        visible: tab.glyph !== 0
                        implicitWidth: glyphItem.width
                        implicitHeight: glyphItem.height
                        width: implicitWidth
                        height: implicitHeight
                        Symbol {
                            id: glyphItem
                            icon: tab.glyph
                            filled: tab.current
                            size: Kirigami.Units.iconSizes.smallMedium
                            color: tab.current ? AtlasStyle.accent : Kirigami.Theme.textColor
                        }
                        Rectangle {
                            visible: tab.badge > 0
                            x: control.LayoutMirroring.enabled ? -width / 3 : parent.width - width * 2 / 3
                            y: -height / 3
                            width: Math.max(height, badgeText.implicitWidth + 6)
                            height: badgeText.implicitHeight + 1
                            radius: height / 2
                            color: AtlasStyle.error
                            Accessible.ignored: true
                            Text {
                                id: badgeText
                                anchors.centerIn: parent
                                text: tab.badge > 99 ? "99+" : String(tab.badge)
                                font.pixelSize: AtlasStyle.fontSizeCaption - 1
                                color: "white"
                            }
                        }
                    }
                    Text {
                        text: tab.label
                        font.pixelSize: control.narrow ? AtlasStyle.fontSizeCaption : AtlasStyle.fontSizeBody
                        font.weight: tab.current ? Font.DemiBold : Font.Normal
                        color: tab.current ? AtlasStyle.accent : Kirigami.Theme.textColor
                        Accessible.ignored: true
                    }
                }

                HoverHandler {
                    id: hover
                }
                TapHandler {
                    id: press
                    onTapped: control._go(tab.index)
                }
            }
        }
    }
}
