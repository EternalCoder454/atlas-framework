pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami

// A rounded drop-down list: the current choice on a pill with a chevron, the
// choices in a raised card like ContextMenu's. `model`, `textRole`,
// `currentIndex` and `onActivated` work as in any ComboBox; `placeholderText`
// shows while nothing is chosen (currentIndex -1). With `filterable: true`
// the list opens with a filter field on top: typing narrows the choices (any
// part of the text, any case), Up and Down move among the ones left, Return
// chooses, and the filter clears when the list closes.
//
//   AtlasComboBox {
//       model: [qsTr("Light"), qsTr("Dark"), qsTr("Automatic")]
//       currentIndex: 2
//       onActivated: index => settings.theme = index
//   }
T.ComboBox {
    id: control

    property string placeholderText
    // A filter field at the top of the list; for long lists.
    property bool filterable: false

    QtObject {
        id: internals
        // What the filter field holds.
        property string filter: ""
        // The row the keyboard is on (filterable lists only); -1 for none.
        property int current: -1
        // Whether each row passes the filter, by index.
        readonly property var flags: {
            const out = [];
            const needle = internals.filter.toLowerCase();
            for (let i = 0; i < control.count; ++i) {
                out.push(!control.filterable || needle.length === 0 || control.textAt(i).toLowerCase().indexOf(needle) >= 0);
            }
            return out;
        }
        readonly property int matchCount: flags.filter(f => f).length

        function step(from: int, dir: int): int {
            for (let i = from + dir; i >= 0 && i < flags.length; i += dir) {
                if (flags[i]) {
                    return i;
                }
            }
            return from;
        }
        function first(): int {
            return flags.indexOf(true);
        }
        function choose(index: int): void {
            if (index < 0 || index >= control.count) {
                return;
            }
            control.currentIndex = index;
            control.activated(index);
            control.popup.close();
        }
    }

    implicitWidth: Kirigami.Units.gridUnit * 12
    implicitHeight: Math.round(Kirigami.Units.gridUnit * 1.9)
    leftPadding: AtlasStyle.spacingLarge + AtlasStyle.spacingSmall
    rightPadding: AtlasStyle.spacingLarge + AtlasStyle.spacingSmall
    hoverEnabled: true
    focusPolicy: Qt.StrongFocus
    opacity: enabled ? 1 : 0.5

    Accessible.role: Accessible.ComboBox
    Accessible.name: control.displayText.length > 0 ? control.displayText : control.placeholderText
    Accessible.description: control.placeholderText

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Down && (event.modifiers & Qt.AltModifier) && !popup.visible) {
            popup.open();
            event.accepted = true;
        }
    }

    delegate: T.ItemDelegate {
        id: row

        required property var model
        required property int index

        width: ListView.view ? ListView.view.width : implicitWidth
        implicitHeight: visible ? Math.round(Kirigami.Units.gridUnit * 1.8) : 0
        height: implicitHeight
        leftPadding: AtlasStyle.spacingLarge
        rightPadding: AtlasStyle.spacingLarge
        hoverEnabled: true
        visible: internals.flags[index] !== false
        highlighted: control.filterable ? internals.current === index : control.highlightedIndex === index
        onHoveredChanged: {
            if (hovered && control.filterable) {
                internals.current = index;
            }
        }
        text: control.textRole.length === 0 ? row.model.modelData : Array.isArray(control.model) ? row.model.modelData[control.textRole] : row.model[control.textRole]

        Accessible.name: text

        background: Item {
        // Soft shadow: faint outlines, no shader, so it also draws with the software renderer.
        Rectangle {
            anchors.fill: parent
            anchors.margins: -1
            anchors.topMargin: 0
            anchors.bottomMargin: -3
            radius: AtlasStyle.radiusLarge + 1
            color: Qt.alpha("black", 0.04)
        }
        Rectangle {
            anchors.fill: parent
            anchors.margins: -2
            anchors.topMargin: -1
            anchors.bottomMargin: -5
            radius: AtlasStyle.radiusLarge + 2
            color: Qt.alpha("black", 0.025)
        }
            Rectangle {
                anchors.fill: parent
                radius: AtlasStyle.radiusSmall
                color: row.highlighted ? Qt.alpha(Kirigami.Theme.highlightColor, row.down ? 0.28 : 0.18) : "transparent"
            }
        }
        contentItem: Row {
            spacing: AtlasStyle.spacingLarge
            Item {
                anchors.verticalCenter: parent.verticalCenter
                width: Kirigami.Units.iconSizes.small
                height: width
                // Only the chosen row makes the symbol.
                Loader {
                    anchors.centerIn: parent
                    active: control.currentIndex === row.index
                    sourceComponent: Symbol {
                        name: "check"
                        weight: 600
                        size: Kirigami.Units.iconSizes.small
                        color: Kirigami.Theme.textColor
                    }
                }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: row.availableWidth - Kirigami.Units.iconSizes.small - parent.spacing
                text: row.text
                font: Kirigami.Theme.defaultFont
                color: Kirigami.Theme.textColor
                elide: Text.ElideRight
                textFormat: Text.PlainText
            }
        }
    }

    indicator: Kirigami.Icon {
        x: control.mirrored ? control.leftPadding : control.width - width - control.rightPadding
        y: Math.round((control.height - height) / 2)
        width: Kirigami.Units.iconSizes.small
        height: width
        source: "arrow-down"
        isMask: true
        color: Kirigami.Theme.textColor
        opacity: 0.6
    }

    contentItem: Text {
        leftPadding: control.mirrored ? control.indicator.width + AtlasStyle.spacingSmall : 0
        rightPadding: control.mirrored ? 0 : control.indicator.width + AtlasStyle.spacingSmall
        text: control.displayText.length > 0 ? control.displayText : control.placeholderText
        font: Kirigami.Theme.defaultFont
        color: control.displayText.length > 0 ? Kirigami.Theme.textColor : Qt.alpha(Kirigami.Theme.textColor, 0.5)
        verticalAlignment: Text.AlignVCenter
        horizontalAlignment: control.mirrored ? Text.AlignRight : Text.AlignLeft
        elide: Text.ElideRight
        textFormat: Text.PlainText
    }

    background: Rectangle {
        radius: AtlasStyle.radiusPill
        color: Qt.alpha(Kirigami.Theme.textColor, control.down || control.popup.visible ? 0.14 : control.hovered ? 0.12 : 0.07)
        border.width: 1
        border.color: Qt.alpha(Kirigami.Theme.textColor, 0.14)
        Behavior on color {
            ColorAnimation {
                duration: AtlasStyle.durationShort
            }
        }
        AtlasFocusRing {
            radius: parent.radius + gap
            shown: control.visualFocus
        }
    }

    popup: T.Popup {
        y: control.height + AtlasStyle.spacingSmall
        width: control.width
        implicitHeight: Math.min(contentItem.implicitHeight + topPadding + bottomPadding, Kirigami.Units.gridUnit * 16)
        padding: AtlasStyle.spacingSmall
        margins: AtlasStyle.spacingSmall
        modal: false
        closePolicy: T.Popup.CloseOnEscape | T.Popup.CloseOnPressOutsideParent

        onOpened: {
            if (control.filterable) {
                internals.current = control.currentIndex >= 0 && internals.flags[control.currentIndex] ? control.currentIndex : internals.first();
                filterField.forceActiveFocus(Qt.PopupFocusReason);
            }
        }
        onAboutToHide: filterField.hadFocus = filterField.activeFocus
        onClosed: {
            if (control.filterable) {
                filterField.clear();
                internals.filter = "";
                internals.current = -1;
                if (filterField.hadFocus) {
                    control.forceActiveFocus(Qt.PopupFocusReason);
                }
            }
        }

        contentItem: ColumnLayout {
            spacing: AtlasStyle.spacingSmall
            AtlasTextField {
                id: filterField
                property bool hadFocus: false
                Layout.fillWidth: true
                visible: control.filterable
                placeholderText: qsTr("Filter")
                clearable: true
                Accessible.name: qsTr("Filter")
                onTextChanged: {
                    internals.filter = text;
                    internals.current = internals.first();
                }
                Keys.onDownPressed: event => {
                    internals.current = internals.step(internals.current, 1);
                    event.accepted = true;
                }
                Keys.onUpPressed: event => {
                    internals.current = internals.step(internals.current, -1);
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
                id: choices
                Layout.fillWidth: true
                Layout.fillHeight: true
                implicitHeight: contentHeight
                model: control.popup.visible ? control.delegateModel : null
                currentIndex: control.filterable ? internals.current : control.highlightedIndex
                clip: true
                keyNavigationEnabled: true
                // An empty model, or a filter nothing passes, opens a single
                // disabled row, not an empty card.
                footer: Item {
                    id: emptyRow
                    readonly property bool noChoices: choices.count === 0
                    width: choices.width
                    visible: noChoices || (control.filterable && internals.matchCount === 0)
                    height: visible ? Math.round(Kirigami.Units.gridUnit * 1.8) : 0
                    Accessible.role: Accessible.StaticText
                    //: Shown in a drop-down list that has no choices
                    Accessible.name: noChoices ? qsTr("No choices") : qsTr("No matches")
                    Text {
                        anchors.fill: parent
                        anchors.leftMargin: AtlasStyle.spacingLarge
                        anchors.rightMargin: AtlasStyle.spacingLarge
                        //: Shown in a drop-down list when what was typed in its filter matches no choice
                        text: emptyRow.noChoices ? qsTr("No choices") : qsTr("No matches")
                        font: Kirigami.Theme.defaultFont
                        color: Qt.alpha(Kirigami.Theme.textColor, 0.5)
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                        textFormat: Text.PlainText
                        Accessible.ignored: true
                    }
                }
            }
        }

        background: Rectangle {
            radius: AtlasStyle.radiusLarge
            readonly property color _solid: Kirigami.Theme.backgroundColor.hslLightness > 0.5 ? Qt.lighter(Kirigami.Theme.backgroundColor, 1.5) : Qt.tint(Kirigami.Theme.backgroundColor, Qt.rgba(1, 1, 1, 0.08))
            color: Appearance.effective ? Qt.alpha(_solid, 0.85) : _solid
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
