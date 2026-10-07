import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Telamon.Ui

// Visual-test scene for TelamonForm: fixed content, no timers or randomness.
// `animate` is switched off by tests/visual before the picture.
Item {
    id: root

    property bool animate: true

    implicitWidth: 520
    implicitHeight: 440
    width: implicitWidth
    height: implicitHeight

    TelamonForm {
        id: form
        x: 16
        y: 16
        width: root.width - 32

        Section {
            title: "Account"
            footer: "Shown to the people you share with."
            TelamonFormEntry {
                label: "Name"
                help: "Your full name"
                required: true
                TelamonTextField {
                    implicitWidth: 200
                    text: "Ada Lovelace"
                }
            }
            TelamonFormEntry {
                label: "Email"
                errorText: "Not an address"
                TelamonTextField {
                    implicitWidth: 200
                    text: "ada@"
                }
            }
            TelamonFormEntry {
                label: "Sync"
                TelamonSwitch {
                    checked: true
                }
            }
            TelamonFormEntry {
                label: "Theme"
                TelamonComboBox {
                    model: ["System", "Light", "Dark"]
                    currentIndex: 0
                }
            }
        }
        Section {
            title: "Notes"
            TelamonFormEntry {
                label: "About"
                help: "A text area sits under its label"
                TelamonTextArea {
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
