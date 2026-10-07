import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Telamon.Ui

// Visual-test scene for TelamonFormEntry: one row of each kind of control, an
// error, a disabled row and a stacked row. Fixed content, no timers or
// randomness. `animate` is switched off by tests/visual before the picture.
Item {
    id: root

    property bool animate: true

    implicitWidth: 520
    implicitHeight: 470
    width: implicitWidth
    height: implicitHeight

    Section {
        x: 16
        y: 16
        width: root.width - 32
        TelamonFormEntry {
            label: "Volume"
            help: "From 0 to 100"
            TelamonSlider {
                from: 0
                to: 100
                value: 40
            }
        }
        TelamonFormEntry {
            label: "Port"
            errorText: "Use a port from 1 to 65535"
            TelamonSpinBox {
                from: 1
                to: 65535
                value: 80
            }
        }
        TelamonFormEntry {
            label: "Colour"
            TelamonColorField {
                color: "#3daee9" // telamon-lint: allow-raw (sample value)
            }
        }
        TelamonFormEntry {
            label: "Download folder"
            TelamonFolderField {
                path: "/home/user/Downloads"
            }
        }
        TelamonFormEntry {
            label: "Disabled option"
            enabled: false
            TelamonCheckBox {
                text: "Off"
            }
        }
        TelamonFormEntry {
            label: "A label that is long enough to wrap onto a second line in a narrow row"
            stacked: true
            TelamonTextField {
                Layout.fillWidth: true
                placeholderText: "Stacked under its label"
            }
        }
    }
}
