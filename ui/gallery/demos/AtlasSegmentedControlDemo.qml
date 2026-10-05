import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Atlas.Ui

// Visual-test scene for AtlasSegmentedControl: fixed content, no timers or
// randomness. `animate` is switched off by tests/visual before the picture.
Item {
    id: root

    property bool animate: true

    implicitWidth: 340
    implicitHeight: 150
    width: implicitWidth
    height: implicitHeight

    ColumnLayout {
        x: 16
        y: 16
        spacing: 16
        AtlasSegmentedControl {
            Accessible.name: "View"
            model: ["List", "Grid", "Table"]
            currentIndex: 1
        }
        AtlasSegmentedControl {
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
    }
}
