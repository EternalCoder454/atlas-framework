import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Atlas.Ui

// Visual-test scene for StatusHero: fixed content, no timers or randomness. `animate`
// is switched off by tests/visual before the picture is taken.
Item {
    id: root

    property bool animate: true

    implicitWidth: 420
    implicitHeight: 330
    width: implicitWidth
    height: implicitHeight

    StatusHero {
        anchors.fill: parent
        anchors.margins: 12
        iconName: "update-none"
        headline: "Your system is up to date"
        subtitle: "Last checked today"
        progress: 0.4
        showBar: true
        barText: "40%"
        PrimaryButton { text: "Check again" }
    }
}
