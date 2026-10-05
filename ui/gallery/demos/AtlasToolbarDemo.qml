import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import Atlas.Ui

// AtlasToolbar wide enough for every action, and narrow, with the rest
// behind the "more" button. Tests set `animate` to false.
Item {
    id: root

    property bool animate: true

    implicitWidth: 560
    implicitHeight: layout.implicitHeight + Kirigami.Units.gridUnit * 2

    AtlasAction {
        id: undo
        text: "Undo"
        symbol: Symbols.Undo
        section: "Edit"
    }
    AtlasAction {
        id: redo
        text: "Redo"
        symbol: Symbols.Redo
        section: "Edit"
        enabled: false
    }
    AtlasAction {
        id: bold
        text: "Bold"
        symbol: Symbols.FormatBold
        section: "Format"
        checkable: true
        checked: true
    }
    AtlasAction {
        id: italic
        text: "Italic"
        symbol: Symbols.FormatItalic
        section: "Format"
        checkable: true
    }
    AtlasAction {
        id: link
        text: "Link"
        symbol: Symbols.Link
        section: "Insert"
    }
    AtlasAction {
        id: image
        text: "Image"
        symbol: Symbols.Image
        section: "Insert"
    }

    ColumnLayout {
        id: layout
        anchors.centerIn: parent
        width: parent.width - Kirigami.Units.gridUnit * 2
        spacing: Kirigami.Units.gridUnit

        QQC2.Label {
            text: "Wide"
            font: Kirigami.Theme.smallFont
            opacity: 0.6
        }
        AtlasToolbar {
            Layout.fillWidth: true
            actions: [undo, redo, bold, italic, link, image]
            leading: QQC2.Label {
                text: "Notes"
                font.bold: true
            }
        }
        QQC2.Label {
            text: "Narrow: the rest is behind More"
            font: Kirigami.Theme.smallFont
            opacity: 0.6
        }
        AtlasToolbar {
            Layout.preferredWidth: Kirigami.Units.gridUnit * 12
            flat: false
            actions: [undo, redo, bold, italic, link, image]
        }
    }
}
