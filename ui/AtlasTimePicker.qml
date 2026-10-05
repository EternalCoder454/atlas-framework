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
// weekly schedule.
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

    // The user changed the hours, minutes, AM/PM or day.
    signal edited

    // `m` as the nearest allowed minute (a multiple of the step, below 60).
    function _snapMinutes(m: int): int {
        const step = Math.max(1, Math.min(59, Math.floor(minuteStep) || 1));
        const top = Math.floor(59 / step) * step;
        return Math.max(0, Math.min(top, Math.round(m / step) * step));
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
        wheelEnabled: true
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
                control.edited();
            }
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
                control.edited();
            }
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
                control.hours = (control.hours + 12) % 24;
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
