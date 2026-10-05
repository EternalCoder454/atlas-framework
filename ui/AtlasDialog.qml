import QtQuick
import QtQuick.Layouts
import QtQuick.Templates as T
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import Atlas.Ui

// The general modal dialog: a title row, a scrolling body and a row of
// buttons (ConfirmDialog is the yes/no one). The window behind is dimmed,
// Escape closes it, and the focus starts on the first thing in the body that
// can take it (the dialog itself when the body has nothing, never a button).
// A body taller than the window scrolls instead of outgrowing it, and the
// dialog is never wider than the window.
//
// The header has an optional Back button at the leading edge (`showBack`,
// then `backRequested()`; the dialog doesn't close itself), the `title`,
// `headerTrailing` items, and a Close button at the trailing edge
// (`showClose`, on by default; it rejects the dialog). `footerContent` holds
// the buttons, right-aligned, in KDE order: the main action last.
//
//   AtlasDialog {
//       title: qsTr("Add account")
//       footerContent: [
//           SecondaryButton { text: qsTr("Cancel"); onClicked: close() },
//           PrimaryButton { text: qsTr("Add"); onClicked: { add(); close() } }
//       ]
//       AtlasTextField { Layout.fillWidth: true; placeholderText: qsTr("Name") }
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
    padding: AtlasStyle.spacingLarge * 2
    // The footer has its own bottom margin.
    bottomPadding: footerRow.children.length > 0 ? 0 : padding
    width: Math.min(control.preferredWidth, parent ? parent.width - control._margin : control.preferredWidth)
    implicitHeight: Math.max(implicitBackgroundHeight + topInset + bottomInset, contentHeight + topPadding + bottomPadding + (implicitHeaderHeight > 0 ? implicitHeaderHeight + spacing : 0) + (implicitFooterHeight > 0 ? implicitFooterHeight + spacing : 0))
    height: Math.min(implicitHeight, parent ? parent.height - control._margin : implicitHeight)
    spacing: AtlasStyle.spacingLarge

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

    QQC2.Overlay.modal: Rectangle {
        color: Qt.rgba(0, 0, 0, 0.35)
    }

    background: Rectangle {
        radius: AtlasStyle.radiusLarge
        // Raised, strongly tinted over the blur; solid without it (floatingBackground switches).
        color: AtlasStyle.floatingBackground
        border.width: 1
        border.color: AtlasStyle.separator
    }

    header: Item {
        visible: control.title.length > 0 || control.showBack || control.showClose || trailingRow.children.length > 0
        implicitHeight: visible ? headerRow.implicitHeight + AtlasStyle.spacingLarge : 0
        // The header spans the card: its own margins, the dialog's padding is for the body.
        RowLayout {
            id: headerRow
            anchors.fill: parent
            anchors.topMargin: AtlasStyle.spacingLarge
            anchors.leftMargin: AtlasStyle.spacingLarge * 2 - AtlasStyle.spacingSmall
            anchors.rightMargin: AtlasStyle.spacingLarge * 2 - AtlasStyle.spacingSmall
            spacing: AtlasStyle.spacing
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
                Layout.leftMargin: control.showBack ? 0 : AtlasStyle.spacingSmall
                Layout.rightMargin: control.showClose || trailingRow.children.length > 0 ? 0 : AtlasStyle.spacingSmall
                text: control.title
                font.bold: true
                font.pointSize: AtlasStyle.fontSizeHeading
                color: AtlasStyle.text
                elide: Text.ElideRight
                textFormat: Text.PlainText
                Accessible.role: Accessible.Heading
            }
            RowLayout {
                id: trailingRow
                spacing: AtlasStyle.spacing
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
            QQC2.ScrollBar.vertical: AtlasScrollBar {}
            ColumnLayout {
                id: body
                width: scroller.width
                spacing: AtlasStyle.spacing
            }
        }
    }

    footer: Item {
        visible: footerRow.children.length > 0
        implicitHeight: visible ? footerLayout.implicitHeight + AtlasStyle.spacingLarge * 2 : 0
        RowLayout {
            id: footerLayout
            anchors.fill: parent
            anchors.leftMargin: AtlasStyle.spacingLarge * 2
            anchors.rightMargin: AtlasStyle.spacingLarge * 2
            anchors.bottomMargin: AtlasStyle.spacingLarge * 2
            spacing: 0
            Item {
                Layout.fillWidth: true
            }
            RowLayout {
                id: footerRow
                spacing: AtlasStyle.spacingLarge
            }
        }
    }
}
