import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import Telamon.Ui

// TelamonAction: what one carries (text, symbol, shortcut, tooltip, section),
// shown as rows. Tests set `animate` to false.
Item {
    id: root

    property bool animate: true

    implicitWidth: 520
    implicitHeight: layout.implicitHeight + Kirigami.Units.gridUnit * 2

    TelamonAction {
        id: save
        text: "&Save"
        symbol: Symbols.Save
        shortcut: "Ctrl+S"
        section: "File"
    }
    TelamonAction {
        id: open
        text: "Open"
        symbol: Symbols.FolderOpen
        shortcut: "Ctrl+O"
        toolTip: "Open a document"
    }
    TelamonAction {
        id: bold
        text: "Bold"
        symbol: Symbols.FormatBold
        shortcut: "Ctrl+B"
        checkable: true
        checked: true
    }
    TelamonAction {
        id: paste
        text: "Paste"
        symbol: Symbols.ContentPaste
        shortcut: "Ctrl+V"
        enabled: false
    }

    ColumnLayout {
        id: layout
        anchors.centerIn: parent
        width: parent.width - Kirigami.Units.gridUnit * 2
        spacing: Kirigami.Units.largeSpacing

        Repeater {
            model: [save, open, bold, paste]
            delegate: RowLayout {
                id: row
                required property var modelData
                Layout.fillWidth: true
                spacing: Kirigami.Units.largeSpacing
                opacity: row.modelData.enabled ? 1 : 0.5
                Symbol {
                    icon: row.modelData.symbol
                    filled: row.modelData.checked
                }
                QQC2.Label {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: row.modelData.text.replace("&", "") + "  (tooltip: " + row.modelData.toolTip + ")"
                    elide: Text.ElideRight
                }
                TelamonShortcutLabel { sequence: row.modelData.shortcut }
            }
        }
    }
}
