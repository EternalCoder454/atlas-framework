import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Atlas.Ui

// Visual-test scene for AtlasLabel: the five text styles. `animate` is
// switched off by tests/visual before the picture is taken.
Item {
    id: root

    property bool animate: true

    implicitWidth: 360
    implicitHeight: 230
    width: implicitWidth
    height: implicitHeight

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 10
        AtlasLabel { Layout.fillWidth: true; text: "Title style"; textStyle: AtlasLabel.Title }
        AtlasLabel { Layout.fillWidth: true; text: "Heading style"; textStyle: AtlasLabel.Heading }
        AtlasLabel { Layout.fillWidth: true; text: "Body style, the default"; textStyle: AtlasLabel.Body }
        AtlasLabel { Layout.fillWidth: true; text: "Caption style, small and muted"; textStyle: AtlasLabel.Caption }
        AtlasLabel { Layout.fillWidth: true; text: "Mono style: v1.4.0 /usr/bin/atlas"; textStyle: AtlasLabel.Mono; elide: Text.ElideRight }
        AtlasLabel { Layout.fillWidth: true; text: "Window title style"; textStyle: AtlasLabel.WindowTitle }
        AtlasLabel { Layout.fillWidth: true; text: "Code style: git commit -m fix"; textStyle: AtlasLabel.Code; elide: Text.ElideRight }
    }
}
