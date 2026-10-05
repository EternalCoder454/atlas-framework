import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import Atlas.Ui

// Visual-test scene for AtlasScrollBar: always shown here (the real one fades
// out when nothing scrolls). `animate` is switched off by tests/visual.
Item {
    id: root

    property bool animate: true

    implicitWidth: 460
    implicitHeight: 260
    width: implicitWidth
    height: implicitHeight

    Flickable {
        id: flick
        x: 20
        y: 20
        width: 400
        height: 200
        clip: true
        contentWidth: 800
        contentHeight: 600
        QQC2.ScrollBar.vertical: AtlasScrollBar {
            policy: QQC2.ScrollBar.AlwaysOn
        }
        QQC2.ScrollBar.horizontal: AtlasScrollBar {
            policy: QQC2.ScrollBar.AlwaysOn
        }
        Rectangle {
            width: 800
            height: 600
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.alpha(AtlasStyle.accent, 0.35) }
                GradientStop { position: 1; color: Qt.alpha(AtlasStyle.accent, 0.05) }
            }
            QQC2.Label {
                x: 16
                y: 16
                text: "Scroll me"
            }
        }
    }
}
