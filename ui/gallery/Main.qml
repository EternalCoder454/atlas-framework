import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Atlas.Ui

// Atlas Gallery: every Material Symbol (copy the QML for one) and every
// Atlas.Ui control, live.
AtlasWindow {
    id: root

    // Set from main.cpp.
    required property var clipboard
    // The generated snippets.json: {demos: [...], snippets: {Type: qml}}.
    required property var catalog

    property int page: 0

    title: qsTr("Atlas Gallery")
    width: Kirigami.Units.gridUnit * 64
    height: Kirigami.Units.gridUnit * 38
    minimumWidth: Kirigami.Units.gridUnit * 36
    minimumHeight: Kirigami.Units.gridUnit * 22
    visible: true

    RowLayout {
        anchors.fill: parent
        spacing: 0

        Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: Kirigami.Units.gridUnit * 11
            color: root.sidebarColor(Kirigami.Theme.backgroundColor)

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Kirigami.Units.largeSpacing
                spacing: 2

                SidebarItem {
                    Layout.fillWidth: true
                    text: qsTr("Symbols")
                    symbol: Symbols.Interests
                    selected: root.page === 0
                    onClicked: root.page = 0
                }
                SidebarItem {
                    Layout.fillWidth: true
                    text: qsTr("Controls")
                    symbol: Symbols.Widgets
                    selected: root.page === 1
                    onClicked: root.page = 1
                }
                Item {
                    Layout.fillHeight: true
                }
            }
        }

        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: root.page

            SymbolsPage {
                clipboard: root.clipboard
                panelColor: root.sidebarColor(Kirigami.Theme.alternateBackgroundColor)
            }
            ControlsPage {
                clipboard: root.clipboard
                catalog: root.catalog
                panelColor: root.sidebarColor(Kirigami.Theme.alternateBackgroundColor)
            }
        }
    }
}
