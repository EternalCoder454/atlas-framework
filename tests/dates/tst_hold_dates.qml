import QtQuick
import QtTest
import Atlas.Ui

// A user edit must not end an app's binding on `selectedDate`, `month` or
// `year` (docs/api-1.5.0.md, Part 1). The three app styles: bound and taking
// the edit, bound and refusing it, and a literal value. Edits are made with
// the keyboard.
TestCase {
    id: test
    name: "HoldDates"
    width: 400
    height: 400
    visible: true
    when: windowShown

    QtObject {
        id: app
        property date day: new Date(2026, 2, 5)
        property int month: 2
    }

    Component {
        id: calAccept
        AtlasCalendar {
            locale: Qt.locale("en_US")
            today: new Date(2026, 2, 12)
            selectedDate: app.day
            onActivated: date => app.day = date
        }
    }
    Component {
        id: calRefuse
        AtlasCalendar {
            locale: Qt.locale("en_US")
            today: new Date(2026, 2, 12)
            selectedDate: app.day
        }
    }
    Component {
        id: calLiteral
        AtlasCalendar {
            locale: Qt.locale("en_US")
            today: new Date(2026, 2, 12)
            selectedDate: new Date(2026, 2, 5)
        }
    }
    // The app owns the month shown.
    Component {
        id: calMonthBound
        AtlasCalendar {
            locale: Qt.locale("en_US")
            today: new Date(2026, 2, 12)
            month: app.month
        }
    }
    // The app owns the month and also binds the selection, in both orders.
    Component {
        id: calBothA
        AtlasCalendar {
            locale: Qt.locale("en_US")
            today: new Date(2026, 2, 12)
            selectedDate: app.day
            month: app.month
        }
    }
    Component {
        id: calBothB
        AtlasCalendar {
            locale: Qt.locale("en_US")
            today: new Date(2026, 2, 12)
            month: app.month
            selectedDate: app.day
        }
    }
    Component {
        id: pickAccept
        AtlasDatePicker {
            locale: Qt.locale("en_US")
            today: new Date(2026, 2, 12)
            clearable: true
            selectedDate: app.day
            onEdited: app.day = selectedDate
        }
    }
    Component {
        id: pickRefuse
        AtlasDatePicker {
            locale: Qt.locale("en_US")
            today: new Date(2026, 2, 12)
            clearable: true
            selectedDate: app.day
        }
    }
    Component {
        id: pickLiteral
        AtlasDatePicker {
            locale: Qt.locale("en_US")
            today: new Date(2026, 2, 12)
            clearable: true
            selectedDate: new Date(2026, 2, 5)
        }
    }

    function init() {
        app.day = new Date(2026, 2, 5);
        app.month = 2;
    }
    function day(d) {
        return d.getFullYear() * 10000 + (d.getMonth() + 1) * 100 + d.getDate();
    }
    function focused(comp) {
        const c = createTemporaryObject(comp, this);
        verify(c !== null);
        c.forceActiveFocus();
        verify(c.activeFocus);
        return c;
    }

    function test_calendar_accept() {
        const c = focused(calAccept);
        keyClick(Qt.Key_Right); // the cursor starts on the selected day
        keyClick(Qt.Key_Return);
        compare(day(c.selectedDate), 20260306);
        compare(day(app.day), 20260306);
        wait(50);
        compare(day(c.selectedDate), 20260306);
        app.day = new Date(2026, 4, 9);
        compare(day(c.selectedDate), 20260509, "the binding follows the model");
        compare(c.month, 4, "the month follows the selection");
    }
    function test_calendar_refuse() {
        const c = focused(calRefuse);
        let seen = 0;
        c.activated.connect(() => seen = day(c.selectedDate));
        keyClick(Qt.Key_Right);
        keyClick(Qt.Key_Return);
        compare(seen, 20260306, "a handler reads the edit");
        tryCompare(c, "selectedDate", app.day);
        app.day = new Date(2026, 5, 20);
        compare(day(c.selectedDate), 20260620, "the binding follows the model");
        compare(c.month, 5);
    }
    function test_calendar_literal() {
        const c = focused(calLiteral);
        keyClick(Qt.Key_Right);
        keyClick(Qt.Key_Return);
        wait(50);
        compare(day(c.selectedDate), 20260306);
    }
    function test_calendar_month_navigation_stays() {
        // No app binding on month: PageDown turns and the month stays turned.
        const c = focused(calLiteral);
        keyClick(Qt.Key_PageDown);
        compare(c.month, 3);
        wait(50);
        compare(c.month, 3);
        compare(day(c.selectedDate), 20260305, "turning the month selects nothing");
        c.selectedDate = new Date(2026, 8, 1);
        compare(c.month, 8, "a new selection turns to its month");
    }
    function test_calendar_month_bound() {
        const c = focused(calMonthBound);
        compare(c.month, 2);
        const months = [];
        c.monthChanged.connect(() => months.push(c.month));
        keyClick(Qt.Key_Down);
        keyClick(Qt.Key_PageDown);
        verify(months.indexOf(3) >= 0, "the month turned for a turn");
        tryCompare(c, "month", 2); // the app did not take it
        app.month = 7;
        compare(c.month, 7, "the month binding follows the model");
    }

    function open(p) {
        p.forceActiveFocus();
        keyClick(Qt.Key_Space);
        tryVerify(() => p.opened && p._popup.contentItem.activeFocus);
    }
    function test_picker_accept() {
        const p = createTemporaryObject(pickAccept, this);
        open(p);
        keyClick(Qt.Key_Right);
        keyClick(Qt.Key_Return);
        compare(day(p.selectedDate), 20260306);
        compare(day(app.day), 20260306);
        tryVerify(() => !p.opened);
        wait(50);
        compare(day(p.selectedDate), 20260306);
        app.day = new Date(2026, 4, 9);
        compare(day(p.selectedDate), 20260509, "the binding follows the model");
        keyClick(Qt.Key_Delete);
        verify(isNaN(app.day.getTime()), "clearing is an edit too");
        app.day = new Date(2026, 6, 1);
        compare(day(p.selectedDate), 20260701, "still bound after a clear");
        p.open();
        tryVerify(() => p.opened);
        compare(day(p._popup.contentItem.selectedDate), 20260701, "the popup follows the picker");
    }
    function test_picker_refuse() {
        const p = createTemporaryObject(pickRefuse, this);
        const seen = [];
        p.edited.connect(() => seen.push(day(p.selectedDate)));
        open(p);
        keyClick(Qt.Key_Right);
        keyClick(Qt.Key_Return);
        compare(seen[0], 20260306, "a handler reads the edit");
        tryVerify(() => !p.opened);
        tryCompare(p, "selectedDate", app.day);
        keyClick(Qt.Key_Delete);
        verify(isNaN(seen[1]), "a handler reads the clear");
        tryCompare(p, "selectedDate", app.day);
        app.day = new Date(2026, 5, 20);
        compare(day(p.selectedDate), 20260620, "the binding follows the model");
    }
    function test_picker_literal() {
        const p = createTemporaryObject(pickLiteral, this);
        open(p);
        keyClick(Qt.Key_Right);
        keyClick(Qt.Key_Return);
        tryVerify(() => !p.opened);
        wait(50);
        compare(day(p.selectedDate), 20260306);
        keyClick(Qt.Key_Delete);
        wait(50);
        verify(isNaN(p.selectedDate.getTime()));
    }

    function test_calendar_starts_on_the_selection() {
        // Never changed after creation: the month is the selection's, not today's.
        const lit = focused(calLiteral);
        lit.selectedDate = new Date(2026, 8, 5);
        compare(lit.month, 8);
        compare(lit.year, 2026);
        app.day = new Date(2026, 8, 5);
        const bound = focused(calAccept);
        compare(bound.month, 8, "a bound selection");
        compare(bound.year, 2026);
        wait(50);
        compare(bound.month, 8);
        const born = createTemporaryObject(calLiteralSeptember, this);
        compare(born.month, 8, "a literal selection at creation");
        compare(born.year, 2026);
        wait(50);
        compare(born.month, 8);
    }
    Component {
        id: calLiteralSeptember
        AtlasCalendar {
            locale: Qt.locale("en_US")
            today: new Date(2026, 2, 12)
            selectedDate: new Date(2026, 8, 5)
        }
    }
    function test_picker_popup_starts_on_the_selection() {
        app.day = new Date(2026, 8, 5);
        const p = createTemporaryObject(pickAccept, this);
        compare(p._popup.contentItem.month, 8);
        compare(p._popup.contentItem.year, 2026);
        open(p);
        compare(p._popup.contentItem.month, 8);
        compare(p._popup.contentItem.year, 2026);
        keyClick(Qt.Key_Escape);
        tryVerify(() => !p.opened);
        wait(50);
        compare(p._popup.contentItem.month, 8);
    }
    function test_calendar_month_and_selection_both_bound() {
        for (const comp of [calBothA, calBothB]) {
            app.day = new Date(2026, 8, 5);
            app.month = 4;
            const c = createTemporaryObject(comp, this);
            verify(c !== null);
            compare(c.month, 4, "the app's month wins at creation");
            wait(50);
            compare(c.month, 4, "and after a turn");
            app.month = 6;
            compare(c.month, 6, "and follows the model");
            app.day = new Date(2026, 10, 1);
            compare(c.month, 6, "a new selection does not move an app-bound month");
        }
    }
    function test_calendar_refused_turn_keeps_the_cursor_in_view() {
        const c = focused(calMonthBound);
        const months = [];
        c.monthChanged.connect(() => months.push(c.month));
        keyClick(Qt.Key_PageDown);
        tryCompare(c, "month", 2);
        compare(c._viewMonth, 2, "the view follows the month that came back");
        months.length = 0;
        keyClick(Qt.Key_Right);
        wait(50);
        compare(months.length, 0, "the cursor is in the month that is shown");
        compare(c.month, 2);
    }
    function test_rapid_edits_last_wins() {
        const c = focused(calAccept);
        c._activate(new Date(2026, 2, 6));
        c._activate(new Date(2026, 2, 9));
        compare(day(c.selectedDate), 20260309);
        wait(50);
        compare(day(c.selectedDate), 20260309);
        compare(day(app.day), 20260309);
        const r = focused(calRefuse);
        r._activate(new Date(2026, 2, 6));
        r._activate(new Date(2026, 2, 10));
        compare(day(r.selectedDate), 20260310);
        tryCompare(r, "selectedDate", app.day);
        const p = createTemporaryObject(pickAccept, this);
        p._userSet(new Date(2026, 3, 1));
        p._userSet(new Date(2026, 3, 2));
        compare(day(p.selectedDate), 20260402);
        wait(50);
        compare(day(p.selectedDate), 20260402);
        compare(day(app.day), 20260402);
        const q = createTemporaryObject(pickRefuse, this);
        q._userSet(new Date(2026, 3, 1));
        q._userSet(new Date(2026, 3, 3));
        compare(day(q.selectedDate), 20260403);
        tryCompare(q, "selectedDate", app.day);
    }
    function test_picker_refused_pick_popup_matches() {
        const p = createTemporaryObject(pickRefuse, this);
        open(p);
        keyClick(Qt.Key_Right);
        keyClick(Qt.Key_Return);
        tryVerify(() => !p.opened);
        tryCompare(p, "selectedDate", app.day);
        wait(50);
        compare(day(p._popup.contentItem.selectedDate), day(p.selectedDate));
        compare(day(p.selectedDate), 20260305);
        p.open();
        tryVerify(() => p.opened);
        compare(day(p._popup.contentItem.selectedDate), 20260305);
    }

    Component {
        id: calDefault
        AtlasCalendar {
            locale: Qt.locale("en_US")
            today: new Date(2026, 2, 12)
        }
    }
    Component {
        id: calLiteralMonth
        AtlasCalendar {
            locale: Qt.locale("en_US")
            today: new Date(2026, 2, 12)
            month: 5
        }
    }
    function test_show_date_keeps_the_default_binding() {
        const c = createTemporaryObject(calDefault, this);
        c.showDate(new Date(2026, 6, 1));
        compare(c.month, 6);
        c.selectedDate = new Date(2026, 9, 3);
        compare(c.month, 9, "a later selection still turns the month");
        c.showDate(new Date(2027, 0, 1));
        compare(c.month, 0);
        compare(c.year, 2027);
        c.selectedDate = new Date(2026, 4, 3);
        compare(c.month, 4);
        compare(c.year, 2026);
    }
    function test_show_date_writes_a_literal_month() {
        const c = createTemporaryObject(calLiteralMonth, this);
        compare(c.month, 5);
        c.showDate(new Date(2026, 8, 1));
        compare(c.month, 8, "as in 1.4.0");
        wait(50);
        compare(c.month, 8);
    }
    function test_picker_popup_follows_a_changed_selection() {
        const p = createTemporaryObject(pickAccept, this);
        app.day = new Date(2026, 8, 5);
        p.open();
        tryVerify(() => p.opened);
        compare(p._popup.contentItem.month, 8);
        p.close();
        tryVerify(() => !p.opened);
        app.day = new Date(2026, 10, 7);
        p.open();
        tryVerify(() => p.opened);
        compare(p._popup.contentItem.month, 10);
        compare(p._popup.contentItem.year, 2026);
        p.close();
        tryVerify(() => !p.opened);
        app.day = new Date(2027, 1, 7);
        p.open();
        tryVerify(() => p.opened);
        compare(p._popup.contentItem.month, 1);
        compare(p._popup.contentItem.year, 2027);
    }
}
