import QtQuick
import QtQuick.Layouts
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami

// A row of joined pill segments, one selected: a choice between a few views or
// modes ("List | Grid", "Day | Week | Month"). `model` is a list of strings or
// of objects { text, symbol, toolTip }; a segment with only a symbol takes its
// tooltip and accessible name from `toolTip`, else `text`. `activated(index)`
// is the user's choice (not a change of `currentIndex` from code).
//
//   AtlasSegmentedControl {
//       model: [qsTr("List"), { text: qsTr("Grid"), symbol: Symbols.GridView }]
//       currentIndex: app.viewMode
//       onActivated: index => app.viewMode = index
//   }
//
// One Tab stop; Left/Right move the selection (mirrored in right-to-left
// layouts), Home and End jump to the ends. Screen readers get a tab list
// (Accessible.PageTabList) of page tabs (PageTab), the selected one marked.
// Segments are all the same width, the widest one's. Give the control an
// Accessible.name ("View mode") for the screen reader's tab list.
T.Control {
    id: control

    property var model: []
    property int currentIndex: 0
    signal activated(int index)

    readonly property int count: model ? model.length : 0

    function _text(i) {
        const m = control.model[i];
        return m === null || m === undefined ? "" : typeof m === "object" ? (m.text || "") : String(m);
    }
    function _symbol(i) {
        const m = control.model[i];
        return m && typeof m === "object" && m.symbol ? m.symbol : 0;
    }
    function _toolTip(i) {
        const m = control.model[i];
        return m && typeof m === "object" && m.toolTip ? m.toolTip : _text(i);
    }
    function _choose(i) {
        if (i < 0 || i >= count || i === currentIndex) {
            return;
        }
        currentIndex = i;
        activated(i);
    }

    implicitWidth: row.implicitWidth
    implicitHeight: Math.round(Kirigami.Units.gridUnit * 1.7)
    hoverEnabled: true
    focusPolicy: Qt.StrongFocus
    Accessible.role: Accessible.PageTabList

    Keys.onPressed: event => {
        const step = control.mirrored ? -1 : 1;
        let target = -1;
        switch (event.key) {
        case Qt.Key_Right:
            target = control.currentIndex + step;
            break;
        case Qt.Key_Left:
            target = control.currentIndex - step;
            break;
        case Qt.Key_Home:
            target = 0;
            break;
        case Qt.Key_End:
            target = control.count - 1;
            break;
        default:
            return;
        }
        event.accepted = true;
        control._choose(Math.max(0, Math.min(control.count - 1, target)));
    }

    background: Rectangle {
        radius: AtlasStyle.radiusPill
        color: Qt.alpha(Kirigami.Theme.textColor, 0.07)
        border.width: 1
        border.color: Qt.alpha(Kirigami.Theme.textColor, 0.14)
        opacity: control.enabled ? 1 : 0.6

        // The selection: slides to the segment (all cells are equal).
        Rectangle {
            readonly property real cell: control.count > 0 ? (parent.width - 4) / control.count : 0
            visible: control.count > 0 && control.currentIndex >= 0 && control.currentIndex < control.count
            x: 2 + (control.mirrored ? control.count - 1 - control.currentIndex : control.currentIndex) * cell
            y: 2
            width: cell
            height: parent.height - 4
            radius: AtlasStyle.radiusPill
            color: control.enabled ? Kirigami.Theme.highlightColor : Qt.alpha(Kirigami.Theme.textColor, 0.2)
            Behavior on x {
                NumberAnimation {
                    duration: AtlasStyle.duration
                    easing.type: Easing.OutCubic
                }
            }
        }
        AtlasFocusRing {
            radius: parent.radius
            shown: control.visualFocus
        }
    }

    contentItem: RowLayout {
        id: row
        spacing: 0
        uniformCellSizes: true
        LayoutMirroring.enabled: control.mirrored
        LayoutMirroring.childrenInherit: false

        Repeater {
            model: control.count
            delegate: Item {
                id: seg
                required property int index
                readonly property bool selected: seg.index === ctl.currentIndex
                readonly property string label: ctl._text(seg.index)
                readonly property AtlasSegmentedControl ctl: control
                readonly property color tint: !ctl.enabled ? Qt.alpha(Kirigami.Theme.textColor, 0.5) : selected ? Kirigami.Theme.highlightedTextColor : Kirigami.Theme.textColor

                Layout.fillWidth: true
                Layout.fillHeight: true
                implicitWidth: inner.implicitWidth + AtlasStyle.spacingLarge * 2
                implicitHeight: ctl.implicitHeight

                Accessible.role: Accessible.PageTab
                Accessible.name: ctl._toolTip(seg.index)
                Accessible.selectable: true
                Accessible.selected: seg.selected
                Accessible.onPressAction: ctl._choose(seg.index)

                Row {
                    id: inner
                    anchors.centerIn: parent
                    spacing: AtlasStyle.spacingSmall
                    Loader {
                        active: ctl._symbol(seg.index) !== 0
                        visible: active
                        anchors.verticalCenter: parent.verticalCenter
                        sourceComponent: Symbol {
                            icon: control._symbol(seg.index)
                            size: Math.round(Kirigami.Units.iconSizes.small * 1.2)
                            color: seg.tint
                        }
                    }
                    Text {
                        visible: seg.label.length > 0
                        anchors.verticalCenter: parent.verticalCenter
                        text: seg.label
                        font: Kirigami.Theme.defaultFont
                        color: seg.tint
                        textFormat: Text.PlainText
                        Accessible.ignored: true
                    }
                }
                HoverHandler {
                    id: hover
                    enabled: seg.ctl.enabled
                }
                TapHandler {
                    enabled: ctl.enabled
                    onTapped: ctl._choose(seg.index)
                }
                AtlasToolTip {
                    text: ctl._toolTip(seg.index)
                    shown: text.length > 0 && (hover.hovered || (ctl.visualFocus && seg.selected))
                }
            }
        }
    }
}
