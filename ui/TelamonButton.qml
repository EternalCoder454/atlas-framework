pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami

// The button every Telamon app uses (PrimaryButton, SecondaryButton and the
// like are this with a preset look). Small rounded corners (radiusSmall; they
// go to radius while pressed), controlHeight tall, grey hover and press.
//
//   TelamonButton { text: qsTr("Save"); variant: TelamonButton.Prominent }
//   TelamonButton { text: qsTr("Delete"); variant: TelamonButton.Destructive; symbol: Symbols.Delete }
//   TelamonButton { text: qsTr("Sync"); busy: model.syncing }
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
    property int variant: TelamonButton.Default
    property bool prominent: false
    // The widest the button asks for (its implicit width); a longer text is
    // elided. 0 means no limit. Since 1.5.0.
    property real maximumWidth: 0
    // Something is in progress: a spinner, and no presses.
    property bool busy: false
    // A Material Symbol (Symbols.<Name>) to draw instead of icon.name.
    property int symbol: 0
    // Whether the busy spinner turns; false for a still arc (screenshots).
    property bool _spinnerAnimated: true
    readonly property color accent: TelamonStyle.accent
    readonly property color textTint: Kirigami.Theme.textColor

    // The look in force: a variant other than Default wins over `prominent`.
    readonly property int _variant: variant !== TelamonButton.Default ? variant : (prominent ? TelamonButton.Prominent : TelamonButton.Default)
    readonly property color _fg: {
        if (!enabled) {
            return TelamonStyle.textDisabled;
        }
        if (checked) {
            return TelamonStyle.accent;
        }
        switch (_variant) {
        case TelamonButton.Prominent:
            return TelamonStyle.accentStrongText;
        case TelamonButton.Destructive:
            return TelamonStyle.error;
        default:
            return Kirigami.Theme.textColor;
        }
    }
    readonly property color _fill: {
        if (checked) {
            return TelamonStyle.selection;
        }
        switch (_variant) {
        case TelamonButton.Prominent:
            return enabled ? TelamonStyle.accentStrong : TelamonStyle.control;
        case TelamonButton.Destructive:
            return TelamonStyle.errorFill;
        case TelamonButton.Ghost:
            return "transparent";
        default:
            return TelamonStyle.control;
        }
    }
    readonly property bool _hasBorder: checked || _variant === TelamonButton.Default || _variant === TelamonButton.Destructive || (_variant === TelamonButton.Prominent && !enabled)
    readonly property color _border: {
        if (checked && enabled) {
            return TelamonStyle.accent;
        }
        if (_variant === TelamonButton.Destructive && enabled) {
            return TelamonStyle.alpha(TelamonStyle.error, 0.5);
        }
        return TelamonStyle.controlBorder;
    }

    implicitWidth: Math.max(Math.round(Kirigami.Units.gridUnit * 4.5), contentItem.implicitWidth + leftPadding + rightPadding)
    implicitHeight: Math.max(TelamonStyle.controlHeight, contentItem.implicitHeight + topPadding + bottomPadding)
    leftPadding: TelamonStyle.spacingLarge + TelamonStyle.spacingSmall
    rightPadding: leftPadding
    topPadding: TelamonStyle.spacingSmall
    bottomPadding: TelamonStyle.spacingSmall
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
            control.click();
        }
    }
    Keys.onEnterPressed: event => {
        if (enabled && !busy && !event.isAutoRepeat) {
            control.click();
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
            duration: TelamonStyle.durationShort
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
            spacing: TelamonStyle.spacingSmall
            // The busy spinner takes the symbol's place.
            Loader {
                id: spinLoader
                active: control.busy
                visible: active
                anchors.verticalCenter: parent.verticalCenter
                sourceComponent: TelamonSpinner {
                    implicitWidth: Math.round(Kirigami.Units.iconSizes.small * 1.2)
                    animated: control._spinnerAnimated
                    color: control._fg
                    Accessible.ignored: true
                }
            }
            // Made only when used, so buttons without one never load the fonts.
            Loader {
                id: symLoader
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
            TelamonIcon {
                id: themeIcon
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
                font.family: TelamonStyle.fontFamily
                font.pointSize: TelamonStyle.fontSizeBody
                color: control._fg
                textFormat: Text.PlainText // no mnemonics
                elide: Text.ElideRight
                // With maximumWidth the text gives way; else it keeps its own width.
                readonly property real _others: (spinLoader.visible ? spinLoader.width + TelamonStyle.spacingSmall : 0) + (symLoader.visible ? symLoader.width + TelamonStyle.spacingSmall : 0) + (themeIcon.visible ? themeIcon.width + TelamonStyle.spacingSmall : 0)
                width: control.maximumWidth > 0 ? Math.min(implicitWidth, Math.max(0, control.maximumWidth - control.leftPadding - control.rightPadding - _others)) : implicitWidth
                Behavior on color {
                    ColorAnimation {
                        duration: TelamonStyle.durationShort
                    }
                }
            }
        }
    }

    background: Rectangle {
        // Pressed corners grow 4 to 6 px.
        radius: control.down && control.enabled && !control.busy ? TelamonStyle.radius : TelamonStyle.radiusSmall
        color: control._fill
        border.width: control._hasBorder ? 1 : 0
        border.color: control._border
        Behavior on radius {
            enabled: !TelamonStyle.reducedMotion
            TelamonSpringAnimation {}
        }
        Behavior on color {
            ColorAnimation {
                duration: TelamonStyle.durationShort
            }
        }
        // The state layer: the same grey for every variant.
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: !control.enabled || control.busy ? "transparent" : control.down ? TelamonStyle.pressed : control.hovered ? TelamonStyle.hover : "transparent"
            Behavior on color {
                ColorAnimation {
                    duration: TelamonStyle.durationShort
                }
            }
        }
        TelamonFocusRing {
            radius: parent.radius + gap
            shown: control.visualFocus
        }
    }
}
