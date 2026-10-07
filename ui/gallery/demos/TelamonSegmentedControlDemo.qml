import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Telamon.Ui

// Visual-test scene for TelamonSegmentedControl: fixed content, no timers or
// randomness. `animate` is switched off by tests/visual before the picture.
Item {
    id: root

    property bool animate: true

    implicitWidth: 340
    implicitHeight: 230
    width: implicitWidth
    height: implicitHeight

    ColumnLayout {
        x: 16
        y: 16
        spacing: 16
        TelamonSegmentedControl {
            Accessible.name: "View"
            model: ["List", "Grid", "Table"]
            currentIndex: 1
        }
        TelamonSegmentedControl {
            Accessible.name: "Layout"
            model: [{
                    "symbol": Symbols.ViewList,
                    "toolTip": "List"
                }, {
                    "symbol": Symbols.GridView,
                    "toolTip": "Grid"
                }, {
                    "symbol": Symbols.Settings,
                    "toolTip": "Settings"
                }]
            currentIndex: 0
        }
        // Too narrow for its text: the labels are elided.
        TelamonSegmentedControl {
            Accessible.name: "Narrow"
            Layout.preferredWidth: 150
            Layout.maximumWidth: 150
            model: ["Everything", "Unread messages", "Starred"]
            currentIndex: 0
        }
        TelamonSegmentedControl {
            Accessible.name: "Disabled"
            enabled: false
            model: ["List", "Grid", "Table"]
            currentIndex: 2
        }
    }
}
