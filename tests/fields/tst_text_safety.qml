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
            const n = createTemporaryObject(notes, root, {
                html: "<p>Fixed <img src=\"http://127.0.0.1:1/x.png\"> a bug</p><style>p { color: red }</style>"
                    + "<script>alert(1)</script><p><a href=\"https://example.org\">more</a></p>"
                    + "<IMG SRC=x><svg onload=1><iframe src=y></iframe><link rel=stylesheet href=z><img src=\"q"
            });
            const body = n.body;
            verify(!/<\s*(img|style|script|svg|iframe|link)/i.test(body), body);
            verify(body.indexOf("alert") < 0 && body.indexOf("color: red") < 0, body);
            verify(body.indexOf("<a href=\"https://example.org\">more</a>") >= 0, "links stay: " + body);
            verify(body.indexOf("Fixed") >= 0 && body.indexOf("a bug") >= 0);
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
