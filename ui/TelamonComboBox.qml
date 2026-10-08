pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQml.Models
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami

// A drop-down list: the current choice in a field with a chevron, the
// choices in a raised card like ContextMenu's. `model`, `textRole`,
// `currentIndex` and `onActivated` work as in any ComboBox; `placeholderText`
// shows while nothing is chosen (currentIndex -1). With `filterable: true`
// the list opens with a filter field on top: typing narrows the choices (any
// part of the text, any case), Up and Down move among the ones left, Return
// chooses, and the filter clears when the list closes.
//
//   TelamonComboBox {
//       model: [qsTr("Light"), qsTr("Dark"), qsTr("Automatic")]
//       currentIndex: 2
//       onActivated: index => settings.theme = index
//   }
T.ComboBox {
    id: control

    property string placeholderText
    // A filter field at the top of the list; for long lists.
    property bool filterable: false

    // The user's choice, held on `currentIndex` for one turn so an app binding survives it.
    property int _edit: -1
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
    // Any choice, also the template's own (a click or the arrow keys on a
    // list that is not filterable), is held for one turn after the app's
    // handler has run.
    onActivated: index => {
        control._edit = index;
        control._editing = true;
        Qt.callLater(control._release);
    }

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
                out.push(!control.filterable || needle.length === 0 || String(control.textAt(i) ?? "").toLowerCase().indexOf(needle) >= 0);
            }
            return out;
        }
        readonly property int matchCount: flags.filter(f => f).length
        // The indexes of the rows that pass the filter.
        readonly property var rows: {
            const out = [];
            for (let i = 0; i < flags.length; ++i) {
                if (flags[i]) {
                    out.push(i);
                }
            }
            return out;
        }

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
            // Held, not written: the app's `currentIndex: x` binding survives.
            control._edit = index;
            control._editing = true;
            control.activated(index);
            control.popup.close();
        }
    }

    implicitWidth: Kirigami.Units.gridUnit * 12
    implicitHeight: Math.max(TelamonStyle.controlHeight, Math.ceil(contentItem.implicitHeight) + TelamonStyle.spacing)
    leftPadding: TelamonStyle.spacingLarge
    rightPadding: TelamonStyle.spacingLarge
    hoverEnabled: true
    focusPolicy: Qt.StrongFocus

    Accessible.role: Accessible.ComboBox
    Accessible.name: control.displayText.length > 0 ? control.displayText : control.placeholderText
    Accessible.description: control.placeholderText

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Down && (event.modifiers & Qt.AltModifier) && !popup.visible) {
            popup.open();
            event.accepted = true;
        }
    }

    component ChoiceRow: T.ItemDelegate {
        id: row

        // The index in the combo box's model (not the row in a filtered list).
        required property int comboIndex

        width: ListView.view ? ListView.view.width : implicitWidth
        implicitHeight: Math.round(Kirigami.Units.gridUnit * 1.8)
        height: implicitHeight
        leftPadding: TelamonStyle.spacingLarge
        rightPadding: TelamonStyle.spacingLarge
        hoverEnabled: true
        highlighted: control.filterable ? internals.current === comboIndex : control.highlightedIndex === comboIndex
        onHoveredChanged: {
            if (hovered && control.filterable) {
                internals.current = comboIndex;
            }
        }
        Accessible.name: text

        background: Rectangle {
            radius: TelamonStyle.radiusSmall
            color: row.highlighted ? TelamonStyle.alpha(TelamonStyle.accent, row.down ? 0.28 : 0.18) : "transparent"
        }
        contentItem: Row {
            spacing: TelamonStyle.spacingLarge
            Item {
                anchors.verticalCenter: parent.verticalCenter
                width: Kirigami.Units.iconSizes.small
                height: width
                // Only the chosen row makes the symbol.
                Loader {
                    anchors.centerIn: parent
                    active: control.currentIndex === row.comboIndex
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
                font.family: TelamonStyle.fontFamily
                font.pointSize: TelamonStyle.fontSizeBody
                color: Kirigami.Theme.textColor
                elide: Text.ElideRight
                textFormat: Text.PlainText
            }
        }
    }

    // The delegate of the template's own list (not filterable): `index` is the model's.
    delegate: ChoiceRow {
        required property var model
        required property int index
        comboIndex: index
        // A null entry or a missing role shows an empty row, not a TypeError.
        text: {
            const value = control.textRole.length === 0 ? model.modelData : Array.isArray(control.model) ? model.modelData?.[control.textRole] : model[control.textRole];
            return value === undefined || value === null ? "" : String(value);
        }
    }
    // A filterable list shows only the matching rows: its model is the list of their
    // indexes, so a model of ten thousand rows builds the few that are on screen.
    Component {
        id: filteredChoice
        ChoiceRow {
            required property int modelData
            comboIndex: modelData
            text: String(control.textAt(modelData) ?? "")
            onClicked: internals.choose(modelData)
        }
    }
    // The list's model in both modes is an instance model (this one, or the
    // template's delegateModel), so the list never has a `delegate` of its own
    // set or cleared: setting one on a view that holds an instance model would
    // replace that model.
    DelegateModel {
        id: filteredRows
        model: control.filterable ? internals.rows : []
        delegate: filteredChoice
    }

    indicator: TelamonIcon {
        x: control.mirrored ? control.leftPadding : control.width - width - control.rightPadding
        y: Math.round((control.height - height) / 2)
        width: Kirigami.Units.iconSizes.small
        height: width
        source: "arrow-down"
        isMask: true
        color: control.enabled ? TelamonStyle.textMuted : TelamonStyle.textDisabled
    }

    contentItem: Text {
        leftPadding: control.mirrored ? control.indicator.width + TelamonStyle.spacingSmall : 0
        rightPadding: control.mirrored ? 0 : control.indicator.width + TelamonStyle.spacingSmall
        text: control.displayText.length > 0 ? control.displayText : control.placeholderText
        font.family: TelamonStyle.fontFamily
        font.pointSize: TelamonStyle.fontSizeBody
        color: !control.enabled ? TelamonStyle.textDisabled : control.displayText.length > 0 ? Kirigami.Theme.textColor : TelamonStyle.textMuted
        verticalAlignment: Text.AlignVCenter
        horizontalAlignment: control.mirrored ? Text.AlignRight : Text.AlignLeft
        elide: Text.ElideRight
        textFormat: Text.PlainText
    }

    background: Rectangle {
        radius: TelamonStyle.radiusSmall
        color: control.down || control.popup.visible ? Qt.tint(TelamonStyle.control, TelamonStyle.pressed) : control.hovered && control.enabled ? Qt.tint(TelamonStyle.control, TelamonStyle.hover) : TelamonStyle.control
        border.width: 1
        border.color: TelamonStyle.controlBorder
        opacity: control.enabled ? 1 : 0.6
        Behavior on color {
            ColorAnimation {
                duration: TelamonStyle.durationShort
            }
        }
        TelamonFocusRing {
            radius: parent.radius + gap
            shown: control.visualFocus
        }
    }

    popup: T.Popup {
        y: control.height + TelamonStyle.spacingSmall
        width: control.width
        implicitHeight: Math.min(contentItem.implicitHeight + topPadding + bottomPadding, Kirigami.Units.gridUnit * 16)
        padding: TelamonStyle.spacingSmall
        margins: TelamonStyle.spacingSmall
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
            spacing: TelamonStyle.spacingSmall
            TelamonTextField {
                id: filterField
                objectName: "filterField"
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
                objectName: "choices"
                Layout.fillWidth: true
                Layout.fillHeight: true
                implicitHeight: contentHeight
                model: !control.popup.visible ? null : control.filterable ? filteredRows : control.delegateModel
                currentIndex: control.filterable ? internals.rows.indexOf(internals.current) : control.highlightedIndex
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
                        anchors.leftMargin: TelamonStyle.spacingLarge
                        anchors.rightMargin: TelamonStyle.spacingLarge
                        //: Shown in a drop-down list when what was typed in its filter matches no choice
                        text: emptyRow.noChoices ? qsTr("No choices") : qsTr("No matches")
                        font.family: TelamonStyle.fontFamily
                        font.pointSize: TelamonStyle.fontSizeBody
                        color: TelamonStyle.alpha(Kirigami.Theme.textColor, 0.5)
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                        textFormat: Text.PlainText
                        Accessible.ignored: true
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
}
