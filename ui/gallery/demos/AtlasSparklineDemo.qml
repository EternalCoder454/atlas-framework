import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Atlas.Ui

// Visual-test scene for AtlasSparkline: fixed content, no timers or randomness.
// `animate` is switched off by tests/visual before the picture.
Item {
    id: root

    property bool animate: true

    implicitWidth: 400
    implicitHeight: 90
    width: implicitWidth
    height: implicitHeight

    RowLayout {
        x: 16
        y: 16
        spacing: 20
        AtlasSparkline {
            Layout.preferredWidth: 110
            values: [1, 3, 2, 5, 4, 6, 3, 7]
            minimum: 0
        }
        AtlasSparkline {
            Layout.preferredWidth: 110
            values: [10, 10.1, 10, 10.2, 10.1]
            minimumRange: 10
            fill: true
            lineWidth: 2
        }
        AtlasSparkline {
            Layout.preferredWidth: 110
            values: [4, 2, 6, 1, 5, 3]
            color: Kirigami.Theme.negativeTextColor
            fill: true
        }
    }
}
