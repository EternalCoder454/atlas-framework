import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Telamon.Ui

// Visual-test scene for TelamonAvatar: fixed content, no timers or randomness.
// `animate` is switched off by tests/visual before the picture.
Item {
    id: root

    property bool animate: true

    implicitWidth: 340
    implicitHeight: 150
    width: implicitWidth
    height: implicitHeight

    Column {
        x: 16
        y: 16
        spacing: 14
        Row {
            spacing: 12
            TelamonAvatar { name: "Ada Lovelace" }
            TelamonAvatar { name: "Grace Brewster Hopper" }
            TelamonAvatar { name: "linus" }
            TelamonAvatar { name: "Alan Turing" }
            TelamonAvatar { name: "Margaret Hamilton" }
            TelamonAvatar { name: "Édith Piaf" }
        }
        Row {
            spacing: 12
            TelamonAvatar { }
            TelamonAvatar { size: 32; name: "Tim Berners-Lee" }
            TelamonAvatar { size: 64; name: "Ken Thompson" }
            TelamonAvatar { size: 48; name: "With Picture"; source: Qt.resolvedUrl("images/shot-green.png") }
            // An image that does not load falls back to the initials.
            TelamonAvatar { size: 48; name: "Missing Picture"; source: "file:///nonexistent/telamon-avatar.png" }
        }
    }
}
