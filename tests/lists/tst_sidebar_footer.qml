import QtQuick
import QtQuick.Layouts
import QtTest
import Atlas.Ui

// AtlasSidebar.footer, SidebarGroup.symbol and badge, and the edit rule for
// filterText (the app's binding survives text typed in the built-in field).
Item {
    id: root
    width: 400
    height: 400

    Component {
        id: footerComp
        AtlasSidebar {
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
    QtObject {
        id: appModel
        property string q: ""
    }
    Component {
        id: acceptComp
        AtlasSidebar {
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
        AtlasSidebar {
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
        AtlasSidebar {
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
