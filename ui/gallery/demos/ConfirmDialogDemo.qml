import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Atlas.Ui

// Visual-test scene for ConfirmDialog: fixed content, no timers or randomness. `animate`
// is switched off by tests/visual before the picture is taken.
Item {
    id: root

    property bool animate: true

    implicitWidth: 520
    implicitHeight: 300
    width: implicitWidth
    height: implicitHeight

    ConfirmDialog {
        parent: root
        title: "Remove this item?"
        text: "It can not be restored."
        acceptText: "Remove"
        rejectText: "Keep"
        alternativeText: "Archive"
        defaultButton: "reject"
        destructive: true
        Component.onCompleted: open()
    }
}
