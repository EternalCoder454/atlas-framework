import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Atlas.Ui

// Visual-test scene for AtlasForm: fixed content, no timers or randomness.
// `animate` is switched off by tests/visual before the picture.
Item {
    id: root

    property bool animate: true

    implicitWidth: 520
    implicitHeight: 440
    width: implicitWidth
    height: implicitHeight

    AtlasForm {
        id: form
        x: 16
        y: 16
        width: root.width - 32

        Section {
            title: "Account"
            footer: "Shown to the people you share with."
            AtlasFormEntry {
                label: "Name"
                help: "Your full name"
                required: true
                AtlasTextField {
                    implicitWidth: 200
                    text: "Ada Lovelace"
                }
            }
            AtlasFormEntry {
                label: "Email"
                errorText: "Not an address"
                AtlasTextField {
                    implicitWidth: 200
                    text: "ada@"
                }
            }
            AtlasFormEntry {
                label: "Sync"
                AtlasSwitch {
                    checked: true
                }
            }
            AtlasFormEntry {
                label: "Theme"
                AtlasComboBox {
                    model: ["System", "Light", "Dark"]
                    currentIndex: 0
                }
            }
        }
        Section {
            title: "Notes"
            AtlasFormEntry {
                label: "About"
                help: "A text area sits under its label"
                AtlasTextArea {
                    Layout.fillWidth: true
                    text: "Hello"
                }
            }
        }
        PrimaryButton {
            Layout.alignment: Qt.AlignRight
            text: "Save"
        }
    }
}
