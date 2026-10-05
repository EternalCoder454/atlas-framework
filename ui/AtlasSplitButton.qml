pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami

// A main button joined to an arrow part that opens a menu: the common action
// ("Save") and its variants ("Save As...", "Save a Copy"). Put ContextMenuItem
// and ContextMenuSeparator children inside, like MenuButton. `prominent`
// fills it with the accent. The main part runs `action` (an Action or
// AtlasAction, optional: it also supplies `text`, `symbol` and the enabled
// state when those are not set) and emits `clicked()`.
//
//   AtlasSplitButton {
//       text: qsTr("Save")
//       symbol: Symbols.Save
//       prominent: true
//       onClicked: document.save()
//       ContextMenuItem { text: qsTr("Save As..."); onTriggered: document.saveAs() }
//   }
//
// Two Tab stops, the main part then the arrow. Alt+Down, or the Menu key,
// on the main part opens the menu too; Enter and Space activate the focused
// part. Accessible names: the main part's is `text`, the arrow's "More options".
Item {
    id: control

    property string text
    property int symbol: 0
    property bool prominent: false
    property T.Action action: null
    default property alias items: menu.contentData
    readonly property alias menu: menu
    signal clicked
    readonly property bool mirrored: LayoutMirroring.enabled

    readonly property string _text: text.length > 0 || !action ? text : action.text.replace(/&(&|.)/g, "$1")
    readonly property int _symbol: symbol !== 0 || !action ? symbol : ((action as AtlasAction)?.symbol ?? 0)
    readonly property color _fg: !enabled ? AtlasStyle.textDisabled : prominent ? AtlasStyle.accentStrongText : Kirigami.Theme.textColor

    implicitWidth: mainPart.implicitWidth + arrowPart.implicitWidth
    implicitHeight: AtlasStyle.controlHeight

    function openMenu() {
        menu.popup(arrowPart, arrowPart.width - menu.implicitWidth, arrowPart.height + 4);
    }

    // One half: a small rounded rectangle (radiusSmall) whose inner end is squared off to meet the other half.
    component Part: T.AbstractButton {
        id: part
        required property bool leading
        // Passed in: an inline component does not see the ids of the file around it.
        required property AtlasSplitButton owner
        // True on the half at the left edge (mirrored layouts swap).
        readonly property bool atLeft: leading !== owner.mirrored

        hoverEnabled: true
        focusPolicy: Qt.StrongFocus
        scale: down && enabled ? 0.97 : 1
        Behavior on scale {
            NumberAnimation {
                duration: AtlasStyle.durationShort
                easing.type: Easing.OutCubic
            }
        }
        background: Item {
            Rectangle {
                id: shape
                anchors.fill: parent
                // Round at the outer end only: the inner end meets the other half.
                radius: 0
                topLeftRadius: part.atLeft ? AtlasStyle.radiusSmall : 0
                bottomLeftRadius: topLeftRadius
                topRightRadius: part.atLeft ? 0 : AtlasStyle.radiusSmall
                bottomRightRadius: topRightRadius
                color: part.fillColor
                border.width: part.owner.prominent && part.enabled ? 0 : 1
                border.color: AtlasStyle.controlBorder
                Behavior on color {
                    ColorAnimation {
                        duration: AtlasStyle.durationShort
                    }
                }
                // The grey state layer, as on AtlasButton.
                Rectangle {
                    anchors.fill: parent
                    topLeftRadius: parent.topLeftRadius
                    bottomLeftRadius: parent.bottomLeftRadius
                    topRightRadius: parent.topRightRadius
                    bottomRightRadius: parent.bottomRightRadius
                    color: !part.enabled ? "transparent" : part.down ? AtlasStyle.pressed : part.hovered ? AtlasStyle.hover : "transparent"
                }
            }
            // A hairline between the halves.
            Rectangle {
                x: part.atLeft ? parent.width - width : 0
                width: 1
                height: parent.height - 8
                y: 4
                color: part.owner.prominent && part.enabled ? Qt.alpha(AtlasStyle.accentStrongText, 0.35) : AtlasStyle.controlBorder
            }
            AtlasFocusRing {
                radius: AtlasStyle.radiusSmall + gap
                shown: part.visualFocus
            }
        }
        readonly property color fillColor: {
            return owner.prominent && enabled ? AtlasStyle.accentStrong : AtlasStyle.control;
        }
    }

    Row {
        anchors.fill: parent
        spacing: 0
        LayoutMirroring.enabled: control.mirrored
        LayoutMirroring.childrenInherit: true

        Part {
            id: mainPart
            owner: control
            leading: true
            height: parent.height
            enabled: control.enabled && (!control.action || control.action.enabled)
            implicitWidth: Math.max(Math.round(Kirigami.Units.gridUnit * 3.5), mainRow.implicitWidth + leftPadding + rightPadding)
            leftPadding: AtlasStyle.spacingLarge + AtlasStyle.spacingSmall
            rightPadding: AtlasStyle.spacingLarge
            Accessible.role: Accessible.Button
            Accessible.name: control._text
            onClicked: {
                if (control.action) {
                    control.action.trigger(mainPart);
                }
                control.clicked();
            }
            Keys.onPressed: event => {
                if ((event.key === Qt.Key_Down && (event.modifiers & Qt.AltModifier)) || event.key === Qt.Key_Menu) {
                    event.accepted = true;
                    control.openMenu();
                }
            }
            contentItem: Item {
                implicitWidth: mainRow.implicitWidth
                implicitHeight: mainRow.implicitHeight
                Row {
                    id: mainRow
                    anchors.centerIn: parent
                    spacing: AtlasStyle.spacingSmall
                    Loader {
                        active: control._symbol !== 0
                        visible: active
                        anchors.verticalCenter: parent.verticalCenter
                        sourceComponent: Symbol {
                            icon: control._symbol
                            size: Math.round(Kirigami.Units.iconSizes.small * 1.2)
                            color: mainLabel.color
                        }
                    }
                    Text {
                        id: mainLabel
                        Accessible.ignored: true
                        anchors.verticalCenter: parent.verticalCenter
                        text: control._text
                        font.family: AtlasStyle.fontFamily
                        font.pointSize: AtlasStyle.fontSizeBody
                        color: control._fg
                        textFormat: Text.PlainText
                    }
                }
            }
        }
        Part {
            id: arrowPart
            owner: control
            leading: false
            height: parent.height
            enabled: control.enabled
            implicitWidth: Math.round(Kirigami.Units.gridUnit * 1.9)
            Accessible.role: Accessible.ButtonMenu
            Accessible.name: qsTr("More options")
            Accessible.description: menu.visible ? qsTr("Expanded") : qsTr("Collapsed")
            onClicked: control.openMenu()
            contentItem: Item {
                Symbol {
                    anchors.centerIn: parent
                    icon: Symbols.ExpandMore
                    size: Math.round(Kirigami.Units.iconSizes.small * 1.2)
                    color: control._fg
                }
            }
        }
    }

    ContextMenu {
        id: menu
    }
}
