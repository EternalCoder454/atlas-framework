import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Atlas.Ui

// Every state of AtlasInstallButton, and a progress of 0.4. Not part of any
// build target: load it with `qml` to look at it.
Rectangle {
    id: root

    // False stops the one running animation (the unknown-progress slide).
    property bool animate: true

    implicitWidth: Kirigami.Units.gridUnit * 36
    implicitHeight: Kirigami.Units.gridUnit * 14
    color: Kirigami.Theme.backgroundColor

    GridLayout {
        anchors.centerIn: parent
        columns: 2
        columnSpacing: Kirigami.Units.gridUnit * 2
        rowSpacing: Kirigami.Units.largeSpacing

        Repeater {
            model: [
                {
                    label: "install",
                    progress: -1
                },
                {
                    label: "installing",
                    progress: 0.4
                },
                {
                    label: "installing",
                    progress: -1
                },
                {
                    label: "installed",
                    progress: -1
                },
                {
                    label: "update",
                    progress: -1
                },
                {
                    label: "error",
                    progress: -1
                }
            ]
            delegate: RowLayout {
                id: cell
                required property var modelData
                readonly property bool unknown: cell.modelData.label === "installing" && cell.modelData.progress < 0
                Layout.columnSpan: 2
                spacing: Kirigami.Units.gridUnit
                Text {
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 12
                    text: cell.modelData.label + (cell.modelData.label === "installing" ? (cell.unknown ? " (unknown)" : " (0.4)") : "")
                    color: Kirigami.Theme.textColor
                    font: Kirigami.Theme.defaultFont
                }
                AtlasInstallButton {
                    animated: root.animate
                    installState: cell.modelData.label
                    // With animation off the unknown slide is replaced by a figure.
                    progress: cell.unknown && !root.animate ? 0.4 : cell.modelData.progress
                }
                AtlasInstallButton {
                    animated: root.animate
                    enabled: false
                    installState: cell.modelData.label
                    progress: cell.modelData.progress < 0 ? 0.4 : cell.modelData.progress
                }
            }
        }
    }
}
