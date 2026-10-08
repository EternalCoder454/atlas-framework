import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import QtTest
import org.kde.kirigami as Kirigami
import Telamon.Ui

// 2.0.6: the visual and accessibility fixes the Telamon Gates screenshots found
// (a code view's bar over its last line, the search field's insets, a sidebar
// title's right padding, a context menu's width, a section row's value, chevron
// and divider, the transparency row's disabled state, the info banner's icon).
Item {
    id: root
    width: 520
    height: 600

    Component {
        id: codeComp
        TelamonCodeView {
            width: 300
            text: "SELECT a_very_long_column_name, another_long_column_name, a_third_column FROM some_table"
        }
    }
    Component {
        id: fitsComp
        TelamonCodeView {
            width: 300
            text: "fits"
        }
    }
    Component {
        id: tallCodeComp
        TelamonCodeView {
            width: 300
            maximumHeight: 60
            text: "SELECT a_very_long_column_name, another_long_column_name, a_third_column FROM some_table\nline 2\nline 3\nline 4\nline 5\nlast line"
        }
    }
    Component {
        id: searchComp
        SearchField {
            width: 260
            text: "abc"
        }
    }
    Component {
        id: sidebarItemComp
        SidebarItem {
            width: 200
            text: "A very very long title that has to be elided"
            symbol: Symbols.Home
            selected: true
        }
    }
    Component {
        id: oneItemMenuComp
        ContextMenu {
            ContextMenuItem { text: "Copy" }
        }
    }
    Component {
        id: longItemMenuComp
        ContextMenu {
            ContextMenuItem { text: "A very very very very very very very very very very very very very very very long label" }
        }
    }
    Component {
        id: sectionComp
        Section {
            width: 400
            SectionRow { title: "License"; value: "MIT" }
            SectionRow { title: "Source"; chevron: true }
            SectionRow { title: "Issues"; chevron: true; iconName: "help-about" }
        }
    }
    Component {
        id: transparencyComp
        Section {
            width: 400
            TelamonTransparencySwitch {}
        }
    }
    Component {
        id: bannerComp
        InfoBanner {
            width: 400
            type: "info"
            text: "An update is available."
            animated: false
        }
    }

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

    TestCase {
        name: "GatesUi"
        when: windowShown

        // 1: the horizontal bar never covers a line of text.
        function test_code_view_bar_does_not_cover_the_last_line() {
            const v = createTemporaryObject(codeComp, root);
            verify(v);
            tryVerify(() => v.implicitHeight > 0);
            const flick = find(v, i => i.contentWidth !== undefined && i.contentY !== undefined);
            const edit = find(v, i => i.readOnly === true && i.cursorRectangle !== undefined);
            verify(flick && edit);
            verify(flick.contentWidth > flick.width, "the line is wider than the view");
            const bar = flick.QQC2.ScrollBar.horizontal;
            verify(bar, "a horizontal bar");
            tryVerify(() => bar.height > 0);
            // The text's bottom edge, in the flickable's own space.
            const textBottom = edit.mapToItem(flick, 0, edit.height).y;
            verify(bar.y >= textBottom - 0.5, "bar at " + bar.y + " covers text ending at " + textBottom);
            verify(flick.height >= textBottom + bar.height - 0.5, "the view has room for the text and the bar");
            // It is a TelamonScrollBar, not the old arrowed one.
            compare(bar.policy, QQC2.ScrollBar.AlwaysOn);
            verify(bar.hoverEnabled, "TelamonScrollBar");
        }

        function test_code_view_reserves_room_only_when_it_scrolls() {
            const wide = createTemporaryObject(codeComp, root);
            const fits = createTemporaryObject(fitsComp, root);
            verify(wide && fits);
            tryVerify(() => wide.implicitHeight > 0 && fits.implicitHeight > 0);
            const bar = find(wide, i => i.contentWidth !== undefined).QQC2.ScrollBar.horizontal;
            tryVerify(() => bar.height > 0);
            fuzzyCompare(wide.implicitHeight - fits.implicitHeight, bar.height, 0.5, "one bar of room");
        }

        function test_code_view_last_line_is_reachable_above_the_bar() {
            const v = createTemporaryObject(tallCodeComp, root);
            verify(v);
            tryVerify(() => v.implicitHeight > 0);
            const flick = find(v, i => i.contentWidth !== undefined && i.contentY !== undefined);
            const edit = find(v, i => i.readOnly === true && i.cursorRectangle !== undefined);
            const bar = flick.QQC2.ScrollBar.horizontal;
            tryVerify(() => bar.height > 0 && flick.contentHeight > flick.height);
            flick.contentY = flick.contentHeight + flick.bottomMargin - flick.height;
            const textBottom = edit.mapToItem(flick, 0, edit.height).y;
            verify(textBottom <= bar.y + 0.5, "the last line ends at " + textBottom + ", the bar starts at " + bar.y);
        }

        // 3: the magnifier and the clear symbol share an inset, and the text clears the magnifier.
        function test_search_field_insets() {
            const f = createTemporaryObject(searchComp, root);
            verify(f);
            const marks = findAll(f, i => i.codepoint !== undefined && i.size !== undefined, []);
            const search = marks.find(m => m.codepoint === Symbols.Search);
            const clear = marks.find(m => m.codepoint === Symbols.Cancel);
            verify(search, "a magnifier symbol");
            verify(clear, "a clear symbol");
            tryVerify(() => clear.visible && clear.width > 0);
            const left = search.mapToItem(f, 0, 0).x;
            const right = f.width - clear.mapToItem(f, clear.width, 0).x;
            fuzzyCompare(left, right, 0.6, "inset of the magnifier and of the clear symbol");
            verify(f.leftPadding >= left + search.width + 6, "the text starts " + (f.leftPadding - left - search.width) + " px after the magnifier");
        }

        // 8: a title that elides keeps the room the icon has on its left.
        function test_sidebar_item_title_keeps_right_padding() {
            const item = createTemporaryObject(sidebarItemComp, root);
            verify(item);
            const title = find(item, i => i.elide === Text.ElideRight && i.text === item.text);
            verify(title, "the title");
            tryVerify(() => title.width > 0 && title.truncated);
            const right = title.mapToItem(item, title.width, 0).x;
            verify(right <= item.width - TelamonStyle.spacingLarge + 0.5, "the title ends at " + right + " of " + item.width);
        }

        // 9: a menu is as wide as its content, between a minimum and a maximum.
        function test_context_menu_width_follows_its_content() {
            const m = createTemporaryObject(oneItemMenuComp, root);
            verify(m);
            m.open();
            tryVerify(() => m.implicitWidth > 0);
            compare(m.implicitWidth, Kirigami.Units.gridUnit * 7, "a one-row menu takes the minimum");
            verify(m.implicitWidth < Kirigami.Units.gridUnit * 11, "narrower than the old fixed minimum");
            m.close();
            const l = createTemporaryObject(longItemMenuComp, root);
            l.open();
            tryVerify(() => l.implicitWidth > Kirigami.Units.gridUnit * 7);
            compare(l.implicitWidth, Kirigami.Units.gridUnit * 24, "a long row is capped");
            l.close();
        }

        // 6: a value, a chevron and a divider share the row's padding.
        function test_section_row_edges_agree() {
            const s = createTemporaryObject(sectionComp, root);
            verify(s);
            const rows = findAll(s, i => i.telamonRow === true, []);
            compare(rows.length, 3);
            tryVerify(() => rows[0].width > 0 && rows[1].width > 0);
            const valueRow = rows[0];
            const label = find(valueRow, i => i.text === "MIT");
            verify(label);
            const valueEnd = label.mapToItem(valueRow, label.width, 0).x;
            fuzzyCompare(valueEnd, valueRow.width - TelamonStyle.spacingLarge, 0.6, "a value ends at the row's padding");
            const chevronRow = rows[1];
            const mark = find(chevronRow, i => i.codepoint === Symbols.ChevronRight);
            verify(mark, "a chevron symbol");
            const slot = mark.parent;
            fuzzyCompare(slot.mapToItem(chevronRow, slot.width, 0).x, valueRow.width - TelamonStyle.spacingLarge, 0.6, "a chevron ends at the row's padding");
            // The divider above the third row: a device pixel thick, padded the same on both sides.
            const iconRow = rows[2];
            const divider = find(iconRow, i => i.parent === iconRow && i.color !== undefined && i.height > 0 && i.height < 1.5 && i.visible);
            verify(divider, "a divider above the row");
            fuzzyCompare(divider.height, 1 / iconRow.Screen.devicePixelRatio, 0.001, "one device pixel");
            fuzzyCompare(iconRow.width - (divider.x + divider.width), TelamonStyle.spacingLarge, 0.6, "right inset");
            verify(divider.x >= TelamonStyle.spacingLarge - 0.5, "left inset");
        }

        // 4: without blur only the switch is disabled, and it shows off.
        function test_transparency_row_without_blur() {
            if (Appearance.blurAvailable) {
                skip("this environment has blur");
            }
            const s = createTemporaryObject(transparencyComp, root);
            verify(s);
            const row = find(s, i => i.telamonRow === true);
            verify(row);
            verify(row.enabled, "the row is not disabled");
            compare(row.opacity, 1);
            verify(!row.switchEnabled);
            verify(!row.switchChecked, "the switch shows off");
            const sw = find(row, i => i.toString().indexOf("TelamonSwitch") === 0);
            verify(sw);
            verify(!sw.enabled);
            verify(!sw.checked);
            // The explanation is still the row's own text, not a dimmed copy.
            const sub = find(row, i => i.text === row.subtitle);
            verify(sub);
            verify(sub.opacity >= 0.65, "subtitle opacity " + sub.opacity);
        }

        // 7: the info icon is drawn in the accent, not a theme's blue.
        function test_info_banner_icon_uses_the_palette() {
            const b = createTemporaryObject(bannerComp, root);
            verify(b);
            const mark = find(b, i => i.codepoint === Symbols.Info);
            verify(mark, "an info symbol");
            verify(Qt.colorEqual(mark.color, TelamonStyle.accent), "icon colour " + mark.color);
            verify(!find(b, i => i.source === "dialog-information"), "no theme icon");
        }
    }
}
