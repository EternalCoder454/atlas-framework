import QtQuick
import QtTest
import Telamon.Ui

// TelamonPreferencesDialog and TelamonPreferencesPage (docs/api-1.5.0.md, item
// 27): the sidebar only for two pages or more, page switching, the search over
// labels and help, choosing a result, Escape clearing the search before it
// closes, and the dialog's settings reaching the entries.
TestCase {
    id: tc
    name: "Preferences"
    width: 1000
    height: 700
    visible: true
    when: windowShown

    QtObject {
        id: app
        property int page: 0
    }

    Component {
        id: storeComp
        TelamonSettings {
            fileName: "telamon-prefs-test"
            group: "Prefs"
        }
    }

    Component {
        id: dialogComp
        TelamonPreferencesDialog {
            id: d
            property alias hidden: hidden
            property alias port: port
            property alias portEntry: portEntry
            property alias needed: needed
            property alias pageB: pageB
            property alias pageA: pageA
            TelamonPreferencesPage {
                id: pageA
                title: "General"
                symbol: Symbols.Settings
                Section {
                    TelamonFormEntry {
                        label: "Show hidden files"
                        help: "Dotfiles too"
                        settingKey: "Hidden"
                        TelamonSwitch {
                            id: hidden
                        }
                    }
                    TelamonFormEntry {
                        label: "Thing hidden by the app"
                        visible: false
                        TelamonSwitch {
                        }
                    }
                    TelamonFormEntry {
                        label: "Disabled thing"
                        enabled: false
                        TelamonSwitch {
                        }
                    }
                }
            }
            TelamonPreferencesPage {
                id: pageB
                title: "Network"
                symbol: Symbols.Language
                Section {
                    TelamonFormEntry {
                        id: portEntry
                        label: "Proxy port"
                        TelamonSpinBox {
                            id: port
                            from: 1
                            to: 65535
                        }
                    }
                    TelamonFormEntry {
                        label: "Thing hidden on another page"
                        visible: false
                        TelamonSwitch {
                        }
                    }
                    TelamonFormEntry {
                        id: needed
                        label: "Needed on another page"
                        required: true
                        TelamonTextField {
                        }
                    }
                }
            }
        }
    }

    Component {
        id: oneComp
        TelamonPreferencesDialog {
            TelamonPreferencesPage {
                title: "Only"
                Section {
                    TelamonFormEntry {
                        label: "Thing"
                        TelamonSwitch {
                        }
                    }
                }
            }
        }
    }

    Component {
        id: boundComp
        TelamonPreferencesDialog {
            currentIndex: app.page
            TelamonPreferencesPage {
                title: "One"
            }
            TelamonPreferencesPage {
                title: "Two"
            }
        }
    }

    function find(item, test) {
        for (const c of item.children) {
            if (test(c)) {
                return c;
            }
            const r = find(c, test);
            if (r) {
                return r;
            }
        }
        return null;
    }

    function open(comp, props) {
        const d = createTemporaryObject(comp, tc, props || {});
        verify(d);
        d.open();
        tryVerify(() => d.opened);
        return d;
    }

    function search(d) {
        return find(d.contentItem, i => i.objectName === "telamonPreferencesSearch");
    }

    function test_one_page_has_no_sidebar() {
        const d = open(oneComp);
        const nav = find(d.contentItem, i => i.objectName === "telamonPreferencesSidebar");
        verify(nav);
        verify(!nav.visible);
        const d2 = open(dialogComp);
        const nav2 = find(d2.contentItem, i => i.objectName === "telamonPreferencesSidebar");
        verify(nav2.visible);
    }

    function test_pages_switch() {
        const d = open(dialogComp);
        compare(d.currentIndex, 0);
        verify(d.pageA.visible);
        verify(!d.pageB.visible);
        const item = find(d.contentItem, i => i.text === "Network" && i.selected !== undefined);
        verify(item);
        mouseClick(item);
        tryCompare(d, "currentIndex", 1);
        verify(!d.pageA.visible);
        verify(d.pageB.visible);
    }

    function test_an_app_binding_on_currentIndex_stays_bound() {
        app.page = 0;
        const d = open(boundComp);
        const item = find(d.contentItem, i => i.text === "Two" && i.selected !== undefined);
        mouseClick(item);
        compare(d.currentIndex, 1, "shows the choice");
        tryCompare(d, "currentIndex", 0);
        app.page = 1;
        compare(d.currentIndex, 1, "still bound");
    }

    function test_search_lists_matches_by_label_and_help() {
        const d = open(dialogComp);
        const s = search(d);
        s.text = "port";
        tryVerify(() => d._results.length === 1);
        compare(d._results[0].text, "Proxy port");
        compare(d._results[0].pageTitle, "Network");
        s.text = "DOTFILES";
        tryVerify(() => d._results.length === 1 && d._results[0].text === "Show hidden files");
        const row = find(d.contentItem, i => i.telamonRow === true && i.title === "Show hidden files");
        verify(row);
        compare(row.subtitle, "General");
    }

    function test_search_skips_disabled_entries() {
        const d = open(dialogComp);
        search(d).text = "thing";
        tryVerify(() => d._searching);
        compare(d._results.length, 0);
    }

    function test_search_skips_entries_the_app_hid() {
        const d = open(dialogComp);
        search(d).text = "hidden";
        tryVerify(() => d._searching);
        tryVerify(() => d._results.length === 1);
        compare(d._results[0].text, "Show hidden files", "neither hidden entry is found, on this page or another");
        search(d).text = "Thing hidden";
        tryVerify(() => d._results.length === 0);
    }

    function test_a_required_entry_on_another_page_still_counts() {
        const d = open(dialogComp);
        verify(d.pageB.visible === false || d.currentIndex === 0);
        verify(!d.needed.valid, "a page that is not shown does not make an entry valid");
    }

    function test_search_with_no_match_shows_the_empty_state() {
        const d = open(dialogComp);
        search(d).text = "zzz";
        tryVerify(() => d._searching);
        compare(d._results.length, 0);
        const empty = find(d.contentItem, i => i.title === "No settings found");
        verify(empty);
        tryVerify(() => empty.visible);
    }

    function test_choosing_a_result_shows_the_page_and_focuses_the_control() {
        const d = open(dialogComp);
        const s = search(d);
        s.text = "port";
        tryVerify(() => d._results.length === 1);
        const spy = createTemporaryObject(spyComp, tc, {target: d.portEntry});
        // The search hit, not the hidden page's own row of that name. It is
        // found as soon as it is visible, a polish before it has a size: a
        // click then lands beside it (width 0), so wait for the layout.
        let row = null;
        tryVerify(() => (row = find(d.contentItem, i => i.telamonRow === true && i.title === "Proxy port" && i.visible && i.chevron === true && i.width > 0)) !== null);
        mouseClick(row);
        tryCompare(d, "currentIndex", 1);
        compare(s.text, "", "the search is cleared");
        tryVerify(() => d.port.activeFocus, 3000);
        if (!TelamonStyle.reducedMotion) {
            tryVerify(() => spy.count > 0, 3000, "the row flashes");
        } else {
            wait(100);
            compare(spy.count, 0, "no flash under reduced motion");
        }
    }
    Component {
        id: spyComp
        SignalSpy {
            signalName: "_flashingChanged"
        }
    }

    function test_escape_clears_the_search_first_then_closes() {
        const d = open(dialogComp);
        const s = search(d);
        s.text = "port";
        tryVerify(() => d._searching);
        s.forceActiveFocus();
        keyClick(Qt.Key_Escape);
        compare(s.text, "");
        verify(d.visible, "still open");
        keyClick(Qt.Key_Escape);
        tryVerify(() => !d.visible);
    }

    function test_escape_on_a_result_row_clears_the_search_too() {
        const d = open(dialogComp);
        const s = search(d);
        s.text = "port";
        tryVerify(() => d._results.length === 1);
        const row = find(d.contentItem, i => i.telamonRow === true && i.title === "Proxy port");
        row.forceActiveFocus();
        keyClick(Qt.Key_Escape);
        compare(s.text, "");
        verify(d.visible, "still open");
    }

    function test_the_dialogs_settings_reach_the_entries() {
        const st = createTemporaryObject(storeComp, tc);
        st.setValue("Hidden", true);
        const d = open(dialogComp, {settings: st});
        tryVerify(() => d.hidden.checked);
        wait(50);
        d.hidden.forceActiveFocus();
        keyClick(Qt.Key_Space);
        compare(st.value("Hidden", true), false);
    }

    function test_the_page_is_remembered_by_stateKey() {
        const d = open(dialogComp, {stateKey: "t1"});
        d._choose(1);
        tryCompare(d, "currentIndex", 1);
        if (!d._store.flush()) {
            skip("this run has no settings file");
        }
        d.close();
        const d2 = open(dialogComp, {stateKey: "t1"});
        tryCompare(d2, "currentIndex", 1);
    }
}
