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
//   AtlasColorField {
//       color: "#3daee9"
//       onEdited: settings.accent = color
//       Accessible.name: qsTr("Accent colour")
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
        readonly property real fieldHeight: Math.max(AtlasStyle.controlHeight, Math.ceil(labelMetrics.height) + AtlasStyle.spacing)

        function pad(n: int): string {
            return (n < 16 ? "0" : "") + n.toString(16);
        }
        function toHex(c: color): string {
            const r = pad(Math.round(c.r * 255)) + pad(Math.round(c.g * 255)) + pad(Math.round(c.b * 255));
            const a = Math.round(c.a * 255);
            return "#" + (control.showAlpha && a < 255 ? pad(a) : "") + r;
        }
        function toLabel(c: color): string {
            if (c.a >= 1) {
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
            control.color = c;
            control.edited();
        }
        // The palette, led by the current colour when it is none of them.
        readonly property var swatches: {
            const h = control.hex.toLowerCase();
            const list = palette.slice();
            if (control.color.a === 1 && list.indexOf(h) < 0 || control.color.a < 1) {
                list.unshift(h);
            }
            return list;
        }
    }

    TextMetrics {
        id: labelMetrics
        font.family: AtlasStyle.fontFamily
        font.pointSize: AtlasStyle.fontSizeBody
        text: control._label
    }

    implicitWidth: Math.max(Kirigami.Units.gridUnit * 8, contentItem.implicitWidth + leftPadding + rightPadding)
    implicitHeight: internals.fieldHeight
    leftPadding: AtlasStyle.spacing
    rightPadding: AtlasStyle.spacingLarge
    hoverEnabled: true
    focusPolicy: Qt.StrongFocus

    Accessible.role: Accessible.Button
    //: Spoken name of a colour chooser that has no name of its own
    Accessible.name: qsTr("Colour")
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
            border.color: Qt.alpha(Kirigami.Theme.textColor, 0.3)
        }
        Text {
            Layout.fillWidth: true
            text: control._label
            font.family: AtlasStyle.fontFamily
            font.pointSize: AtlasStyle.fontSizeBody
            color: control.enabled ? Kirigami.Theme.textColor : AtlasStyle.textDisabled
            elide: Text.ElideRight
            textFormat: Text.PlainText
        }
    }

    background: Rectangle {
        radius: AtlasStyle.radiusSmall
        color: control.down || popup.visible ? Qt.tint(AtlasStyle.control, AtlasStyle.pressed) : control.hovered && control.enabled ? Qt.tint(AtlasStyle.control, AtlasStyle.hover) : AtlasStyle.control
        border.width: 1
        border.color: AtlasStyle.controlBorder
        opacity: control.enabled ? 1 : 0.6
        AtlasFocusRing {
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
        onAboutToHide: _hadFocus = hexField.activeFocus || contentItem.activeFocus
        onClosed: {
            const item = control.Window.activeFocusItem;
            if (popup._hadFocus && (!item || popup.contentItem.contains(item))) {
                control.forceActiveFocus(Qt.PopupFocusReason);
            }
            popup._hadFocus = false;
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
                            border.color: swatch.current ? AtlasStyle.accent : Qt.alpha(Kirigami.Theme.textColor, swatch.hovered ? 0.5 : 0.25)
                            AtlasFocusRing {
                                radius: parent.radius + gap
                                shown: swatch.visualFocus
                            }
                        }
                    }
                }
            }
            RowLayout {
                spacing: Kirigami.Units.smallSpacing
                AtlasTextField {
                    id: hexField
                    Layout.fillWidth: true
                    placeholderText: control.showAlpha ? "#aarrggbb, rgba(r, g, b, a)" : "#rrggbb, rgb(r, g, b)"
                    maximumLength: 40
                    inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                    Accessible.name: qsTr("Hex colour")
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
                    errorText: _checked && text.length > 0 && internals.parse(text) === undefined ? qsTr("Not a colour") : ""
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
                radius: AtlasStyle.radius + 1
                color: Qt.alpha("black", 0.04)
            }
            Rectangle {
                anchors.fill: parent
                anchors.margins: -2
                anchors.topMargin: -1
                anchors.bottomMargin: -5
                radius: AtlasStyle.radius + 2
                color: Qt.alpha("black", 0.025)
            }
            Rectangle {
                anchors.fill: parent
                radius: AtlasStyle.radius
                color: AtlasStyle.floatingBackground
                border.width: 1
                border.color: AtlasStyle.separator
            }
        }

        enter: Transition {
            NumberAnimation {
                property: "opacity"
                from: 0
                to: 1
                duration: AtlasStyle.durationShort
            }
        }
        exit: Transition {
            NumberAnimation {
                property: "opacity"
                from: 1
                to: 0
                duration: AtlasStyle.durationShort
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
