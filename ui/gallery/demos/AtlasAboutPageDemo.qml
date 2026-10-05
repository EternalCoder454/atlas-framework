import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Atlas.Ui

// Visual-test scene for AtlasAboutPage: fixed content, no timers or randomness. `animate`
// is switched off by tests/visual before the picture is taken.
Item {
    id: root

    property bool animate: true

    implicitWidth: 520
    implicitHeight: 520
    width: implicitWidth
    height: implicitHeight

    AtlasAboutPage {
        anchors.fill: parent
        description: "A demonstration application."
        showSystemRows: false
        links: [
            {
                title: "Homepage",
                url: "https://example.org/"
            },
            {
                title: "Write to us",
                url: "mailto:hello@example.org"
            }
        ]
    }
}
