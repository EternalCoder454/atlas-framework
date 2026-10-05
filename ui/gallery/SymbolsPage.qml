pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Atlas.Ui

// Every symbol in a searchable grid. Pick one to see it large and copy the
// QML that draws it, with the style, fill and weight set here.
Item {
    id: root

    // Set by Main.qml.
    required property var clipboard
    // Colour of the preview column: the window's sidebarColor().
    required property color panelColor

    property int style: Symbol.Rounded
    property bool filled: false
    property int weight: 400
    property string selected: "home"
    // Names that start with a letter first: the "10k" and "123" kind after.
    readonly property var all: {
        const names = Symbols.names();
        return names.filter(n => !/^[0-9]/.test(n)).concat(names.filter(n => /^[0-9]/.test(n)));
    }
    readonly property var shown: {
        const q = search.query.trim().toLowerCase().replace(/[ -]+/g, "_");
        return q.length === 0 ? all : all.filter(n => n.includes(q));
    }

    // The QML for the selected symbol with the current settings.
    readonly property string snippet: {
        let props = ["icon: Symbols." + Symbols.key(Symbols.codepoint(selected))];
        if (style !== Symbol.Rounded)
            props.push("style: Symbol." + ["Outlined", "Rounded", "Sharp"][style]);
        if (filled)
            props.push("filled: true");
        if (weight !== 400)
            props.push("weight: " + weight);
        return "Symbol { " + props.join("; ") + " }";
    }


    // Filled when the chosen style's font is not installed.
    readonly property bool styleMissing: !Symbols.available(style)

    RowLayout {
        anchors.fill: parent
        spacing: 0

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Kirigami.Units.largeSpacing

            InfoBanner {
                Layout.fillWidth: true
                type: "warning"
                shown: root.styleMissing
                text: qsTr("Outlined and Sharp need atlas-symbols-fonts-extra")
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.margins: Kirigami.Units.largeSpacing * 2
                Layout.bottomMargin: 0
                spacing: Kirigami.Units.largeSpacing

                SearchField {
                    id: search
                    Layout.fillWidth: true
                    placeholderText: qsTr("Search %1 symbols").arg(root.all.length.toLocaleString(Qt.locale(), "f", 0))
                    Component.onCompleted: forceActiveFocus()
                }
                Repeater {
                    model: [qsTr("Outlined"), qsTr("Rounded"), qsTr("Sharp")]
                    delegate: SecondaryButton {
                        required property string modelData
                        required property int index
                        text: modelData
                        prominent: root.style === index
                        onClicked: root.style = index
                    }
                }
                QQC2.Label {
                    text: qsTr("Filled")
                }
                AtlasSwitch {
                    checked: root.filled
                    onToggled: root.filled = checked
                    Accessible.name: qsTr("Filled")
                }
            }

            QQC2.Label {
                Layout.leftMargin: Kirigami.Units.largeSpacing * 2
                text: root.shown.length === 0 ? qsTr("No symbol matches “%1”.").arg(search.query) : root.shown.length === 1 ? qsTr("1 symbol") : qsTr("%1 symbols").arg(root.shown.length.toLocaleString(Qt.locale(), "f", 0))
                opacity: 0.6
            }

            GridView {
                id: grid
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.leftMargin: Kirigami.Units.largeSpacing
                clip: true
                model: root.shown
                cellWidth: Math.floor(width / Math.max(1, Math.floor(width / (Kirigami.Units.gridUnit * 6.5))))
                cellHeight: Kirigami.Units.gridUnit * 5.5
                reuseItems: true
                QQC2.ScrollBar.vertical: QQC2.ScrollBar {}

                delegate: QQC2.AbstractButton {
                    id: cell
                    required property string modelData
                    width: grid.cellWidth
                    height: grid.cellHeight
                    hoverEnabled: true
                    Accessible.name: modelData
                    onClicked: root.selected = modelData

                    background: Rectangle {
                        anchors.fill: parent
                        anchors.margins: 3
                        radius: 10 // atlas-lint: allow-raw swatch tile shape
                        color: root.selected === cell.modelData ? AtlasStyle.alpha(AtlasStyle.accent, 0.18) : AtlasStyle.alpha(Kirigami.Theme.textColor, cell.hovered ? 0.06 : 0)
                    }
                    contentItem: ColumnLayout {
                        spacing: Kirigami.Units.smallSpacing
                        Symbol {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.topMargin: Kirigami.Units.largeSpacing
                            name: cell.modelData
                            size: 32
                            style: root.style
                            filled: root.filled
                            weight: root.weight
                        }
                        QQC2.Label {
                            Layout.fillWidth: true
                            Layout.leftMargin: Kirigami.Units.smallSpacing
                            Layout.rightMargin: Kirigami.Units.smallSpacing
                            horizontalAlignment: Text.AlignHCenter
                            text: cell.modelData.replace(/_/g, " ")
                            font: Kirigami.Theme.smallFont
                            elide: Text.ElideRight
                            opacity: 0.75
                        }
                    }
                }
            }
        }

        Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: Kirigami.Units.gridUnit * 17
            color: root.panelColor

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Kirigami.Units.largeSpacing * 2
                spacing: Kirigami.Units.largeSpacing

                Symbol {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: Kirigami.Units.gridUnit
                    name: root.selected
                    size: 96
                    style: root.style
                    filled: root.filled
                    weight: root.weight
                    color: AtlasStyle.accent
                }
                // atlas-lint: allow the gallery shows Kirigami.Heading as is
                Kirigami.Heading {
                    Layout.fillWidth: true
                    Layout.topMargin: Kirigami.Units.largeSpacing
                    horizontalAlignment: Text.AlignHCenter
                    level: 3
                    text: root.selected
                    wrapMode: Text.Wrap
                }
                QQC2.Label {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: "Symbols." + Symbols.key(Symbols.codepoint(root.selected))
                    font.family: Kirigami.Theme.fixedWidthFont.family
                    opacity: 0.7
                }

                QQC2.Label {
                    Layout.topMargin: Kirigami.Units.gridUnit
                    text: qsTr("Weight %1").arg(root.weight)
                }
                AtlasSlider {
                    Layout.fillWidth: true
                    from: 100
                    to: 700
                    stepSize: 100
                    snapMode: AtlasSlider.SnapAlways
                    value: root.weight
                    onMoved: root.weight = value
                    Accessible.name: qsTr("Weight")
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.topMargin: Kirigami.Units.largeSpacing
                    implicitHeight: code.implicitHeight + Kirigami.Units.largeSpacing * 2
                    radius: AtlasStyle.radiusLarge
                    color: AtlasStyle.alpha(Kirigami.Theme.textColor, 0.06)
                    QQC2.Label {
                        id: code
                        anchors.fill: parent
                        anchors.margins: Kirigami.Units.largeSpacing
                        text: root.snippet
                        font.family: Kirigami.Theme.fixedWidthFont.family
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                        wrapMode: Text.Wrap
                    }
                }
                PrimaryButton {
                    id: copyButton
                    Layout.alignment: Qt.AlignHCenter
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
                Item {
                    Layout.fillHeight: true
                }
            }
        }
    }
}
