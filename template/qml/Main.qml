import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Telamon.Ui

// TelamonWindow follows the shared transparency switch: blurred, or opaque.
TelamonWindow {
    id: root

    // The Rust backend; telamon_app_run sets it.
    required property var backend

    title: TelamonApp.name
    width: Kirigami.Units.gridUnit * 40
    height: Kirigami.Units.gridUnit * 30
    visible: true
    LayoutMirroring.enabled: Qt.application.layoutDirection === Qt.RightToLeft
    LayoutMirroring.childrenInherit: true

    // Drill-down pages with a Back button and the page title; Alt+Left and the
    // mouse Back button go back too, and reduced motion is respected.
    TelamonNavigationStack {
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
        // Telamon.Ui's About page: name, version, OS, links, all from TelamonApp.
        TelamonAboutPage {
            description: qsTr("A starting point for Telamon apps.")
        }
    }
}
