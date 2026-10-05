import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import QtTest
import Atlas.Ui

// 1.5.0 display items: AtlasAboutPage rows and links, AtlasDetailGrid title
// and footer, AtlasBreadcrumb.hiddenText and AtlasCodeView.inset.
Item {
    id: root
    width: 520
    height: 600

    Component {
        id: gridComp
        AtlasDetailGrid {
            width: 400
            model: [
                { label: "Version", value: "1.4.0" },
                { label: "Checksum", value: "9f86", copyable: true }
            ]
        }
    }
    Component {
        id: aboutComp
        AtlasAboutPage {
            width: 520
            height: 600
        }
    }
    Component {
        id: crumbComp
        AtlasBreadcrumb {
            width: 120
            segments: [{ title: "Home" }, { title: "Documents" }, { title: "Projects" }, { title: "Atlas" }, { title: "Deep" }]
        }
    }
    Component {
        id: codeComp
        AtlasCodeView {
            width: 300
            wrap: true
            framed: false
            text: "x"
        }
    }

    // The first item under `item` (depth first) for which `match` is true.
    function find(item, match) {
        if (match(item)) {
            return item;
        }
        for (const child of item.children) {
            const hit = find(child, match);
            if (hit) {
                return hit;
            }
        }
        return null;
    }
    function findAll(item, match, out) {
        if (match(item)) {
            out.push(item);
        }
        for (const child of item.children) {
            findAll(child, match, out);
        }
        return out;
    }
    function row(page, title) {
        return findAll(page, i => i.title === title && i.chevron !== undefined, [])[0] ?? null;
    }

    TestCase {
        name: "Display"
        when: windowShown

        function test_detail_grid_title_and_footer() {
            const g = createTemporaryObject(gridComp, root);
            verify(g);
            tryVerify(() => g.implicitHeight > 0);
            wait(50);
            const plain = g.implicitHeight;
            compare(g.title, "");
            compare(g.footer, "");
            verify(!g.framed);
            g.title = "Details";
            tryVerify(() => g.implicitHeight > plain);
            const withTitle = g.implicitHeight;
            g.footer = "A note";
            tryVerify(() => g.implicitHeight > withTitle);
            compare(g.Accessible.name, "Details");
            compare(g.Accessible.description, "A note");
            g.title = "";
            g.footer = "";
            tryCompare(g, "implicitHeight", plain);
        }

        function test_detail_grid_framed_pads_the_grid() {
            const g = createTemporaryObject(gridComp, root);
            verify(g);
            tryVerify(() => g.implicitHeight > 0);
            wait(50);
            const plain = g.implicitHeight;
            g.framed = true;
            tryVerify(() => g.implicitHeight > plain);
            // The card is the first Rectangle with a border.
            const card = find(g, i => i.border !== undefined && i.border.width === 1);
            verify(card, "a framed grid draws a card");
            fuzzyCompare(card.width, g.width, 0.5);
        }

        function test_breadcrumb_hidden_text() {
            const c = createTemporaryObject(crumbComp, root);
            verify(c);
            compare(c.hiddenText, "Hidden folders");
            c.hiddenText = "Verborgen";
            const more = find(c, i => i.Accessible.name === "Verborgen");
            verify(more, "the … button is named by hiddenText");
            verify(!find(c, i => i.Accessible.name === "Hidden folders"));
        }

        function test_code_view_inset() {
            const v = createTemporaryObject(codeComp, root);
            verify(v);
            const edit = find(v, i => i.selectByMouse !== undefined && i.readOnly === true);
            verify(edit);
            tryVerify(() => edit.width > 0);
            fuzzyCompare(edit.width, 300, 0.5);
            v.inset = true;
            tryVerify(() => Math.abs(edit.width - (300 - 2 * AtlasStyle.spacingLarge)) < 0.5);
            // A framed view has the room already: inset changes nothing.
            v.framed = true;
            tryVerify(() => Math.abs(edit.width - (300 - 2 * AtlasStyle.spacingLarge)) < 0.5);
            v.inset = false;
            wait(50);
            fuzzyCompare(edit.width, 300 - 2 * AtlasStyle.spacingLarge, 0.5);
        }

        function test_about_system_rows() {
            const p = createTemporaryObject(aboutComp, root);
            verify(p);
            const qt = findAll(p, i => i.title === "Qt", [])[0];
            verify(qt, "the Qt row exists");
            tryVerify(() => qt.visible);
            p.showSystemRows = false;
            tryVerify(() => !qt.visible);
            const os = findAll(p, i => i.title === "Operating system", [])[0];
            verify(!os || !os.visible);
            // The bug report keeps them.
            verify(p.systemInfo().indexOf("Qt: ") >= 0);
        }

        function test_about_links() {
            const p = createTemporaryObject(aboutComp, root);
            verify(p);
            p.links = [
                { title: "Homepage", url: "https://example.org/" },
                { title: "Mail", url: "mailto:a@example.org" },
                { title: "Bad", url: "file:///etc/passwd" },
                { title: "Custom", url: "atlas-evil://x" },
                { title: "Empty", url: "" },
                { url: "https://example.org/untitled" }
            ];
            tryVerify(() => p._links.length === 2);
            compare(p._links[0].title, "Homepage");
            compare(p._links[1].title, "Mail");
            tryVerify(() => row(p, "Homepage") && row(p, "Homepage").visible);
            tryVerify(() => row(p, "Mail") !== null);
            verify(row(p, "Bad") === null);
            verify(row(p, "Custom") === null);
            verify(row(p, "Empty") === null);
            // The built-in rows are replaced.
            const src = row(p, "Source code");
            verify(!src || !src.visible);
            const issues = row(p, "Report a problem");
            verify(!issues || !issues.visible);
        }

        function test_about_links_ignores_junk() {
            const p = createTemporaryObject(aboutComp, root);
            verify(p);
            p.links = "not a list";
            compare(p._links.length, 0);
            p.links = [null, 7, { title: 5, url: "https://x.org" }, { title: "NoUrl" }, { title: "Nul", url: null }];
            compare(p._links.length, 0);
            compare(p._customLinks, false);
        }

        function test_about_links_accepts_url_values() {
            const p = createTemporaryObject(aboutComp, root);
            verify(p);
            p.links = [
                { title: "Resolved", url: Qt.resolvedUrl("https://example.org/a") },
                { title: "Js", url: "javascript:alert(1)" },
                { title: "File", url: Qt.resolvedUrl("file:///etc/passwd") },
                { title: "Spaced", url: "  HTTPS://example.org/b " }
            ];
            compare(p._links.length, 2);
            compare(p._links[0].title, "Resolved");
            compare(p._links[1].title, "Spaced");
        }

        function test_about_all_invalid_links_keep_the_built_in_rows() {
            const p = createTemporaryObject(aboutComp, root);
            verify(p);
            p.links = [{ title: "Bad", url: "file:///x" }, { url: "https://x.org" }];
            compare(p._links.length, 0);
            compare(p._customLinks, false);
            const src = row(p, "Source code");
            verify(src, "the built-in row is still there");
            compare(src.visible, AtlasApp.sourceUrl.length > 0);
            p.links = [{ title: "Good", url: "https://x.org" }];
            compare(p._customLinks, true);
            tryVerify(() => !row(p, "Source code").visible);
        }

        // --- the AtlasDetailGrid rewrite: cells built from Loaders ---

        function gridModel(extra) {
            return [
                { label: "Version", value: "1.4.0" },
                { label: "Checksum", value: "9f86d081", mono: true, copyable: true },
                { label: "Path", value: "/usr/share/atlas", copyable: false }
            ].concat(extra ?? []);
        }
        function values(g) {
            return findAll(g, i => i.selectByMouse !== undefined && i.readOnly === true, []);
        }
        function copyButtons(g) {
            return findAll(g, i => i.Accessible.role === Accessible.Button && String(i.Accessible.name).startsWith("Copy "), []);
        }
        function labelItem(g, text) {
            return find(g, i => i.elide !== undefined && i.text === text && i.selectByMouse === undefined);
        }
        function makeGrid(props) {
            const g = createTemporaryObject(gridComp, root, props ?? {});
            verify(g);
            if (g._count > 0) {
                tryVerify(() => g.implicitHeight > 0);
            }
            wait(50);
            return g;
        }

        function test_grid_mono_and_normal_font() {
            const g = makeGrid({ model: gridModel() });
            tryCompare(values(g), "length", 3);
            const v = values(g);
            compare(v[0].font.family, AtlasStyle.fontFamily);
            compare(v[1].font.family, AtlasStyle.monoFamily);
            compare(v[2].font.family, AtlasStyle.fontFamily);
        }

        function test_grid_copy_button_only_on_copyable_cells() {
            const g = makeGrid({ model: gridModel() });
            tryCompare(values(g), "length", 3);
            const b = copyButtons(g);
            compare(b.length, 1);
            compare(b[0].Accessible.name, "Copy Checksum");
        }

        function test_grid_accessible_names() {
            const g = makeGrid({ model: gridModel() });
            tryCompare(values(g), "length", 3);
            const v = values(g);
            compare(v[0].Accessible.name, "Version: 1.4.0");
            compare(v[1].Accessible.name, "Checksum: 9f86d081");
            compare(v[0].Accessible.role, Accessible.StaticText);
            // The labels are not read twice.
            verify(labelItem(g, "Version").Accessible.ignored);
            // A plain grid adds no group node; a titled one is a group.
            verify(g.Accessible.role !== Accessible.Grouping);
            g.title = "T";
            compare(g.Accessible.role, Accessible.Grouping);
        }

        function test_grid_copy_button_copies_and_shows_copied() {
            const g = makeGrid({ model: gridModel() });
            tryCompare(copyButtons(g), "length", 1);
            const b = copyButtons(g)[0];
            AtlasClipboard.setText("before");
            verify(!b.copied);
            mouseClick(b);
            compare(AtlasClipboard.text(), "9f86d081");
            verify(b.copied);
            // The text edit is left unselected.
            compare(values(g)[1].selectedText, "");
            tryVerify(() => !b.copied, 4000);
        }

        function test_grid_rows_added_and_removed() {
            const g = makeGrid({ model: gridModel() });
            tryCompare(values(g), "length", 3);
            const h3 = g.implicitHeight;
            g.model = gridModel([{ label: "Extra", value: "x", copyable: true }]);
            tryCompare(values(g), "length", 4);
            tryCompare(copyButtons(g), "length", 2);
            tryVerify(() => g.implicitHeight > h3);
            g.model = [];
            tryCompare(values(g), "length", 0);
            compare(copyButtons(g).length, 0);
            tryCompare(g, "implicitHeight", 0);
            g.model = gridModel().slice(0, 1);
            tryCompare(values(g), "length", 1);
        }

        function test_grid_copyable_and_mono_toggled_at_runtime() {
            const g = makeGrid({ model: gridModel() });
            tryCompare(copyButtons(g), "length", 1);
            g.model = [
                { label: "Version", value: "1.4.0", copyable: true, mono: true },
                { label: "Checksum", value: "9f86d081" },
                { label: "Path", value: "/usr/share/atlas", copyable: true }
            ];
            tryCompare(copyButtons(g), "length", 2);
            const v = values(g);
            compare(v[0].font.family, AtlasStyle.monoFamily);
            compare(v[1].font.family, AtlasStyle.fontFamily);
            compare(copyButtons(g)[0].Accessible.name, "Copy Version");
        }

        function test_grid_tab_lands_on_copy_buttons_only() {
            const g = makeGrid({
                model: [
                    { label: "A", value: "1", copyable: true },
                    { label: "B", value: "2" },
                    { label: "C", value: "3", copyable: true }
                ]
            });
            tryCompare(copyButtons(g), "length", 2);
            const win = root.Window.window;
            const seen = [];
            for (let i = 0; i < 6; ++i) {
                keyClick(Qt.Key_Tab);
                const f = win.activeFocusItem;
                if (f && g.contains(g.mapFromItem(f, 0, 0)) && f !== win.contentItem) {
                    seen.push(f);
                }
            }
            verify(seen.length >= 2, "Tab reached the copy buttons");
            for (const f of seen) {
                verify(f.selectByMouse === undefined, "no TextEdit takes Tab");
                verify(String(f.Accessible.name).startsWith("Copy "), "only copy buttons: " + f);
            }
        }

        function test_grid_layouts_stacked_one_and_many_columns() {
            const m = [
                { label: "One", value: "1" },
                { label: "Two", value: "2" },
                { label: "Three", value: "3" },
                { label: "Four", value: "4" }
            ];
            // Wide, one column: the value sits beside its label.
            let g = makeGrid({ model: m, width: 500 });
            tryCompare(values(g), "length", 4);
            let l = labelItem(g, "One").mapToItem(g, 0, 0);
            let v = values(g)[0].mapToItem(g, 0, 0);
            verify(v.x > l.x + 1, "value beside label");
            fuzzyCompare(v.y, l.y, 6);
            let l2 = labelItem(g, "Two").mapToItem(g, 0, 0);
            verify(l2.y > l.y, "second pair below the first");
            g.destroy();

            // Narrow: stacked, the value under its label.
            g = makeGrid({ model: m, width: 150 });
            tryCompare(values(g), "length", 4);
            verify(g._stacked);
            l = labelItem(g, "One").mapToItem(g, 0, 0);
            v = values(g)[0].mapToItem(g, 0, 0);
            fuzzyCompare(v.x, l.x, 1);
            verify(v.y > l.y, "value under label");
            g.destroy();

            // Wide with columns: two pairs per row.
            g = makeGrid({ model: m, width: 900, columns: 2, columnsBreakpoint: 10 });
            tryCompare(values(g), "length", 4);
            compare(g._pairs, 2);
            l = labelItem(g, "One").mapToItem(g, 0, 0);
            l2 = labelItem(g, "Two").mapToItem(g, 0, 0);
            fuzzyCompare(l2.y, l.y, 1);
            verify(l2.x > l.x + 100, "second pair in the next column");
            const l3 = labelItem(g, "Three").mapToItem(g, 0, 0);
            verify(l3.y > l.y, "third pair on the next row");
            // Too narrow for the columns asked: fewer per row.
            g.width = 300;
            tryCompare(g, "_pairs", 1);
        }

        function test_grid_empty_model_adds_no_gap() {
            const g = makeGrid({ model: [] });
            compare(g.implicitHeight, 0);
            g.title = "T";
            g.footer = "F";
            wait(50);
            const both = g.implicitHeight;
            g.footer = "";
            tryVerify(() => g.implicitHeight < both);
            const titleOnly = g.implicitHeight;
            g.title = "";
            tryCompare(g, "implicitHeight", 0);
            // Framed and empty: no card either.
            g.framed = true;
            wait(50);
            compare(g.implicitHeight, 0);
            verify(titleOnly > 0);
        }
    }
}
