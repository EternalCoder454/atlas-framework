pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Templates as T
import QtQuick.Dialogs
import org.kde.kirigami as Kirigami

// A colour chooser: a field with a swatch and the colour as hex text (a colour
// with alpha shows as RGBA instead, "rgba(104, 88, 226, 0.5)"). Clicking
// it opens a card with a palette of swatches (the current colour first when it
// is not one of them), a hex field and, with `showMore`, a "More..." button for
// the system colour dialog. The hex field takes #rgb and #rrggbb (and #aarrggbb
// with `showAlpha`; the "#" may be left out) and applies the colour as soon as
// what is typed is complete; "rgb(104, 88, 226)" and "rgba(104, 88, 226, 0.5)"
// are accepted too (alpha 0 to 1; the alpha form needs `showAlpha`). `edited()` is emitted when the user changes the
// colour, not when the app sets it.
//
//   TelamonColorField {
//       color: "#3daee9"
//       onEdited: settings.accent = color
//       Accessible.name: qsTr("Accent color")
//   }
//
// Name it for screen readers with Accessible.name (what the colour is for);
// the hex value is spoken as the description.
T.AbstractButton {
    id: control

    // The colour. Hex text shows #rrggbb, or #aarrggbb when it is not opaque.
    property color color: "#3daee9"
    // Accept and show an alpha channel.
    property bool showAlpha: false
    // The "More..." button that opens the system colour dialog.
    property bool showMore: true

    signal edited

    // A user edit is held by a Binding for one turn, so an app binding on
    // `color` is kept (see docs/reference/telamon-ui/telamon-color-field.md).
    property color _edit: "transparent"
    property bool _editing: false
    readonly property Binding _hold: Binding {
        target: control
        property: "color"
        value: control._edit
        when: control._editing
        restoreMode: Binding.RestoreBinding
    }
    function _release(): void {
        control._editing = false;
    }

    readonly property string hex: internals.toHex(control.color)
    // What the field shows: the hex, or rgba(r, g, b, a) when not opaque.
    readonly property string _label: internals.toLabel(control.color)

    // The colour a typed text stands for, or undefined (for the tests).
    function _parseHex(text: string): var {
        return internals.parse(text);
    }

    QtObject {
        id: internals

        readonly property var palette: ["#da4453", "#f67400", "#fdbc4b", "#27ae60", "#1abc9c", "#3daee9", "#3f51b5", "#9b59b6", "#e93a9a", "#7f8c8d", "#31363b", "#ffffff"]
        readonly property real swatchSize: Math.round(Kirigami.Units.gridUnit * 1.5)
        readonly property real fieldHeight: Math.max(TelamonStyle.controlHeight, Math.ceil(labelMetrics.height) + TelamonStyle.spacing)

        function pad(n: int): string {
            return (n < 16 ? "0" : "") + n.toString(16);
        }
        function toHex(c: color): string {
            const r = pad(Math.round(c.r * 255)) + pad(Math.round(c.g * 255)) + pad(Math.round(c.b * 255));
            const a = Math.round(c.a * 255);
            return "#" + (control.showAlpha && a < 255 ? pad(a) : "") + r;
        }
        function toLabel(c: color): string {
            // 0.999 rounds to 1 in the label, so it is shown as the plain hex.
            if (Math.round(c.a * 100) / 100 >= 1) {
                return toHex(c);
            }
            const alpha = String(Math.round(c.a * 100) / 100);
            return "rgba(" + Math.round(c.r * 255) + ", " + Math.round(c.g * 255) + ", " + Math.round(c.b * 255) + ", " + alpha + ")";
        }
        // The colour a typed text stands for, or undefined when it is not a
        // complete colour. Never throws.
        function parse(text: string): var {
            let t = text.trim();
            if (t.length > 40) {
                return undefined;
            }
            if (t.charAt(0) === "r" || t.charAt(0) === "R") {
                const m = /^rgba?\(\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3})\s*(?:,\s*(\d*\.?\d+|\d+\.)\s*)?\)$/i.exec(t);
                if (!m) {
                    return undefined;
                }
                const a = m[4] === undefined ? 1 : Number(m[4]);
                if (Number(m[1]) > 255 || Number(m[2]) > 255 || Number(m[3]) > 255 || !(a >= 0 && a <= 1) || (a < 1 && !control.showAlpha)) {
                    return undefined;
                }
                return Qt.rgba(Number(m[1]) / 255, Number(m[2]) / 255, Number(m[3]) / 255, a);
            }
            if (t.charAt(0) !== "#") {
                t = "#" + t;
            }
            const digits = t.length - 1;
            if (!/^#[0-9a-fA-F]+$/.test(t) || !(digits === 3 || digits === 6 || (control.showAlpha && digits === 8))) {
                return undefined;
            }
            return Qt.color(t);
        }
        function apply(c: color): void {
            if (control.hex === toHex(c) && control.color.a === c.a) {
                return;
            }
            control._edit = c;
            control._editing = true;
            control.edited();
            Qt.callLater(control._release);
        }
        // The palette, led by the current colour when it is none of them.
        readonly property var swatches: {
            const h = control.hex.toLowerCase();
            const list = palette.slice();
            // Once: a translucent colour whose hex is in the palette adds no second swatch.
            if (list.indexOf(h) < 0) {
                list.unshift(h);
            }
            return list;
        }
    }

    TextMetrics {
        id: labelMetrics
        font.family: TelamonStyle.fontFamily
        font.pointSize: TelamonStyle.fontSizeBody
        text: control._label
    }

    implicitWidth: Math.max(Kirigami.Units.gridUnit * 8, contentItem.implicitWidth + leftPadding + rightPadding)
    implicitHeight: internals.fieldHeight
    leftPadding: TelamonStyle.spacing
    rightPadding: TelamonStyle.spacingLarge
    hoverEnabled: true
    focusPolicy: Qt.StrongFocus

    Accessible.role: Accessible.Button
    //: Spoken name of a colour chooser that has no name of its own
    Accessible.name: qsTr("Color")
    Accessible.description: control.hex

    onClicked: popup.opened ? popup.close() : popup.open()
    Keys.onReturnPressed: event => {
        if (enabled && !event.isAutoRepeat) {
            control.clicked();
        }
    }
    Keys.onEnterPressed: event => {
        if (enabled && !event.isAutoRepeat) {
            control.clicked();
        }
    }

    contentItem: RowLayout {
        spacing: Kirigami.Units.largeSpacing
        Rectangle {
            Layout.preferredWidth: Math.round(Kirigami.Units.gridUnit * 1.3)
            Layout.preferredHeight: Layout.preferredWidth
            radius: width / 2
            color: control.color
            border.width: 1
            border.color: TelamonStyle.alpha(Kirigami.Theme.textColor, 0.3)
        }
        Text {
            Layout.fillWidth: true
            text: control._label
            font.family: TelamonStyle.fontFamily
            font.pointSize: TelamonStyle.fontSizeBody
            color: control.enabled ? Kirigami.Theme.textColor : TelamonStyle.textDisabled
            elide: Text.ElideRight
            textFormat: Text.PlainText
        }
    }

    background: Rectangle {
        radius: TelamonStyle.radiusSmall
        color: control.down || popup.visible ? Qt.tint(TelamonStyle.control, TelamonStyle.pressed) : control.hovered && control.enabled ? Qt.tint(TelamonStyle.control, TelamonStyle.hover) : TelamonStyle.control
        border.width: 1
        border.color: TelamonStyle.controlBorder
        opacity: control.enabled ? 1 : 0.6
        TelamonFocusRing {
            radius: parent.radius + gap
            shown: control.visualFocus
        }
    }

    T.Popup {
        id: popup
        y: control.height + Kirigami.Units.smallSpacing
        x: control.mirrored ? control.width - width : 0
        padding: Kirigami.Units.largeSpacing
        margins: Kirigami.Units.smallSpacing
        modal: false
        closePolicy: T.Popup.CloseOnEscape | T.Popup.CloseOnPressOutsideParent

        onOpened: {
            hexField.text = control.hex;
            hexField._checked = false;
            hexField.forceActiveFocus(Qt.PopupFocusReason);
        }
        property bool _hadFocus: false
        // True when item is the root or a descendant (Item.contains takes a point).
        function _holds(root: Item, item: Item): bool {
            for (let i = item; i; i = i.parent) {
                if (i === root) {
                    return true;
                }
            }
            return false;
        }
        onAboutToHide: _hadFocus = hexField.activeFocus || contentItem.activeFocus
        // After the close is over (a click outside has then reached its
        // target): the focus comes back to the field unless the user put it on
        // something that takes focus. Qt leaves it on the window's root item.
        onClosed: {
            if (popup._hadFocus) {
                popup._hadFocus = false;
                Qt.callLater(popup._giveFocusBack);
            }
        }
        function _giveFocusBack(): void {
            const w = control.Window.window;
            if (!w || popup.visible || !control.visible || !control.enabled) {
                return;
            }
            const item = w.activeFocusItem;
            const chosen = item && !popup._holds(popup.contentItem, item)
                && ((item.focusPolicy ?? 0) !== 0 || item.activeFocusOnTab || item.activeFocusOnPress === true);
            if (!chosen) {
                control.forceActiveFocus(Qt.PopupFocusReason);
            }
        }

        contentItem: ColumnLayout {
            spacing: Kirigami.Units.largeSpacing
            Flow {
                Layout.preferredWidth: Math.round(Kirigami.Units.gridUnit * 14)
                spacing: Kirigami.Units.smallSpacing
                Repeater {
                    model: internals.swatches
                    delegate: T.AbstractButton {
                        id: swatch
                        required property string modelData
                        readonly property bool current: modelData === control.hex.toLowerCase()
                        implicitWidth: internals.swatchSize
                        implicitHeight: internals.swatchSize
                        hoverEnabled: true
                        focusPolicy: Qt.StrongFocus
                        checkable: false
                        Accessible.role: Accessible.RadioButton
                        Accessible.name: modelData
                        Accessible.checked: current
                        onClicked: {
                            internals.apply(Qt.color(modelData));
                            hexField.text = control.hex;
                            popup.close();
                        }
                        Keys.onReturnPressed: clicked()
                        Keys.onEnterPressed: clicked()
                        background: Rectangle {
                            radius: width / 2
                            color: Qt.color(swatch.modelData)
                            border.width: swatch.current || swatch.hovered ? 2 : 1
                            border.color: swatch.current ? TelamonStyle.accent : TelamonStyle.alpha(Kirigami.Theme.textColor, swatch.hovered ? 0.5 : 0.25)
                            TelamonFocusRing {
                                radius: parent.radius + gap
                                shown: swatch.visualFocus
                            }
                        }
                    }
                }
            }
            RowLayout {
                spacing: Kirigami.Units.smallSpacing
                TelamonTextField {
                    id: hexField
                    Layout.fillWidth: true
                    placeholderText: control.showAlpha ? "#aarrggbb, rgba(r, g, b, a)" : "#rrggbb, rgb(r, g, b)"
                    maximumLength: 40
                    inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                    Accessible.name: qsTr("Hex color")
                    onTextEdited: {
                        const c = internals.parse(text);
                        if (c !== undefined) {
                            internals.apply(c);
                        }
                    }
                    onAccepted: popup.close()
                    validator: RegularExpressionValidator {
                        regularExpression: /[#0-9a-fA-FrgbaRGBA(), .]{0,40}/
                    }
                    // The validator only limits the characters; parse() says whether the text is a whole colour.
                    // Shown once the focus has left the field, then live (as for validator errors).
                    property bool _checked: false
                    onActiveFocusChanged: {
                        if (!activeFocus) {
                            _checked = true;
                        }
                    }
                    errorText: _checked && text.length > 0 && internals.parse(text) === undefined ? qsTr("Not a color") : ""
                }
                TextButton {
                    visible: control.showMore
                    text: qsTr("More…")
                    onClicked: {
                        popup.close();
                        if (dialogLoader.item) {
                            (dialogLoader.item as ColorDialog).selectedColor = control.color;
                            (dialogLoader.item as ColorDialog).open();
                        } else {
                            dialogLoader.active = true;
                        }
                    }
                }
            }
        }

        background: Item {
            // Same card as ContextMenu. Soft shadow: faint outlines, no shader, so it also draws with the software renderer.
            Rectangle {
                anchors.fill: parent
                anchors.margins: -1
                anchors.topMargin: 0
                anchors.bottomMargin: -3
                radius: TelamonStyle.radius + 1
                color: TelamonStyle.alpha("black", 0.04)
            }
            Rectangle {
                anchors.fill: parent
                anchors.margins: -2
                anchors.topMargin: -1
                anchors.bottomMargin: -5
                radius: TelamonStyle.radius + 2
                color: TelamonStyle.alpha("black", 0.025)
            }
            Rectangle {
                anchors.fill: parent
                radius: TelamonStyle.radius
                color: TelamonStyle.floatingBackground
                border.width: 1
                border.color: TelamonStyle.separator
            }
        }

        enter: Transition {
            NumberAnimation {
                property: "opacity"
                from: 0
                to: 1
                duration: TelamonStyle.durationShort
            }
        }
        exit: Transition {
            NumberAnimation {
                property: "opacity"
                from: 1
                to: 0
                duration: TelamonStyle.durationShort
            }
        }
    }

    // The system dialog is made on first use, so the field costs nothing before.
    Loader {
        id: dialogLoader
        active: false
        sourceComponent: ColorDialog {
            id: dialog
            parentWindow: control.Window.window
            selectedColor: control.color
            options: control.showAlpha ? ColorDialog.ShowAlphaChannel : 0
            onAccepted: internals.apply(dialog.selectedColor)
        }
        onLoaded: (item as ColorDialog).open()
    }
}
