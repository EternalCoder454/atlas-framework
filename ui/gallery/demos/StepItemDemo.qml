import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Atlas.Ui

// Visual-test scene for StepItem: fixed content, no timers or randomness. `animate`
// is switched off by tests/visual before the picture is taken.
Item {
    id: root

    property bool animate: true

    implicitWidth: 540
    implicitHeight: 90
    width: implicitWidth
    height: implicitHeight

    RowLayout {
        anchors.centerIn: parent
        spacing: 14
        StepItem { number: 1; text: "Language"; done: true }
        StepItem { number: 2; text: "Disk"; current: true }
        StepItem { number: 3; text: "Account" }
    }
}
