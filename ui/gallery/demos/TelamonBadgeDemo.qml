import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Telamon.Ui

// Visual-test scene for TelamonBadge: fixed content, no timers or randomness.
// `animate` is switched off by tests/visual before the picture.
Item {
    id: root

    property bool animate: true

    implicitWidth: 360
    implicitHeight: 140
    width: implicitWidth
    height: implicitHeight

    ColumnLayout {
        x: 16
        y: 16
        spacing: 12
        Row {
            spacing: 8
            TelamonBadge { text: "Neutral" }
            TelamonBadge { text: "Accent"; type: "accent" }
            TelamonBadge { text: "Success"; type: "success" }
            TelamonBadge { text: "Warning"; type: "warning" }
            TelamonBadge { text: "Error"; type: "error" }
        }
        Row {
            spacing: 8
            TelamonBadge { text: "3"; type: "error" }
            TelamonBadge { text: "Verified"; type: "success"; symbol: Symbols.Check }
            TelamonBadge { symbol: Symbols.Star; type: "warning" }
        }
        Row {
            spacing: 8
            TelamonBadge { }
            TelamonBadge { type: "accent" }
            TelamonBadge { type: "success" }
            TelamonBadge { type: "warning" }
            TelamonBadge { type: "error" }
        }
    }
}
