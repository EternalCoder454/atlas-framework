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
    // an http or https address) and applies <style> rules: the backend sends
    // neither, and whatever slips through is dropped here, so the notes can
    // never make this item fetch anything.
    readonly property string body: root._withoutActive(html).replace(/^\s*<h[1-5][^>]*>\s*What(?:'|&#39;|&#x27;|&rsquo;|\u2019)?s new[^<]*<\/h[1-5]>/i, "")

    function _withoutActive(markup: string): string {
        return markup.replace(/<\s*(style|script|object|iframe|svg|video|audio)\b[\s\S]*?<\s*\/\s*\1\s*>/gi, "").replace(/<\s*\/?\s*(?:img|link|style|script|object|embed|iframe|svg|video|audio|source|meta|base|input|form)\b[^>]*>?/gi, "");
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
