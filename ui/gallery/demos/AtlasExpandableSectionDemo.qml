import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Atlas.Ui

// Visual-test scene for AtlasExpandableSection: fixed content, no timers or randomness. `animate`
// is switched off by tests/visual before the picture is taken.
Item {
    id: root

    property bool animate: true

    implicitWidth: 440
    implicitHeight: 300
    width: implicitWidth
    height: implicitHeight

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 4
        AtlasExpandableSection {
            title: "Advanced"
            subtitle: "For experts"
            symbol: Symbols.Settings
            expanded: true
            AtlasCheckBox {
                text: "Verbose log"
            }
            AtlasCheckBox {
                text: "Keep old versions"
            }
        }
        AtlasExpandableSection {
            title: "Folded"
            AtlasCheckBox {
                text: "Hidden"
            }
        }
        Item {
            Layout.fillHeight: true
        }
    }
}
