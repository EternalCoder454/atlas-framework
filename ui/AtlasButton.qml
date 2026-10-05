pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami

// The button every Atlas app uses (PrimaryButton, SecondaryButton and the
// like are this with a preset look). Small rounded corners (radiusSmall; they
// go to radius while pressed), controlHeight tall, grey hover and press.
//
//   AtlasButton { text: qsTr("Save"); variant: AtlasButton.Prominent }
//   AtlasButton { text: qsTr("Delete"); variant: AtlasButton.Destructive; symbol: Symbols.Delete }
//   AtlasButton { text: qsTr("Sync"); busy: model.syncing }
//
// `variant` chooses the look: Default (control fill, hairline border),
// Prominent (accentStrong fill, the one main action of a view), Destructive
// (error text and border on a faint error fill) or Ghost (no fill and no
// border until hover). `prominent: true` is the same as `variant: Prominent`
// and stays supported. Precedence: a variant other than Default wins; with
// Default, `prominent` decides.
//
// The states are one layer for every variant: hover and press lay a grey
// overlay over the fill, `checked` (with `checkable`) shows the selection fill
// with an accent border and accent text, a disabled button has readable
// disabled text, and the keyboard focus ring is drawn outside. `busy` shows a
// spinner in place of the symbol (before the text when there is no symbol, so
// the button grows a little), and while busy the button takes no mouse or
// Return/Enter/Space press and describes itself as "Busy" to screen readers.
T.AbstractButton {
    id: control

    enum Variant {
        Default,
        Prominent,
        Destructive,
        Ghost
    }

    // The look (see above). Default leaves the choice to `prominent`.
    property int variant: AtlasButton.Default
    property bool prominent: false
    // Something is in progress: a spinner, and no presses.
    property bool busy: false
    // A Material Symbol (Symbols.<Name>) to draw instead of icon.name.
    property int symbol: 0
    // Whether the busy spinner turns; false for a still arc (screenshots).
    property bool _spinnerAnimated: true
    readonly property color accent: AtlasStyle.accent
    readonly property color textTint: Kirigami.Theme.textColor

    // The look in force: a variant other than Default wins over `prominent`.
    readonly property int _variant: variant !== AtlasButton.Default ? variant : (prominent ? AtlasButton.Prominent : AtlasButton.Default)
    readonly property color _fg: {
        if (!enabled) {
            return AtlasStyle.textDisabled;
        }
        if (checked) {
            return AtlasStyle.accent;
        }
        switch (_variant) {
        case AtlasButton.Prominent:
            return AtlasStyle.accentStrongText;
        case AtlasButton.Destructive:
            return AtlasStyle.error;
        default:
            return Kirigami.Theme.textColor;
        }
    }
    readonly property color _fill: {
        if (checked) {
            return AtlasStyle.selection;
        }
        switch (_variant) {
        case AtlasButton.Prominent:
            return enabled ? AtlasStyle.accentStrong : AtlasStyle.control;
        case AtlasButton.Destructive:
            return AtlasStyle.errorFill;
        case AtlasButton.Ghost:
            return "transparent";
        default:
            return AtlasStyle.control;
        }
    }
    readonly property bool _hasBorder: checked || _variant === AtlasButton.Default || _variant === AtlasButton.Destructive || (_variant === AtlasButton.Prominent && !enabled)
    readonly property color _border: {
        if (checked && enabled) {
            return AtlasStyle.accent;
        }
        if (_variant === AtlasButton.Destructive && enabled) {
            return Qt.alpha(AtlasStyle.error, 0.5);
        }
        return AtlasStyle.controlBorder;
    }

    implicitWidth: Math.max(Math.round(Kirigami.Units.gridUnit * 4.5), contentItem.implicitWidth + leftPadding + rightPadding)
    implicitHeight: Math.max(AtlasStyle.controlHeight, contentItem.implicitHeight + topPadding + bottomPadding)
    leftPadding: AtlasStyle.spacingLarge + AtlasStyle.spacingSmall
    rightPadding: leftPadding
    topPadding: AtlasStyle.spacingSmall
    bottomPadding: AtlasStyle.spacingSmall
    hoverEnabled: true
    focusPolicy: Qt.StrongFocus
    scale: control.down && control.enabled ? 0.97 : 1

    Accessible.name: control.text
    Accessible.description: control.busy ? qsTr("Busy") : ""
    // A screen reader's press must not click a busy or disabled button.
    Accessible.onPressAction: {
        if (control.enabled && !control.busy) {
            control.click();
        }
    }
    Keys.onReturnPressed: event => {
        if (enabled && !busy && !event.isAutoRepeat) {
            control.clicked();
        }
    }
    Keys.onEnterPressed: event => {
        if (enabled && !busy && !event.isAutoRepeat) {
            control.clicked();
        }
    }
    // A busy button swallows Space too, so it neither presses nor toggles.
    Keys.onSpacePressed: event => event.accepted = control.busy
    Keys.onReleased: event => {
        if (control.busy && event.key === Qt.Key_Space) {
            event.accepted = true;
        }
    }

    Behavior on scale {
        NumberAnimation {
            duration: AtlasStyle.durationShort
            easing.type: Easing.OutCubic
        }
    }

    // While busy, a cover takes the mouse so the button neither hovers nor presses.
    MouseArea {
        anchors.fill: parent
        z: 10
        enabled: control.busy
        acceptedButtons: Qt.AllButtons
        cursorShape: Qt.BusyCursor
    }

    contentItem: Item {
        implicitWidth: row.implicitWidth
        implicitHeight: row.implicitHeight
        Row {
            id: row
            anchors.centerIn: parent
            spacing: AtlasStyle.spacingSmall
            // The busy spinner takes the symbol's place.
            Loader {
                active: control.busy
                visible: active
                anchors.verticalCenter: parent.verticalCenter
                sourceComponent: AtlasSpinner {
                    implicitWidth: Math.round(Kirigami.Units.iconSizes.small * 1.2)
                    animated: control._spinnerAnimated
                    color: control._fg
                    Accessible.ignored: true
                }
            }
            // Made only when used, so buttons without one never load the fonts.
            Loader {
                active: control.symbol !== 0 && !control.busy
                visible: active
                anchors.verticalCenter: parent.verticalCenter
                sourceComponent: Symbol {
                    icon: control.symbol
                    // A symbol fills about 5/6 of its square: a little larger
                    // matches a theme icon of the same slot.
                    size: Math.round(Kirigami.Units.iconSizes.small * 1.2)
                    color: label.color
                }
            }
            Kirigami.Icon {
                visible: control.symbol === 0 && control.icon.name.length > 0 && !control.busy
                source: control.icon.name
                isMask: true
                color: label.color
                width: Kirigami.Units.iconSizes.small
                height: width
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                id: label
                Accessible.ignored: true
                anchors.verticalCenter: parent.verticalCenter
                text: control.text
                font.family: AtlasStyle.fontFamily
                font.pointSize: AtlasStyle.fontSizeBody
                color: control._fg
                textFormat: Text.PlainText // no mnemonics
                Behavior on color {
                    ColorAnimation {
                        duration: AtlasStyle.durationShort
                    }
                }
            }
        }
    }

    background: Rectangle {
        // Pressed corners grow 4 to 6 px.
        radius: control.down && control.enabled && !control.busy ? AtlasStyle.radius : AtlasStyle.radiusSmall
        color: control._fill
        border.width: control._hasBorder ? 1 : 0
        border.color: control._border
        Behavior on radius {
            enabled: !AtlasStyle.reducedMotion
            AtlasSpringAnimation {}
        }
        Behavior on color {
            ColorAnimation {
                duration: AtlasStyle.durationShort
            }
        }
        // The state layer: the same grey for every variant.
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: !control.enabled || control.busy ? "transparent" : control.down ? AtlasStyle.pressed : control.hovered ? AtlasStyle.hover : "transparent"
            Behavior on color {
                ColorAnimation {
                    duration: AtlasStyle.durationShort
                }
            }
        }
        AtlasFocusRing {
            radius: parent.radius + gap
            shown: control.visualFocus
        }
    }
}
