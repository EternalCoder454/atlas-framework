import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Atlas.Ui

// Visual-test scene for AtlasChip and AtlasChipGroup: fixed content, no timers
// or randomness. `animate` is switched off by tests/visual before the picture.
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
        spacing: 12
        Row {
            spacing: 8
            AtlasChip { text: "Plain" }
            AtlasChip { text: "Symbol"; symbol: Symbols.Favorite }
            AtlasChip { text: "Checked"; checkable: true; checked: true }
            AtlasChip { text: "Off"; checkable: true }
        }
        Row {
            spacing: 8
            AtlasChip { text: "Closable"; closable: true }
            AtlasChip { text: "Both"; checkable: true; checked: true; closable: true }
            AtlasChip { text: "Disabled"; enabled: false }
        }
        AtlasChipGroup {
            Layout.preferredWidth: 220
            exclusive: true
            AtlasChip { text: "All"; checkable: true; checked: true }
            AtlasChip { text: "Unread"; checkable: true }
            AtlasChip { text: "Starred"; checkable: true }
            AtlasChip { text: "Archived"; checkable: true }
            AtlasChip { text: "Drafts"; checkable: true }
        }
    }
}
