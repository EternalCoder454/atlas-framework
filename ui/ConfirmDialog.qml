import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

// Modal dialog in the Telamon look: rounded card, TelamonButtons.
//
// Two buttons by default (`rejectText`, `acceptText`); a non-empty
// `alternativeText` ("Don't Save") adds a third at the leading edge, which
// emits `alternative()`. `defaultButton` ("accept", "reject" or "alternative")
// is the one that starts with the focus, that Return and Enter activate from
// anywhere in the dialog, and that is drawn filled. `destructive` gives the
// accept button the Destructive look (error text and border on a faint error
// fill) in place of the filled one. The text and the body are as wide as the
// card and wrap; when they are taller than the window they scroll.
//
//   ConfirmDialog {
//       title: qsTr("Save changes?")
//       acceptText: qsTr("Save"); alternativeText: qsTr("Don't Save")
//       onAccepted: save()
//       onAlternative: discard()
//   }
QQC2.Popup {
    id: dialog

    property string title
    property string text
    //: Default text of the confirming button of a dialog
    property string acceptText: qsTr("OK")
    property string rejectText: qsTr("Cancel")
    property bool showReject: true
    // Destructive dialogs start on Cancel; informational ones on the main button.
    property bool focusReject: false
    // Closes the dialog after accepted() or alternative().
    property bool closeOnAccept: true
    // A third button, before Cancel; empty for none.
    property string alternativeText
    // "accept" (default), "reject" or "alternative".
    property string defaultButton: "accept"
    // The accept button in TelamonButton's Destructive look (for deleting, resetting).
    property bool destructive: false
    default property alias body: bodyColumn.data

    signal accepted
    signal alternative

    QtObject {
        id: internals
        // The button the dialog starts on and Return activates. A name that
        // names no shown button falls back to accept.
        readonly property string defaultName: dialog.defaultButton === "reject" && dialog.showReject ? "reject" : dialog.defaultButton === "alternative" && dialog.alternativeText.length > 0 ? "alternative" : "accept"

        // Return from a field in the body must not run a destructive accept (or
        // anything on a dialog that starts on Cancel); the buttons still take
        // Return themselves.
        readonly property bool bodyReturnBlocked: defaultName === "accept" && (dialog.destructive || dialog.focusReject && dialog.showReject)

        function button(name: string): TelamonButton {
            return name === "reject" ? rejectButton : name === "alternative" ? alternativeButton : acceptButton;
        }
        function activateDefault(): void {
            const b = button(defaultName);
            if (b.enabled) {
                b.clicked();
            }
        }
    }

    parent: QQC2.Overlay.overlay
    anchors.centerIn: parent
    modal: true
    focus: true
    closePolicy: QQC2.Popup.CloseOnEscape | QQC2.Popup.CloseOnPressOutside
    width: Math.min(parent ? Math.max(0, parent.width - Kirigami.Units.gridUnit * 2) : 0, Kirigami.Units.gridUnit * 25)
    padding: Math.round(Kirigami.Units.gridUnit * 1.3)
    height: Math.min(implicitHeight, parent ? Math.max(0, parent.height - Kirigami.Units.gridUnit * 2) : implicitHeight)
    onOpened: internals.button(dialog.focusReject && dialog.showReject ? "reject" : internals.defaultName).forceActiveFocus()

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

    contentItem: ColumnLayout {
        Accessible.role: Accessible.Dialog
        Accessible.name: dialog.title
        // The question, so a screen reader reads it with the title.
        Accessible.description: dialog.text
        spacing: TelamonStyle.spacingLarge
        // From a field in the body, Return reaches here; buttons take it themselves.
        Keys.onReturnPressed: event => {
            if (!event.isAutoRepeat && !internals.bodyReturnBlocked) {
                internals.activateDefault();
            }
            event.accepted = true;
        }
        Keys.onEnterPressed: event => {
            if (!event.isAutoRepeat && !internals.bodyReturnBlocked) {
                internals.activateDefault();
            }
            event.accepted = true;
        }
        QQC2.Label {
            id: titleLabel
            Layout.fillWidth: true
            text: dialog.title
            font.bold: true
            font.pointSize: TelamonStyle.fontSizeHeading
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
            Accessible.role: Accessible.Heading
        }
        // The text and the body scroll together when they are taller than the card.
        Flickable {
            id: scroller
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredHeight: bodyContent.implicitHeight
            Layout.minimumHeight: Math.min(bodyContent.implicitHeight, Kirigami.Units.gridUnit * 3)
            contentWidth: width
            contentHeight: bodyContent.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            QQC2.ScrollBar.vertical: TelamonScrollBar {}
            ColumnLayout {
                id: bodyContent
                width: scroller.width
                spacing: TelamonStyle.spacingLarge
                QQC2.Label {
                    Layout.fillWidth: true
                    visible: dialog.text.length > 0
                    text: dialog.text
                    wrapMode: Text.Wrap
                    opacity: 0.8
                    textFormat: Text.PlainText
                }
                ColumnLayout {
                    id: bodyColumn
                    Layout.fillWidth: true
                    spacing: TelamonStyle.spacingLarge
                }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: TelamonStyle.spacingSmall
            spacing: TelamonStyle.spacingLarge
            TelamonButton {
                id: alternativeButton
                visible: dialog.alternativeText.length > 0
                prominent: internals.defaultName === "alternative"
                text: dialog.alternativeText
                onClicked: {
                    dialog.alternative();
                    if (dialog.closeOnAccept) {
                        dialog.close();
                    }
                }
            }
            Item {
                Layout.fillWidth: true
            }
            TelamonButton {
                id: rejectButton
                visible: dialog.showReject
                prominent: internals.defaultName === "reject"
                text: dialog.rejectText
                onClicked: dialog.close()
            }
            TelamonButton {
                id: acceptButton
                variant: dialog.destructive ? TelamonButton.Destructive : (internals.defaultName === "accept" ? TelamonButton.Prominent : TelamonButton.Default)
                text: dialog.acceptText
                onClicked: {
                    dialog.accepted();
                    if (dialog.closeOnAccept) {
                        dialog.close();
                    }
                }
            }
        }
    }
}
