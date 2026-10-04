import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Atlas.Ui

// AtlasBreadcrumb with a short path, an overflowing one (in a narrow box),
// and the last segment pressed, shown below. Not part of any build target.
Rectangle {
    id: root

    // Nothing here moves on its own; kept so every demo takes the same switch.
    property bool animate: true
    property string last: "(nothing pressed)"

    implicitWidth: Kirigami.Units.gridUnit * 36
    implicitHeight: Kirigami.Units.gridUnit * 12
    color: Kirigami.Theme.backgroundColor

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.gridUnit
        spacing: Kirigami.Units.gridUnit

        AtlasBreadcrumb {
            objectName: "short"
            Layout.fillWidth: true
            segments: [
                {
                    title: "Home",
                    symbol: Symbols.Home
                },
                {
                    title: "Documents"
                },
                {
                    title: "Projects"
                }
            ]
            onActivated: index => root.last = "short: " + index
        }
        AtlasBreadcrumb {
            objectName: "long"
            Layout.preferredWidth: Kirigami.Units.gridUnit * 20
            focus: true
            segments: [
                {
                    title: "Home",
                    symbol: Symbols.Home
                },
                {
                    title: "Documents"
                },
                {
                    title: "Projects"
                },
                {
                    title: "Atlas Framework"
                },
                {
                    title: "ui"
                },
                {
                    title: "gallery"
                },
                {
                    title: "demos"
                }
            ]
            onActivated: index => root.last = "long: " + index
        }
        Text {
            objectName: "status"
            text: root.last
            color: Kirigami.Theme.textColor
            font: Kirigami.Theme.defaultFont
        }
        Item {
            Layout.fillHeight: true
        }
    }
}
