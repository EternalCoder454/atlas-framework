pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Templates as T
import QtQuick.Dialogs
import org.kde.kirigami as Kirigami

// A colour chooser: a pill with a swatch and the colour as hex text. Clicking
// it opens a card with a palette of swatches (the current colour first when it
// is not one of them), a hex field and, with `showMore`, a "More..." button for
// the system colour dialog. The hex field takes #rgb and #rrggbb (and #aarrggbb
// with `showAlpha`; the "#" may be left out) and applies the colour as soon as
// what is typed is complete. `edited()` is emitted when the user changes the
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

    // The colour a typed text stands for, or undefined (for the tests).
    function _parseHex(text: string): var {
        return internals.parse(text);
    }

    QtObject {
        id: internals

        readonly property var palette: ["#da4453", "#f67400", "#fdbc4b", "#27ae60", "#1abc9c", "#3daee9", "#3f51b5", "#9b59b6", "#e93a9a", "#7f8c8d", "#31363b", "#ffffff"]
        readonly property real swatchSize: Math.round(Kirigami.Units.gridUnit * 1.5)
        readonly property real fieldHeight: Math.round(Kirigami.Units.gridUnit * 1.9)

        function pad(n: int): string {
            return (n < 16 ? "0" : "") + n.toString(16);
        }
        function toHex(c: color): string {
            const r = pad(Math.round(c.r * 255)) + pad(Math.round(c.g * 255)) + pad(Math.round(c.b * 255));
            const a = Math.round(c.a * 255);
            return "#" + (control.showAlpha && a < 255 ? pad(a) : "") + r;
        }
        // The colour a typed text stands for, or undefined when it is not a
        // complete colour. Never throws.
        function parse(text: string): var {
            let t = text.trim();
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

    implicitWidth: Math.max(Kirigami.Units.gridUnit * 8, contentItem.implicitWidth + leftPadding + rightPadding)
    implicitHeight: internals.fieldHeight
    leftPadding: Kirigami.Units.smallSpacing + 2
    rightPadding: Kirigami.Units.largeSpacing + Kirigami.Units.smallSpacing
    hoverEnabled: true
    focusPolicy: Qt.StrongFocus
    opacity: enabled ? 1 : 0.5

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
            text: control.hex
            font: Kirigami.Theme.defaultFont
            color: Kirigami.Theme.textColor
            elide: Text.ElideRight
            textFormat: Text.PlainText
        }
    }

    background: Rectangle {
        radius: height / 2
        color: Qt.alpha(Kirigami.Theme.textColor, control.down || popup.visible ? 0.14 : control.hovered ? 0.12 : 0.07)
        border.width: 1
        border.color: Qt.alpha(Kirigami.Theme.textColor, 0.14)
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
            hexField.forceActiveFocus(Qt.PopupFocusReason);
        }
        onClosed: control.forceActiveFocus(Qt.PopupFocusReason)

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
                    placeholderText: control.showAlpha ? "#aarrggbb" : "#rrggbb"
                    maximumLength: 9
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
                        regularExpression: /#?[0-9a-fA-F]{0,8}/
                    }
                    // The validator only limits the characters; parse() says whether the text is a whole colour.
                    errorText: text.length > 0 && internals.parse(text) === undefined && activeFocus ? qsTr("Not a colour") : ""
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

        background: Rectangle {
            radius: AtlasStyle.radiusLarge
            color: Kirigami.Theme.backgroundColor.hslLightness > 0.5 ? Qt.lighter(Kirigami.Theme.backgroundColor, 1.5) : Qt.tint(Kirigami.Theme.backgroundColor, Qt.rgba(1, 1, 1, 0.08))
            border.width: 1
            border.color: Qt.alpha(Kirigami.Theme.textColor, 0.16)
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
