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
//   AtlasDetailGrid {
//       Layout.fillWidth: true
//       model: [
//           { label: qsTr("Version"), value: "1.4.0" },
//           { label: qsTr("Checksum"), value: sha, mono: true, copyable: true }
//       ]
//   }
//
// `columns` is how many label/value pairs sit in a row (default 1). A column
// needs `columnsBreakpoint` grid units (default 20): below that the label
// stacks over its value, and a grid with `columns` > 1 shows fewer pairs per
// row, as many as fit. Give it a width (fill it): its height depends on it.
// A screen reader reads each value as "label: value".
Item {
    id: grid

    property var model: []
    property int columns: 1
    // The least width of one pair, in grid units.
    property real columnsBreakpoint: 20

    readonly property int _count: Array.isArray(model) ? model.length : 0
    readonly property real _pairWidth: Kirigami.Units.gridUnit * Math.max(1, columnsBreakpoint)
    readonly property bool _stacked: width < _pairWidth
    readonly property int _pairs: _stacked ? 1 : Math.max(1, Math.min(columns, Math.floor(width / _pairWidth)))

    implicitHeight: layout.implicitHeight
    implicitWidth: layout.implicitWidth
    opacity: enabled ? 1 : 0.6

    GridLayout {
        id: layout
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
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
                Layout.maximumWidth: isValue || grid._stacked ? Number.POSITIVE_INFINITY : grid.width / grid._pairs * 0.45
                Layout.preferredWidth: isValue || grid._stacked ? 1 : label.implicitWidth
                Layout.topMargin: grid._stacked && !isValue && entryIndex > 0 ? Kirigami.Units.smallSpacing * 2 : 0
                implicitHeight: isValue ? Math.max(valueText.implicitHeight, copyButton.visible ? copyButton.implicitHeight : 0) : label.implicitHeight

                QQC2.Label {
                    id: label
                    visible: !cell.isValue
                    width: parent.width
                    text: cell.text
                    color: Qt.alpha(Kirigami.Theme.textColor, 0.65)
                    horizontalAlignment: grid._stacked ? Text.AlignLeft : Text.AlignRight
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                    Accessible.ignored: true
                }

                TextEdit {
                    id: valueText
                    visible: cell.isValue
                    anchors.left: parent.left
                    anchors.right: copyButton.visible ? copyButton.left : parent.right
                    anchors.rightMargin: copyButton.visible ? Kirigami.Units.smallSpacing : 0
                    text: cell.text
                    readOnly: true
                    selectByMouse: true
                    activeFocusOnTab: false
                    wrapMode: Text.Wrap
                    textFormat: TextEdit.PlainText
                    font: cell.entry.mono === true ? Kirigami.Theme.fixedWidthFont : Kirigami.Theme.defaultFont
                    color: Kirigami.Theme.textColor
                    selectionColor: AtlasStyle.accent
                    selectedTextColor: AtlasStyle.accentText
                    Accessible.role: Accessible.StaticText
                    Accessible.name: (cell.labelText) + ": " + cell.text
                }

                T.AbstractButton {
                    id: copyButton
                    property bool copied: false
                    visible: cell.copyable
                    enabled: grid.enabled
                    anchors.right: parent.right
                    anchors.top: parent.top
                    implicitWidth: Math.round(Kirigami.Units.gridUnit * 1.3)
                    implicitHeight: implicitWidth
                    hoverEnabled: true
                    focusPolicy: Qt.StrongFocus
                    Accessible.role: Accessible.Button
                    Accessible.name: qsTr("Copy %1").arg(cell.labelText)
                    onClicked: {
                        valueText.selectAll();
                        valueText.copy();
                        valueText.deselect();
                        copied = true;
                        resetCopied.restart();
                    }
                    Timer {
                        id: resetCopied
                        interval: 1500
                        onTriggered: copyButton.copied = false
                    }
                    background: Rectangle {
                        radius: AtlasStyle.radiusSmall
                        color: Qt.alpha(Kirigami.Theme.textColor, copyButton.down ? 0.16 : copyButton.hovered ? 0.1 : 0)
                        AtlasFocusRing {
                            radius: parent.radius
                            shown: copyButton.visualFocus
                        }
                    }
                    contentItem: Symbol {
                        icon: copyButton.copied ? Symbols.Check : Symbols.ContentCopy
                        size: Kirigami.Units.iconSizes.small
                        color: copyButton.copied ? Kirigami.Theme.positiveTextColor : Qt.alpha(Kirigami.Theme.textColor, 0.65)
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
