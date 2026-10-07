import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Telamon.Ui

// Visual-test scene for TelamonChip and TelamonChipGroup: fixed content, no timers
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
            TelamonChip { text: "Plain" }
            TelamonChip { text: "Symbol"; symbol: Symbols.Favorite }
            TelamonChip { text: "Checked"; checkable: true; checked: true }
            TelamonChip { text: "Off"; checkable: true }
        }
        Row {
            spacing: 8
            TelamonChip { text: "Closable"; closable: true }
            TelamonChip { text: "Both"; checkable: true; checked: true; closable: true }
            TelamonChip { text: "Disabled"; enabled: false }
        }
        TelamonChipGroup {
            Layout.preferredWidth: 220
            exclusive: true
            TelamonChip { text: "All"; checkable: true; checked: true }
            TelamonChip { text: "Unread"; checkable: true }
            TelamonChip { text: "Starred"; checkable: true }
            TelamonChip { text: "Archived"; checkable: true }
            TelamonChip { text: "Drafts"; checkable: true }
        }
    }
}
