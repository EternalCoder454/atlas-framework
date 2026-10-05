import QtQuick
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami

// AtlasSpinBox for numbers with decimals: the same pill with a minus and a
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
        readonly property real buttonSize: Math.round(Kirigami.Units.gridUnit * 1.9)
        readonly property real sidePadding: control.showButtons ? buttonSize : AtlasStyle.spacingLarge + AtlasStyle.spacingSmall
        // The widest text the field can show: the longest of the two ends.
        readonly property real textWidth: Math.max(metricsFrom.advanceWidth, metricsTo.advanceWidth)
    }

    TextMetrics {
        id: metricsFrom
        font: Kirigami.Theme.defaultFont
        text: control.textFromValue(control.from, null)
    }
    TextMetrics {
        id: metricsTo
        font: Kirigami.Theme.defaultFont
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
    opacity: enabled ? 1 : 0.5

    Accessible.role: Accessible.SpinBox
    //: Spoken name of a number field that has no label of its own (the app sets Accessible.name)
    Accessible.name: qsTr("Number")
    Accessible.description: textFromValue(control.value, null)

    // PageUp and PageDown move ten steps at a time.
    Keys.onPressed: event => {
        if (event.key !== Qt.Key_PageUp && event.key !== Qt.Key_PageDown) {
            return;
        }
        const target = control.value + (event.key === Qt.Key_PageUp ? 1 : -1) * 10 * control.stepSize;
        const clamped = Math.max(Math.min(control.from, control.to), Math.min(Math.max(control.from, control.to), target));
        if (clamped !== control.value) {
            control.value = clamped;
            control.valueModified();
        }
        event.accepted = true;
    }

    textFromValue: (value, _) => prefix + control.locale.toString(Number(value), 'f', control.decimals) + suffix
    valueFromText: (text, _) => {
        let t = text;
        if (prefix.length > 0 && t.startsWith(prefix)) {
            t = t.slice(prefix.length);
        }
        if (suffix.length > 0 && t.endsWith(suffix)) {
            t = t.slice(0, t.length - suffix.length);
        }
        const n = Number.fromLocaleString(control.locale, t.trim());
        return isNaN(n) ? control.value : n;
    }

    contentItem: TextInput {
        text: control.displayText
        font: Kirigami.Theme.defaultFont
        color: Kirigami.Theme.textColor
        selectionColor: Kirigami.Theme.highlightColor
        selectedTextColor: Kirigami.Theme.highlightedTextColor
        horizontalAlignment: Qt.AlignHCenter
        verticalAlignment: Qt.AlignVCenter
        readOnly: !control.editable
        validator: control.validator
        inputMethodHints: control.inputMethodHints
        selectByMouse: control.editable
        clip: true
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
            anchors.margins: 3
            radius: AtlasStyle.radiusPill
            color: Qt.alpha(Kirigami.Theme.textColor, control.up.pressed ? 0.2 : control.up.hovered ? 0.12 : 0)
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
            anchors.margins: 3
            radius: AtlasStyle.radiusPill
            color: Qt.alpha(Kirigami.Theme.textColor, control.down.pressed ? 0.2 : control.down.hovered ? 0.12 : 0)
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
        radius: AtlasStyle.radiusPill
        color: Qt.alpha(Kirigami.Theme.textColor, 0.06)
        border.width: control.activeFocus ? 2 : 1
        border.color: control.activeFocus ? Qt.alpha(Kirigami.Theme.highlightColor, 0.7) : Qt.alpha(Kirigami.Theme.textColor, 0.1)
        AtlasFocusRing {
            radius: parent.radius + gap
            shown: control.visualFocus
        }
    }
}
