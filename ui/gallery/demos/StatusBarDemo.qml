import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Atlas.Ui

// Visual-test scene for StatusBar: fixed content, no timers or randomness. `animate`
// is switched off by tests/visual before the picture is taken.
Item {
    id: root

    property bool animate: true

    implicitWidth: 520
    implicitHeight: 60
    width: implicitWidth
    height: implicitHeight

    StatusBar {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        StatusBarItem { text: "Ln 3, Col 14" }
        StatusBarItem { text: "42 characters" }
        StatusBarItem { symbol: Symbols.codepoint("lock"); text: "Saved" }
        Item { Layout.fillWidth: true }
        StatusBarItem { text: "100%"; clickable: true }
        StatusBarItem { text: "UTF-8" }
    }
}
