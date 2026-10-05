pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import Atlas.Ui

// A header row that folds its content away: an optional symbol, a title with
// an optional subtitle, and a chevron. A click, Space, Return or Enter on the
// header toggles `expanded` and emits `toggled(expanded)`. The content grows
// and shrinks in AtlasStyle.duration, and while it is folded nothing in it
// can take the keyboard focus. (Section folds a card and leaves the state to
// the page; this one keeps its own.)
//
//   AtlasExpandableSection {
//       title: qsTr("Advanced")
//       subtitle: qsTr("For experts")
//       symbol: Symbols.Settings
//       onToggled: expanded => settings.advancedOpen = expanded
//       AtlasCheckBox { text: qsTr("Verbose log") }
//   }
ColumnLayout {
    id: root

    property string title
    property string subtitle
    // A Material Symbol (Symbols.<Name>) in front of the title; 0 for none.
    property int symbol: 0
    property bool expanded: false
    default property alias content: col.data

    // The header was used: `expanded` is the new state.
    signal toggled(bool expanded)

    // 0 folded, 1 open; moves while the content grows or shrinks.
    property real _progress: expanded ? 1 : 0
    Behavior on _progress {
        NumberAnimation {
            duration: AtlasStyle.duration
            easing.type: Easing.InOutCubic
        }
    }

    Layout.fillWidth: true
    spacing: 0

    function _toggle(): void {
        root.expanded = !root.expanded;
        root.toggled(root.expanded);
    }

    QQC2.AbstractButton {
        id: header
        Layout.fillWidth: true
        implicitHeight: Math.max(AtlasStyle.rowHeight, contentItem.implicitHeight + topPadding + bottomPadding)
        leftPadding: AtlasStyle.spacingLarge
        rightPadding: AtlasStyle.spacingLarge
        topPadding: AtlasStyle.spacingSmall
        bottomPadding: AtlasStyle.spacingSmall
        hoverEnabled: true
        focusPolicy: Qt.StrongFocus
        text: root.title
        onClicked: root._toggle()
        // A button takes Space only; a fold header also takes Return and Enter.
        Keys.onReturnPressed: event => {
            if (!event.isAutoRepeat) {
                root._toggle();
            }
        }
        Keys.onEnterPressed: event => {
            if (!event.isAutoRepeat) {
                root._toggle();
            }
        }
        Accessible.role: Accessible.Button
        Accessible.name: root.title
        // As Section and SidebarGroup say it: QML's Accessible has no expanded state.
        Accessible.description: root.expanded ? qsTr("Expanded") : qsTr("Collapsed")

        background: Rectangle {
            radius: AtlasStyle.radius
            color: Qt.alpha(Kirigami.Theme.textColor, header.pressed ? 0.1 : header.hovered ? 0.05 : 0)
            AtlasFocusRing {
                radius: parent.radius
                shown: header.visualFocus
            }
        }

        contentItem: RowLayout {
            spacing: AtlasStyle.spacingLarge
            opacity: header.enabled ? 1 : 0.5
            Loader {
                active: root.symbol !== 0
                visible: active
                sourceComponent: Symbol {
                    icon: root.symbol
                    size: Math.round(Kirigami.Units.iconSizes.small * 1.2)
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                QQC2.Label {
                    Layout.fillWidth: true
                    text: root.title
                    font.bold: true
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                    Accessible.ignored: true
                }
                QQC2.Label {
                    visible: root.subtitle.length > 0
                    Layout.fillWidth: true
                    text: root.subtitle
                    color: AtlasStyle.textMuted
                    font.pointSize: AtlasStyle.fontSizeCaption
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                    Accessible.ignored: true
                }
            }
            Symbol {
                icon: Symbols.ExpandMore
                size: Math.round(Kirigami.Units.iconSizes.small * 1.2)
                color: AtlasStyle.textMuted
                // Down when open; towards the content's side when folded.
                rotation: (1 - root._progress) * (header.mirrored ? 90 : -90)
            }
        }
    }

    Item {
        id: clip
        Layout.fillWidth: true
        // Nothing of a folded section is drawn, and Tab skips it.
        visible: root._progress > 0
        clip: root._progress < 1
        implicitHeight: Math.round((col.implicitHeight + col.y) * root._progress)
        opacity: root._progress

        ColumnLayout {
            id: col
            x: AtlasStyle.spacingLarge
            y: AtlasStyle.spacingSmall
            width: parent.width - AtlasStyle.spacingLarge * 2
            spacing: AtlasStyle.spacing
        }
    }
}
