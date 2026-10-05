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

    // Drill-down pages with a Back button and the page title; Alt+Left and the
    // mouse Back button go back too, and reduced motion is respected.
    AtlasNavigationStack {
        id: stack
        anchors.fill: parent
        // The first page shows its own title; the header is for pages above it.
        showHeader: stack.canGoBack
        initialItem: MainPage {
            backend: root.backend
            onAboutRequested: stack.push(aboutPage)
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
