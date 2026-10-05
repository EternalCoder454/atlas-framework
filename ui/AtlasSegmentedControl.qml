import QtQuick
import QtQuick.Layouts
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami

// A row of joined segments, one selected: a choice between a few views or
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
// Segments are all the same width, the widest one's; text that does not fit
// is elided. The accent highlight slides to the chosen segment with a small
// overshoot (not under reduced motion, and never on a resize). Give the control an
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

    // The highlight's place in hundredths of a cell, so one spring setting
    // serves every distance. Only a change of the choice moves it: a resize
    // or the first layout rescales x without animating.
    readonly property real _pos: (control.mirrored ? control.count - 1 - control.currentIndex : control.currentIndex) * 100
    property real _slidePos: _pos

    padding: 2
    // uniformCellSizes makes the row as wide as its widest cell times the count,
    // a binding, so there is no first frame at width 0.
    implicitWidth: row.implicitWidth + leftPadding + rightPadding
    implicitHeight: Math.max(AtlasStyle.controlHeight, row.implicitHeight + topPadding + bottomPadding)
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

    Behavior on _slidePos {
        enabled: !AtlasStyle.reducedMotion
        AtlasSpringAnimation {
            expressive: true
        }
    }

    background: Rectangle {
        radius: AtlasStyle.radiusLarge
        color: AtlasStyle.control
        border.width: 1
        border.color: AtlasStyle.controlBorder

        // The selection: slides to the segment (all cells are equal).
        Rectangle {
            readonly property real cell: control.count > 0 ? (parent.width - 4) / control.count : 0
            visible: control.count > 0 && control.currentIndex >= 0 && control.currentIndex < control.count
            x: 2 + control._slidePos / 100 * cell
            y: 2
            width: cell
            height: parent.height - 4
            // Rounder than the hover shape of the other segments.
            radius: AtlasStyle.radius
            color: control.enabled ? AtlasStyle.accent : AtlasStyle.controlBorder
        }
        AtlasFocusRing {
            radius: parent.radius + gap
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
            id: segments
            model: control.count
            delegate: Item {
                id: seg
                required property int index
                readonly property bool selected: seg.index === ctl.currentIndex
                readonly property string label: ctl._text(seg.index)
                readonly property AtlasSegmentedControl ctl: control
                readonly property color tint: !ctl.enabled ? AtlasStyle.textDisabled : selected ? AtlasStyle.accentText : Kirigami.Theme.textColor
                readonly property real _room: Math.max(0, seg.width - AtlasStyle.spacingLarge * 2 - (symbolSlot.visible ? symbolSlot.width + inner.spacing : 0))

                Layout.fillWidth: true
                Layout.fillHeight: true
                // The text's own width, not the elided one, so the width does not loop.
                implicitWidth: (symbolSlot.visible ? symbolSlot.width + inner.spacing : 0) + (segText.visible ? Math.ceil(metrics.advanceWidth) : 0) + AtlasStyle.spacingLarge * 2
                implicitHeight: inner.implicitHeight

                Accessible.role: Accessible.PageTab
                Accessible.name: ctl._toolTip(seg.index)
                Accessible.selectable: true
                Accessible.selected: seg.selected
                Accessible.onPressAction: ctl._choose(seg.index)

                // Hover shape: slightly less round than the selected one.
                Rectangle {
                    anchors.fill: parent
                    radius: AtlasStyle.radiusSmall
                    color: !seg.selected && ctl.enabled && hover.hovered ? AtlasStyle.hover : "transparent"
                    Behavior on color {
                        ColorAnimation {
                            duration: AtlasStyle.durationShort
                        }
                    }
                }
                // The text's natural width: a Text's own implicitWidth shrinks once elided.
                TextMetrics {
                    id: metrics
                    font: segText.font
                    text: seg.label
                }
                Row {
                    id: inner
                    anchors.centerIn: parent
                    spacing: AtlasStyle.spacingSmall
                    Loader {
                        id: symbolSlot
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
                        id: segText
                        visible: seg.label.length > 0
                        anchors.verticalCenter: parent.verticalCenter
                        text: seg.label
                        width: Math.min(Math.ceil(metrics.advanceWidth), seg._room)
                        elide: Text.ElideRight
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
