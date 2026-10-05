import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import Atlas.Ui

// Visual-test scene for AtlasCard: fixed content, no timers or randomness. `animate`
// is switched off by tests/visual before the picture is taken.
Item {
    id: root

    property bool animate: true

    implicitWidth: 480
    implicitHeight: 400
    width: implicitWidth
    height: implicitHeight

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 12
        AtlasCard {
            title: "Backups"
            subtitle: "Last run yesterday"
            headerTrailing: [
                SecondaryButton {
                    text: "Run now"
                }
            ]
            QQC2.Label {
                text: "42 files protected."
            }
            footer: [
                TextButton {
                    text: "Details"
                }
            ]
        }
        AtlasCard {
            title: "Clickable card"
            clickable: true
            QQC2.Label {
                text: "The whole card is a button."
            }
        }
        AtlasCard {
            enabled: false
            title: "Disabled"
            subtitle: "Dimmed"
        }
    }
}
