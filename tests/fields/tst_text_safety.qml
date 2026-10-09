import QtQuick
import QtTest
import Telamon.Ui

// What a string or a url from outside can do in the controls that draw it
// (docs/SECURITY.md, "Rich text" and "Fetching"): the markup of a suggestion
// is escaped, an editor and a notes text never load a picture, and a picture
// source is checked before it loads.
Item {
    id: root
    width: 400
    height: 300

    Component {
        id: autocomplete
        TelamonAutocompleteField {
            width: 300
            model: ["Berlin", "Bern"]
        }
    }
    Component {
        id: textArea
        TelamonTextArea {
            width: 200
            height: 100
        }
    }
    Component {
        id: notes
        NotesText {
            width: 300
        }
    }
    Component {
        id: avatar
        TelamonAvatar {}
    }
    Component {
        id: card
        TelamonChoiceCard {
            text: "Dark"
        }
    }

    TestCase {
        name: "TextSafety"
        when: windowShown

        // The marked suggestion holds no tag but <b> and </b>, and reads back
        // as the suggestion.
        function readsBack(marked, original) {
            const stripped = marked.replace(/<\/?b>/g, "");
            verify(stripped.indexOf("<") < 0 && stripped.indexOf(">") < 0, "a raw tag in: " + marked);
            compare(stripped.replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&amp;/g, "&"), original);
        }

        function test_autocomplete_escapes_the_suggestion_and_the_query() {
            const f = createTemporaryObject(autocomplete, root);
            const hostile = [
                "<a href=\"https://evil.example\">click</a>",
                "<img src=\"http://127.0.0.1:1/x.png\">",
                "x <b>y</b> &amp; &lt;i&gt; z",
                "</b><a href=x>",
                "aİ<img src=q>b"
            ];
            for (const query of ["", "a", "<", "<a", "<a href", "&", "&amp;", "b>", "<img src=q>", "</b>"]) {
                f.text = query;
                for (const s of hostile) {
                    readsBack(f._mark(s), s);
                }
            }
        }

        function test_text_area_is_plain_text() {
            const t = createTemporaryObject(textArea, root, {text: "<b>bold</b> <img src=\"http://127.0.0.1:1/x.png\">"});
            compare(t.textFormat, TextEdit.PlainText);
            compare(t.getText(0, 200), "<b>bold</b> <img src=\"http://127.0.0.1:1/x.png\">");
        }

        function test_notes_text_drops_what_would_fetch() {
            const allowed = ["a", "b", "i", "u", "s", "p", "br", "hr", "ul", "ol", "li", "em", "strong", "del", "h1", "h2", "h3", "h4", "h5", "h6", "code", "pre", "blockquote"];
            const hostile = [
                "<p>Fixed <img src=\"http://127.0.0.1:1/x.png\"> a bug</p><style>p { color: red }</style><script>alert(1)</script>",
                "<IMG SRC=x><svg onload=1><iframe src=y></iframe><link rel=stylesheet href=z><img src=\"q",
                "<im<img>g src=\"https://x/a.png\">",
                "<i<form>mg src=x>",
                "<sty<style></style>le>@import url(https://x);</style>",
                "<img/src=\"https://x/a.png\">< img src=x><\timg src=x>",
                "<table background=\"https://x/a.png\"><tr><td>x</td></tr></table>",
                "<p style=\"background-image:url(https://x/a.png)\">x</p>",
                "<a href=\"https://example.org\" style=\"background:url(https://x/a.png)\" onclick=\"x\">more</a>",
                "<<<img src=x>>>",
                "<"
            ];
            for (const html of hostile) {
                const n = createTemporaryObject(notes, root, {html: html});
                const body = n.body;
                const tagStart = /<\/?([a-zA-Z0-9]*)/g;
                let m;
                while ((m = tagStart.exec(body)) !== null) {
                    verify(allowed.indexOf(m[1]) >= 0, "tag <" + m[1] + "> left in: " + body + " (from " + html + ")");
                }
                for (const t of body.match(/<[^>]*>/g) ?? []) {
                    verify(/^<\/?[a-z0-9]+>$/.test(t) || /^<a href="[^"<>]*">$/.test(t), "tag with attributes left: " + t + " in " + body);
                }
            }
            const n = createTemporaryObject(notes, root, {
                html: "<p>Fixed a bug</p><p><a href=\"https://example.org\" onclick=\"x\">more</a> &amp; <code>x</code></p>"
            });
            compare(n.body, "<p>Fixed a bug</p><p><a href=\"https://example.org\">more</a> &amp; <code>x</code></p>");
        }

        function test_avatar_loads_local_sources_only() {
            const a = createTemporaryObject(avatar, root);
            const cases = [
                ["file:///usr/share/a.png", "file:///usr/share/a.png"],
                ["qrc:/a/b.png", "qrc:/a/b.png"],
                ["image://theme/x", "image://theme/x"],
                ["http://127.0.0.1:1/a.png", ""],
                ["https://example.org/a.png", ""],
                ["ftp://example.org/a.png", ""],
                ["data:image/png;base64,AAAA", ""],
                ["file://server/share/a.png", ""],
                ["", ""]
            ];
            for (const [src, want] of cases) {
                a.source = src;
                compare(a._safeSource, want, src);
            }
            a.allowRemote = true;
            a.source = "https://example.org/a.png";
            compare(a._safeSource, "https://example.org/a.png");
            a.source = "http://example.org/a.png";
            compare(a._safeSource, "", "http is never loaded");
        }

        function test_choice_card_loads_local_sources_only() {
            const c = createTemporaryObject(card, root);
            c.source = "http://127.0.0.1:1/a.png";
            compare(c._safeSource, "");
            c.source = "https://example.org/a.png";
            compare(c._safeSource, "");
            c.allowRemote = true;
            compare(c._safeSource, "https://example.org/a.png");
            c.source = "qrc:/themes/dark.png";
            compare(c._safeSource, "qrc:/themes/dark.png");
        }
    }
}
