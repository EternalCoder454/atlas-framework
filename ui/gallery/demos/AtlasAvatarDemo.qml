import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Atlas.Ui

// Visual-test scene for AtlasAvatar: fixed content, no timers or randomness.
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
            AtlasAvatar { name: "Ada Lovelace" }
            AtlasAvatar { name: "Grace Brewster Hopper" }
            AtlasAvatar { name: "linus" }
            AtlasAvatar { name: "Alan Turing" }
            AtlasAvatar { name: "Margaret Hamilton" }
            AtlasAvatar { name: "Édith Piaf" }
        }
        Row {
            spacing: 12
            AtlasAvatar { }
            AtlasAvatar { size: 32; name: "Tim Berners-Lee" }
            AtlasAvatar { size: 64; name: "Ken Thompson" }
            // An image that does not load falls back to the initials.
            AtlasAvatar { size: 48; name: "Missing Picture"; source: "file:///nonexistent/atlas-avatar.png" }
        }
    }
}
