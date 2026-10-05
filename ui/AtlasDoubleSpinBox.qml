import QtQuick
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami

// AtlasSpinBox for numbers with decimals: the same field with a minus and a
// plus button, `prefix`, `suffix` and `showButtons`, and the same keys (Up/Down,
// PageUp/PageDown for ten steps, the wheel). `from`, `to`, `value`, `stepSize`
// and `editable` are reals, `decimals` (default 2) says how many digits follow
// the decimal separator. The text is written in the field's locale ("1,5" in
// German); typed text the field cannot read is dropped and the old value comes
// back. Without `prefix` and `suffix` the field also refuses characters that
// cannot be part of a number as they are typed.
//
//   AtlasDoubleSpinBox { from: 0; to: 10; value: 2.5; stepSize: 0.5; decimals: 1; editable: true; suffix: " s"; Accessible.name: qsTr("Delay") }
//
// Name it for screen readers with Accessible.name (what the number is for);
// the value itself is spoken as the description.
T.DoubleSpinBox {
    id: control

    // Text drawn before and after the number.
    property string prefix
    property string suffix
    // False hides the minus and plus buttons.
    property bool showButtons: true

    decimals: 2

    QtObject {
        id: internals
        readonly property real buttonSize: Math.max(AtlasStyle.controlHeight, Math.ceil(metricsFrom.height) + AtlasStyle.spacing)
        readonly property real sidePadding: control.showButtons ? buttonSize : AtlasStyle.spacingLarge
        // The widest text the field can show: the longest of the two ends.
        readonly property real textWidth: Math.max(metricsFrom.advanceWidth, metricsTo.advanceWidth)
    }

    TextMetrics {
        id: metricsFrom
        font.family: AtlasStyle.fontFamily
        font.pointSize: AtlasStyle.fontSizeBody
        text: control.textFromValue(control.from, null)
    }
    TextMetrics {
        id: metricsTo
        font.family: AtlasStyle.fontFamily
        font.pointSize: AtlasStyle.fontSizeBody
        text: control.textFromValue(control.to, null)
    }

    implicitWidth: Math.ceil(Math.max(Kirigami.Units.gridUnit * 5, internals.textWidth + internals.sidePadding * 2 + AtlasStyle.spacingLarge * 2))
    implicitHeight: internals.buttonSize
    leftPadding: internals.sidePadding
    rightPadding: internals.sidePadding
    editable: false
    inputMethodHints: Qt.ImhFormattedNumbersOnly
    // A plain number can be checked while typing; with a prefix or suffix the
    // text has more in it, and valueFromText decides when editing ends.
    validator: (prefix.length > 0 || suffix.length > 0) ? null : numberValidator

    DoubleValidator {
        id: numberValidator
        bottom: Math.min(control.from, control.to)
        top: Math.max(control.from, control.to)
        decimals: control.decimals
        notation: DoubleValidator.StandardNotation
        locale: control.locale.name
    }
    hoverEnabled: true
    focusPolicy: Qt.StrongFocus

    Accessible.role: Accessible.SpinBox
    //: Spoken name of a number field that has no label of its own (the app sets Accessible.name)
    Accessible.name: qsTr("Number")
    Accessible.description: textFromValue(control.value, null)

    // PageUp and PageDown move ten steps at a time.
    Keys.onPressed: event => {
        if (event.key !== Qt.Key_PageUp && event.key !== Qt.Key_PageDown) {
            return;
        }
        // Step through increase()/decrease(), not `value = ...`: an assignment
        // from here would replace an app's binding (`value: settings.x`).
        // Stop at the end so a `wrap` spin box does not jump round.
        const up = event.key === Qt.Key_PageUp;
        for (let i = 0; i < 10; ++i) {
            if (up ? control.value >= Math.max(control.from, control.to) : control.value <= Math.min(control.from, control.to)) {
                break;
            }
            if (up) {
                control.increase();
            } else {
                control.decrease();
            }
        }
        event.accepted = true;
    }

    // No group separators ("1234.50"): the validator would refuse "1,234.50" while editing.
    textFromValue: (value, _) => prefix + control.locale.toString(Number(value), 'f', control.decimals).split(control.locale.groupSeparator).join("") + suffix
    valueFromText: (text, _) => {
        let t = text;
        if (prefix.length > 0 && t.startsWith(prefix)) {
            t = t.slice(prefix.length);
        }
        if (suffix.length > 0 && t.endsWith(suffix)) {
            t = t.slice(0, t.length - suffix.length);
        }
        try {
            const n = Number.fromLocaleString(control.locale, t.trim());
            return isNaN(n) ? control.value : n;
        } catch (e) {
            return control.value;
        }
    }

    contentItem: TextInput {
        text: control.displayText
        font.family: AtlasStyle.fontFamily
        font.pointSize: AtlasStyle.fontSizeBody
        color: control.enabled ? Kirigami.Theme.textColor : AtlasStyle.textDisabled
        selectionColor: AtlasStyle.accent
        selectedTextColor: AtlasStyle.accentText
        horizontalAlignment: Qt.AlignHCenter
        verticalAlignment: Qt.AlignVCenter
        readOnly: !control.editable
        validator: control.validator
        inputMethodHints: control.inputMethodHints
        selectByMouse: control.editable
        clip: true
        Component.onCompleted: activeFocusOnTab = false
        Accessible.role: Accessible.EditableText
        Accessible.name: control.Accessible.name
        Accessible.description: control.Accessible.description
    }

    up.indicator: Item {
        visible: control.showButtons
        x: control.mirrored ? 0 : control.width - width
        width: internals.buttonSize
        height: control.height
        opacity: control.up.indicator.enabled ? 1 : 0.4
        Rectangle {
            anchors.fill: parent
            anchors.margins: AtlasStyle.spacingXSmall
            radius: AtlasStyle.radiusSmall
            color: control.up.pressed ? AtlasStyle.pressed : control.up.hovered ? AtlasStyle.hover : "transparent"
        }
        Rectangle {
            anchors.centerIn: parent
            width: Kirigami.Units.iconSizes.small * 0.6
            height: 2
            radius: 1
            color: Kirigami.Theme.textColor
        }
        Rectangle {
            anchors.centerIn: parent
            width: 2
            height: Kirigami.Units.iconSizes.small * 0.6
            radius: 1
            color: Kirigami.Theme.textColor
        }
    }

    down.indicator: Item {
        visible: control.showButtons
        x: control.mirrored ? control.width - width : 0
        width: internals.buttonSize
        height: control.height
        opacity: control.down.indicator.enabled ? 1 : 0.4
        Rectangle {
            anchors.fill: parent
            anchors.margins: AtlasStyle.spacingXSmall
            radius: AtlasStyle.radiusSmall
            color: control.down.pressed ? AtlasStyle.pressed : control.down.hovered ? AtlasStyle.hover : "transparent"
        }
        Rectangle {
            anchors.centerIn: parent
            width: Kirigami.Units.iconSizes.small * 0.6
            height: 2
            radius: 1
            color: Kirigami.Theme.textColor
        }
    }

    background: Rectangle {
        radius: AtlasStyle.radiusSmall
        color: AtlasStyle.control
        border.width: 1
        border.color: control.activeFocus ? AtlasStyle.focus : AtlasStyle.controlBorder
        opacity: control.enabled ? 1 : 0.6
        AtlasFocusRing {
            radius: parent.radius + gap
            shown: control.visualFocus
        }
    }
}
