import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami

// Sidebar entry: accent icon plus label, with a rounded selection pill, and
// optionally a live value on the right ("42%", "1.2 MB/s"). A `sub` entry is
// indented under a SidebarGroup's header; a `disclosure` entry is that header.
// A `badge` icon flags something on the entry's page that needs attention:
// after the label, or on the icon's corner when compact. When compact, hover
// or the keyboard focus shows the title (and value) as a tooltip.
T.AbstractButton {
    id: control

    property bool selected: false
    // Icon only (narrow windows); the text becomes the tooltip and accessible name.
    property bool compact: false
    // Tint a monochrome icon with the accent; false keeps a coloured icon as is.
    property bool tintIcon: true
    // A Material Symbol (Symbols.<Name>) to draw instead of icon.name. It
    // fills in while the entry is selected.
    property int symbol: 0
    // Shown dimmed at the right edge; hidden when compact.
    property string value
    property bool sub: false
    // A chevron that turns down when `expanded` (SidebarGroup's header).
    property bool disclosure: false
    property bool expanded: false
    // An icon name, such as "dialog-warning"; empty for none. Drawn in its
    // own colours: a tint would fill in the mark inside a status icon.
    property string badge
    // What the badge means, for screen readers ("2 problems").
    property string badgeText

    // AtlasStyle.Normal or AtlasStyle.Compact; Compact shrinks the height and
    // the vertical padding to about 75%. Follows the app-wide AtlasStyle.density
    // unless set here.
    property int density: AtlasStyle.density
    readonly property real _k: density === AtlasStyle.Compact ? 0.75 : 1

    implicitHeight: Math.round(Kirigami.Units.gridUnit * (sub ? 1.8 : 2.1) * _k)
    implicitWidth: compact ? implicitHeight + AtlasStyle.spacingSmall : Kirigami.Units.gridUnit * 10
    hoverEnabled: true
    focusPolicy: Qt.StrongFocus
    Accessible.name: control.text
    Accessible.description: {
        const own = control.disclosure ? (control.expanded ? qsTr("Expanded") : qsTr("Collapsed")) : control.value;
        return control.badge.length > 0 && control.badgeText.length > 0 ? (own.length > 0 ? own + ", " + control.badgeText : control.badgeText) : own;
    }
    Accessible.checkable: true
    Accessible.checked: control.selected
    Keys.onReturnPressed: event => {
        if (!event.isAutoRepeat) {
            control.clicked();
        }
    }
    Keys.onEnterPressed: event => {
        if (!event.isAutoRepeat) {
            control.clicked();
        }
    }

    AtlasToolTip {
        text: control.value.length > 0 ? control.text + ": " + control.value : control.text
        shown: control.compact && control.text.length > 0 && (control.hovered || control.visualFocus)
    }

    background: Rectangle {
        radius: AtlasStyle.radius
        color: control.selected ? Qt.alpha(Kirigami.Theme.highlightColor, 0.18) : Qt.alpha(Kirigami.Theme.textColor, control.down ? 0.1 : control.hovered ? 0.06 : 0)
        border.width: control.visualFocus ? 2 : 0
        border.color: Qt.alpha(Kirigami.Theme.highlightColor, 0.6)
        Behavior on color {
            ColorAnimation {
                duration: AtlasStyle.durationShort
            }
        }
    }

    contentItem: RowLayout {
        spacing: AtlasStyle.spacingLarge
        Item {
            Layout.fillWidth: control.compact
            visible: control.compact
        }
        Item {
            id: iconSlot
            readonly property int side: control.sub ? Kirigami.Units.iconSizes.small : Kirigami.Units.iconSizes.smallMedium
            Layout.leftMargin: control.compact ? 0 : AtlasStyle.spacingLarge + (control.sub ? Kirigami.Units.gridUnit : 0)
            Layout.preferredWidth: side
            Layout.preferredHeight: side

            Kirigami.Icon {
                anchors.fill: parent
                visible: control.symbol === 0
                source: control.icon.name
                isMask: control.tintIcon
                color: Kirigami.Theme.highlightColor
            }
            // Made only when used, so entries without one never load the fonts.
            Loader {
                anchors.centerIn: parent
                active: control.symbol !== 0
                sourceComponent: Symbol {
                    icon: control.symbol
                    // A symbol fills about 5/6 of its square: a little larger
                    // matches a theme icon of the same slot.
                    size: Math.round(iconSlot.side * 1.2)
                    filled: control.selected
                    color: control.tintIcon ? Kirigami.Theme.highlightColor : Kirigami.Theme.textColor
                }
            }

            Kirigami.Icon {
                visible: control.compact && control.badge.length > 0
                width: Kirigami.Units.iconSizes.small * 0.75
                height: width
                // On the trailing bottom corner, half over the edge.
                x: control.mirrored ? -width / 3 : parent.width - width * 2 / 3
                y: parent.height - height * 2 / 3
                source: control.badge
            }
        }
        Text {
            visible: !control.compact
            Layout.fillWidth: true
            text: control.text
            font.family: Kirigami.Theme.defaultFont.family
            font.pointSize: AtlasStyle.fontSizeBody
            font.weight: control.sub ? Font.Normal : Font.Medium
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: Kirigami.Theme.textColor
        }
        Kirigami.Icon {
            visible: !control.compact && control.badge.length > 0
            Layout.rightMargin: control.value.length > 0 || control.disclosure ? 0 : AtlasStyle.spacingLarge
            Layout.preferredWidth: Kirigami.Units.iconSizes.small
            Layout.preferredHeight: Kirigami.Units.iconSizes.small
            source: control.badge
        }
        QQC2.Label {
            visible: !control.compact && control.value.length > 0
            Layout.rightMargin: control.disclosure ? 0 : AtlasStyle.spacingLarge
            text: control.value
            font.family: Kirigami.Theme.smallFont.family
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            // Figures of one width, so a changing value doesn't jiggle.
            font.features: ({
                    "tnum": 1
                })
            textFormat: Text.PlainText
            opacity: 0.6
        }
        Kirigami.Icon {
            visible: !control.compact && control.disclosure
            Layout.rightMargin: AtlasStyle.spacingLarge
            Layout.preferredWidth: Kirigami.Units.iconSizes.small
            Layout.preferredHeight: Kirigami.Units.iconSizes.small
            source: control.mirrored ? "arrow-left" : "arrow-right"
            isMask: true
            color: Kirigami.Theme.textColor
            opacity: 0.45
            // A quarter turn to point down, whichever way it starts.
            rotation: control.expanded ? (control.mirrored ? -90 : 90) : 0
            Behavior on rotation {
                NumberAnimation {
                    duration: AtlasStyle.durationShort
                }
            }
        }
        Item {
            Layout.fillWidth: control.compact
            visible: control.compact
        }
    }
}
