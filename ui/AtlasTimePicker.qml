import QtQuick
import QtQuick.Layouts
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami

// A time of day: hours and minutes as two number fields (Up and Down, the
// wheel, or type a number and press Return; both wrap round), and in 12-hour
// mode an AM/PM button. `hours` is always 0-23, also in 12-hour mode. Minutes
// snap to `minuteStep` (7 with a step of 5 becomes 5; the last allowed value
// below 60 is the largest multiple), and an out-of-range `hours` or `minutes`
// is clamped, so a binding to either is replaced by the corrected value. With
// `showDay: true` a drop-down with the days of the week comes first, for a
// weekly schedule. `minuteArrowStep` sets the step of the minutes' arrow keys
// and wheel apart from `minuteStep` (typed minutes stay as typed): with
// `minuteStep: 1` and `minuteArrowStep: 5`, 07 goes up to 10 and down to 05.
// `minimumHours` and `minimumMinutes` set the earliest time: an earlier typed
// or stepped time is raised to it and `adjusted()` is emitted, and the fields
// stop at the minimum instead of wrapping. The minimum is in 24-hour terms,
// also in 12-hour mode. The app's own `hours` and `minutes` are not raised.
//
//   AtlasTimePicker {
//       hours: 7; minutes: 30
//       minuteStep: 5
//       onEdited: alarm.set(hours, minutes)
//   }
//
// Each part has its own accessible name (hours, minutes, AM or PM, day).
T.Control {
    id: control

    // 0-23.
    property int hours: 0
    // 0-59, a multiple of `minuteStep`.
    property int minutes: 0
    property int minuteStep: 1
    // 24-hour clock; the default follows the locale's short time format.
    property bool use24Hour: !/ap/i.test(locale.timeFormat(Locale.ShortFormat))
    // A day-of-week drop-down before the time.
    property bool showDay: false
    // Qt.Monday .. Qt.Sunday; used with `showDay`.
    property int day: Qt.Monday
    // The step of the minutes' arrow keys and wheel, 1-30; 0 follows `minuteStep`.
    property int minuteArrowStep: 0
    // The earliest hour (0-23).
    property int minimumHours: 0
    // The earliest minute when the hour equals `minimumHours` (0-59).
    property int minimumMinutes: 0

    // The user changed the hours, minutes, AM/PM or day.
    signal edited
    // A typed or stepped time was changed to fit the minimum or the step.
    signal adjusted

    // `m` as the nearest allowed minute (a multiple of the step, below 60).
    function _snapMinutes(m: int): int {
        const step = Math.max(1, Math.min(59, Math.floor(minuteStep) || 1));
        const top = Math.floor(59 / step) * step;
        return Math.max(0, Math.min(top, Math.round(m / step) * step));
    }

    readonly property int _minH: Math.max(0, Math.min(23, Math.floor(minimumHours) || 0))
    // The minimum minute, on the minute grid (the next allowed minute).
    readonly property int _minM: {
        const m = Math.max(0, Math.min(59, Math.floor(minimumMinutes) || 0));
        const step = Math.max(1, Math.min(59, Math.floor(minuteStep) || 1));
        const top = Math.floor(59 / step) * step;
        return Math.min(top, Math.ceil(m / step) * step);
    }
    readonly property bool _hasMinimum: _minH > 0 || _minM > 0
    // The arrow keys' and wheel's step.
    readonly property int _arrowStep: {
        const a = Math.floor(minuteArrowStep);
        return a > 0 ? Math.min(30, a) : Math.max(1, Math.min(30, Math.floor(minuteStep) || 1));
    }

    // Raises a time before the minimum to it. True when it did.
    function _fit(): bool {
        if (!_hasMinimum || hours > _minH || (hours === _minH && minutes >= _minM)) {
            return false;
        }
        hours = _minH;
        minutes = _minM;
        //: Spoken when a time picker raised the time to its earliest allowed time: %1 is that time ("09:00")
        Accessible.announce(qsTr("Set to %1").arg(String(hours).padStart(2, "0") + ":" + String(minutes).padStart(2, "0")));
        adjusted();
        return true;
    }
    // One step of the hours field; `base` is the hour to step from.
    function _stepHours(dir: int, base: int): void {
        let next = base + dir;
        if (use24Hour) {
            if (next < 0 || next > 23) {
                if (_hasMinimum) {
                    return;
                }
                next = (next + 24) % 24;
            }
        } else {
            const r = ((base % 12) + dir + 12) % 12;
            const crossed = dir > 0 ? r < base % 12 : r > base % 12;
            if (crossed && _hasMinimum) {
                return;
            }
            next = (base >= 12 ? 12 : 0) + r;
        }
        if (next < _minH) {
            return;
        }
        hours = next;
        _fit();
        edited();
    }
    // One step of the minutes field: to the next or previous multiple of the arrow step.
    function _stepMinutes(dir: int, base: int): void {
        const step = _arrowStep;
        const top = _snapMinutes(59);
        let next = dir > 0 ? (Math.floor(base / step) + 1) * step : (Math.ceil(base / step) - 1) * step;
        if (next > top || next < 0) {
            // Past the end: wrap, unless there is a minimum.
            if (_hasMinimum) {
                return;
            }
            next = dir > 0 ? 0 : Math.floor(top / step) * step;
        }
        next = _snapMinutes(next);
        if (next < (hours === _minH ? _minM : 0)) {
            return;
        }
        minutes = next;
        edited();
    }
    // The number typed into a field and not yet applied, else `fallback`.
    function _typed(field: var, fallback: int): int {
        const n = parseInt(field.contentItem.text, 10);
        return isNaN(n) ? fallback : n;
    }

    onHoursChanged: {
        const h = Math.max(0, Math.min(23, hours));
        if (h !== hours) {
            hours = h;
        }
    }
    onMinutesChanged: {
        const m = _snapMinutes(minutes);
        if (m !== minutes) {
            minutes = m;
        }
    }
    onMinuteStepChanged: {
        const m = _snapMinutes(minutes);
        if (m !== minutes) {
            minutes = m;
        }
    }

    QtObject {
        id: internals
        readonly property bool pm: control.hours >= 12
        readonly property int hours12: control.hours % 12 === 0 ? 12 : control.hours % 12
        readonly property int firstDay: control.locale.firstDayOfWeek >= 1 && control.locale.firstDayOfWeek <= 7 ? control.locale.firstDayOfWeek : Qt.Monday
        // Qt.Monday..Qt.Sunday in the order the locale's week starts.
        readonly property var order: {
            const out = [];
            for (let i = 0; i < 7; ++i) {
                out.push((internals.firstDay - 1 + i) % 7 + 1);
            }
            return out;
        }
        readonly property var dayNames: order.map(d => control.locale.dayName(d % 7, Locale.LongFormat))
    }

    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight
    opacity: enabled ? 1 : 0.5

    Accessible.role: Accessible.Grouping
    //: Spoken name of the control that sets a time of day
    Accessible.name: qsTr("Time")

    component Field: AtlasSpinBox {
        implicitWidth: Math.round(Kirigami.Units.gridUnit * 3.4)
        editable: true
        showButtons: false
        wrap: true
        // Up, Down and the wheel step through the picker, which knows the minimum and the arrow step.
        wheelEnabled: false
        property real wheelRemainder: 0
        signal stepped(int dir)
        Keys.onUpPressed: event => {
            stepped(1);
            event.accepted = true;
        }
        Keys.onDownPressed: event => {
            stepped(-1);
            event.accepted = true;
        }
        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: event => {
                parent.wheelRemainder += event.angleDelta.y / 120;
                const whole = parent.wheelRemainder > 0 ? Math.floor(parent.wheelRemainder) : Math.ceil(parent.wheelRemainder);
                parent.wheelRemainder -= whole;
                for (let i = 0; i < Math.abs(whole); ++i) {
                    parent.stepped(whole > 0 ? 1 : -1);
                }
            }
        }
        textFromValue: (value, locale) => String(value).padStart(2, "0")
        valueFromText: (text, locale) => {
            const n = parseInt(text, 10);
            return isNaN(n) ? value : n;
        }
    }

    contentItem: RowLayout {
        id: row
        spacing: AtlasStyle.spacingSmall

        AtlasComboBox {
            visible: control.showDay
            Layout.preferredWidth: Math.round(Kirigami.Units.gridUnit * 8)
            Layout.rightMargin: AtlasStyle.spacing
            model: internals.dayNames
            currentIndex: internals.order.indexOf(control.day)
            //: Spoken name of the day-of-week drop-down of a time picker
            Accessible.name: qsTr("Day")
            onActivated: index => {
                control.day = internals.order[index];
                control.edited();
            }
        }

        Field {
            id: hoursField
            from: control.use24Hour ? 0 : 1
            to: control.use24Hour ? 23 : 12
            value: control.use24Hour ? control.hours : internals.hours12
            //: Spoken name of the hours field of a time picker
            Accessible.name: qsTr("Hours")
            onValueModified: {
                control.hours = control.use24Hour ? value : (value % 12) + (internals.pm ? 12 : 0);
                control._fit();
                control.edited();
            }
            onStepped: dir => control._stepHours(dir, control.use24Hour ? control._typed(hoursField, control.hours) : (control._typed(hoursField, internals.hours12) % 12) + (internals.pm ? 12 : 0))
        }
        Text {
            text: ":"
            font.family: AtlasStyle.fontFamily
            font.pointSize: AtlasStyle.fontSizeBody
            color: AtlasStyle.text
            textFormat: Text.PlainText
            Accessible.ignored: true
        }
        Field {
            id: minutesField
            from: 0
            to: control._snapMinutes(59)
            stepSize: Math.max(1, control.minuteStep)
            value: control.minutes
            //: Spoken name of the minutes field of a time picker
            Accessible.name: qsTr("Minutes")
            onValueModified: {
                control.minutes = value;
                control._fit();
                control.edited();
            }
            onStepped: dir => control._stepMinutes(dir, control._typed(minutesField, control.minutes))
        }

        T.AbstractButton {
            id: ampm
            visible: !control.use24Hour
            Layout.leftMargin: AtlasStyle.spacingSmall
            implicitWidth: Math.max(Math.round(Kirigami.Units.gridUnit * 3), amMetrics.advanceWidth + AtlasStyle.spacingLarge * 2, pmMetrics.advanceWidth + AtlasStyle.spacingLarge * 2)
            implicitHeight: Math.max(AtlasStyle.controlHeight, Math.ceil(amMetrics.height) + AtlasStyle.spacing)
            hoverEnabled: true
            focusPolicy: Qt.StrongFocus
            text: internals.pm ? pmMetrics.text : amMetrics.text
            Accessible.role: Accessible.Button
            //: Spoken name of the button that switches a 12-hour time between morning and afternoon
            Accessible.name: qsTr("AM or PM")
            Accessible.description: text
            Accessible.onPressAction: clicked()
            onClicked: {
                const next = (control.hours + 12) % 24;
                // A half of the day before the minimum is skipped.
                if (next < control._minH) {
                    return;
                }
                control.hours = next;
                control._fit();
                control.edited();
            }
            Keys.onPressed: event => {
                if (event.key === Qt.Key_Up || event.key === Qt.Key_Down) {
                    clicked();
                    event.accepted = true;
                }
            }
            TextMetrics {
                id: amMetrics
                font.family: AtlasStyle.fontFamily
                font.pointSize: AtlasStyle.fontSizeBody
                text: control.locale.amText || "AM"
            }
            TextMetrics {
                id: pmMetrics
                font.family: AtlasStyle.fontFamily
                font.pointSize: AtlasStyle.fontSizeBody
                text: control.locale.pmText || "PM"
            }
            contentItem: Text {
                text: ampm.text
                font.family: AtlasStyle.fontFamily
                font.pointSize: AtlasStyle.fontSizeBody
                color: AtlasStyle.text
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                textFormat: Text.PlainText
                Accessible.ignored: true
            }
            background: Rectangle {
                radius: AtlasStyle.radiusSmall
                color: ampm.down ? Qt.tint(AtlasStyle.control, AtlasStyle.pressed) : ampm.hovered ? Qt.tint(AtlasStyle.control, AtlasStyle.hover) : AtlasStyle.control
                border.width: 1
                border.color: AtlasStyle.controlBorder
                AtlasFocusRing {
                    radius: parent.radius + gap
                    shown: ampm.visualFocus
                }
            }
        }
    }
}
