import QtQuick
import QtQuick.Layouts
import QtQuick.Templates as T
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import Telamon.Ui

// The general modal dialog: a title row, a scrolling body and a row of
// buttons (ConfirmDialog is the yes/no one). The window behind is dimmed,
// Escape closes it, and the focus starts on the first thing in the body that
// can take it (the dialog itself when the body has nothing, never a button).
// A body taller than the window scrolls instead of outgrowing it, and the
// dialog is never wider than the window. The body scrolls to a field that
// takes the focus.
//
// The header has an optional Back button at the leading edge (`showBack`,
// then `backRequested()`; the dialog doesn't close itself), the `title`,
// `headerTrailing` items, and a Close button at the trailing edge
// (`showClose`, on by default; it rejects the dialog). `footerContent` holds
// the buttons, right-aligned, in KDE order: the main action last.
//
//   TelamonDialog {
//       title: qsTr("Add account")
//       footerContent: [
//           SecondaryButton { text: qsTr("Cancel"); onClicked: close() },
//           PrimaryButton { text: qsTr("Add"); onClicked: { add(); close() } }
//       ]
//       TelamonTextField { Layout.fillWidth: true; placeholderText: qsTr("Name") }
//   }
T.Dialog {
    id: control

    property bool showBack: false
    property bool showClose: true
    // The body is as wide as this, up to the window's width less the margins.
    property real preferredWidth: Kirigami.Units.gridUnit * 30
    // Items in the header, before the Close button.
    property alias headerTrailing: trailingRow.data
    // The buttons, in KDE order (cancel first, the main action last).
    property alias footerContent: footerRow.data
    default property alias content: body.data

    // The Back button was used.
    signal backRequested

    readonly property real _margin: Kirigami.Units.gridUnit * 2

    parent: QQC2.Overlay.overlay
    anchors.centerIn: parent
    modal: true
    focus: true
    closePolicy: T.Popup.CloseOnEscape | T.Popup.CloseOnPressOutside
    padding: TelamonStyle.spacingLarge * 2
    // The footer has its own bottom margin.
    bottomPadding: footerRow.children.length > 0 ? 0 : padding
    width: Math.min(control.preferredWidth, parent ? Math.max(0, parent.width - control._margin) : control.preferredWidth)
    implicitHeight: Math.max(implicitBackgroundHeight + topInset + bottomInset, contentHeight + topPadding + bottomPadding + (implicitHeaderHeight > 0 ? implicitHeaderHeight + spacing : 0) + (implicitFooterHeight > 0 ? implicitFooterHeight + spacing : 0))
    height: Math.min(implicitHeight, parent ? Math.max(0, parent.height - control._margin) : implicitHeight)
    spacing: TelamonStyle.spacingLarge

    // Moves the body to its top, with no animation. Focus does not move.
    function scrollToTop(): void {
        if (!scroller) {
            return;
        }
        scroller.cancelFlick();
        scroller.contentY = scroller.originY;
    }
    // A reopened dialog does not keep the last scroll.
    onAboutToShow: control.scrollToTop()

    // Keeps the item that took the focus in view in the body.
    // In a list property of its own, not the default one (content).
    readonly property list<QtObject> _watchers: [
        Connections {
            target: control.parent ? control.parent.Window.window : null
            function onActiveFocusItemChanged(): void {
                const win = control.parent ? control.parent.Window.window : null;
                const item = win ? win.activeFocusItem : null;
                if (control.visible && item && control._inside(item) && item !== control.contentItem && scroller && scroller.contentItem) {
                    control._reveal(item);
                }
            }
        }
    ]
    function _reveal(item: Item): void {
        const top = item.mapToItem(scroller.contentItem, 0, 0).y;
        const bottom = top + item.height;
        const view = scroller.height;
        if (top < scroller.contentY) {
            scroller.contentY = Math.max(scroller.originY, top);
        } else if (bottom > scroller.contentY + view) {
            // A tall item (a text area) shows its top rather than its end.
            scroller.contentY = Math.min(top, bottom - view);
        }
    }

    // True when item is in the body (the content item), not the header or the footer.
    function _inside(item: Item): bool {
        for (let i = item; i; i = i.parent) {
            if (i === control.contentItem) {
                return true;
            }
        }
        return false;
    }

    // The first item the Tab key reaches in the body; the dialog itself when
    // there is none (never a header or footer button, so Return right after
    // opening cannot press Back, Close or Cancel), so Escape still works.
    onOpened: {
        const first = control.contentItem.nextItemInFocusChain(true);
        if (first && control._inside(first)) {
            first.forceActiveFocus(Qt.PopupFocusReason);
        } else {
            control.forceActiveFocus(Qt.PopupFocusReason);
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

    QQC2.Overlay.modal: Rectangle {
        color: Qt.rgba(0, 0, 0, 0.35)
    }

    background: Rectangle {
        radius: TelamonStyle.radiusLarge
        // Raised, strongly tinted over the blur; solid without it (floatingBackground switches).
        color: TelamonStyle.floatingBackground
        border.width: 1
        border.color: TelamonStyle.separator
    }

    header: Item {
        visible: control.title.length > 0 || control.showBack || control.showClose || trailingRow.children.length > 0
        implicitHeight: visible ? headerRow.implicitHeight + TelamonStyle.spacingLarge : 0
        // The header spans the card: its own margins, the dialog's padding is for the body.
        RowLayout {
            id: headerRow
            anchors.fill: parent
            anchors.topMargin: TelamonStyle.spacingLarge
            anchors.leftMargin: TelamonStyle.spacingLarge * 2 - TelamonStyle.spacingSmall
            anchors.rightMargin: TelamonStyle.spacingLarge * 2 - TelamonStyle.spacingSmall
            spacing: TelamonStyle.spacing
            ToolbarButton {
                visible: control.showBack
                focusable: true
                symbol: LayoutMirroring.enabled ? Symbols.ArrowForward : Symbols.ArrowBack
                //: Name of the Back button in a dialog's title row
                text: qsTr("Back")
                onClicked: control.backRequested()
            }
            QQC2.Label {
                Layout.fillWidth: true
                Layout.leftMargin: control.showBack ? 0 : TelamonStyle.spacingSmall
                Layout.rightMargin: control.showClose || trailingRow.children.length > 0 ? 0 : TelamonStyle.spacingSmall
                text: control.title
                font.bold: true
                font.pointSize: TelamonStyle.fontSizeHeading
                color: TelamonStyle.text
                elide: Text.ElideRight
                textFormat: Text.PlainText
                Accessible.role: Accessible.Heading
            }
            RowLayout {
                id: trailingRow
                spacing: TelamonStyle.spacing
            }
            ToolbarButton {
                visible: control.showClose
                focusable: true
                symbol: Symbols.Close
                //: Name of the Close button in a dialog's title row
                text: qsTr("Close")
                onClicked: control.reject()
            }
        }
    }

    contentItem: Item {
        implicitWidth: scroller.implicitWidth
        implicitHeight: scroller.implicitHeight
        Accessible.role: Accessible.Dialog
        Accessible.name: control.title
        Flickable {
            id: scroller
            anchors.fill: parent
            implicitWidth: body.implicitWidth
            implicitHeight: body.implicitHeight
            contentWidth: width
            contentHeight: body.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            QQC2.ScrollBar.vertical: TelamonScrollBar {}
            ColumnLayout {
                id: body
                width: scroller.width
                spacing: TelamonStyle.spacing
            }
        }
    }

    footer: Item {
        visible: footerRow.children.length > 0
        implicitHeight: visible ? footerLayout.implicitHeight + TelamonStyle.spacingLarge * 2 : 0
        RowLayout {
            id: footerLayout
            anchors.fill: parent
            anchors.leftMargin: TelamonStyle.spacingLarge * 2
            anchors.rightMargin: TelamonStyle.spacingLarge * 2
            anchors.bottomMargin: TelamonStyle.spacingLarge * 2
            spacing: 0
            Item {
                Layout.fillWidth: true
            }
            RowLayout {
                id: footerRow
                spacing: TelamonStyle.spacingLarge
            }
        }
    }
}
