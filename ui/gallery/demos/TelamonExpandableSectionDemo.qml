import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Telamon.Ui

// Visual-test scene for TelamonExpandableSection: fixed content, no timers or randomness. `animate`
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
        TelamonExpandableSection {
            title: "Advanced"
            subtitle: "For experts"
            symbol: Symbols.Settings
            expanded: true
            TelamonCheckBox {
                text: "Verbose log"
            }
            TelamonCheckBox {
                text: "Keep old versions"
            }
        }
        TelamonExpandableSection {
            title: "Folded"
            TelamonCheckBox {
                text: "Hidden"
            }
        }
        Item {
            Layout.fillHeight: true
        }
    }
}
