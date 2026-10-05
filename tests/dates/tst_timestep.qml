import QtQuick
import QtTest
import Atlas.Ui

// AtlasTimePicker: the arrow step apart from the minute grid, and a minimum.
TestCase {
    id: tc
    name: "TimeStep"
    width: 400
    height: 200
    visible: true
    when: windowShown

    Component {
        id: timeComp
        AtlasTimePicker {
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
