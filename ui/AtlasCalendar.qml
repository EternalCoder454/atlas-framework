pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami

// A month grid. The header names the month and has previous and next buttons;
// below it come the weekday names and six rows of days, the first day of the
// week and the names taken from `locale`. Today is ringed, the selected day is
// filled with the accent, days outside `minimumDate`..`maximumDate` are
// disabled. An invalid Date (new Date(NaN)) means "no date": no selection, no
// bound. Click a day, or move with the keys and press Return or Space: that
// sets `selectedDate` and emits `activated`.
//
// Keys (the calendar holds focus, not each day): Left and Right a day (swapped
// in right-to-left), Up and Down a week, Home and End the start and end of the
// week, PageUp and PageDown a month; a move stops at the bounds.
//
//   AtlasCalendar {
//       minimumDate: new Date()
//       onActivated: date => booking.day = date
//   }
//
// `showDate(date)` turns to the month of a date without selecting it. `today`
// is the date that gets the ring (default: the current day); set it only to
// make a picture or test repeatable.
T.Control {
    id: control

    // The chosen day; invalid for none.
    property date selectedDate
    // The earliest and latest day that can be chosen; invalid for no limit.
    property date minimumDate
    property date maximumDate
    // The month shown (0 is January) and its year: the selected date's, else today's.
    property int month: _isValid(selectedDate) ? selectedDate.getMonth() : today.getMonth()
    property int year: _isValid(selectedDate) ? selectedDate.getFullYear() : today.getFullYear()
    // The day that is ringed.
    property date today: new Date()

    // A day was chosen by click, Return or Space; `selectedDate` is set too.
    signal activated(date date)

    // A copy of `d` at noon of its local day, in any year (JavaScript's Date
    // constructor maps years 0..99 to the 1900s).
    function _makeDate(y: int, m: int, d: int): date {
        const out = new Date(2000, 0, 1, 12);
        out.setFullYear(y, m, d);
        return out;
    }
    function _isValid(d): bool {
        return d instanceof Date && !isNaN(d.getTime());
    }
    // A number that orders days and tells equal ones apart.
    function _dayKey(d: date): int {
        return d.getFullYear() * 10000 + d.getMonth() * 100 + d.getDate();
    }
    function _inRange(d: date): bool {
        const k = _dayKey(d);
        return (!_isValid(minimumDate) || k >= _dayKey(minimumDate)) && (!_isValid(maximumDate) || k <= _dayKey(maximumDate));
    }
    // Turns to the month of `d` (nothing for an invalid date).
    function showDate(d: date): void {
        if (_isValid(d)) {
            month = d.getMonth();
            year = d.getFullYear();
        }
    }
    function _firstDay(): int {
        // Qt.Monday is 1 and Qt.Sunday 7; JavaScript's getDay() has Sunday 0.
        const f = locale.firstDayOfWeek;
        return f >= 1 && f <= 7 ? f % 7 : 0;
    }
    function _addDays(d: date, n: int): date {
        return _makeDate(d.getFullYear(), d.getMonth(), d.getDate() + n);
    }
    function _clampToRange(d: date): date {
        if (_isValid(minimumDate) && _dayKey(d) < _dayKey(minimumDate)) {
            return _makeDate(minimumDate.getFullYear(), minimumDate.getMonth(), minimumDate.getDate());
        }
        if (_isValid(maximumDate) && _dayKey(d) > _dayKey(maximumDate)) {
            return _makeDate(maximumDate.getFullYear(), maximumDate.getMonth(), maximumDate.getDate());
        }
        return d;
    }
    function _moveCursor(d: date): void {
        internals.cursor = _clampToRange(d);
        showDate(internals.cursor);
    }
    function _activate(d: date): void {
        if (!_inRange(d)) {
            return;
        }
        selectedDate = d;
        showDate(d);
        internals.cursor = d;
        activated(d);
    }

    onSelectedDateChanged: showDate(selectedDate)

    QtObject {
        id: internals
        // The day the keyboard is on.
        property date cursor
        readonly property bool hasCursor: control._isValid(cursor)
        readonly property real cell: Math.round(Kirigami.Units.gridUnit * 2.1)
        // The six weeks shown: 42 days from the first day-of-week on or before the 1st.
        readonly property var days: {
            const first = control._makeDate(control.year, control.month, 1);
            const offset = (first.getDay() - control._firstDay() + 7) % 7;
            const out = [];
            for (let i = 0; i < 42; ++i) {
                out.push(control._makeDate(control.year, control.month, 1 - offset + i));
            }
            return out;
        }
        readonly property bool canGoBack: !control._isValid(control.minimumDate) || control._dayKey(control._makeDate(control.year, control.month, 0)) >= control._dayKey(control.minimumDate)
        readonly property bool canGoForward: !control._isValid(control.maximumDate) || control._dayKey(control._makeDate(control.year, control.month + 1, 1)) <= control._dayKey(control.maximumDate)

        function shiftMonth(n: int): void {
            const target = control._makeDate(control.year, control.month + n, 1);
            const wanted = hasCursor ? cursor.getDate() : 1;
            const last = control._makeDate(target.getFullYear(), target.getMonth() + 1, 0).getDate();
            if (n < 0 && !canGoBack || n > 0 && !canGoForward) {
                return;
            }
            control.showDate(target);
            if (hasCursor) {
                internals.cursor = control._clampToRange(control._makeDate(target.getFullYear(), target.getMonth(), Math.min(wanted, last)));
                control.showDate(internals.cursor);
            }
        }
    }

    implicitWidth: internals.cell * 7 + leftPadding + rightPadding
    implicitHeight: header.implicitHeight + internals.cell * 7 + topPadding + bottomPadding + AtlasStyle.spacingSmall
    padding: AtlasStyle.spacingSmall
    hoverEnabled: true
    focusPolicy: Qt.StrongFocus
    opacity: enabled ? 1 : 0.5

    Accessible.role: Accessible.Table
    //: Spoken name of a month calendar
    Accessible.name: qsTr("Calendar")
    Accessible.description: header.title

    onActiveFocusChanged: {
        if (activeFocus && !internals.hasCursor) {
            const pick = _isValid(selectedDate) && selectedDate.getMonth() === month && selectedDate.getFullYear() === year ? selectedDate : today.getMonth() === month && today.getFullYear() === year ? today : _makeDate(year, month, 1);
            internals.cursor = _clampToRange(pick);
        }
    }

    Keys.onPressed: event => {
        if (!internals.hasCursor) {
            return;
        }
        const c = internals.cursor;
        const dir = control.mirrored ? -1 : 1;
        const weekday = (c.getDay() - _firstDay() + 7) % 7;
        switch (event.key) {
        case Qt.Key_Left:
            _moveCursor(_addDays(c, -dir));
            break;
        case Qt.Key_Right:
            _moveCursor(_addDays(c, dir));
            break;
        case Qt.Key_Up:
            _moveCursor(_addDays(c, -7));
            break;
        case Qt.Key_Down:
            _moveCursor(_addDays(c, 7));
            break;
        case Qt.Key_Home:
            _moveCursor(_addDays(c, -weekday));
            break;
        case Qt.Key_End:
            _moveCursor(_addDays(c, 6 - weekday));
            break;
        case Qt.Key_PageUp:
        case Qt.Key_PageDown:
            {
                const n = event.key === Qt.Key_PageUp ? -1 : 1;
                const target = _makeDate(c.getFullYear(), c.getMonth() + n, 1);
                const last = _makeDate(target.getFullYear(), target.getMonth() + 1, 0).getDate();
                _moveCursor(_makeDate(target.getFullYear(), target.getMonth(), Math.min(c.getDate(), last)));
            }
            break;
        case Qt.Key_Return:
        case Qt.Key_Enter:
        case Qt.Key_Space:
            _activate(c);
            break;
        default:
            return;
        }
        event.accepted = true;
    }

    background: Item {}

    contentItem: ColumnLayout {
        spacing: AtlasStyle.spacingSmall

        RowLayout {
            id: header
            readonly property string title: control.locale.toString(control._makeDate(control.year, control.month, 1), "MMMM yyyy")
            Layout.fillWidth: true
            spacing: 0

            component NavButton: T.AbstractButton {
                id: nav
                required property string symbol
                implicitWidth: internals.cell
                implicitHeight: internals.cell
                focusPolicy: Qt.NoFocus
                hoverEnabled: true
                opacity: enabled ? 1 : 0.35
                Accessible.role: Accessible.Button
                Accessible.name: text
                Accessible.onPressAction: clicked()
                background: Rectangle {
                    radius: AtlasStyle.radiusPill
                    color: Qt.alpha(AtlasStyle.text, nav.down ? 0.2 : nav.hovered ? 0.12 : 0)
                }
                contentItem: Symbol {
                    name: nav.symbol
                    size: Kirigami.Units.iconSizes.smallMedium
                    color: AtlasStyle.text
                    anchors.centerIn: parent
                }
            }

            NavButton {
                //: Button that shows the previous month in a calendar
                text: qsTr("Previous month")
                symbol: control.mirrored ? "chevron_right" : "chevron_left"
                enabled: internals.canGoBack
                onClicked: internals.shiftMonth(-1)
            }
            Text {
                Layout.fillWidth: true
                text: header.title
                font.pointSize: AtlasStyle.fontSizeBody
                font.weight: Font.DemiBold
                color: AtlasStyle.text
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                textFormat: Text.PlainText
                Accessible.ignored: true
            }
            NavButton {
                //: Button that shows the next month in a calendar
                text: qsTr("Next month")
                symbol: control.mirrored ? "chevron_left" : "chevron_right"
                enabled: internals.canGoForward
                onClicked: internals.shiftMonth(1)
            }
        }

        Row {
            Layout.alignment: Qt.AlignHCenter
            Repeater {
                model: 7
                Text {
                    required property int index
                    width: internals.cell
                    height: internals.cell
                    text: control.locale.dayName((control._firstDay() + index) % 7, Locale.NarrowFormat)
                    font.pointSize: AtlasStyle.fontSizeCaption
                    color: AtlasStyle.textMuted
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    textFormat: Text.PlainText
                    Accessible.ignored: true
                }
            }
        }

        Grid {
            Layout.alignment: Qt.AlignHCenter
            columns: 7
            Repeater {
                model: internals.days
                delegate: Item {
                    id: day
                    required property var modelData
                    required property int index
                    readonly property date dayDate: modelData
                    readonly property bool inMonth: dayDate.getMonth() === control.month
                    readonly property bool allowed: control._inRange(dayDate)
                    readonly property bool isSelected: control._isValid(control.selectedDate) && control._dayKey(control.selectedDate) === control._dayKey(dayDate)
                    readonly property bool isToday: control._isValid(control.today) && control._dayKey(control.today) === control._dayKey(dayDate)
                    readonly property bool isCursor: internals.hasCursor && control._dayKey(internals.cursor) === control._dayKey(dayDate)

                    width: internals.cell
                    height: internals.cell
                    opacity: allowed ? 1 : 0.35

                    Accessible.role: Accessible.Button
                    Accessible.name: dayDate.toLocaleDateString(control.locale, Locale.LongFormat)
                    Accessible.selected: isSelected
                    Accessible.onPressAction: control._activate(dayDate)

                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width - 4
                        height: width
                        radius: width / 2
                        color: day.isSelected ? AtlasStyle.accent : Qt.alpha(AtlasStyle.text, day.allowed && area.containsMouse ? (area.pressed ? 0.2 : 0.12) : 0)
                        border.width: day.isToday && !day.isSelected ? 1 : 0
                        border.color: AtlasStyle.accent
                        Behavior on color {
                            ColorAnimation {
                                duration: AtlasStyle.durationShort
                            }
                        }
                        AtlasFocusRing {
                            radius: parent.radius + gap
                            shown: control.visualFocus && day.isCursor
                        }
                    }
                    Text {
                        anchors.centerIn: parent
                        text: day.dayDate.getDate()
                        font.pointSize: AtlasStyle.fontSizeBody
                        font.weight: day.isSelected || day.isToday ? Font.DemiBold : Font.Normal
                        color: day.isSelected ? AtlasStyle.accentText : day.inMonth ? AtlasStyle.text : AtlasStyle.textMuted
                        textFormat: Text.PlainText
                        Accessible.ignored: true
                    }
                    MouseArea {
                        id: area
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: day.allowed
                        onClicked: {
                            control.forceActiveFocus(Qt.MouseFocusReason);
                            control._activate(day.dayDate);
                        }
                    }
                }
            }
        }
    }
}
