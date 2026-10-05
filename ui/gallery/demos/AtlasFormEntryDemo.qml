import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Atlas.Ui

// Visual-test scene for AtlasFormEntry: one row of each kind of control, an
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
        AtlasFormEntry {
            label: "Volume"
            help: "From 0 to 100"
            AtlasSlider {
                from: 0
                to: 100
                value: 40
            }
        }
        AtlasFormEntry {
            label: "Port"
            errorText: "Use a port from 1 to 65535"
            AtlasSpinBox {
                from: 1
                to: 65535
                value: 80
            }
        }
        AtlasFormEntry {
            label: "Colour"
            AtlasColorField {
                color: "#3daee9" // atlas-lint: allow-raw (sample value)
            }
        }
        AtlasFormEntry {
            label: "Download folder"
            AtlasFolderField {
                path: "/home/user/Downloads"
            }
        }
        AtlasFormEntry {
            label: "Disabled option"
            enabled: false
            AtlasCheckBox {
                text: "Off"
            }
        }
        AtlasFormEntry {
            label: "A label that is long enough to wrap onto a second line in a narrow row"
            stacked: true
            AtlasTextField {
                Layout.fillWidth: true
                placeholderText: "Stacked under its label"
            }
        }
    }
}
