import QtQuick
import QtTest
import Atlas.Ui

TestCase {
    name: "Dates"
    width: 400
    height: 400
    visible: true
    when: windowShown

    readonly property var en: Qt.locale("en_US")
    readonly property var de: Qt.locale("de_DE")

    Component {
        id: calendarComp
        AtlasCalendar {
            locale: Qt.locale("en_US")
            today: new Date(2026, 2, 12)
        }
    }
    Component {
        id: pickerComp
        AtlasDatePicker {
            locale: Qt.locale("en_US")
            today: new Date(2026, 2, 12)
        }
    }
    Component {
        id: timeComp
        AtlasTimePicker {
            locale: Qt.locale("en_US")
        }
    }

    function day(d) {
        return d.getFullYear() * 10000 + (d.getMonth() + 1) * 100 + d.getDate();
    }

    function newCalendar(props) {
        const c = createTemporaryObject(calendarComp, this, props);
        verify(c !== null);
        c.forceActiveFocus();
        verify(c.activeFocus);
        return c;
    }

    function test_calendar_default_month_follows_selection() {
        const c = newCalendar({
            selectedDate: new Date(2026, 6, 4)
        });
        compare(c.month, 6);
        compare(c.year, 2026);
        const empty = newCalendar({});
        compare(empty.month, 2); // today
        verify(!empty._isValid(empty.selectedDate));
        const invalid = newCalendar({
            selectedDate: new Date(NaN)
        });
        verify(!invalid._isValid(invalid.selectedDate));
    }

    function test_calendar_keyboard() {
        const c = newCalendar({
            selectedDate: new Date(2026, 2, 15) // a Sunday
        });
        const seen = [];
        c.activated.connect(d => seen.push(day(d)));
        keyClick(Qt.Key_Right);
        keyClick(Qt.Key_Return);
        compare(day(c.selectedDate), 20260316);
        keyClick(Qt.Key_Down);
        keyClick(Qt.Key_Space);
        compare(day(c.selectedDate), 20260323);
        keyClick(Qt.Key_Home); // en_US weeks start on Sunday: the 22nd
        keyClick(Qt.Key_Return);
        compare(day(c.selectedDate), 20260322);
        keyClick(Qt.Key_End);
        keyClick(Qt.Key_Return);
        compare(day(c.selectedDate), 20260328);
        keyClick(Qt.Key_PageDown);
        compare(c.month, 3);
        keyClick(Qt.Key_Return);
        compare(day(c.selectedDate), 20260428);
        keyClick(Qt.Key_PageUp);
        keyClick(Qt.Key_PageUp);
        compare(c.month, 1);
        keyClick(Qt.Key_Return);
        compare(day(c.selectedDate), 20260228); // clamped to the month's end
        compare(seen.length, 6);
        keyClick(Qt.Key_Up);
        keyClick(Qt.Key_Up);
        keyClick(Qt.Key_Up);
        keyClick(Qt.Key_Up); // Jan 31
        compare(c.month, 0);
        compare(c.year, 2026);
    }

    function test_calendar_monday_start() {
        const c = newCalendar({
            locale: de,
            selectedDate: new Date(2026, 2, 18) // a Wednesday
        });
        keyClick(Qt.Key_Home);
        keyClick(Qt.Key_Return);
        compare(day(c.selectedDate), 20260316);
        keyClick(Qt.Key_End);
        keyClick(Qt.Key_Return);
        compare(day(c.selectedDate), 20260322);
    }

    function test_calendar_bounds() {
        const c = newCalendar({
            selectedDate: new Date(2026, 2, 15),
            minimumDate: new Date(2026, 2, 10),
            maximumDate: new Date(2026, 2, 20)
        });
        verify(c._inRange(new Date(2026, 2, 10)));
        verify(c._inRange(new Date(2026, 2, 20)));
        verify(!c._inRange(new Date(2026, 2, 9)));
        verify(!c._inRange(new Date(2026, 2, 21)));
        for (let i = 0; i < 10; ++i) {
            keyClick(Qt.Key_Right);
        }
        keyClick(Qt.Key_Return);
        compare(day(c.selectedDate), 20260320); // stopped at the maximum
        for (let i = 0; i < 6; ++i) {
            keyClick(Qt.Key_Up);
        }
        keyClick(Qt.Key_Return);
        compare(day(c.selectedDate), 20260310);
        keyClick(Qt.Key_PageDown);
        keyClick(Qt.Key_Return);
        compare(day(c.selectedDate), 20260320);
        // A disabled day cannot be activated.
        c._activate(new Date(2026, 2, 25));
        compare(day(c.selectedDate), 20260320);
    }

    function test_picker_popup_reflects_picker_after_pick_and_clear() {
        const p = createTemporaryObject(pickerComp, this, {
            selectedDate: new Date(NaN),
            clearable: true
        });
        verify(p !== null);
        p.forceActiveFocus();
        keyClick(Qt.Key_Space);
        tryVerify(() => p.opened && p._popup.contentItem.activeFocus);
        keyClick(Qt.Key_Return);
        tryVerify(() => !p.opened);
        compare(day(p.selectedDate), 20260312);
        keyClick(Qt.Key_Delete);
        verify(isNaN(p.selectedDate.getTime()));
        keyClick(Qt.Key_Space);
        tryVerify(() => p.opened);
        verify(isNaN(p._popup.contentItem.selectedDate.getTime()));
        p.close();
        tryVerify(() => !p.opened);
        // Set from the app, then reopen: the popup shows that day.
        p.selectedDate = new Date(2026, 5, 2);
        p.open();
        tryVerify(() => p.opened);
        compare(day(p._popup.contentItem.selectedDate), 20260602);
    }

    function test_picker_popup_and_edit() {
        const p = createTemporaryObject(pickerComp, this, {
            selectedDate: new Date(NaN),
            clearable: true
        });
        verify(p !== null);
        let edits = 0;
        p.edited.connect(() => ++edits);
        compare(p.placeholderText, "Pick a date");
        p.forceActiveFocus();
        verify(p.activeFocus);
        keyClick(Qt.Key_Space);
        tryVerify(() => p.opened);
        keyClick(Qt.Key_Escape);
        tryVerify(() => !p.opened);
        verify(p.activeFocus);
        compare(edits, 0);
        keyClick(Qt.Key_Space);
        tryVerify(() => p.opened && p._popup.contentItem.activeFocus);
        keyClick(Qt.Key_Return);
        tryVerify(() => !p.opened);
        compare(edits, 1);
        compare(day(p.selectedDate), 20260312); // the cursor starts on today
        keyClick(Qt.Key_Delete);
        compare(edits, 2);
        verify(isNaN(p.selectedDate.getTime()));
    }

    function test_time_minute_step() {
        const t = createTemporaryObject(timeComp, this, {
            minuteStep: 5,
            minutes: 7
        });
        verify(t !== null);
        compare(t.minutes, 5);
        t.minutes = 58;
        compare(t.minutes, 55);
        t.minuteStep = 15;
        compare(t.minutes, 60 - 15 === 45 ? 60 - 15 : 0); // 55 snaps to 45
        t.hours = 31;
        compare(t.hours, 23);
        compare(t._snapMinutes(59), 45);
    }

    function test_time_12_hour() {
        const t = createTemporaryObject(timeComp, this, {
            use24Hour: false,
            hours: 0,
            minutes: 0
        });
        verify(t !== null);
        let edits = 0;
        t.edited.connect(() => ++edits);
        const spins = [];
        function find(item) {
            for (const c of item.children) {
                if (c.hasOwnProperty("textFromValue") && c.visible) {
                    spins.push(c);
                }
                find(c);
            }
        }
        find(t);
        compare(spins.length, 2);
        compare(spins[0].value, 12); // midnight reads 12 AM
        spins[0].forceActiveFocus();
        keyClick(Qt.Key_Down); // wraps 12 -> 1? from 12 down gives 11 
        compare(t.hours, 11);
        compare(edits, 1);
        t.hours = 13;
        compare(spins[0].value, 1);
        keyClick(Qt.Key_Up);
        compare(t.hours, 14); // stays PM
    }

    function test_time_default_clock_follows_locale() {
        const us = createTemporaryObject(timeComp, this, {});
        verify(!us.use24Hour);
        const gb = createTemporaryObject(timeComp, this, {
            locale: de
        });
        verify(gb.use24Hour);
    }
}
