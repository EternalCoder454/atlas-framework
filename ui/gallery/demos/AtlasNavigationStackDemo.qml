import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import Atlas.Ui

// Visual-test scene for AtlasNavigationStack: two pages deep, so Back shows.
Item {
    id: root

    property bool animate: true

    implicitWidth: 420
    implicitHeight: 180
    width: implicitWidth
    height: implicitHeight

    Component {
        id: page
        Item {
            property string title: "Details"
            QQC2.Label {
                anchors.centerIn: parent
                text: "Second page"
            }
        }
    }

    AtlasNavigationStack {
        id: stack
        anchors.fill: parent
        initialItem: Item {
            property string title: "Home"
        }
        Component.onCompleted: stack.push(page)
    }
}
