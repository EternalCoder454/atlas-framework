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
            p.links = [null, 7, { title: 5, url: "https://x.org" }, { title: "Ok", url: { toString() { return "https://x.org"; } } }];
            compare(p._links.length, 0);
        }
    }
}
