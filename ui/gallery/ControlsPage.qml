pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Atlas.Ui

// Every Atlas.Ui control, live. The list on the left is the demos bundled in
// the gallery (ui/gallery/demos), grouped here; a demo this list does not know
// lands in "Other". The same demos are the visual tests' scenes.
Item {
    id: root

    // Set by Main.qml.
    required property var clipboard
    required property var catalog
    required property color panelColor

    property string selected: "AtlasButton"
    property bool disabled: false

    readonly property var groups: [
        {
            title: qsTr("Buttons"),
            types: ["AtlasButton", "PrimaryButton", "SecondaryButton", "TextButton", "ToolbarButton", "MenuButton", "AtlasInstallButton", "AtlasSplitButton", "AtlasCopyButton", "AtlasSegmentedControl", "AtlasToolbar", "AtlasFloatingToolbar"]
        },
        {
            title: qsTr("Inputs"),
            types: ["AtlasTextField", "AtlasPasswordField", "AtlasTextArea", "SearchField", "AtlasSpinBox", "AtlasDoubleSpinBox", "AtlasSlider", "AtlasAutocompleteField", "AtlasFileField", "AtlasShortcutField", "AtlasDropZone"]
        },
        {
            title: qsTr("Pickers"),
            types: ["AtlasComboBox", "AtlasDatePicker", "AtlasTimePicker", "AtlasCalendar", "AtlasColorField", "AtlasFontPicker"]
        },
        {
            title: qsTr("Selection"),
            types: ["AtlasCheckBox", "AtlasRadioButton", "AtlasSwitch", "AtlasTransparencySwitch", "AtlasRating", "AtlasChip"]
        },
        {
            title: qsTr("Lists and tables"),
            types: ["AtlasListView", "AtlasTreeView", "DataTable", "AtlasIconGrid", "AtlasSearchResults", "AtlasScrollBar", "AtlasFlowLayout"]
        },
        {
            title: qsTr("Navigation and layout"),
            types: ["SidebarItem", "SidebarGroup", "AtlasSidebar", "TabBar", "AtlasViewSwitcher", "AtlasBreadcrumb", "AtlasNavigationStack", "AtlasSplitView", "ContextMenu", "FindBar", "StepItem", "AtlasCommandPalette", "AtlasExpandableSection"]
        },
        {
            title: qsTr("Windows and dialogs"),
            types: ["AtlasWindow", "AtlasWindowButtons", "AtlasHeaderBar", "AtlasPage", "AtlasAboutPage", "AtlasDialog", "ConfirmDialog", "AtlasPopover", "AtlasOnboarding", "AtlasShortcutsDialog", "StatusBar"]
        },
        {
            title: qsTr("Feedback and status"),
            types: ["AtlasProgressBar", "AtlasSpinner", "InfoBanner", "Toast", "AtlasToolTip", "UsageBar", "AtlasPlaceholder", "AtlasEmptyState", "AtlasBadge", "StatusHero"]
        },
        {
            title: qsTr("Data display"),
            types: ["LiveChart", "MiniBars", "AtlasSparkline", "AtlasStat", "AtlasDetailGrid", "AtlasAppCard", "AtlasCard", "AtlasScreenshotCarousel", "AtlasAvatar"]
        },
        {
            title: qsTr("Text"),
            types: ["AtlasLabel", "NotesText", "AtlasCodeView", "AtlasShortcutLabel"]
        },
        {
            title: qsTr("Style and services"),
            types: ["AtlasStyle", "AtlasFormat", "AtlasAction", "AtlasValidators", "Section", "SectionRow", "Symbol", "AtlasFocusRing"]
        }
    ]

    // [{type, group}] in display order, one row per demo.
    readonly property var entries: {
        const have = new Set(root.catalog.demos);
        const used = new Set();
        const out = [];
        for (const g of root.groups) {
            for (const t of g.types) {
                if (have.has(t)) {
                    out.push({
                        type: t,
                        group: g.title
                    });
                    used.add(t);
                }
            }
        }
        for (const t of root.catalog.demos) {
            if (!used.has(t))
                out.push({
                    type: t,
                    group: qsTr("Other")
                });
        }
        return out;
    }
    readonly property string snippet: root.catalog.snippets[selected] ?? (selected + " {}")
    // The loaded demo: an Item, or (AtlasWindowDemo) a window.
    readonly property var demo: loader.item
    readonly property bool isWindow: demo !== null && demo.hasOwnProperty("visibility")

    // Picking the shown demo again starts it over: a dialog or toast that
    // was dismissed comes back.
    function open(type: string): void {
        if (type === selected) {
            loader.active = false;
            loader.active = true;
        }
        selected = type;
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        ListView {
            id: list
            Layout.fillHeight: true
            Layout.preferredWidth: Kirigami.Units.gridUnit * 14
            Layout.leftMargin: Kirigami.Units.smallSpacing
            clip: true
            model: root.entries
            currentIndex: {
                for (let i = 0; i < root.entries.length; ++i)
                    if (root.entries[i].type === root.selected)
                        return i;
                return -1;
            }
            QQC2.ScrollBar.vertical: QQC2.ScrollBar {}

            section.property: "group"
            section.criteria: ViewSection.FullString
            // atlas-lint: allow the gallery shows Kirigami.Heading as is
            section.delegate: Kirigami.Heading {
                required property string section
                width: ListView.view.width
                level: 5
                topPadding: Kirigami.Units.largeSpacing
                leftPadding: Kirigami.Units.largeSpacing
                text: section
                opacity: 0.6
            }
            delegate: SidebarItem {
                required property var modelData
                width: ListView.view.width - Kirigami.Units.smallSpacing
                text: modelData.type
                tintIcon: false
                selected: modelData.type === root.selected
                onClicked: root.open(modelData.type)
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: Kirigami.Units.largeSpacing * 2
            spacing: Kirigami.Units.largeSpacing

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.largeSpacing

                // atlas-lint: allow the gallery shows Kirigami.Heading as is
                Kirigami.Heading {
                    Layout.fillWidth: true
                    level: 2
                    text: root.selected
                    elide: Text.ElideRight
                }
                QQC2.Label {
                    text: qsTr("Disabled")
                }
                AtlasSwitch {
                    checked: root.disabled
                    onToggled: root.disabled = checked
                    Accessible.name: qsTr("Disabled")
                }
                PrimaryButton {
                    text: copied.running ? qsTr("Copied") : qsTr("Copy QML")
                    onClicked: {
                        root.clipboard.copy(root.snippet);
                        copied.restart();
                    }
                    Timer {
                        id: copied
                        interval: 1500
                    }
                }
            }

            // The demo, live. It keeps its own size; a bigger one scrolls.
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 12 // atlas-lint: allow-raw gallery card shape
                color: Qt.alpha(Kirigami.Theme.textColor, 0.04)
                clip: true

                Flickable {
                    id: flick
                    anchors.fill: parent
                    contentWidth: Math.max(width, stage.width)
                    contentHeight: Math.max(height, stage.height)
                    boundsBehavior: Flickable.StopAtBounds
                    QQC2.ScrollBar.vertical: QQC2.ScrollBar {}
                    QQC2.ScrollBar.horizontal: QQC2.ScrollBar {}

                    Item {
                        id: stage
                        width: root.demo && !root.isWindow ? root.demo.width : 0
                        height: root.demo && !root.isWindow ? root.demo.height : 0
                        x: Math.max(0, (flick.contentWidth - width) / 2)
                        y: Math.max(0, (flick.contentHeight - height) / 2)

                        Loader {
                            id: loader
                            enabled: !root.disabled
                            source: "qrc:/net/eterneon/atlas/symbols/demos/" + root.selected + "Demo.qml"
                            onLoaded: {
                                if (root.demo.animate !== undefined)
                                    root.demo.animate = true;
                                if (root.isWindow)
                                    root.demo.visible = false;
                            }
                            onStatusChanged: if (status === Loader.Error)
                                console.warn("Could not load the demo", root.selected)
                        }
                    }
                }

                // A window demo opens its own window.
                PrimaryButton {
                    anchors.centerIn: parent
                    visible: root.isWindow
                    text: qsTr("Open the window")
                    enabled: !root.disabled
                    onClicked: root.demo.visible = true
                }
            }

            AtlasCodeView {
                Layout.fillWidth: true
                text: root.snippet
                maximumHeight: Kirigami.Units.gridUnit * 12
                Accessible.name: qsTr("QML snippet")
            }
        }
    }
}
