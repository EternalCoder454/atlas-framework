import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

// Release notes. The backend sends a safe HTML fragment (no images, no styles,
// https links only); this styles it with Telamon colours and spacing. The page
// decides, through backend.isSafeLink, whether a clicked link opens.
Text {
    id: root

    // The safe HTML fragment (backend.notesHtml).
    property string html
    // The same notes as plain text, for screen readers.
    property string plain
    signal linkClicked(string link)

    readonly property bool darkTheme: Kirigami.Theme.backgroundColor.hslLightness < 0.5
    readonly property color accent: darkTheme ? Qt.lighter(TelamonStyle.accent, 1.45) : TelamonStyle.accent
    readonly property string css: "a { color: " + accent + "; text-decoration: underline; } " + "h3 { font-size: large; } h4, h5 { font-size: medium; } h3, h4, h5 { margin-top: 10px; margin-bottom: 2px; font-weight: bold; } " + "p { margin-top: 3px; margin-bottom: 3px; } " + "ul, ol { margin-top: 2px; margin-bottom: 2px; margin-left: 0px; -qt-list-indent: 1; } " + "li { margin-top: 1px; margin-bottom: 1px; } " + "code, pre { font-family: '" + Kirigami.Theme.fixedWidthFont.family + "'; } " + "blockquote { margin-left: 8px; color: " + TelamonStyle.alpha(Kirigami.Theme.textColor, 0.7) + "; }"

    // The section title already says "What's new in X": drop a leading heading
    // that repeats it.
    //
    // Qt's rich text loads a picture named by an <img> (over the network, for
    // an http or https address), a background image, and applies <style>
    // rules: the backend sends none of that, and whatever slips through is
    // dropped here, so the notes can never make this item fetch anything.
    // _safeMarkup lets through only the tags of a release note, without their
    // attributes (an <a> keeps its href) and escapes every other "<".
    readonly property string body: root._safeMarkup(html).replace(/^\s*<h[1-5][^>]*>\s*What(?:'|&#39;|&#x27;|&rsquo;|\u2019)?s new[^<]*<\/h[1-5]>/i, "")

    readonly property var _allowedTags: ({
            "a": 1, "b": 1, "i": 1, "u": 1, "s": 1, "p": 1, "br": 1, "hr": 1, "ul": 1, "ol": 1, "li": 1, "em": 1, "strong": 1, "del": 1,
            "h1": 1, "h2": 1, "h3": 1, "h4": 1, "h5": 1, "h6": 1, "code": 1, "pre": 1, "blockquote": 1
        })

    // One pass over the markup: each tag is rebuilt from its name (and, for a
    // link, its href) or dropped; a "<" that starts no tag is text. Nothing
    // the pass writes can be read as a different tag by a second look.
    function _safeMarkup(markup: string): string {
        return markup.replace(/<(\/?)\s*([a-zA-Z][a-zA-Z0-9]*)\b([^<>]*)>|</g, (m, close, name, rest) => {
            if (name === undefined) {
                return "&lt;";
            }
            const tag = name.toLowerCase();
            if (root._allowedTags[tag] !== 1) {
                return "";
            }
            if (close === "/") {
                return "</" + tag + ">";
            }
            if (tag === "a") {
                const href = /\bhref\s*=\s*(?:"([^"]*)"|'([^']*)')/i.exec(rest);
                const value = href ? (href[1] !== undefined ? href[1] : href[2]) : "";
                return value.length > 0 ? "<a href=\"" + value.replace(/"/g, "&quot;") + "\">" : "<a>";
            }
            return "<" + tag + ">";
        });
    }

    text: "<style>" + css + "</style>" + body
    Accessible.role: Accessible.StaticText
    Accessible.name: root.plain.replace(/^\s*What(?:'|\u2019)?s new[^\n]*\n?/i, "")
    textFormat: Text.RichText
    wrapMode: Text.Wrap
    color: Kirigami.Theme.textColor
    font.family: TelamonStyle.fontFamily
    font.pointSize: TelamonStyle.fontSizeBody
    linkColor: accent
    onLinkActivated: link => root.linkClicked(link)

    HoverHandler {
        cursorShape: root.hoveredLink.length > 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
    }
}
