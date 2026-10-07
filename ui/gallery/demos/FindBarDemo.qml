import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Telamon.Ui

// Visual-test scene for FindBar: fixed content, no timers or randomness. `animate`
// is switched off by tests/visual before the picture is taken.
Item {
    id: root

    property bool animate: true

    implicitWidth: 520
    implicitHeight: 130
    width: implicitWidth
    height: implicitHeight

    FindBar {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 8
        replaceVisible: true
        matchCase: true
        findText: "needle"
        replaceText: "thread"
        matchCount: 7
        currentMatch: 2
        opened: true
    }
}
