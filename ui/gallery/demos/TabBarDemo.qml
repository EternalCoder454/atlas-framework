import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Atlas.Ui

// Visual-test scene for TabBar: fixed content, no timers or randomness. `animate`
// is switched off by tests/visual before the picture is taken.
Item {
    id: root

    property bool animate: true

    implicitWidth: 520
    implicitHeight: 60
    width: implicitWidth
    height: implicitHeight

    ListModel {
        id: tabs
        ListElement { title: "notes.md"; modified: false; toolTip: "" }
        ListElement { title: "todo.txt"; modified: true; toolTip: "" }
        ListElement { title: "a-longer-file-name.cpp"; modified: false; toolTip: "" }
    }
    TabBar {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        model: tabs
        currentIndex: 1
    }
}
