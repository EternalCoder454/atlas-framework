import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Telamon.Ui

// Visual-test scene for NotesText: fixed content, no timers or randomness. `animate`
// is switched off by tests/visual before the picture is taken.
Item {
    id: root

    property bool animate: true

    implicitWidth: 420
    implicitHeight: 150
    width: implicitWidth
    height: implicitHeight

    NotesText {
        anchors.fill: parent
        anchors.margins: 12
        wrapMode: Text.WordWrap
        html: "<h3>What's new</h3><p>Fixed a <b>crash</b> on start and a <a href=\"https://example.org\">link</a>.</p><ul><li>First</li><li>Second</li></ul>"
    }
}
