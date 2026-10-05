import QtQuick

// Lays its children out left to right and wraps them onto new rows, like
// Flow, but it honours the Layout attached properties (QtQuick.Layouts) that
// Flow ignores: `Layout.preferredWidth`, `Layout.minimumWidth`,
// `Layout.maximumWidth`, and `Layout.fillWidth`, where the items of a row
// that have it share the room left in that row (usually the last one). A child
// is as wide as its preferred width, else its implicit width, and never wider
// than the layout. Rows are as tall as their tallest child. Hidden children
// take no room. `implicitHeight` is the height for the current `width`, so a
// parent that sizes to it grows as the layout wraps. It is written in QML:
// the work runs once per change of width or of a child's size, not per frame.
//
//   AtlasFlowLayout {
//       width: parent.width
//       spacing: Kirigami.Units.smallSpacing
//       Repeater { model: tags; AtlasButton { text: modelData } }
//       AtlasTextField { Layout.fillWidth: true; Layout.minimumWidth: 120 }
//   }
//
// Right-to-left layouts (LayoutMirroring) start rows at the right.
Item {
    id: root

    // Space between items of a row.
    property real spacing: 8
    // Space between rows.
    property real rowSpacing: spacing

    // The width that fits every child on one row, and the height at the
    // current width.
    implicitWidth: _naturalWidth

    property real _naturalWidth: 0
    // Children whose changes are watched, so a child is connected once.
    property var _watched: new Set()
    property bool _pending: false
    property bool _busy: false

    onSpacingChanged: _schedule()
    onRowSpacingChanged: _schedule()
    onWidthChanged: _schedule()
    onChildrenChanged: {
        _watch();
        _schedule();
    }
    LayoutMirroring.childrenInherit: true
    Component.onCompleted: {
        _watch();
        _relayout();
    }

    // Layout.* values of `item`; -1 means unset.
    function _num(v, fallback) {
        return v !== undefined && v >= 0 ? v : fallback;
    }
    function _isRepeater(item) {
        return item.delegate !== undefined && item.count !== undefined && item.model !== undefined;
    }
    function _schedule() {
        if (!_pending) {
            _pending = true;
            Qt.callLater(_relayout);
        }
    }
    function _watch() {
        const now = new Set();
        for (const child of root.children) {
            now.add(child);
            if (!_watched.has(child)) {
                child.implicitWidthChanged.connect(_schedule);
                child.implicitHeightChanged.connect(_schedule);
                child.visibleChanged.connect(_schedule);
                // A child's Layout.* values: the attached object is made here,
                // which Layout does for any item laid out by it.
                const attached = child.Layout;
                if (attached) {
                    for (const name of ["fillWidthChanged", "preferredWidthChanged", "minimumWidthChanged", "maximumWidthChanged"]) {
                        if (attached[name]) {
                            attached[name].connect(_schedule);
                        }
                    }
                }
            }
        }
        _watched = now;
    }

    function _relayout() {
        _pending = false;
        if (_busy) {
            return;
        }
        _busy = true;
        const items = [];
        for (const child of root.children) {
            if (child.visible && !_isRepeater(child)) {
                items.push(child);
            }
        }
        const total = root.width;
        const mirrored = LayoutMirroring.enabled;
        let natural = 0;
        let y = 0;
        let row = [];
        let rowWidth = 0; // preferred widths and gaps
        const place = last => {
            // Leftover room goes to the fillWidth items of the row.
            let fills = 0;
            for (const e of row) {
                fills += e.fill ? 1 : 0;
            }
            let extra = fills > 0 ? Math.max(0, total - rowWidth) : 0;
            let rowHeight = 0;
            let x = 0;
            for (const e of row) {
                let w = e.width;
                if (e.fill && extra > 0) {
                    const grown = Math.min(e.max, w + extra / fills);
                    extra -= grown - w;
                    fills -= 1;
                    w = grown;
                } else if (e.fill) {
                    fills -= 1;
                }
                e.item.width = w;
                e.item.x = mirrored ? total - x - w : x;
                e.item.y = y;
                rowHeight = Math.max(rowHeight, e.item.height);
                x += w + spacing;
            }
            y += rowHeight + (last ? 0 : rowSpacing);
        };
        for (const item of items) {
            const lay = item.Layout;
            const min = lay ? _num(lay.minimumWidth, 0) : 0;
            const max = lay ? _num(lay.maximumWidth, Infinity) : Infinity;
            let w = lay ? _num(lay.preferredWidth, item.implicitWidth) : item.implicitWidth;
            w = Math.max(min, Math.min(max, w));
            natural += (natural > 0 ? spacing : 0) + w;
            if (total > 0) {
                w = Math.min(w, total);
            }
            const needed = row.length > 0 ? rowWidth + spacing + w : w;
            if (row.length > 0 && needed > total) {
                place(false);
                row = [];
                rowWidth = 0;
            }
            rowWidth = row.length > 0 ? rowWidth + spacing + w : w;
            row.push({
                item: item,
                width: w,
                max: max,
                fill: lay ? lay.fillWidth === true : false
            });
        }
        if (row.length > 0) {
            place(true);
        }
        _naturalWidth = natural;
        implicitHeight = row.length > 0 || items.length > 0 ? y : 0;
        _busy = false;
    }
}
