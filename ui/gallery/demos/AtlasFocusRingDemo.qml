import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Atlas.Ui

// Visual-test scene for AtlasFocusRing: fixed content, no timers or randomness. `animate`
// is switched off by tests/visual before the picture is taken.
Item {
    id: root

    property bool animate: true

    implicitWidth: 260
    implicitHeight: 100
    width: implicitWidth
    height: implicitHeight

    RowLayout {
        anchors.centerIn: parent
        spacing: 30
        Rectangle {
            implicitWidth: 80
            implicitHeight: 36
            color: Kirigami.Theme.backgroundColor
            border.color: Kirigami.Theme.disabledTextColor
            AtlasFocusRing { shown: true }
        }
        Rectangle {
            implicitWidth: 80
            implicitHeight: 36
            radius: 18 // atlas-lint: allow-raw ring shape wraps the box
            color: Kirigami.Theme.backgroundColor
            border.color: Kirigami.Theme.disabledTextColor
            AtlasFocusRing { shown: true; radius: 18 } // atlas-lint: allow-raw ring shape wraps the box
        }
    }
}
