import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Atlas.Ui

// Visual-test scene for TextButton: fixed content, no timers or randomness. `animate`
// is switched off by tests/visual before the picture is taken.
Item {
    id: root

    property bool animate: true

    implicitWidth: 360
    implicitHeight: 80
    width: implicitWidth
    height: implicitHeight

    RowLayout {
        anchors.centerIn: parent
        spacing: 16
        TextButton { text: "Learn more" }
        TextButton { text: "Skip" }
        TextButton { text: "Off"; enabled: false }
    }
}
