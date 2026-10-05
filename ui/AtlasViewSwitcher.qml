import QtQuick
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami

// Page tabs for the top of a window, after libadwaita's ViewSwitcher: each tab
// is a symbol with its text beside it (or under it with `narrow`), the current
// one tinted with the accent, and an optional count badge.
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
    padding: 2
    focusPolicy: Qt.TabFocus

    Accessible.role: Accessible.PageTabList
    Accessible.name: qsTr("Views")

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
        spacing: 2

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
                    radius: AtlasStyle.radius
                    color: tab.current ? Qt.alpha(AtlasStyle.accent, press.pressed ? 0.28 : 0.18) : Qt.alpha(Kirigami.Theme.textColor, press.pressed ? 0.12 : hover.hovered ? 0.07 : 0)
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
                    spacing: control.narrow ? 2 : Kirigami.Units.smallSpacing

                    Item {
                        visible: tab.glyph !== 0
                        implicitWidth: glyphItem.width
                        implicitHeight: glyphItem.height
                        width: implicitWidth
                        height: implicitHeight
                        Symbol {
                            id: glyphItem
                            icon: tab.glyph
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
