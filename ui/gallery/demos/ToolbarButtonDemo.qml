import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Atlas.Ui

// Visual-test scene for ToolbarButton: fixed content, no timers or randomness. `animate`
// is switched off by tests/visual before the picture is taken.
Item {
    id: root

    property bool animate: true

    implicitWidth: 300
    implicitHeight: 70
    width: implicitWidth
    height: implicitHeight

    RowLayout {
        anchors.centerIn: parent
        spacing: 6
        ToolbarButton { icon.name: "format-text-bold"; text: "Bold"; shortcutText: "Ctrl+B" }
        ToolbarButton { icon.name: "format-text-italic"; text: "Italic"; checkable: true; checked: true }
        ToolbarButton { icon.name: "format-text-underline"; text: "Underline"; enabled: false }
        ToolbarButton { icon.name: "go-down"; text: "More"; iconRotation: 90 }
    }
}
