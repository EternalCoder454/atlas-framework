// TelamonCodeHighlighter: syntax highlighting for TelamonCodeEditor's document
// with KSyntaxHighlighting, lazily. Not API (TelamonCodeCorePrivate owns it).
//
// KSyntaxHighlighting needs the state a line ends in to read the next line, so
// a line far down a file cannot be highlighted without reading the lines above
// it. The stock QSyntaxHighlighter reads the whole document when it is
// attached and tells the layout once per line, which freezes the window on a
// big file. This one:
//
// - reads lines in slices of a few milliseconds from the event loop, and only
//   as far as the end of the viewport (plus a margin). Lines above that are
//   read for their state only; the colours are set on the lines near the
//   viewport. Scrolling on moves the end of the reading with it.
// - keeps the state a line ends in on the line (a QTextBlockUserData), so it
//   moves with the line when lines are inserted or removed. After an edit it
//   reads the changed lines at once and the lines after them while their end
//   state changes, no further.
// - leaves a line longer than MaxLineLength unhighlighted (a regular expression
//   over a megabyte line is a stall); the lines around it are unaffected.
// - sets the colours straight on the line's text layout, not through
//   QTextCharFormat in the document, and tells the document's layout once per
//   slice (the way Telamon Notepad's highlighter does).
//
// GUI thread only.
#pragma once

#include <QElapsedTimer>
#include <QHash>
#include <QList>
#include <QObject>
#include <QPointer>
#include <QTextBlock>
#include <QTextCharFormat>
#include <QTextCursor>
#include <QTextLayout>
#include <QTimer>

#include <KSyntaxHighlighting/AbstractHighlighter>
#include <KSyntaxHighlighting/Definition>
#include <KSyntaxHighlighting/Format>
#include <KSyntaxHighlighting/State>

class QTextDocument;

class TelamonCodeHighlighter : public QObject, public KSyntaxHighlighting::AbstractHighlighter
{
    Q_OBJECT
public:
    // A line longer than this many UTF-16 units is not highlighted.
    static constexpr qsizetype MaxLineLength = 4000;
    // Lines read beyond the viewport, each way, with their colours set.
    static constexpr int Margin = 40;

    explicit TelamonCodeHighlighter(QTextDocument *document, QObject *parent = nullptr);
    ~TelamonCodeHighlighter() override;

    void setDefinition(const KSyntaxHighlighting::Definition &definition) override;
    // The look of each text style (KSyntaxHighlighting::Theme::TextStyle as an
    // int); a style that is missing is drawn in the editor's own colour.
    void setStyles(const QHash<int, QTextCharFormat> &styles);
    // No highlighting at all while false (the definition is kept).
    void setEnabled(bool enabled);
    bool enabled() const { return m_enabled; }
    // The lines in view, as block numbers (first <= last).
    void setViewport(int firstBlock, int lastBlock);

    // True when everything wanted for the viewport has been read and coloured.
    bool settled() const;
    // Reads now, for at most `budgetNs` (0: until settled). For tests and for
    // the editor's first paint.
    void runNow(qint64 budgetNs = 0);

protected:
    void applyFormat(int offset, int length, const KSyntaxHighlighting::Format &format) override;

private:
    struct Style {
        QTextCharFormat format;
        bool plain;
    };

    void onContentsChange(int position, int removed, int added);
    bool usable() const;
    const Style &styleFor(const KSyntaxHighlighting::Format &format);
    // Reads one line; sets its colours when `apply`. Marks the next line stale
    // when the state the line ends in is not the one it ended in before.
    void process(const QTextBlock &block, bool apply);
    void run(qint64 budgetNs);
    void schedule();
    void kick();
    void invalidateAll();
    void flushDirty();

    QPointer<QTextDocument> m_doc;
    bool m_enabled = true;
    // Bumped to make every line stale: its state (a new definition or a new
    // text) or its colours (new styles).
    quint32 m_stateGen = 1;
    quint32 m_formatGen = 1;
    // The first line that may still need reading (it moves with edits).
    QTextCursor m_resume;
    int m_applyFirst = 0;
    int m_applyLast = Margin;
    bool m_busy = false;
    QTimer m_timer;

    QHash<int, Style> m_formats; // by KSyntaxHighlighting format id
    QHash<int, QTextCharFormat> m_styles;
    QList<QTextLayout::FormatRange> m_ranges;
    bool m_collect = false;
    // The span of the text the layout has still to be told about.
    int m_dirtyFrom = -1;
    int m_dirtyEnd = 0;
};
