import QtQuick
import QtQuick.Layouts
import QtTest
import Telamon.Ui

// TelamonSidebar.footer, SidebarGroup.symbol and badge, and the edit rule for
// filterText (the app's binding survives text typed in the built-in field).
Item {
    id: root
    width: 400
    height: 400

    Component {
        id: footerComp
        TelamonSidebar {
            width: 240
            height: 300
            property alias settings: settingsItem
            property alias first: firstItem
            footer: [
                SidebarItem { id: settingsItem; Layout.fillWidth: true; text: "Settings" }
            ]
            SidebarItem { id: firstItem; Layout.fillWidth: true; text: "One"; selected: true }
            SidebarItem { Layout.fillWidth: true; text: "Two" }
        }
    }
    Component {
        id: groupComp
        SidebarGroup {
            width: 200
            text: "Disk"
            symbol: Symbols.Home
            badge: "dialog-warning"
            badgeText: "1 problem"
        }
    }
    Component {
        id: dynComp
        TelamonSidebar {
            width: 240
            height: 300
            property int lateCount: 0
            property bool hidden: false
            property alias firstItem: one
            footer: [
                Repeater {
                    model: lateCount
                    SidebarItem { required property int index; Layout.fillWidth: true; text: "Late " + index; visible: !hidden }
                }
            ]
            SidebarItem { id: one; Layout.fillWidth: true; text: "One"; selected: true }
        }
    }
    Component {
        id: tallFooterComp
        TelamonSidebar {
            width: 240
            height: 200
            property alias last: lastItem
            footer: [
                Repeater {
                    model: 11
                    SidebarItem { required property int index; Layout.fillWidth: true; text: "F" + index }
                },
                SidebarItem { id: lastItem; Layout.fillWidth: true; text: "Last" }
            ]
            SidebarItem { Layout.fillWidth: true; text: "One"; selected: true }
        }
    }
    QtObject {
        id: appModel
        property string q: ""
    }
    Component {
        id: acceptComp
        TelamonSidebar {
            width: 240
            height: 300
            showFilter: true
            filterText: appModel.q
            onFilterTextChanged: appModel.q = filterText
            SidebarItem { Layout.fillWidth: true; text: "One" }
        }
    }
    Component {
        id: refuseComp
        TelamonSidebar {
            width: 240
            height: 300
            showFilter: true
            filterText: appModel.q
            property int changes: 0
            onFilterTextChanged: changes++
            SidebarItem { Layout.fillWidth: true; text: "One" }
        }
    }
    Component {
        id: unboundComp
        TelamonSidebar {
            width: 240
            height: 300
            showFilter: true
            SidebarItem { Layout.fillWidth: true; text: "One" }
        }
    }

    TestCase {
        name: "SidebarFooter"
        when: windowShown

        function test_footer_is_pinned_and_unfiltered() {
            const sb = createTemporaryObject(footerComp, root);
            verify(sb);
            tryVerify(() => sb.settings.height > 0);
            const y = sb.settings.mapToItem(sb, 0, 0).y;
            verify(y > sb.first.mapToItem(sb, 0, 0).y, "the footer is below the list");
            verify(y + sb.settings.height <= sb.height, "inside the sidebar");
            sb.filterText = "zzz";
            wait(50);
            verify(!sb.first.visible, "the list is filtered");
            verify(sb.settings.visible, "the footer never hides");
        }

        function test_footer_shares_compact_and_selection() {
            const sb = createTemporaryObject(footerComp, root);
            sb.compact = true;
            tryCompare(sb.settings, "compact", true);
            sb.settings.selected = true;
            sb.first.selected = false;
            wait(50);
            verify(sb.settings.selected);
        }

        function test_current_index_with_a_filter() {
            const sb = createTemporaryObject(footerComp, root);
            sb.filterText = "Two";
            wait(50);
            sb.currentIndex = 2;
            wait(50);
            verify(sb.settings.visible, "the footer entry at index 2 stays");
            compare(sb.currentIndex, 2);
        }

        function test_footer_changed_at_runtime() {
            const sb = createTemporaryObject(dynComp, root);
            wait(50);
            sb.lateCount = 2;
            tryVerify(() => sb.firstItem.parent && sb.height > 0 && footerEntries(sb).length === 2);
            const e = footerEntries(sb);
            tryVerify(() => e[0].height > 0 && e[0].mapToItem(sb, 0, 0).y > sb.firstItem.mapToItem(sb, 0, 0).y + sb.firstItem.height, 2000, "the late entries are pinned below the list");
            sb.hidden = true;
            sb.lateCount = 0;
            tryVerify(() => footerEntries(sb).length === 0);
        }

        function footerEntries(sb) {
            const out = [];
            const walk = it => {
                for (const c of it.children) {
                    if (c.selected !== undefined && typeof c.text === "string" && c.text.indexOf("Late") === 0) {
                        out.push(c);
                    }
                    walk(c);
                }
            };
            walk(sb);
            return out;
        }

        function test_tab_crosses_from_list_to_footer() {
            const sb = createTemporaryObject(footerComp, root);
            sb.first.forceActiveFocus(Qt.TabFocusReason);
            verify(sb.first.activeFocus);
            keyClick(Qt.Key_Tab);
            keyClick(Qt.Key_Tab);
            tryVerify(() => sb.settings.activeFocus, 1000, "Tab reaches the footer after the list");
        }

        function test_focus_scrolls_a_footer_entry_into_view() {
            const sb = createTemporaryObject(tallFooterComp, root);
            wait(100);
            sb.last.forceActiveFocus(Qt.TabFocusReason);
            tryVerify(() => {
                const y = sb.last.mapToItem(sb, 0, 0).y;
                return y >= sb.height / 2 - 1 && y + sb.last.height <= sb.height + 1;
            }, 2000, "the last footer entry is inside the footer region");
        }

        function test_group_symbol_and_badge() {
            const g = createTemporaryObject(groupComp, root);
            verify(g);
            compare(g.symbol, Symbols.Home);
            compare(g.badge, "dialog-warning");
            compare(g.badgeText, "1 problem");
            compare(g._header.symbol, Symbols.Home);
        }
    }

    TestCase {
        name: "SidebarFilterEdit"
        when: windowShown

        function field(item) {
            if (item.query !== undefined && item.placeholderText !== undefined) {
                return item;
            }
            for (const c of item.children) {
                const f = field(c);
                if (f) {
                    return f;
                }
            }
            return null;
        }
        function init() {
            appModel.q = "";
        }

        function test_bound_and_accepting() {
            const sb = createTemporaryObject(acceptComp, root);
            const f = field(sb);
            verify(f);
            f.text = "ab";
            tryCompare(sb, "filterText", "ab");
            wait(50);
            compare(appModel.q, "ab");
            compare(sb.filterText, "ab");
            appModel.q = "zz";
            compare(sb.filterText, "zz", "the binding is intact");
        }

        function test_bound_and_refusing() {
            const sb = createTemporaryObject(refuseComp, root);
            const f = field(sb);
            f.text = "ab";
            tryVerify(() => sb.changes >= 2, 2000, "the edit is seen, then taken back");
            tryCompare(sb, "filterText", "", 1000, "springs back");
            tryCompare(f, "text", "", 1000, "the field follows");
            appModel.q = "x";
            compare(sb.filterText, "x", "the binding is intact");
        }

        function test_unbound_keeps_the_edit() {
            const sb = createTemporaryObject(unboundComp, root);
            const f = field(sb);
            f.text = "ab";
            tryCompare(sb, "filterText", "ab");
            wait(50);
            compare(sb.filterText, "ab");
            compare(f.text, "ab");
        }
    }
}
