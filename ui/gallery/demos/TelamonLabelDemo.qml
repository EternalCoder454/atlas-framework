import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Telamon.Ui

// Visual-test scene for TelamonLabel: the five text styles. `animate` is
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
        TelamonLabel { Layout.fillWidth: true; text: "Title style"; textStyle: TelamonLabel.Title }
        TelamonLabel { Layout.fillWidth: true; text: "Heading style"; textStyle: TelamonLabel.Heading }
        TelamonLabel { Layout.fillWidth: true; text: "Body style, the default"; textStyle: TelamonLabel.Body }
        TelamonLabel { Layout.fillWidth: true; text: "Caption style, small and muted"; textStyle: TelamonLabel.Caption }
        TelamonLabel { Layout.fillWidth: true; text: "Mono style: v1.4.0 /usr/bin/atlas"; textStyle: TelamonLabel.Mono; elide: Text.ElideRight }
        TelamonLabel { Layout.fillWidth: true; text: "Window title style"; textStyle: TelamonLabel.WindowTitle }
        TelamonLabel { Layout.fillWidth: true; text: "Code style: git commit -m fix"; textStyle: TelamonLabel.Code; elide: Text.ElideRight }
    }
}
