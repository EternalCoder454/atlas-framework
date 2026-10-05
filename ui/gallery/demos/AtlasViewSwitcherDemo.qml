import QtQuick
import QtQuick.Layouts
import Atlas.Ui

// Visual-test scene for AtlasViewSwitcher: wide and narrow, with a badge.
Item {
    id: root

    property bool animate: true

    implicitWidth: 520
    implicitHeight: 130
    width: implicitWidth
    height: implicitHeight

    ColumnLayout {
        anchors.centerIn: parent
        spacing: 12

        AtlasViewSwitcher {
            Layout.alignment: Qt.AlignHCenter
            model: [
                { text: "Home", symbol: Symbols.Home },
                { text: "Updates", symbol: Symbols.Search, badge: 3 },
                { text: "Settings", symbol: Symbols.Settings }
            ]
            currentIndex: 1
        }
        AtlasViewSwitcher {
            Layout.alignment: Qt.AlignHCenter
            narrow: true
            model: [
                { text: "Home", symbol: Symbols.Home },
                { text: "Updates", symbol: Symbols.Search, badge: 120 },
                { text: "Settings", symbol: Symbols.Settings }
            ]
            currentIndex: 0
        }
    }
}
