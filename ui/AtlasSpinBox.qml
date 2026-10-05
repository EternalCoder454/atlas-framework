import QtQuick
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami

// A number field with a minus and a plus button at its ends. `from`, `to`,
// `value`, `stepSize` and `editable` work as in any SpinBox; `prefix` and
// `suffix` ("MB", "%") are drawn beside the number. The default width fits the
// widest value between `from` and `to`. With `showButtons: false` it is a plain
// number field; Up/Down, PageUp/PageDown (ten steps) and the wheel work either way.
//
//   AtlasSpinBox { from: 1; to: 64; value: 8; editable: true; suffix: " GB"; Accessible.name: qsTr("Memory") }
//
// Name it for screen readers with Accessible.name (what the number is for);
// the value itself is spoken as the description.
T.SpinBox {
    id: control

    // Text drawn before and after the number.
    property string prefix
    property string suffix
    // False hides the minus and plus buttons.
    property bool showButtons: true

    QtObject {
        id: internals
        readonly property real buttonSize: Math.round(Kirigami.Units.gridUnit * 1.9)
        readonly property real sidePadding: control.showButtons ? buttonSize : Kirigami.Units.largeSpacing + Kirigami.Units.smallSpacing
        // The widest text the field can show: the longest of the two ends.
        readonly property real textWidth: Math.max(metricsFrom.advanceWidth, metricsTo.advanceWidth)
    }

    TextMetrics {
        id: metricsFrom
        font: Kirigami.Theme.defaultFont
        text: control.textFromValue(control.from, control.locale)
    }
    TextMetrics {
        id: metricsTo
        font: Kirigami.Theme.defaultFont
        text: control.textFromValue(control.to, control.locale)
    }

    implicitWidth: Math.ceil(Math.max(Kirigami.Units.gridUnit * 5, internals.textWidth + internals.sidePadding * 2 + Kirigami.Units.largeSpacing * 2))
    implicitHeight: internals.buttonSize
    leftPadding: internals.sidePadding
    rightPadding: internals.sidePadding
    editable: false
    inputMethodHints: Qt.ImhFormattedNumbersOnly
    hoverEnabled: true
    focusPolicy: Qt.StrongFocus
    opacity: enabled ? 1 : 0.5

    Accessible.role: Accessible.SpinBox
    //: Spoken name of a number field that has no label of its own (the app sets Accessible.name)
    Accessible.name: qsTr("Number")
    Accessible.description: textFromValue(control.value, control.locale)

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

    textFromValue: (value, locale) => prefix + Number(value).toLocaleString(locale, 'f', 0) + suffix
    valueFromText: (text, locale) => {
        let t = text;
        if (prefix.length > 0 && t.startsWith(prefix)) {
            t = t.slice(prefix.length);
        }
        if (suffix.length > 0 && t.endsWith(suffix)) {
            t = t.slice(0, t.length - suffix.length);
        }
        const n = Number.fromLocaleString(locale, t.trim());
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
            radius: height / 2
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
            radius: height / 2
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
        radius: height / 2
        color: Qt.alpha(Kirigami.Theme.textColor, 0.06)
        border.width: control.activeFocus ? 2 : 1
        border.color: control.activeFocus ? Qt.alpha(Kirigami.Theme.highlightColor, 0.7) : Qt.alpha(Kirigami.Theme.textColor, 0.1)
        AtlasFocusRing {
            radius: parent.radius + gap
            shown: control.visualFocus
        }
    }
}
