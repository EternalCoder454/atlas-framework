import QtQuick
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami

// A right-click menu in the Atlas look: a rounded raised card with inset
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
T.Menu {
    id: control

    implicitWidth: Math.max(Kirigami.Units.gridUnit * 11, contentItem.implicitWidth + leftPadding + rightPadding)
    // The window's height less the margins bounds the menu; it scrolls past that.
    readonly property real _maxHeight: list.windowHeight - topMargin - bottomMargin
    implicitHeight: Math.min(contentItem.implicitHeight + topPadding + bottomPadding, Math.max(_maxHeight, 0))
    padding: AtlasStyle.spacingSmall
    margins: AtlasStyle.spacingSmall
    overlap: 1
    modal: false
    focus: true

    delegate: ContextMenuItem {}

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
        keyNavigationEnabled: true
        keyNavigationWraps: true
    }

    background: Item {
        // Soft shadow: faint outlines, no shader, so it also draws with the software renderer.
        Rectangle {
            anchors.fill: parent
            anchors.margins: -1
            anchors.topMargin: 0
            anchors.bottomMargin: -3
            radius: AtlasStyle.radius + 1
            color: Qt.alpha("black", 0.04)
        }
        Rectangle {
            anchors.fill: parent
            anchors.margins: -2
            anchors.topMargin: -1
            anchors.bottomMargin: -5
            radius: AtlasStyle.radius + 2
            color: Qt.alpha("black", 0.025)
        }
        Rectangle {
            anchors.fill: parent
            radius: AtlasStyle.radius
            // floatingBackground is tinted translucent over the blurred window, solid without it.
            color: AtlasStyle.floatingBackground
            border.width: 1
            border.color: AtlasStyle.separator
        }
    }

    enter: Transition {
        NumberAnimation {
            property: "opacity"
            from: 0
            to: 1
            duration: AtlasStyle.durationShort
        }
    }
    exit: Transition {
        NumberAnimation {
            property: "opacity"
            from: 1
            to: 0
            duration: AtlasStyle.durationShort
        }
    }
}
