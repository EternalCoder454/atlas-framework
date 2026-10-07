import QtQuick
import QtTest
import Telamon.Ui

// TelamonTimePicker: the arrow step apart from the minute grid, and a minimum.
TestCase {
    id: tc
    name: "TimeStep"
    width: 400
    height: 200
    visible: true
    when: windowShown

    Component {
        id: timeComp
        TelamonTimePicker {
            locale: Qt.locale("en_US")
            use24Hour: true
        }
    }

    function picker(props) {
        const t = createTemporaryObject(timeComp, tc, props);
        verify(t);
        return t;
    }

    function spins(t) {
        const out = [];
        function find(item) {
            for (const c of item.children) {
                if (c.hasOwnProperty("textFromValue") && c.visible) {
                    out.push(c);
                }
                find(c);
            }
        }
        find(t);
        return out;
    }

    function test_arrow_step_goes_to_the_next_multiple() {
        const t = picker({
            minuteArrowStep: 5,
            minutes: 7
        });
        compare(t.minutes, 7, "a typed 07 stays 07");
        const s = spins(t);
        s[1].forceActiveFocus();
        keyClick(Qt.Key_Up);
        compare(t.minutes, 10);
        t.minutes = 7;
        keyClick(Qt.Key_Down);
        compare(t.minutes, 5);
        t.minutes = 55;
        keyClick(Qt.Key_Up);
        compare(t.minutes, 0, "wraps without a minimum");
        keyClick(Qt.Key_Down);
        compare(t.minutes, 55);
    }

    function test_no_arrow_step_follows_minute_step() {
        const t = picker({
            minuteStep: 15,
            minutes: 0
        });
        spins(t)[1].forceActiveFocus();
        keyClick(Qt.Key_Up);
        compare(t.minutes, 15);
    }

    function test_arrow_step_is_held_to_30() {
        const t = picker({
            minuteArrowStep: 99,
            minutes: 0
        });
        spins(t)[1].forceActiveFocus();
        keyClick(Qt.Key_Up);
        compare(t.minutes, 30);
    }

    function test_minimum_raises_a_typed_time() {
        const t = picker({
            minimumHours: 9,
            hours: 10,
            minutes: 0
        });
        let adjusted = 0;
        t.adjusted.connect(() => ++adjusted);
        const s = spins(t);
        s[0].forceActiveFocus();
        s[0].contentItem.selectAll();
        keyClick("7");
        keyClick(Qt.Key_Return);
        compare(t.hours, 9);
        compare(t.minutes, 0);
        compare(adjusted, 1);
    }

    function test_minimum_stops_the_arrows() {
        const t = picker({
            minimumHours: 9,
            minimumMinutes: 30,
            hours: 9,
            minutes: 30
        });
        let adjusted = 0;
        t.adjusted.connect(() => ++adjusted);
        const s = spins(t);
        s[1].forceActiveFocus();
        keyClick(Qt.Key_Down);
        compare(t.minutes, 30, "down at the minimum stays");
        s[0].forceActiveFocus();
        keyClick(Qt.Key_Down);
        compare(t.hours, 9, "hours stay too");
        keyClick(Qt.Key_Up);
        compare(t.hours, 10);
        compare(adjusted, 0);
    }

    function test_no_minimum_wraps_as_before() {
        const t = picker({
            hours: 0
        });
        spins(t)[0].forceActiveFocus();
        keyClick(Qt.Key_Down);
        compare(t.hours, 23);
    }

    function test_minimum_in_12_hour_mode_skips_early_halves() {
        const t = picker({
            use24Hour: false,
            minimumHours: 13,
            hours: 14,
            minutes: 0
        });
        const ampm = tc.findAmPm(t);
        mouseClick(ampm); // AM would be before 13:00
        compare(t.hours, 14);
    }

    function test_minimum_carries_into_the_next_hour() {
        const t = picker({
            minuteStep: 15,
            minimumHours: 9,
            minimumMinutes: 50
        });
        compare(t._minH, 10);
        compare(t._minM, 0);
        const late = picker({
            minuteStep: 15,
            minimumHours: 23,
            minimumMinutes: 50
        });
        compare(late._minH, 23, "no later hour: the latest allowed time");
        compare(late._minM, 45);
        const rounded = picker({
            minuteStep: 5,
            minimumHours: 9,
            minimumMinutes: 31
        });
        compare(rounded._minM, 35, "rounded up, never down");
    }

    function test_up_at_2359_with_a_minimum_stops() {
        const t = picker({
            minimumHours: 1,
            hours: 23,
            minutes: 59
        });
        const s = spins(t);
        s[0].forceActiveFocus();
        keyClick(Qt.Key_Up);
        compare(t.hours, 23);
        s[1].forceActiveFocus();
        keyClick(Qt.Key_Up);
        compare(t.minutes, 59);
    }

    function test_typed_minute_below_the_minimum_is_raised() {
        const t = picker({
            minimumHours: 9,
            minimumMinutes: 30,
            hours: 9,
            minutes: 45
        });
        let adjusted = 0;
        t.adjusted.connect(() => ++adjusted);
        const s = spins(t);
        s[1].forceActiveFocus();
        s[1].contentItem.selectAll();
        keyClick("5");
        keyClick(Qt.Key_Return);
        compare(t.minutes, 30);
        compare(adjusted, 1);
    }

    function test_wheel_and_touchpad_deltas() {
        const t = picker({
            minuteArrowStep: 5,
            minimumHours: 9,
            minimumMinutes: 10,
            hours: 9,
            minutes: 20
        });
        const s = spins(t);
        mouseWheel(s[1], s[1].width / 2, s[1].height / 2, 0, -120);
        compare(t.minutes, 15);
        // Four small touchpad deltas make one step.
        for (let i = 0; i < 4; ++i) {
            mouseWheel(s[1], s[1].width / 2, s[1].height / 2, 0, -30);
        }
        compare(t.minutes, 10);
        mouseWheel(s[1], s[1].width / 2, s[1].height / 2, 0, -120);
        compare(t.minutes, 10, "stops at the minimum");
        mouseWheel(s[1], s[1].width / 2, s[1].height / 2, 0, 120);
        compare(t.minutes, 15);
    }

    function test_12_hour_stepping_across_12_with_a_minimum() {
        const t = picker({
            use24Hour: false,
            minimumHours: 9,
            hours: 12,
            minutes: 0
        });
        const s = spins(t);
        s[0].forceActiveFocus();
        keyClick(Qt.Key_Up);
        compare(t.hours, 13);
        keyClick(Qt.Key_Down);
        compare(t.hours, 12);
        keyClick(Qt.Key_Down);
        compare(t.hours, 12, "11 PM is not reached by wrapping");
        t.hours = 11;
        keyClick(Qt.Key_Up);
        compare(t.hours, 11, "nor 12 AM");
        t.hours = 10;
        keyClick(Qt.Key_Down);
        compare(t.hours, 9);
        keyClick(Qt.Key_Down);
        compare(t.hours, 9, "stops at the minimum");
    }

    function test_arrow_step_with_a_coarser_grid() {
        const t = picker({
            minuteStep: 5,
            minuteArrowStep: 3,
            minutes: 0
        });
        spins(t)[1].forceActiveFocus();
        keyClick(Qt.Key_Up);
        compare(t.minutes, 5, "3 rounds up to the grid");
        keyClick(Qt.Key_Up);
        compare(t.minutes, 10);
        const u = picker({
            minuteStep: 5,
            minuteArrowStep: 7,
            minutes: 0
        });
        spins(u)[1].forceActiveFocus();
        keyClick(Qt.Key_Up);
        compare(u.minutes, 10);
        keyClick(Qt.Key_Up);
        compare(u.minutes, 20);
    }

    function findAmPm(t) {
        function find(item) {
            for (const c of item.children) {
                if (c.hasOwnProperty("pressed") && c.hasOwnProperty("checkable") && c.visible && c.text.length > 0 && !c.hasOwnProperty("textFromValue")) {
                    return c;
                }
                const r = find(c);
                if (r) {
                    return r;
                }
            }
            return null;
        }
        return find(t);
    }
}
