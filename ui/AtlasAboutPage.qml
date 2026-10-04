import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// An About page every Atlas app can drop in: the app's icon, name and
// version, an optional description, the version, OS and Qt in use, links to
// the source and the issue tracker, and the licence. All of it comes from
// AtlasApp, which reads the app's own name, version and desktop file name
// (set them on the application object at startup) and its `atlasRepo`
// property (a repository name under github.com/EternalCoder454/).
//
//     AtlasAboutPage {
//         description: qsTr("Updates for AtlasOS.")
//         license: qsTr("MIT")
//         // Anything declared inside is added after the built-in sections.
//         Section {
//             title: qsTr("Credits")
//             SectionRow { title: qsTr("Made by"); value: "Eterneon" }
//         }
//     }
AtlasPage {
    id: page

    // One or two sentences under the version. Hidden when empty.
    property string description
    property string license: "MIT"
    // Sections an app adds after the built-in ones.
    default property alias extraContent: extra.data

    title: qsTr("About")

    ColumnLayout {
        Layout.fillWidth: true
        Layout.topMargin: Kirigami.Units.gridUnit
        spacing: Kirigami.Units.smallSpacing

        Kirigami.Icon {
            Layout.alignment: Qt.AlignHCenter
            source: AtlasApp.id
            Layout.preferredWidth: Math.round(Kirigami.Units.gridUnit * 5)
            Layout.preferredHeight: Layout.preferredWidth
        }
        Kirigami.Heading {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: Kirigami.Units.smallSpacing
            text: AtlasApp.name
            textFormat: Text.PlainText
        }
        QQC2.Label {
            Layout.alignment: Qt.AlignHCenter
            visible: AtlasApp.version.length > 0
            opacity: 0.7
            text: qsTr("Version %1").arg(AtlasApp.version)
            textFormat: Text.PlainText
        }
        QQC2.Label {
            Layout.fillWidth: true
            visible: page.description.length > 0
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            opacity: 0.7
            text: page.description
            textFormat: Text.PlainText
        }
    }

    Section {
        title: qsTr("About")
        SectionRow {
            title: qsTr("Version")
            value: AtlasApp.version
            visible: AtlasApp.version.length > 0
        }
        SectionRow {
            title: qsTr("Operating system")
            value: AtlasApp.osPrettyName
            visible: AtlasApp.osPrettyName.length > 0
        }
        SectionRow {
            title: qsTr("Qt")
            value: AtlasApp.qtVersion
        }
        SectionRow {
            title: qsTr("License")
            value: page.license
            visible: page.license.length > 0
        }
    }

    Section {
        title: qsTr("Links")
        visible: AtlasApp.sourceUrl.length > 0
        SectionRow {
            title: qsTr("Source code")
            chevron: true
            visible: AtlasApp.sourceUrl.length > 0
            onClicked: Qt.openUrlExternally(AtlasApp.sourceUrl)
        }
        SectionRow {
            title: qsTr("Report a problem")
            chevron: true
            visible: AtlasApp.issuesUrl.length > 0
            onClicked: Qt.openUrlExternally(AtlasApp.issuesUrl)
        }
    }

    ColumnLayout {
        id: extra
        Layout.fillWidth: true
        spacing: Kirigami.Units.gridUnit * 1.2
    }
}
