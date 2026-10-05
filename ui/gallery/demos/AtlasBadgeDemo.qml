import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Atlas.Ui

// Visual-test scene for AtlasBadge: fixed content, no timers or randomness.
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
            AtlasBadge { text: "Neutral" }
            AtlasBadge { text: "Accent"; type: "accent" }
            AtlasBadge { text: "Success"; type: "success" }
            AtlasBadge { text: "Warning"; type: "warning" }
            AtlasBadge { text: "Error"; type: "error" }
        }
        Row {
            spacing: 8
            AtlasBadge { text: "3"; type: "error" }
            AtlasBadge { text: "Verified"; type: "success"; symbol: Symbols.Check }
            AtlasBadge { symbol: Symbols.Star; type: "warning" }
        }
        Row {
            spacing: 8
            AtlasBadge { }
            AtlasBadge { type: "accent" }
            AtlasBadge { type: "success" }
            AtlasBadge { type: "warning" }
            AtlasBadge { type: "error" }
        }
    }
}
