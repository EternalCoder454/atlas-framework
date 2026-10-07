pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami

// Names and values: a muted label at the trailing edge of its column, the
// value beside it, for facts like an item's properties. `model` is a list of
// `{ label, value, mono, copyable }`: `mono` sets the value in the fixed-width
// font (paths, hashes), `copyable` adds a copy button. Values can be selected
// with the mouse.
//
//   TelamonDetailGrid {
//       Layout.fillWidth: true
//       model: [
//           { label: qsTr("Version"), value: "1.4.0" },
//           { label: qsTr("Checksum"), value: sha, mono: true, copyable: true }
//       ]
//   }
//
// See docs/reference/telamon-ui/telamon-detail-grid.md.
Item {
    id: grid

    property var model: []
    property int columns: 1
    // The least width of one pair, in grid units.
    property real columnsBreakpoint: 20
    property string title
    property string footer
    property bool framed: false

    // A list from C++ (a QVariantList) is not a JS array but has a length.
    // Capped, so a plain object with a huge `length` cannot build a million cells.
    readonly property int _count: model !== null && typeof model === "object" && Number.isInteger(model.length) && model.length >= 0 ? Math.min(model.length, 100000) : 0
    // Room the card takes on each side of the grid inside it.
    readonly property real _padX: framed ? TelamonStyle.spacingLarge : 0
    readonly property real _padY: framed ? TelamonStyle.spacing : 0
    readonly property real _innerWidth: Math.max(0, width - _padX * 2)
    readonly property real _pairWidth: Kirigami.Units.gridUnit * Math.max(1, columnsBreakpoint)
    readonly property bool _stacked: _innerWidth < _pairWidth
    readonly property int _pairs: _stacked ? 1 : Math.max(1, Math.min(columns, Math.floor(_innerWidth / _pairWidth)))

    implicitHeight: stack.implicitHeight
    implicitWidth: layout.implicitWidth + _padX * 2
    opacity: enabled ? 1 : 0.6

    // A group only when there is a title or a footer to name it by: a plain
    // grid adds no node of its own, as in 1.4.0.
    Accessible.role: grid.title.length > 0 || grid.footer.length > 0 ? Accessible.Grouping : Accessible.NoRole
    Accessible.name: grid.title
    Accessible.description: grid.footer

    ColumnLayout {
        id: stack
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: TelamonStyle.spacingSmall

        QQC2.Label {
            visible: grid.title.length > 0
            Layout.fillWidth: true
            Layout.leftMargin: grid.framed ? TelamonStyle.spacingLarge : 0
            text: grid.title
            font.bold: true
            opacity: 0.65
            elide: Text.ElideRight
            textFormat: Text.PlainText
            Accessible.ignored: true
        }

        Rectangle {
            // No card and no gap round a grid with nothing to show.
            visible: grid._count > 0
            Layout.fillWidth: true
            implicitHeight: layout.implicitHeight + grid._padY * 2 + (grid.framed ? 2 : 0)
            radius: TelamonStyle.radius
            color: grid.framed ? TelamonStyle.surface : "transparent"
            border.width: grid.framed ? 1 : 0
            border.color: TelamonStyle.separator

            GridLayout {
                id: layout
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.leftMargin: grid._padX
                anchors.rightMargin: grid._padX
                anchors.topMargin: grid._padY + (grid.framed ? 1 : 0)
                // Cells: two per pair (label, value), one when stacked.
                columns: grid._stacked ? 1 : grid._pairs * 2
                rowSpacing: Kirigami.Units.smallSpacing + 2
                columnSpacing: Kirigami.Units.largeSpacing

                Repeater {
                    model: grid._count * 2

                    delegate: Item {
                        id: cell
                        required property int index
                        readonly property int entryIndex: Math.floor(index / 2)
                        readonly property bool isValue: index % 2 === 1
                        readonly property var entry: grid.model[entryIndex] ?? ({})
                        readonly property string text: String((isValue ? entry.value : entry.label) ?? "")
                        readonly property string labelText: String(entry.label ?? "")
                        readonly property bool copyable: isValue && entry.copyable === true

                        Layout.fillWidth: isValue || grid._stacked
                        Layout.alignment: Qt.AlignTop
                        Layout.minimumWidth: 0
                        // A long label gives way to its value in a narrow column.
                        Layout.maximumWidth: isValue || grid._stacked ? Number.POSITIVE_INFINITY : grid._innerWidth / grid._pairs * 0.45
                        Layout.preferredWidth: isValue || grid._stacked ? 1 : labelLoader.implicitWidth
                        Layout.topMargin: grid._stacked && !isValue && entryIndex > 0 ? Kirigami.Units.smallSpacing * 2 : 0
                        implicitHeight: isValue ? Math.max(valueLoader.implicitHeight, copyLoader.active ? copyLoader.implicitHeight : 0) : labelLoader.implicitHeight

                        // A cell holds only the parts its kind needs: a label
                        // cell no text edit, a value cell no label, and a
                        // copy button only where `copyable` asks for one.
                        Loader {
                            id: labelLoader
                            active: !cell.isValue
                            anchors.left: parent.left
                            anchors.right: parent.right
                            sourceComponent: QQC2.Label {
                                text: cell.text
                                color: TelamonStyle.textMuted
                                horizontalAlignment: grid._stacked ? Text.AlignLeft : Text.AlignRight
                                elide: Text.ElideRight
                                textFormat: Text.PlainText
                                Accessible.ignored: true
                            }
                        }

                        Loader {
                            id: valueLoader
                            active: cell.isValue
                            anchors.left: parent.left
                            anchors.right: copyLoader.active ? copyLoader.left : parent.right
                            anchors.rightMargin: copyLoader.active ? Kirigami.Units.smallSpacing : 0
                            sourceComponent: TextEdit {
                                text: cell.text
                                readOnly: true
                                selectByMouse: true
                                activeFocusOnTab: false
                                wrapMode: Text.Wrap
                                textFormat: TextEdit.PlainText
                                font: cell.entry.mono === true ? Qt.font({ "family": TelamonStyle.monoFamily, "pointSize": TelamonStyle.fontSizeBody }) : Qt.font({ "family": TelamonStyle.fontFamily, "pointSize": TelamonStyle.fontSizeBody })
                                color: Kirigami.Theme.textColor
                                selectionColor: TelamonStyle.accent
                                selectedTextColor: TelamonStyle.accentText
                                Accessible.role: Accessible.StaticText
                                Accessible.name: (cell.labelText) + ": " + cell.text
                            }
                        }

                        Loader {
                            id: copyLoader
                            active: cell.copyable
                            anchors.right: parent.right
                            anchors.top: parent.top
                            sourceComponent: T.AbstractButton {
                                id: copyButton
                                property bool copied: false
                                enabled: grid.enabled
                                implicitWidth: Math.round(Kirigami.Units.gridUnit * 1.3)
                                implicitHeight: implicitWidth
                                hoverEnabled: true
                                focusPolicy: Qt.StrongFocus
                                Accessible.role: Accessible.Button
                                Accessible.name: qsTr("Copy %1").arg(cell.labelText)
                                onClicked: {
                                    const edit = valueLoader.item as TextEdit;
                                    if (edit) {
                                        edit.selectAll();
                                        edit.copy();
                                        edit.deselect();
                                    }
                                    copied = true;
                                    resetCopied.restart();
                                }
                                Timer {
                                    id: resetCopied
                                    interval: 1500
                                    onTriggered: copyButton.copied = false
                                }
                                background: Rectangle {
                                    radius: TelamonStyle.radiusSmall
                                    color: copyButton.down ? TelamonStyle.pressed : copyButton.hovered ? TelamonStyle.hover : "transparent"
                                    TelamonFocusRing {
                                        radius: parent.radius
                                        shown: copyButton.visualFocus
                                    }
                                }
                                contentItem: Symbol {
                                    icon: copyButton.copied ? Symbols.Check : Symbols.ContentCopy
                                    size: Kirigami.Units.iconSizes.small
                                    color: copyButton.copied ? Kirigami.Theme.positiveTextColor : TelamonStyle.textMuted
                                    anchors.centerIn: parent
                                }
                                QQC2.ToolTip.visible: hovered
                                QQC2.ToolTip.text: qsTr("Copy")
                                QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                            }
                        }
                    }
                }
            }
        }

        Text {
            visible: grid.footer.length > 0
            Layout.fillWidth: true
            Layout.leftMargin: grid.framed ? TelamonStyle.spacingLarge : 0
            Layout.rightMargin: grid.framed ? TelamonStyle.spacingLarge : 0
            text: grid.footer
            wrapMode: Text.Wrap
            font.family: TelamonStyle.fontFamily
            font.pointSize: TelamonStyle.fontSizeCaption
            color: TelamonStyle.textMuted
            textFormat: Text.PlainText
            Accessible.ignored: true
        }
    }
}
