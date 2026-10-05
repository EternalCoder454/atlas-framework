import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Atlas.Ui

// Visual-test scene for AtlasDetailGrid: fixed content, no timers or randomness.
// `animate` is switched off by tests/visual before the picture.
Item {
    id: root

    property bool animate: true

    implicitWidth: 520
    implicitHeight: 430
    width: implicitWidth
    height: implicitHeight

    readonly property var rows: [
        {
            label: "Version",
            value: "1.4.0"
        },
        {
            label: "Checksum",
            value: "9f86d081884c7d65",
            mono: true,
            copyable: true
        },
        {
            label: "Install location",
            value: "/usr/share/atlas/very/long/path/that/wraps/onto/another/line"
        },
        {
            label: "Licence",
            value: "MIT"
        }
    ]

    ColumnLayout {
        x: 16
        y: 16
        width: parent.width - 32
        spacing: 16
        AtlasDetailGrid {
            Layout.fillWidth: true
            model: root.rows
        }
        AtlasDetailGrid {
            Layout.fillWidth: true
            columns: 2
            columnsBreakpoint: 10
            model: root.rows
        }
        AtlasDetailGrid {
            Layout.preferredWidth: 220
            model: root.rows.slice(0, 2)
        }
    }
}
