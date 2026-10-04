import QtQuick
import org.kde.kirigami as Kirigami
import Atlas.Ui

// AtlasWindow follows the shared transparency switch: blurred, or opaque.
AtlasWindow {
    id: root

    // Set from main.cpp through setInitialProperties().
    required property var backend

    title: qsTr("Atlas App")
    width: Kirigami.Units.gridUnit * 40
    height: Kirigami.Units.gridUnit * 30
    visible: true
    LayoutMirroring.enabled: Qt.application.layoutDirection === Qt.RightToLeft
    LayoutMirroring.childrenInherit: true

    MainPage {
        anchors.fill: parent
        backend: root.backend
    }
}
