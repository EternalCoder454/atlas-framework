import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Atlas.Ui

// Visual-test scene for AtlasButton: fixed content, no timers or randomness. `animate`
// is switched off by tests/visual before the picture is taken.
Item {
    id: root

    property bool animate: true

    implicitWidth: 420
    implicitHeight: 130
    width: implicitWidth
    height: implicitHeight

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 10
        RowLayout {
            spacing: 10
            AtlasButton { text: "Default" }
            AtlasButton { text: "Prominent"; prominent: true }
            AtlasButton { text: "Icon"; icon.name: "document-save" }
            AtlasButton { text: "Disabled"; enabled: false }
        }
        RowLayout {
            spacing: 10
            AtlasButton { text: "Symbol"; symbol: Symbols.codepoint("home") }
            AtlasButton { text: "Checked"; checkable: true; checked: true }
        }
    }
}
