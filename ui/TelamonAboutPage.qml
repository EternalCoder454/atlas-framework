import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// An About page every Telamon app can drop in: the app's icon, name and
// version, an optional description, the version, OS and Qt in use, links to
// the source and the issue tracker, the licence, and a "Copy system info"
// button for bug reports (`systemInfo()` returns the same text). All of it comes from
// TelamonApp, which reads the app's own name, version and desktop file name
// (set them on the application object at startup) and its `telamonRepo`
// property (a repository name under github.com/EternalCoder454/).
//
//     TelamonAboutPage {
//         description: qsTr("Updates for Telamon OS.")
//         license: qsTr("MIT")
//         // Anything declared inside is added after the built-in sections.
//         Section {
//             title: qsTr("Credits")
//             SectionRow { title: qsTr("Made by"); value: "Eterneon" }
//         }
//     }
TelamonPage {
    id: page

    // One or two sentences under the version. Hidden when empty.
    property string description
    property string license: "MIT"
    // See docs/reference/telamon-ui/telamon-about-page.md.
    property bool showSystemRows: true
    property var links: []
    // Sections an app adds after the built-in ones.
    default property alias extraContent: extra.data

    title: qsTr("About")

    // `links` as shown: entries with a title and a URL of an allowed scheme.
    // App data decides the URL, so any other scheme (file:, a custom one) is
    // skipped with a warning and never reaches the desktop.
    readonly property var _links: {
        const out = [];
        if (!Array.isArray(page.links)) {
            return out;
        }
        for (const entry of page.links) {
            const title = typeof entry?.title === "string" ? entry.title : "";
            // A `url` value (Qt.resolvedUrl) is as good as a string.
            const raw = entry?.url;
            const url = raw === null || raw === undefined ? "" : String(raw).trim();
            if (title.length === 0) {
                continue;
            }
            if (!/^(https?|mailto):/i.test(url)) {
                console.warn("TelamonAboutPage: link \"" + title + "\" skipped, its URL is not http, https or mailto");
                continue;
            }
            out.push({
                "title": title,
                "url": url
            });
        }
        return out;
    }
    // True only while one valid link remains: if none does, the built-in rows stay.
    readonly property bool _customLinks: _links.length > 0

    // Plain text for a bug report: app, versions, OS and graphics platform.
    function systemInfo(): string {
        const lines = [TelamonApp.name + (TelamonApp.version.length > 0 ? " " + TelamonApp.version : "")];
        if (TelamonApp.id.length > 0) {
            lines.push("ID: " + TelamonApp.id);
        }
        lines.push("Telamon.Ui: " + TelamonApp.uiVersion);
        lines.push("Qt: " + TelamonApp.qtVersion);
        const os = TelamonApp.osPrettyName.length > 0 ? TelamonApp.osPrettyName : TelamonApp.osName + (TelamonApp.osVersion.length > 0 ? " " + TelamonApp.osVersion : "");
        if (os.trim().length > 0) {
            lines.push("OS: " + os.trim());
        }
        // The session type (XDG_SESSION_TYPE) is not a TelamonApp property: the
        // Qt platform plugin ("wayland", "xcb") says the same.
        lines.push("Platform: " + Qt.platform.pluginName);
        return lines.join("\n");
    }

    Toast {
        id: copiedToast
        parent: page
    }

    ColumnLayout {
        Layout.fillWidth: true
        Layout.topMargin: Kirigami.Units.gridUnit
        spacing: TelamonStyle.spacingSmall

        Kirigami.Icon {
            Layout.alignment: Qt.AlignHCenter
            source: TelamonApp.id
            // No hole where an icon that isn't installed would be.
            visible: valid
            Accessible.ignored: true
            Layout.preferredWidth: Math.round(Kirigami.Units.gridUnit * 5)
            Layout.preferredHeight: Layout.preferredWidth
        }
        Kirigami.Heading {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: TelamonStyle.spacingSmall
            text: TelamonApp.name
            textFormat: Text.PlainText
        }
        QQC2.Label {
            Layout.alignment: Qt.AlignHCenter
            visible: TelamonApp.version.length > 0
            opacity: 0.7
            //: Version line under the app name: %1 is the version number ("Version 1.2.0")
            text: qsTr("Version %1").arg(TelamonApp.version)
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
        SecondaryButton {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: TelamonStyle.spacingSmall
            symbol: Symbols.ContentCopy
            text: qsTr("Copy system info")
            onClicked: {
                TelamonClipboard.setText(page.systemInfo());
                copiedToast.show(qsTr("Copied"));
            }
        }
    }

    Section {
        title: qsTr("About")
        SectionRow {
            title: qsTr("Version")
            value: TelamonApp.version
            visible: TelamonApp.version.length > 0
        }
        SectionRow {
            title: qsTr("Operating system")
            value: TelamonApp.osPrettyName
            visible: page.showSystemRows && TelamonApp.osPrettyName.length > 0
        }
        SectionRow {
            title: qsTr("Qt")
            value: TelamonApp.qtVersion
            visible: page.showSystemRows
        }
        SectionRow {
            //: The software licence of the app, as in "MIT License" (not a driving licence)
            title: qsTr("License")
            value: page.license
            visible: page.license.length > 0
        }
    }

    Section {
        title: qsTr("Links")
        visible: page._customLinks || TelamonApp.sourceUrl.length > 0 || TelamonApp.issuesUrl.length > 0
        SectionRow {
            title: qsTr("Source code")
            chevron: true
            visible: !page._customLinks && TelamonApp.sourceUrl.length > 0
            onClicked: Qt.openUrlExternally(TelamonApp.sourceUrl)
        }
        SectionRow {
            title: qsTr("Report a problem")
            chevron: true
            visible: !page._customLinks && TelamonApp.issuesUrl.length > 0
            onClicked: Qt.openUrlExternally(TelamonApp.issuesUrl)
        }
        Repeater {
            model: page._links
            delegate: SectionRow {
                required property var modelData
                title: modelData.title
                chevron: true
                onClicked: Qt.openUrlExternally(modelData.url)
            }
        }
    }

    ColumnLayout {
        id: extra
        Layout.fillWidth: true
        visible: children.length > 0
        spacing: Kirigami.Units.gridUnit * 1.2
    }
}
