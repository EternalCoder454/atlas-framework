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
        readonly property real buttonSize: Math.max(AtlasStyle.controlHeight, Math.ceil(metricsFrom.height) + AtlasStyle.spacing)
        readonly property real sidePadding: control.showButtons ? buttonSize : AtlasStyle.spacingLarge
        // The widest text the field can show: the longest of the two ends.
        readonly property real textWidth: Math.max(metricsFrom.advanceWidth, metricsTo.advanceWidth)
    }

    TextMetrics {
        id: metricsFrom
        font.family: AtlasStyle.fontFamily
        font.pointSize: AtlasStyle.fontSizeBody
        text: control.textFromValue(control.from, control.locale)
    }
    TextMetrics {
        id: metricsTo
        font.family: AtlasStyle.fontFamily
        font.pointSize: AtlasStyle.fontSizeBody
        text: control.textFromValue(control.to, control.locale)
    }

    implicitWidth: Math.ceil(Math.max(Kirigami.Units.gridUnit * 5, internals.textWidth + internals.sidePadding * 2 + AtlasStyle.spacingLarge * 2))
    implicitHeight: internals.buttonSize
    leftPadding: internals.sidePadding
    rightPadding: internals.sidePadding
    editable: false
    inputMethodHints: Qt.ImhFormattedNumbersOnly
    hoverEnabled: true
    focusPolicy: Qt.StrongFocus

    Accessible.role: Accessible.SpinBox
    //: Spoken name of a number field that has no label of its own (the app sets Accessible.name)
    Accessible.name: qsTr("Number")
    Accessible.description: textFromValue(control.value, control.locale)

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

    // Only the number is checked: the text may be the prefix, digits (with a
    // sign and the locale's separators) and the suffix, so what is typed
    // between them cannot be a letter. Prefix and suffix are both optional (a
    // number typed over a selection has neither), and a part of one still
    // matches, as a partial match. Arabic separators (U+066B, U+066C) and the
    // direction marks (U+061C, U+200E, U+200F) some locales put round a sign
    // are part of a number. Since 1.5.0.
    readonly property var _pattern: {
        const esc = s => s.replace(/[.*+?^${}()|[\]\\\/]/g, "\\$&");
        return new RegExp("^(?:" + esc(prefix) + ")?[\u061c\u200e\u200f]*[-+\u2212]?[0-9\u0660-\u0669\u06f0-\u06f9,.\u066b\u066c\u061c\u200e\u200f\\s\u00a0\u202f'\u2019]*(?:" + esc(suffix) + ")?$");
    }
    validator: RegularExpressionValidator {
        regularExpression: control._pattern
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
        try {
            const n = Number.fromLocaleString(locale, t.replace(/[\u061c\u200e\u200f]/g, "").trim());
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
