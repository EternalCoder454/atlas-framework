import QtQuick
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami

// A right-click menu in the Telamon look: a rounded raised card with inset
// rows. Fill it with ContextMenuItem and ContextMenuSeparator, and open it
// with popup() at the pointer, or popup(item, x, y) from the keyboard.
//
//   ContextMenu {
//       id: menu
//       ContextMenuItem { text: qsTr("Details"); icon.name: "documentinfo" }
//       ContextMenuSeparator {}
//       ContextMenuItem { text: qsTr("End Task"); destructive: true }
//   }
//
// A menu taller than the window (less its margins) is cut to fit and scrolls;
// the arrow keys keep the current row in view. Radio rows: see ContextMenuItem.
//
// Keyboard: Up and Down move over the rows that can be chosen (not over
// separators, disabled or hidden rows) and wrap at the ends, Home and End go to
// the first and last, Enter and Space choose, Escape closes. Right opens a
// submenu and Left closes it (the other way round in a right-to-left layout).
// A row of your own (a T.MenuItem with several buttons, say) gets the keys
// first; let the ones it does not use go on (`event.accepted = false`).
T.Menu {
    id: control

    // As wide as its widest row, between 7 and 24 grid units: a one-row menu
    // is not a wide empty card, and a long label elides instead.
    implicitWidth: Math.min(Kirigami.Units.gridUnit * 24, Math.max(Kirigami.Units.gridUnit * 7, contentItem.implicitWidth + leftPadding + rightPadding))
    // The window's height less the margins bounds the menu; it scrolls past that.
    readonly property real _maxHeight: list.windowHeight - topMargin - bottomMargin
    implicitHeight: Math.min(contentItem.implicitHeight + topPadding + bottomPadding, Math.max(_maxHeight, 0))
    padding: TelamonStyle.spacingSmall
    margins: TelamonStyle.spacingSmall
    overlap: 1
    modal: false
    focus: true

    delegate: ContextMenuItem {}

    // Whether the keyboard may stop on this row: a menu item that is shown and on.
    // Separators, labels and hidden or disabled rows are passed over.
    function _canChoose(item: var): bool {
        return item instanceof T.MenuItem && item.visible && item.enabled;
    }
    // The nearest row from `from` to choose, going `dir` (1 or -1) and wrapping
    // at the ends; -1 when there is none. `from` -1 starts before the first row
    // going down and after the last going up.
    function _next(from: int, dir: int): int {
        const n = control.count;
        const start = from < 0 ? (dir > 0 ? -1 : n) : from;
        for (let k = 1; k <= n; ++k) {
            const i = (((start + dir * k) % n) + n) % n;
            if (control._canChoose(control.itemAt(i))) {
                return i;
            }
        }
        return -1;
    }
    // The first (`dir` 1) or last (-1) row to choose; -1 when there is none.
    function _edge(dir: int): int {
        const n = control.count;
        for (let k = 0; k < n; ++k) {
            const i = dir > 0 ? k : n - 1 - k;
            if (control._canChoose(control.itemAt(i))) {
                return i;
            }
        }
        return -1;
    }
    function _go(index: int): void {
        if (index >= 0) {
            control.currentIndex = index;
        }
    }
    // Whether this menu is the submenu of a row of another menu.
    readonly property bool _isSubmenu: (control.parent as T.MenuItem)?.subMenu === control
    // Opens the submenu of the current row, if it has one.
    function _openSubmenu(): void {
        const row = control.itemAt(control.currentIndex) as T.MenuItem;
        const sub = row?.subMenu;
        if (sub && control._canChoose(row)) {
            row.click();
            // The submenu starts on its first row, as the pointer would not.
            if (sub.count > 0 && sub.currentIndex < 0) {
                sub.currentIndex = typeof sub._edge === "function" ? sub._edge(1) : 0;
            }
        }
    }
    // Handles a key the rows did not take; true when it was the menu's.
    function _key(key: int): bool {
        switch (key) {
        case Qt.Key_Right:
        case Qt.Key_Left:
            // Towards the end of the line opens a submenu, back from it closes
            // one; Qt's own keys ignore a right-to-left layout.
            if ((key === Qt.Key_Right) !== control.mirrored) {
                control._openSubmenu();
            } else if (control._isSubmenu) {
                control.close();
            }
            return true;
        case Qt.Key_Down:
            control._go(control._next(control.currentIndex, 1));
            return true;
        case Qt.Key_Up:
            control._go(control._next(control.currentIndex, -1));
            return true;
        case Qt.Key_Home:
            control._go(control._edge(1));
            return true;
        case Qt.Key_End:
            control._go(control._edge(-1));
            return true;
        }
        return false;
    }

    // Items added just before popup() are measured before it is placed,
    // not one turn later (when it would first be placed too narrow).
    onAboutToShow: list._settle()

    contentItem: ListView {
        id: list
        readonly property real windowHeight: Window.window ? Window.window.height : Number.POSITIVE_INFINITY
        // The menu's item count once a change is over. Menu.takeItem() reports
        // the new count while the item is still being removed, and itemAt()
        // then returns an object that is no longer valid (a crash), so the
        // width is measured one turn later, never during the removal.
        property int _rows: 0
        function _settle(): void {
            // A call queued by the menu's teardown can arrive after it.
            if (control) {
                list._rows = control.count;
            }
        }
        Connections {
            target: control
            function onCountChanged(): void {
                Qt.callLater(list._settle);
            }
        }
        Component.onCompleted: list._settle()
        implicitWidth: {
            let w = 0;
            // The menu's own items, not the list's delegates: the list makes
            // only the rows in view, so a long label further down would elide.
            for (let i = 0; i < list._rows; ++i) {
                const item = control.itemAt(i);
                if (item) {
                    w = Math.max(w, item.implicitWidth);
                }
            }
            return w;
        }
        implicitHeight: contentHeight
        model: control.contentModel
        interactive: contentHeight > height
        clip: interactive
        boundsBehavior: Flickable.StopAtBounds
        onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
        currentIndex: control.currentIndex
        // The menu moves the current row itself (Keys.onPressed below), over the
        // rows it may choose: the list's own keys would stop on separators and
        // take the arrow keys from a row that holds the keyboard.
        keyNavigationEnabled: false
        focus: true
        Keys.onPressed: event => {
            // Ctrl, Alt and Meta with a key are the application's (shortcuts).
            event.accepted = !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) && control._key(event.key);
        }
    }

    background: Item {
        // Soft shadow: faint outlines, no shader, so it also draws with the software renderer.
        // Black over a dark window barely shows, so Dark's is stronger.
        Rectangle {
            anchors.fill: parent
            anchors.margins: -1
            anchors.topMargin: 0
            anchors.bottomMargin: -3
            radius: TelamonStyle.radius + 1
            color: TelamonStyle.alpha("black", Appearance.darkMode ? 0.16 : 0.04)
        }
        Rectangle {
            anchors.fill: parent
            anchors.margins: -2
            anchors.topMargin: -1
            anchors.bottomMargin: -5
            radius: TelamonStyle.radius + 2
            color: TelamonStyle.alpha("black", Appearance.darkMode ? 0.1 : 0.025)
        }
        Rectangle {
            anchors.fill: parent
            radius: TelamonStyle.radius
            // floatingBackground is tinted translucent over the blurred window, solid without it.
            color: TelamonStyle.floatingBackground
            // A real edge: the menu is a shade lighter than the sidebar it opens over.
            border.width: 1
            border.color: TelamonStyle.outline
        }
    }

    enter: Transition {
        NumberAnimation {
            property: "opacity"
            from: 0
            to: 1
            duration: TelamonStyle.durationShort
        }
    }
    exit: Transition {
        NumberAnimation {
            property: "opacity"
            from: 1
            to: 0
            duration: TelamonStyle.durationShort
        }
    }
}
