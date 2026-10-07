import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Telamon.Ui

// Visual-test scene for TelamonDialog: fixed content, no timers or randomness. `animate`
// is switched off by tests/visual before the picture is taken.
Item {
    id: root

    property bool animate: true

    implicitWidth: 560
    implicitHeight: 380
    width: implicitWidth
    height: implicitHeight

    TelamonDialog {
        parent: root
        title: "Add account"
        showBack: true
        preferredWidth: 420
        headerTrailing: [
            TelamonLabel {
                text: "Step 2 of 2"
                opacity: 0.65
            }
        ]
        footerContent: [
            SecondaryButton {
                text: "Cancel"
            },
            PrimaryButton {
                text: "Add"
            }
        ]
        TelamonTextField {
            Layout.fillWidth: true
            placeholderText: "Name"
        }
        TelamonTextField {
            Layout.fillWidth: true
            placeholderText: "Server"
        }
        TelamonCheckBox {
            text: "Sync automatically"
            checked: true
        }
        Component.onCompleted: open()
    }
}
