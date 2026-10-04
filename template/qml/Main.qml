import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Atlas.Ui

// AtlasWindow follows the shared transparency switch: blurred, or opaque.
AtlasWindow {
    id: root

    // The Rust backend; atlas_app_run sets it.
    required property var backend

    title: AtlasApp.name
    width: Kirigami.Units.gridUnit * 40
    height: Kirigami.Units.gridUnit * 30
    visible: true
    LayoutMirroring.enabled: Qt.application.layoutDirection === Qt.RightToLeft
    LayoutMirroring.childrenInherit: true

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        TextButton {
            Layout.margins: Kirigami.Units.smallSpacing
            visible: stack.depth > 1
            text: qsTr("Back")
            onClicked: stack.pop()
        }

        QQC2.StackView {
            id: stack
            Layout.fillWidth: true
            Layout.fillHeight: true
            initialItem: MainPage {
                backend: root.backend
                onAboutRequested: stack.push(aboutPage)
            }
        }
    }

    Component {
        id: aboutPage
        // Atlas.Ui's About page: name, version, OS, links, all from AtlasApp.
        AtlasAboutPage {
            description: qsTr("A starting point for Atlas apps.")
        }
    }
}
