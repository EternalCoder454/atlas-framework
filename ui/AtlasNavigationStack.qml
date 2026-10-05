import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

// Drill-down navigation: pages pushed one over another, with a header row
// holding a Back button and the current page's title. Alt+Left and the mouse
// Back button go back too; Escape does not (it belongs to dialogs and search).
// Pages slide sideways (instantly under reduced motion).
//
//   AtlasNavigationStack {
//       initialItem: ListPage { }
//       // inside ListPage:  onOpened: stack.push(detailComponent, { title: "Details" })
//   }
//
// A page is any Item, or a Component or URL of one. Its `title` property (a
// string, if it has one) shows in the header; an AtlasPage then hides its own
// title row (its headerTrailing items stay). wentBack() is emitted when the
// stack pops by pop(), the Back button, Alt+Left or the mouse Back button.
Item {
    id: control

    // The value as `var`: a page is any item, and its `title` is read when it
    // has one (lint cannot know the page's type).
    function _untyped(o: var): var {
        return o;
    }

    // The page shown first.
    property var initialItem: null
    // Shows the Back button and the title row.
    property bool showHeader: true
    readonly property int depth: stack.depth
    readonly property bool canGoBack: stack.depth > 1
    readonly property Item currentItem: stack.currentItem

    signal wentBack

    // False until the first page is in, so only later changes are announced.
    property bool _ready: false
    Component.onCompleted: control._ready = true
    // Tells screen readers which page came up; a page without a title says nothing.
    function _announcePage(page: var): void {
        const t = page ? page["title"] : undefined;
        if (t !== undefined && t !== null && String(t).length > 0) {
            control.Accessible.announce(String(t));
        }
    }

    implicitWidth: Kirigami.Units.gridUnit * 24
    implicitHeight: Kirigami.Units.gridUnit * 16

    // Shows a page on top. `page` is an Item, Component or URL; `properties`
    // are set on it. Returns the new page.
    function push(page, properties) {
        return stack.push(page, properties === undefined || properties === null ? ({}) : properties);
    }

    // Goes back one page (nothing at the first page). Returns the page that
    // was removed, or null.
    function pop() {
        if (stack.depth <= 1) {
            return null;
        }
        const old = stack.pop();
        control.wentBack();
        return old;
    }

    // Goes back to the first page.
    function popToRoot() {
        while (stack.depth > 1) {
            control.pop();
        }
    }

    Shortcut {
        sequence: "Alt+Left"
        enabled: control.canGoBack && control.visible
        onActivated: control.pop()
    }
    TapHandler {
        acceptedButtons: Qt.BackButton
        grabPermissions: PointerHandler.ApprovesTakeOverByAnything
        enabled: control.canGoBack
        onTapped: control.pop()
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        RowLayout {
            id: header

            readonly property string title: {
                const page = control._untyped(stack.currentItem);
                const t = page ? page.title : undefined;
                return t === undefined || t === null ? "" : String(t);
            }

            Layout.fillWidth: true
            Layout.margins: AtlasStyle.spacing
            visible: control.showHeader
            spacing: AtlasStyle.spacing

            ToolbarButton {
                id: backButton
                symbol: Symbols.ArrowBack
                text: qsTr("Back")
                focusable: true
                enabled: control.canGoBack
                // The arrow points the other way in a right-to-left layout.
                transform: Scale {
                    origin.x: backButton.width / 2
                    xScale: control.LayoutMirroring.enabled ? -1 : 1
                }
                Accessible.role: Accessible.Button
                Accessible.name: qsTr("Back")
                onClicked: control.pop()
            }
            QQC2.Label {
                Layout.fillWidth: true
                text: header.title
                elide: Text.ElideRight
                font.pointSize: AtlasStyle.fontSizeHeading
                font.weight: Font.DemiBold
                color: Kirigami.Theme.textColor
                Accessible.role: Accessible.Heading
                Accessible.name: text
            }
        }

        QQC2.StackView {
            id: stack

            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            initialItem: control.initialItem

            // Tell an AtlasPage that the header shows its title.
            onCurrentItemChanged: {
                const page = stack.currentItem;
                if (control._ready) {
                    control._announcePage(page);
                }
                if (page && "_titleInHeader" in page) {
                    page._titleInHeader = Qt.binding(() => control.showHeader);
                }
            }

            readonly property int _dur: AtlasStyle.duration
            readonly property real _dir: control.LayoutMirroring.enabled ? -1 : 1

            pushEnter: Transition {
                NumberAnimation { property: "x"; from: stack.width * stack._dir; to: 0; duration: stack._dur; easing.type: Easing.OutCubic }
            }
            pushExit: Transition {
                NumberAnimation { property: "x"; from: 0; to: -stack.width * stack._dir * 0.3; duration: stack._dur; easing.type: Easing.OutCubic }
            }
            popEnter: Transition {
                NumberAnimation { property: "x"; from: -stack.width * stack._dir * 0.3; to: 0; duration: stack._dur; easing.type: Easing.OutCubic }
            }
            popExit: Transition {
                NumberAnimation { property: "x"; from: 0; to: stack.width * stack._dir; duration: stack._dur; easing.type: Easing.OutCubic }
            }
            replaceEnter: pushEnter
            replaceExit: pushExit
        }
    }
}
