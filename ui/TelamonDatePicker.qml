import QtQuick
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami

// A date field: a field like TelamonComboBox that shows the chosen date and opens
// a TelamonCalendar in a raised card. An invalid Date (new Date(NaN)) means "no
// date": the field shows `placeholderText`. Choosing a day sets `selectedDate`,
// emits `edited` and closes the card; Escape closes it too, and focus returns
// to the field. Alt+Down, Return or Space on the field open the card.
//
//   TelamonDatePicker {
//       selectedDate: new Date(2026, 2, 15)
//       minimumDate: new Date(2026, 0, 1)
//       clearable: true
//       onEdited: task.due = selectedDate
//   }
//
// Name it for screen readers with Accessible.name (what the date is for); the
// date itself is spoken as the description.
T.Control {
    id: control

    // The chosen day; invalid for none.
    property date selectedDate
    // The earliest and latest day that can be chosen; invalid for no limit.
    property date minimumDate
    property date maximumDate
    // How the date reads on the field: a Locale format, or a format string.
    property var format: Locale.ShortFormat
    property string placeholderText: qsTr("Pick a date")
    // A clear button on the field (and Delete or Backspace) while a date is set.
    property bool clearable: false
    // The day that is ringed in the calendar (default: the current day).
    property date today: new Date()
    readonly property bool opened: _popup.visible

    // The user changed `selectedDate` (a day chosen or cleared).
    signal edited

    function open(): void {
        _popup.open();
    }
    function close(): void {
        _popup.close();
    }

    function _valid(d): bool {
        return d instanceof Date && !isNaN(d.getTime());
    }
    readonly property bool _hasDate: _valid(selectedDate)
    readonly property string _text: _hasDate ? (typeof format === "string" ? locale.toString(selectedDate, format) : selectedDate.toLocaleDateString(locale, format)) : ""

    // A user edit is held by a Binding for one turn, so an app binding on
    // `selectedDate` is kept (see docs/reference/telamon-ui/telamon-date-picker.md).
    property date _edit
    property bool _editing: false
    readonly property Binding _hold: Binding {
        target: control
        property: "selectedDate"
        value: control._edit
        when: control._editing
        restoreMode: Binding.RestoreBinding
    }
    function _release(): void {
        control._editing = false;
    }
    function _userSet(d: date): void {
        _edit = d;
        _editing = true;
        edited();
        Qt.callLater(_release);
    }

    function _clear(): void {
        if (clearable && _hasDate) {
            _userSet(new Date(NaN));
        }
    }

    implicitWidth: Kirigami.Units.gridUnit * 12
    implicitHeight: Math.max(TelamonStyle.controlHeight, Math.ceil(contentItem.implicitHeight) + TelamonStyle.spacing)
    leftPadding: TelamonStyle.spacingLarge
    rightPadding: TelamonStyle.spacingLarge
    hoverEnabled: true
    focusPolicy: Qt.StrongFocus

    Accessible.role: Accessible.ComboBox
    Accessible.name: control._hasDate ? control._text : control.placeholderText
    Accessible.description: control.placeholderText
    Accessible.onPressAction: control.open()

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space || (event.key === Qt.Key_Down && (event.modifiers & Qt.AltModifier))) {
            control.open();
            event.accepted = true;
        } else if (event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace) {
            control._clear();
            event.accepted = control.clearable;
        }
    }

    contentItem: Text {
        text: control._hasDate ? control._text : control.placeholderText
        font.family: TelamonStyle.fontFamily
        font.pointSize: TelamonStyle.fontSizeBody
        color: !control.enabled ? TelamonStyle.textDisabled : control._hasDate ? TelamonStyle.text : TelamonStyle.textMuted
        verticalAlignment: Text.AlignVCenter
        horizontalAlignment: control.mirrored ? Text.AlignRight : Text.AlignLeft
        elide: Text.ElideRight
        textFormat: Text.PlainText
        // Room for the clear button and the calendar symbol.
        leftPadding: control.mirrored ? tail.width : 0
        rightPadding: control.mirrored ? 0 : tail.width
    }

    // The clear button (when it applies) and the calendar symbol, at the end.
    Row {
        id: tail
        x: control.mirrored ? control.leftPadding : control.width - width - control.rightPadding
        y: Math.round((control.height - height) / 2)
        spacing: TelamonStyle.spacingSmall
        layoutDirection: control.mirrored ? Qt.RightToLeft : Qt.LeftToRight
        z: 2

        Item {
            id: clearButton
            visible: control.clearable && control._hasDate
            width: visible ? Kirigami.Units.iconSizes.small : 0
            height: Kirigami.Units.iconSizes.small
            Accessible.role: Accessible.Button
            //: Button that empties a date field
            Accessible.name: qsTr("Clear")
            Accessible.onPressAction: control._clear()
            Symbol {
                anchors.centerIn: parent
                name: "close"
                size: Kirigami.Units.iconSizes.small
                color: TelamonStyle.text
                opacity: clearArea.containsMouse ? 1 : 0.6
            }
            MouseArea {
                id: clearArea
                anchors.fill: parent
                anchors.margins: -2
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: control._clear()
            }
        }
        Symbol {
            name: "calendar_month"
            size: Kirigami.Units.iconSizes.small
            color: control.enabled ? TelamonStyle.textMuted : TelamonStyle.textDisabled
        }
    }

    TapHandler {
        // The clear button sits above this and takes its own clicks.
        onTapped: {
            if (clearArea.containsMouse && clearButton.visible) {
                return;
            }
            control._popup.visible ? control.close() : control.open();
        }
        gesturePolicy: TapHandler.ReleaseWithinBounds
    }

    background: Rectangle {
        radius: TelamonStyle.radiusSmall
        color: control._popup.visible ? Qt.tint(TelamonStyle.control, TelamonStyle.pressed) : control.hovered && control.enabled ? Qt.tint(TelamonStyle.control, TelamonStyle.hover) : TelamonStyle.control
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

    readonly property T.Popup _popup: T.Popup {
        parent: control
        y: control.height + TelamonStyle.spacingSmall
        padding: TelamonStyle.spacingSmall
        margins: TelamonStyle.spacingSmall
        modal: false
        focus: true
        closePolicy: T.Popup.CloseOnEscape | T.Popup.CloseOnPressOutsideParent

        onAboutToShow: {
            popupCalendar.showDate(control._hasDate ? control.selectedDate : control.today);
        }
        onOpened: popupCalendar.forceActiveFocus(Qt.PopupFocusReason)
        onAboutToHide: _hadFocus = popupCalendar.activeFocus
        onClosed: {
            // Give focus back only if it was in the popup and nothing else took it
            // (a click into another field keeps its caret).
            const item = control.Window.activeFocusItem;
            if (_hadFocus && (!item || _holds(popupCalendar, item))) {
                control.forceActiveFocus(Qt.PopupFocusReason);
            }
            _hadFocus = false;
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

        // A Binding, not a plain binding: the calendar assigns selectedDate itself
        // when a day is picked, which would break a plain one.
        readonly property Binding _sync: Binding {
            target: popupCalendar
            property: "selectedDate"
            value: control.selectedDate
        }

        contentItem: TelamonCalendar {
            id: popupCalendar
            minimumDate: control.minimumDate
            maximumDate: control.maximumDate
            locale: control.locale
            today: control.today
            onActivated: date => {
                control._userSet(date);
                control.close();
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
