import QtQuick
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami

// A number field with a minus and a plus button at its ends. `from`, `to`,
// `value`, `stepSize` and `editable` work as in any SpinBox; `prefix` and
// `suffix` ("MB", "%") are drawn beside the number.
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

    QtObject {
        id: internals
        readonly property real buttonSize: Math.round(Kirigami.Units.gridUnit * 1.9)
    }

    implicitWidth: Kirigami.Units.gridUnit * 9
    implicitHeight: internals.buttonSize
    leftPadding: internals.buttonSize
    rightPadding: internals.buttonSize
    editable: false
    inputMethodHints: Qt.ImhFormattedNumbersOnly
    hoverEnabled: true
    focusPolicy: Qt.StrongFocus
    opacity: enabled ? 1 : 0.5

    Accessible.role: Accessible.SpinBox
    //: Spoken name of a number field that has no label of its own (the app sets Accessible.name)
    Accessible.name: qsTr("Number")
    Accessible.description: textFromValue(control.value, control.locale)

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
