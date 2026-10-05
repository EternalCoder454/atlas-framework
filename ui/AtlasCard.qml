import QtQuick
import QtQuick.Layouts
import QtQuick.Templates as T
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import Atlas.Ui

// A padded card on the raised surface (Section's look: rounded, hairline
// border). An optional header (`title`, `subtitle`, and `headerTrailing`, items
// at the far edge such as a button or a badge), then whatever you put inside,
// then an optional `footer` row. With `clickable` the whole card is a button:
// it reacts to the pointer, takes the keyboard focus (Return, Enter and Space
// click it) and emits `clicked()`. Controls inside a clickable card keep their
// own clicks.
//
//   AtlasCard {
//       title: qsTr("Backups")
//       subtitle: qsTr("Last run yesterday")
//       headerTrailing: [ SecondaryButton { text: qsTr("Run now") } ]
//       AtlasLabel { text: qsTr("42 files protected.") }
//       footer: [ TextButton { text: qsTr("Details") } ]
//   }
T.Control {
    id: control

    property string title
    property string subtitle
    property bool clickable: false
    // Items at the trailing edge of the header row.
    property alias headerTrailing: trailingRow.data
    // A row under the content, aligned to the trailing edge.
    property alias footer: footerRow.data
    default property alias content: contentColumn.data

    signal clicked

    readonly property bool _hasHeader: title.length > 0 || subtitle.length > 0 || trailingRow.children.length > 0

    implicitWidth: Math.max(implicitBackgroundWidth + leftInset + rightInset, implicitContentWidth + leftPadding + rightPadding)
    implicitHeight: Math.max(implicitBackgroundHeight + topInset + bottomInset, implicitContentHeight + topPadding + bottomPadding)
    padding: AtlasStyle.spacingLarge * 2
    hoverEnabled: control.clickable
    focusPolicy: control.clickable ? Qt.StrongFocus : Qt.NoFocus
    Layout.fillWidth: true

    Accessible.role: control.clickable ? Accessible.Button : Accessible.Grouping
    Accessible.name: control.title
    Accessible.description: control.subtitle
    Accessible.focusable: control.clickable
    Accessible.onPressAction: control.clicked()

    function _activate(event: var): void {
        if (control.clickable && control.enabled && !event.isAutoRepeat) {
            control.clicked();
        } else if (!control.clickable) {
            event.accepted = false;
        }
    }
    Keys.onReturnPressed: event => control._activate(event)
    Keys.onEnterPressed: event => control._activate(event)
    Keys.onSpacePressed: event => control._activate(event)

    background: Rectangle {
        radius: AtlasStyle.radiusLarge
        color: AtlasStyle.surface
        border.width: 1
        border.color: AtlasStyle.separator
        opacity: control.enabled ? 1 : 0.5
        // The hover and press tint over the surface.
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: Qt.alpha(Kirigami.Theme.textColor, press.pressed ? 0.1 : control.hovered ? 0.05 : 0)
            Behavior on color {
                ColorAnimation {
                    duration: AtlasStyle.durationShort
                }
            }
        }
        // Under the content, so what is inside keeps its own clicks.
        MouseArea {
            id: press
            anchors.fill: parent
            enabled: control.clickable
            cursorShape: control.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: control.clicked()
        }
        AtlasFocusRing {
            radius: parent.radius
            shown: control.visualFocus
        }
    }

    contentItem: ColumnLayout {
        spacing: AtlasStyle.spacingLarge
        opacity: control.enabled ? 1 : 0.5

        RowLayout {
            visible: control._hasHeader
            Layout.fillWidth: true
            spacing: AtlasStyle.spacingLarge
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                QQC2.Label {
                    visible: control.title.length > 0
                    Layout.fillWidth: true
                    text: control.title
                    font.bold: true
                    font.pointSize: AtlasStyle.fontSizeHeading
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                    Accessible.ignored: true
                }
                QQC2.Label {
                    visible: control.subtitle.length > 0
                    Layout.fillWidth: true
                    text: control.subtitle
                    color: AtlasStyle.textMuted
                    font.pointSize: AtlasStyle.fontSizeCaption
                    wrapMode: Text.Wrap
                    textFormat: Text.PlainText
                    Accessible.ignored: true
                }
            }
            RowLayout {
                id: trailingRow
                spacing: AtlasStyle.spacing
            }
        }

        ColumnLayout {
            id: contentColumn
            visible: contentColumn.children.length > 0
            Layout.fillWidth: true
            spacing: AtlasStyle.spacing
        }

        RowLayout {
            visible: footerRow.children.length > 0
            Layout.fillWidth: true
            spacing: 0
            // Pushes the footer to the trailing edge, either way round.
            Item {
                Layout.fillWidth: true
            }
            RowLayout {
                id: footerRow
                spacing: AtlasStyle.spacing
            }
        }
    }
}
