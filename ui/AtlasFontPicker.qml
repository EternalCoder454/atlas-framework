pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami

// A font chooser: a pill with the family drawn in its own face and the size.
// Clicking it opens a card with a search field, the list of installed families
// (each in its own face, drawn only while visible) and a size spin box. `font`
// is the chosen font (its `family` and `pointSize`); the other parts of `font`
// are left as they are. With `fixedOnly` the list holds monospace families only
// (found a few at a time after the first opening, so the list fills in).
// `edited()` is emitted when the user chooses a family or a size, not when the
// app sets them.
//
//   AtlasFontPicker {
//       font.family: "Noto Sans Mono"
//       font.pointSize: 11
//       fixedOnly: true
//       onEdited: terminal.font = font
//       Accessible.name: qsTr("Terminal font")
//   }
//
// Name it for screen readers with Accessible.name (what the font is for); the
// family and size are spoken as the description.
T.AbstractButton {
    id: control

    // Only monospace families.
    property bool fixedOnly: false

    signal edited

    // The pill never draws the picker's own font at the picked size: it uses
    // the application font for everything but the family name.
    readonly property font _nameFont: Qt.font({
        family: control.font.family,
        pointSize: AtlasStyle.fontSizeBody
    })

    QtObject {
        id: internals

        readonly property real fieldHeight: Math.max(AtlasStyle.controlHeight, Math.ceil(sizeMetrics.height) + AtlasStyle.spacing)
        readonly property var all: Qt.fontFamilies()
        // Families found to be monospace, and how far the scan has got.
        property var fixed: []
        property int scanned: 0
        readonly property bool scanning: control.fixedOnly && scanned < all.length
        property string search: ""
        // The row the keyboard is on.
        property int current: 0
        readonly property var shown: {
            const base = control.fixedOnly ? fixed : all;
            const n = search.trim().toLowerCase();
            return n.length === 0 ? base : base.filter(f => f.toLowerCase().indexOf(n) >= 0);
        }

        function isFixed(family: string): bool {
            narrow.font.family = family;
            wide.font.family = family;
            return narrow.width > 0 && Math.abs(narrow.width - wide.width) < 0.01;
        }
        // Looks at a few families per turn of the event loop so the window stays alive.
        function scanSome(): void {
            const end = Math.min(all.length, scanned + 40);
            const found = fixed.slice();
            for (let i = scanned; i < end; ++i) {
                if (isFixed(all[i])) {
                    found.push(all[i]);
                }
            }
            scanned = end;
            fixed = found;
        }
        function choose(index: int): void {
            if (index < 0 || index >= shown.length) {
                return;
            }
            control.font.family = shown[index];
            control.edited();
        }
    }

    // Two strings of the same number of characters with very different glyph
    // widths: they are as wide as each other only in a monospace face.
    Text {
        id: narrow
        visible: false
        text: "iiiiiiiiii"
        font.pointSize: 12
    }
    Text {
        id: wide
        visible: false
        text: "WWWWWWWWWW"
        font.pointSize: 12
    }
    Timer {
        interval: 0
        repeat: true
        running: internals.scanning && popup.visible
        onTriggered: internals.scanSome()
    }

    TextMetrics {
        id: sizeMetrics
        font.family: AtlasStyle.fontFamily
        font.pointSize: AtlasStyle.fontSizeBody
        text: "0"
    }

    implicitWidth: Math.max(Kirigami.Units.gridUnit * 12, contentItem.implicitWidth + leftPadding + rightPadding)
    implicitHeight: internals.fieldHeight
    leftPadding: AtlasStyle.spacingLarge
    rightPadding: leftPadding
    hoverEnabled: true
    focusPolicy: Qt.StrongFocus

    Accessible.role: Accessible.Button
    //: Spoken name of a font chooser that has no name of its own
    Accessible.name: qsTr("Font")
    Accessible.description: qsTr("%1, %2 pt").arg(control.font.family).arg(Math.round(control.font.pointSize * 10) / 10)

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
        Text {
            Layout.fillWidth: true
            text: control.font.family
            font: control._nameFont
            color: control.enabled ? Kirigami.Theme.textColor : AtlasStyle.textDisabled
            elide: Text.ElideRight
            textFormat: Text.PlainText
        }
        Text {
            text: qsTr("%1 pt").arg(Math.round(control.font.pointSize * 10) / 10)
            font.family: AtlasStyle.fontFamily
            font.pointSize: AtlasStyle.fontSizeBody
            color: control.enabled ? AtlasStyle.textMuted : AtlasStyle.textDisabled
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
        width: Math.max(control.width, Kirigami.Units.gridUnit * 16)
        padding: Kirigami.Units.smallSpacing
        margins: Kirigami.Units.smallSpacing
        modal: false
        closePolicy: T.Popup.CloseOnEscape | T.Popup.CloseOnPressOutsideParent

        onOpened: {
            internals.current = Math.max(0, internals.shown.indexOf(control.font.family));
            familyList.positionViewAtIndex(internals.current, ListView.Contain);
            searchField.forceActiveFocus(Qt.PopupFocusReason);
        }
        property bool _hadFocus: false
        onAboutToHide: _hadFocus = popup.contentItem.activeFocus
        onClosed: {
            searchField.clear();
            internals.search = "";
            const item = control.Window.activeFocusItem;
            if (popup._hadFocus && (!item || popup.contentItem.contains(item))) {
                control.forceActiveFocus(Qt.PopupFocusReason);
            }
            popup._hadFocus = false;
        }

        contentItem: ColumnLayout {
            spacing: Kirigami.Units.smallSpacing
            AtlasTextField {
                id: searchField
                Layout.fillWidth: true
                placeholderText: qsTr("Search fonts")
                clearable: true
                Accessible.name: qsTr("Search fonts")
                onTextChanged: {
                    internals.search = text;
                    internals.current = 0;
                }
                Keys.onDownPressed: event => {
                    internals.current = Math.min(internals.current + 1, internals.shown.length - 1);
                    event.accepted = true;
                }
                Keys.onUpPressed: event => {
                    internals.current = Math.max(internals.current - 1, 0);
                    event.accepted = true;
                }
                Keys.onReturnPressed: event => {
                    internals.choose(internals.current);
                    event.accepted = true;
                }
                Keys.onEnterPressed: event => {
                    internals.choose(internals.current);
                    event.accepted = true;
                }
            }
            ListView {
                id: familyList
                Layout.fillWidth: true
                Layout.preferredHeight: Math.round(Kirigami.Units.gridUnit * 12)
                clip: true
                reuseItems: true
                model: popup.visible ? internals.shown : []
                currentIndex: internals.current
                highlightFollowsCurrentItem: false
                boundsBehavior: Flickable.StopAtBounds
                onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
                delegate: T.ItemDelegate {
                    id: row
                    required property string modelData
                    required property int index
                    width: ListView.view ? ListView.view.width : implicitWidth
                    implicitHeight: Math.round(Kirigami.Units.gridUnit * 1.8)
                    leftPadding: Kirigami.Units.largeSpacing
                    rightPadding: Kirigami.Units.largeSpacing
                    hoverEnabled: true
                    focusPolicy: Qt.NoFocus
                    highlighted: internals.current === index
                    onHoveredChanged: {
                        if (hovered) {
                            internals.current = index;
                        }
                    }
                    onClicked: internals.choose(index)
                    Accessible.role: Accessible.ListItem
                    Accessible.name: modelData
                    background: Rectangle {
                        radius: AtlasStyle.radiusSmall
                        color: row.highlighted ? Qt.alpha(AtlasStyle.accent, row.down ? 0.28 : 0.18) : "transparent"
                    }
                    contentItem: Text {
                        text: row.modelData
                        font.family: row.modelData
                        font.pointSize: AtlasStyle.fontSizeBody
                        color: Kirigami.Theme.textColor
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                        textFormat: Text.PlainText
                    }
                }
                footer: Item {
                    width: familyList.width
                    visible: internals.shown.length === 0
                    height: visible ? Math.round(Kirigami.Units.gridUnit * 1.8) : 0
                    Accessible.role: Accessible.StaticText
                    Accessible.name: internals.scanning ? qsTr("Looking for fonts") : qsTr("No matches")
                    Text {
                        anchors.fill: parent
                        anchors.leftMargin: Kirigami.Units.largeSpacing
                        text: internals.scanning ? qsTr("Looking for fonts…") : qsTr("No matches")
                        font.family: AtlasStyle.fontFamily
                        font.pointSize: AtlasStyle.fontSizeBody
                        color: Qt.alpha(Kirigami.Theme.textColor, 0.5)
                        verticalAlignment: Text.AlignVCenter
                        textFormat: Text.PlainText
                        Accessible.ignored: true
                    }
                }
            }
            RowLayout {
                spacing: Kirigami.Units.largeSpacing
                Text {
                    text: qsTr("Size")
                    font.family: AtlasStyle.fontFamily
                    font.pointSize: AtlasStyle.fontSizeBody
                    color: Kirigami.Theme.textColor
                    textFormat: Text.PlainText
                    Accessible.ignored: true
                }
                AtlasSpinBox {
                    from: 6
                    to: 96
                    editable: true
                    suffix: qsTr(" pt")
                    value: Math.round(control.font.pointSize)
                    Accessible.name: qsTr("Size")
                    onValueModified: {
                        control.font.pointSize = value;
                        control.edited();
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
}
