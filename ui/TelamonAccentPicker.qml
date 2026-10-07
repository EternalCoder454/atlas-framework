pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami

// A row of round colour swatches, one chosen: the accent colour for an app or
// the desktop. `model` is a list of colours or of objects { color, name };
// `name` is what a screen reader and the tooltip say ("Accent color 3" when a
// swatch has none). `currentIndex` is the chosen swatch, `currentColor` its
// colour (read-only), and `activated(index)` is the user's choice (not a
// change of `currentIndex` from code). A user's choice does not end an app's
// binding on `currentIndex` (see docs/reference/telamon-ui/telamon-accent-picker.md).
//
//   TelamonAccentPicker {
//       model: [{ color: "#3584e4", name: qsTr("Blue") }, { color: "#e5487a", name: qsTr("Pink") }]
//       currentIndex: app.accentIndex
//       onActivated: index => app.accentIndex = index
//       Accessible.name: qsTr("Accent color")
//   }
//
// One Tab stop; Left and Right move the choice (mirrored in right-to-left
// layouts), Home and End jump to the ends. Screen readers get a group of
// radio buttons, the chosen one checked.
T.Control {
    id: control

    property var model: []
    property int currentIndex: 0
    readonly property color currentColor: control._colorAt(control.currentIndex)
    signal activated(int index)

    readonly property int count: control._length(control.model)

    // A list from QML code, or one handed over from C++ (a QVariantList is not
    // always seen as an Array): any object with a whole-number length.
    function _length(m): int {
        return m !== null && m !== undefined && typeof m === "object" && Number.isInteger(m.length) && m.length > 0 ? m.length : 0;
    }
    function _entry(i) {
        return i >= 0 && i < control._length(control.model) ? control.model[i] : undefined;
    }
    // An object with a `color` is { color, name }; anything else is the colour itself.
    function _isObject(m) {
        return m !== null && m !== undefined && typeof m === "object" && m.color !== undefined;
    }
    function _colorAt(i) {
        const m = control._entry(i);
        const c = control._isObject(m) ? m.color : m;
        if (c === undefined || c === null) {
            return Qt.rgba(0, 0, 0, 0);
        }
        try {
            return Qt.color(c);
        } catch (e) {
            // A string that is not a colour: shown as nothing, not as an error.
            return Qt.rgba(0, 0, 0, 0);
        }
    }
    function _name(i) {
        const m = control._entry(i);
        const n = control._isObject(m) && m.name !== undefined && m.name !== null ? String(m.name) : "";
        //: Name of an unnamed colour swatch: %1 is its place in the row, from 1
        return n.length > 0 ? n : qsTr("Accent color %1").arg(i + 1);
    }

    // A user choice is held by a Binding for one turn, so an app binding on
    // `currentIndex` is kept.
    property int _edit: 0
    property bool _editing: false
    readonly property Binding _hold: Binding {
        target: control
        property: "currentIndex"
        value: control._edit
        when: control._editing
        restoreMode: Binding.RestoreBinding
    }
    function _release(): void {
        control._editing = false;
    }
    function _choose(i: int): void {
        if (i < 0 || i >= control.count || i === control.currentIndex) {
            return;
        }
        control._edit = i;
        control._editing = true;
        control.activated(i);
        Qt.callLater(control._release);
    }

    implicitWidth: row.implicitWidth + leftPadding + rightPadding
    implicitHeight: row.implicitHeight + topPadding + bottomPadding
    padding: TelamonStyle.spacingSmall
    hoverEnabled: true
    focusPolicy: Qt.StrongFocus

    Accessible.role: Accessible.Grouping
    //: Name of a row of colour swatches; an app usually sets its own
    Accessible.name: qsTr("Accent color")

    Keys.onPressed: event => {
        const step = control.mirrored ? -1 : 1;
        let target = -1;
        switch (event.key) {
        case Qt.Key_Right:
            target = control.currentIndex + step;
            break;
        case Qt.Key_Left:
            target = control.currentIndex - step;
            break;
        case Qt.Key_Home:
            target = 0;
            break;
        case Qt.Key_End:
            target = control.count - 1;
            break;
        default:
            return;
        }
        event.accepted = true;
        control._choose(Math.max(0, Math.min(control.count - 1, target)));
    }

    contentItem: Row {
        id: row
        spacing: TelamonStyle.spacingLarge
        LayoutMirroring.enabled: control.mirrored
        LayoutMirroring.childrenInherit: true

        Repeater {
            model: control.count
            delegate: Item {
                id: swatch
                required property int index
                readonly property bool selected: swatch.index === control.currentIndex
                readonly property color swatchColor: control._colorAt(swatch.index)
                readonly property real size: Math.round(Kirigami.Units.gridUnit * 1.6)

                implicitWidth: swatch.size
                implicitHeight: swatch.size
                width: swatch.size
                height: swatch.size

                Accessible.role: Accessible.RadioButton
                Accessible.name: control._name(swatch.index)
                Accessible.checkable: true
                Accessible.checked: swatch.selected
                Accessible.onPressAction: control._choose(swatch.index)

                // The colour, with a hairline edge so a pale one shows on a pale window.
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: swatch.swatchColor
                    border.width: 1
                    border.color: TelamonStyle.highContrast ? TelamonStyle.controlBorder : TelamonStyle.alpha(TelamonStyle.text, 0.2)
                    opacity: control.enabled ? 1 : 0.5
                    Accessible.ignored: true
                }
                // The choice: a ring in the text colour just outside the swatch.
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: -TelamonStyle.spacingSmall
                    radius: width / 2
                    color: "transparent"
                    border.width: 2
                    border.color: swatch.selected ? TelamonStyle.text : control.enabled && hover.hovered ? TelamonStyle.alpha(TelamonStyle.text, 0.35) : "transparent"
                    Accessible.ignored: true
                    Behavior on border.color {
                        ColorAnimation {
                            duration: TelamonStyle.durationShort
                        }
                    }
                }
                // The keyboard focus, on the chosen swatch (the one Left and Right move).
                TelamonFocusRing {
                    anchors.margins: -(TelamonStyle.spacingSmall + 2 + gap)
                    radius: width / 2
                    shown: control.visualFocus && swatch.selected
                }
                Kirigami.Icon {
                    anchors.centerIn: parent
                    width: Math.round(swatch.size * 0.55)
                    height: width
                    visible: swatch.selected
                    source: "checkmark"
                    isMask: true
                    // Dark on a light colour, light on a dark one.
                    color: swatch.swatchColor.hslLightness > 0.6 ? Qt.rgba(0, 0, 0, 1) : Qt.rgba(1, 1, 1, 1)
                    Accessible.ignored: true
                }
                HoverHandler {
                    id: hover
                    enabled: control.enabled
                }
                TapHandler {
                    enabled: control.enabled
                    onTapped: {
                        control.forceActiveFocus(Qt.MouseFocusReason);
                        control._choose(swatch.index);
                    }
                }
                TelamonToolTip {
                    text: control._name(swatch.index)
                    shown: hover.hovered
                }
            }
        }
    }
}
