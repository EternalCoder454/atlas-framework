import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Atlas.Ui

// AtlasScreenshotCarousel with no images, and with three. Not part of any
// build target.
Rectangle {
    id: root

    // Nothing runs by itself; the slide only plays on a key or a click.
    property bool animate: true

    implicitWidth: Kirigami.Units.gridUnit * 44
    implicitHeight: Kirigami.Units.gridUnit * 20
    color: Kirigami.Theme.backgroundColor

    RowLayout {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.gridUnit
        spacing: Kirigami.Units.gridUnit

        AtlasScreenshotCarousel {
            objectName: "empty"
            Layout.fillWidth: true
            Layout.fillHeight: true
            sources: []
        }
        AtlasScreenshotCarousel {
            objectName: "full"
            Layout.fillWidth: true
            Layout.fillHeight: true
            focus: true
            sources: [Qt.resolvedUrl("images/shot-blue.png"), Qt.resolvedUrl("images/shot-green.png"), Qt.resolvedUrl("images/shot-orange.png")]
        }
    }
}
