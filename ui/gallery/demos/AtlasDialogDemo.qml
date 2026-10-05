import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Atlas.Ui

// Visual-test scene for AtlasDialog: fixed content, no timers or randomness. `animate`
// is switched off by tests/visual before the picture is taken.
Item {
    id: root

    property bool animate: true

    implicitWidth: 560
    implicitHeight: 380
    width: implicitWidth
    height: implicitHeight

    AtlasDialog {
        parent: root
        title: "Add account"
        showBack: true
        preferredWidth: 420
        headerTrailing: [
            AtlasLabel {
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
        AtlasTextField {
            Layout.fillWidth: true
            placeholderText: "Name"
        }
        AtlasTextField {
            Layout.fillWidth: true
            placeholderText: "Server"
        }
        AtlasCheckBox {
            text: "Sync automatically"
            checked: true
        }
        Component.onCompleted: open()
    }
}
