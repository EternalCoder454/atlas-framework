// AtlasTextView (1.5.0 item 38, step 1b): the read-only virtualized text view
// over TextBuffer. Only the lines in view are laid out. The reference page in
// docs/reference/atlas-ui/atlas-text-view.md is the API description; the C++
// interface is atlas/textview.h. Editing, undo and the input method are step 2:
// until then the editing members of the interface do nothing.
#pragma once

#include "textbuffer.h"

#include <atlas/textview.h>

#include <QBasicTimer>
#include <QColor>
#include <QFont>
#include <QPointer>
#include <QQuickItem>
#include <QVariantList>
#include <QtQml/qqmlregistration.h>

#include <algorithm>
#include <memory>
#include <unordered_map>
#include <vector>

class QTextLayout;

namespace AtlasTextViewDetail {

// A Fenwick tree of the rows of every line (wrap mode).
class RowIndex
{
public:
    void reset(qsizetype lines);
    void resize(qsizetype lines); // keeps the values it has; growing is O(log n) per line
    void dropFront(qsizetype lines); // removes the first lines, keeping the rest; amortised O(1) per line
    qsizetype lines() const { return qsizetype(m_value.size()) - m_head; }
    int rows(qsizetype line) const { return m_value[size_t(m_head + line)]; }
    void set(qsizetype line, int rows);
    qint64 before(qsizetype line) const; // rows of lines [0, line)
    qint64 total() const { return before(lines()); }
    qsizetype lineAtRow(qint64 row) const; // clamped
private:
    void rebuild();
    void pushOne(int rows);
    // Dropped lines stay at the front with 0 rows until the next compaction, so
    // the sums of the lines that are left do not change.
    qsizetype m_head = 0;
    std::vector<int> m_value;
    std::vector<qint64> m_tree;
};

struct LineBox {
    qsizetype start = 0;      // position of the line's first unit
    qsizetype len = 0;        // units without the break
    qsizetype breakLen = 0;   // units of the break (0, 1 or 2)
    qsizetype sliceStart = 0; // the part laid out (a long line only: a window)
    qsizetype sliceEnd = 0;
    int rowOffset = 0; // rows above the slice (wrap, long line)
    quint64 revision = 0;
    quint64 generation = 0;
    std::unique_ptr<QTextLayout> layout;
};

} // namespace AtlasTextViewDetail

class AtlasTextView : public QQuickItem, public AtlasTextViewInterface
{
    Q_OBJECT
    Q_INTERFACES(AtlasTextViewInterface)
    QML_NAMED_ELEMENT(AtlasTextView)

    Q_PROPERTY(QString text READ text WRITE setText NOTIFY textChanged FINAL)
    Q_PROPERTY(bool readOnly READ readOnly WRITE setReadOnly NOTIFY readOnlyChanged FINAL)
    Q_PROPERTY(bool wrap READ wrap WRITE setWrap NOTIFY wrapChanged FINAL)
    Q_PROPERTY(QFont font READ font WRITE setFont NOTIFY fontChanged FINAL)
    Q_PROPERTY(int tabWidth READ tabWidth WRITE setTabWidth NOTIFY tabWidthChanged FINAL)
    Q_PROPERTY(qsizetype lineCount READ lineCount NOTIFY lineCountChanged FINAL)
    Q_PROPERTY(qsizetype length READ length NOTIFY lengthChanged FINAL)
    Q_PROPERTY(qsizetype cursorPosition READ cursorPosition WRITE setCursorPosition NOTIFY cursorPositionChanged FINAL)
    Q_PROPERTY(qsizetype selectionStart READ selectionStart NOTIFY selectionChanged FINAL)
    Q_PROPERTY(qsizetype selectionEnd READ selectionEnd NOTIFY selectionChanged FINAL)
    Q_PROPERTY(bool hasSelection READ hasSelection NOTIFY selectionChanged FINAL)
    Q_PROPERTY(QString selectedText READ selectedText NOTIFY selectionChanged FINAL)
    Q_PROPERTY(qreal contentX READ contentX WRITE setContentX NOTIFY contentXChanged FINAL)
    Q_PROPERTY(qreal contentY READ contentY WRITE setContentY NOTIFY contentYChanged FINAL)
    Q_PROPERTY(qreal contentWidth READ contentWidth NOTIFY contentWidthChanged FINAL)
    Q_PROPERTY(qreal contentHeight READ contentHeight NOTIFY contentHeightChanged FINAL)
    Q_PROPERTY(qsizetype firstVisibleLine READ firstVisibleLine NOTIFY visibleRangeChanged FINAL)
    Q_PROPERTY(qsizetype lastVisibleLine READ lastVisibleLine NOTIFY visibleRangeChanged FINAL)
    Q_PROPERTY(LineEnding lineEnding READ lineEndingValue NOTIFY lineEndingChanged FINAL)
    Q_PROPERTY(bool modified READ modified NOTIFY modifiedChanged FINAL)
    Q_PROPERTY(bool canUndo READ canUndo NOTIFY canUndoChanged FINAL)
    Q_PROPERTY(bool canRedo READ canRedo NOTIFY canRedoChanged FINAL)
    Q_PROPERTY(int undoLimit READ undoLimit WRITE setUndoLimit NOTIFY undoLimitChanged FINAL)
    Q_PROPERTY(bool loading READ loading NOTIFY loadingChanged FINAL)
    Q_PROPERTY(qreal loadProgress READ loadProgress NOTIFY loadProgressChanged FINAL)
    Q_PROPERTY(bool hadInvalidText READ hadInvalidText NOTIFY hadInvalidTextChanged FINAL)
    Q_PROPERTY(bool loadFailed READ loadFailed NOTIFY loadFailedChanged FINAL)
    Q_PROPERTY(QString syntax READ syntax WRITE setSyntax NOTIFY syntaxChanged FINAL)
    Q_PROPERTY(QString syntaxTheme READ syntaxTheme WRITE setSyntaxTheme NOTIFY syntaxThemeChanged FINAL)
    Q_PROPERTY(qsizetype highlightLimit READ highlightLimit WRITE setHighlightLimit NOTIFY highlightLimitChanged FINAL)
    Q_PROPERTY(bool showLineNumbers READ showLineNumbers WRITE setShowLineNumbers NOTIFY showLineNumbersChanged FINAL)
    Q_PROPERTY(bool highlightCurrentLine READ highlightCurrentLine WRITE setHighlightCurrentLine NOTIFY highlightCurrentLineChanged FINAL)
    Q_PROPERTY(bool follow READ follow WRITE setFollow NOTIFY followChanged FINAL)
    Q_PROPERTY(qsizetype maximumLines READ maximumLines WRITE setMaximumLines NOTIFY maximumLinesChanged FINAL)
    Q_PROPERTY(QColor textColor READ textColor WRITE setTextColor NOTIFY colorsChanged FINAL)
    Q_PROPERTY(QColor selectionColor READ selectionColor WRITE setSelectionColor NOTIFY colorsChanged FINAL)
    Q_PROPERTY(QColor lineNumberColor READ lineNumberColor WRITE setLineNumberColor NOTIFY colorsChanged FINAL)

public:
    enum LineEnding { LF = 0, CRLF = 1, CR = 2, Mixed = 3 };
    Q_ENUM(LineEnding)

    explicit AtlasTextView(QQuickItem *parent = nullptr);
    ~AtlasTextView() override;

    // ---- AtlasTextViewInterface ----
    int interfaceVersion() const override { return ATLAS_TEXTVIEW_INTERFACE_VERSION; }
    QQuickItem *item() override { return this; }
    QString text() const override;
    void setText(const QString &text) override;
    qsizetype length() const override { return m_buf.tree().length(); }
    qsizetype lineCount() const override { return m_buf.tree().lineCount(); }
    Q_INVOKABLE QString textInRange(qsizetype start, qsizetype end) const override;
    // At most `limit` units of [start, end), never cut inside a surrogate pair
    // and empty when the memory is not there. For the accessible.
    QString boundedText(qsizetype start, qsizetype end, qsizetype limit) const;
    qsizetype alignedPosition(qsizetype position) const { return m_buf.tree().alignDown(position); }
    Q_INVOKABLE qsizetype positionAt(const QPointF &itemPoint) const override;
    Q_INVOKABLE QRectF rectangleAt(qsizetype position) const override;
    Q_INVOKABLE qsizetype positionOfLine(qsizetype line) const override;
    AtlasText::LineColumn lineColumn(qsizetype position) const override;
    Q_INVOKABLE qsizetype lineOf(qsizetype position) const { return lineColumn(position).line; }
    Q_INVOKABLE qsizetype columnOf(qsizetype position) const { return lineColumn(position).column; }
    AtlasTextSnapshot snapshot() const override { return m_buf.snapshot(); }

    Q_INVOKABLE void beginLoad() override;
    void appendData(const char *utf8, qsizetype size) override;
    using AtlasTextViewInterface::appendData;
    Q_INVOKABLE void appendBytes(const QByteArray &utf8);
    Q_INVOKABLE void endLoad() override;
    Q_INVOKABLE void appendText(const QString &text) override;
    Q_INVOKABLE void markSaved(quint64 revision) override;

    bool readOnly() const override { return m_readOnly; }
    void setReadOnly(bool readOnly) override;
    void insert(qsizetype, const QString &) override {}
    void remove(qsizetype, qsizetype) override {}
    void replace(qsizetype, qsizetype, const QString &) override {}
    void beginEdit() override {}
    void endEdit() override {}
    void undo() override {}
    void redo() override {}
    bool canUndo() const override { return false; }
    bool canRedo() const override { return false; }
    int undoLimit() const override { return m_undoLimit; }
    void setUndoLimit(int limit) override;
    bool modified() const override { return false; }
    AtlasText::LineEnding lineEnding() const override { return m_buf.lineEnding(); }
    void convertLineEndings(AtlasText::LineEnding) override {}
    LineEnding lineEndingValue() const { return LineEnding(int(m_buf.lineEnding())); }

    qsizetype cursorPosition() const override { return m_cursor; }
    void setCursorPosition(qsizetype position) override;
    qsizetype selectionStart() const override { return std::min(m_anchor, m_cursor); }
    qsizetype selectionEnd() const override { return std::max(m_anchor, m_cursor); }
    bool hasSelection() const { return m_anchor != m_cursor; }
    QString selectedText() const override;
    Q_INVOKABLE void select(qsizetype start, qsizetype end) override;
    Q_INVOKABLE void selectAll() override;
    void cut() override {}
    Q_INVOKABLE void copy() override;
    void paste() override {}

    bool wrap() const override { return m_wrap; }
    void setWrap(bool wrap) override;
    int tabWidth() const override { return m_tabWidth; }
    void setTabWidth(int columns) override;
    bool showLineNumbers() const override { return m_lineNumbers; }
    void setShowLineNumbers(bool show) override;
    bool highlightCurrentLine() const override { return m_currentLine; }
    void setHighlightCurrentLine(bool highlight) override;
    qsizetype firstVisibleLine() const override;
    qsizetype lastVisibleLine() const override;
    Q_INVOKABLE void ensureVisible(qsizetype position) override;
    Q_INVOKABLE qreal lineY(qsizetype line) const override;
    QRectF cursorRectangle() const override;

    bool follow() const override { return m_follow; }
    void setFollow(bool follow) override;
    qsizetype maximumLines() const override { return m_maxLines; }
    void setMaximumLines(qsizetype lines) override;

    bool loading() const override { return m_loading; }
    qreal loadProgress() const override { return m_loading ? m_buf.loadProgress() : 1.0; }
    bool hadInvalidText() const override { return m_buf.hadInvalidText(); }
    bool loadFailed() const { return m_buf.loadFailed(); }

    void setDecorations(const QString &layer, const QList<AtlasText::Range> &ranges, AtlasText::DecorationStyle style) override;
    // QML: `pairs` is [start, end, start, end, ...]; `style` is a DecorationStyle value (0 to 7).
    Q_INVOKABLE void setDecorationPairs(const QString &layer, const QVariantList &pairs, int style);
    void replaceDecorations(const QString &, const AtlasText::Range &, const QList<AtlasText::Range> &, AtlasText::DecorationStyle) override {}
    Q_INVOKABLE void clearDecorations(const QString &layer) override;

    QString syntax() const override { return m_syntax; }
    void setSyntax(const QString &name) override;
    QString syntaxTheme() const override { return m_syntaxTheme; }
    void setSyntaxTheme(const QString &name) override;
    QString syntaxForFile(const QString &, const QString &) const override { return QString(); }
    qsizetype highlightLimit() const override { return m_highlightLimit; }
    void setHighlightLimit(qsizetype units) override;
    void setHighlighter(std::shared_ptr<const AtlasTextHighlighterInterface> highlighter) override;
    void rehighlight(qsizetype firstLine, qsizetype lastLine) override;
    void rehighlight() override;
    AtlasText::Format formatAt(qsizetype position) const override;

    // ---- Scrolling and colours ----
    qreal contentX() const { return m_contentX; }
    void setContentX(qreal x);
    qreal contentY() const { return m_contentY; }
    void setContentY(qreal y);
    qreal contentWidth() const;
    qreal contentHeight() const;
    QFont font() const { return m_font; }
    void setFont(const QFont &font);
    QColor textColor() const { return m_textColor; }
    void setTextColor(const QColor &c);
    QColor selectionColor() const { return m_selectionColor; }
    void setSelectionColor(const QColor &c);
    QColor lineNumberColor() const { return m_numberColor; }
    void setLineNumberColor(const QColor &c);

    // The text view's own measures, for the accessible and the tests.
    qreal rowHeight() const { return m_rowH; }
    qreal characterWidth() const { return m_cw; }
    // Test hook: the number of cached line layouts.
    int cachedLayouts() const { return int(m_cache.size()); }
    bool dragging() const { return m_dragging; }
    bool autoScrolling() const { return m_scrollTimer.isActive(); }

signals:
    void textChanged();
    void readOnlyChanged();
    void wrapChanged();
    void fontChanged();
    void tabWidthChanged();
    void lineCountChanged();
    void lengthChanged();
    void cursorPositionChanged();
    void selectionChanged();
    void contentXChanged();
    void contentYChanged();
    void contentWidthChanged();
    void contentHeightChanged();
    void visibleRangeChanged();
    void lineEndingChanged();
    void modifiedChanged();
    void canUndoChanged();
    void canRedoChanged();
    void undoLimitChanged();
    void loadingChanged();
    void loadProgressChanged();
    void hadInvalidTextChanged();
    void loadFailedChanged();
    void syntaxChanged();
    void syntaxThemeChanged();
    void highlightLimitChanged();
    void showLineNumbersChanged();
    void highlightCurrentLineChanged();
    void followChanged();
    void maximumLinesChanged();
    void colorsChanged();
    void contentsChange(qsizetype position, qsizetype removed, qsizetype added);
    void loaded();

protected:
    QSGNode *updatePaintNode(QSGNode *old, UpdatePaintNodeData *) override;
    void updatePolish() override;
    void geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry) override;
    void keyPressEvent(QKeyEvent *event) override;
    void mousePressEvent(QMouseEvent *event) override;
    void mouseMoveEvent(QMouseEvent *event) override;
    void mouseReleaseEvent(QMouseEvent *event) override;
    void mouseDoubleClickEvent(QMouseEvent *event) override;
    void wheelEvent(QWheelEvent *event) override;
    void focusInEvent(QFocusEvent *event) override;
    void focusOutEvent(QFocusEvent *event) override;
    void timerEvent(QTimerEvent *event) override;
    void mouseUngrabEvent() override;
    void itemChange(ItemChange change, const ItemChangeData &value) override;

private slots:
    void onLoadNotify();

private:
    using LineBox = AtlasTextViewDetail::LineBox;
    struct Decorations {
        QString layer;
        AtlasText::DecorationStyle style;
        std::vector<AtlasText::Range> ranges; // sorted by start
        qsizetype longest = 0;
    };

    void updateMetrics();
    qreal gutterWidth() const;
    qreal textLeft() const; // item x of the first column at contentX 0
    qreal wrapWidth() const;
    int columnsPerRow() const;
    qreal viewWidth() const { return width(); }
    qreal viewHeight() const { return height(); }

    void ensureRows() const;
    qsizetype lineAtY(qreal y) const;
    qreal lineTop(qsizetype line) const;
    qreal maxContentY() const;
    LineBox &layoutLine(qsizetype line) const;
    QRectF contentRectOf(qsizetype position) const;
    void startLayoutFor(LineBox &box, qsizetype line) const;
    void applyHighlight(LineBox &box, qsizetype line) const;
    bool lineStatesTo(qsizetype line) const;

    void setCursorAndAnchor(qsizetype cursor, qsizetype anchor, bool keepGoal = false);
    void moveCursor(qsizetype position, bool extend, bool keepGoal = false);
    void moveVertically(int rows, bool extend);
    bool wordWindow(qsizetype position, qsizetype *base, qsizetype *col, QString *s) const;
    qsizetype wordStart(qsizetype position) const;
    qsizetype wordEnd(qsizetype position) const;
    void lineExtent(qsizetype line, qsizetype *start, qsizetype *len, qsizetype *breakLen) const;
    bool runsFor(qsizetype line, QList<AtlasText::FormatRun> *runs) const;
    qsizetype lineRowCount(qsizetype line) const;
    void scrollTo(qreal x, qreal y);
    // `droppedLines` > 0: that many lines were removed from the front.
    void documentChanged(bool appended, qsizetype oldLength, qsizetype oldLines, qsizetype droppedLines = 0);
    void stopDrag();
    void notifyReplaced(const QString &oldHead);
    void recordAnchor();
    void finishLoad(qsizetype oldLength);
    void invalidateLayouts();
    void applyMaximumLines();
    bool atBottom() const;
    void scheduleUpdate();
    void autoScroll();

    AtlasTextDetail::TextBuffer m_buf;
    bool m_loading = false;
    bool m_inputEnded = false;
    qsizetype m_loadOldLength = 0;
    bool m_readOnly = true;
    int m_undoLimit = 1000;

    qsizetype m_cursor = 0, m_anchor = 0;
    qreal m_goalX = -1;

    bool m_wrap = false;
    int m_tabWidth = 4;
    bool m_lineNumbers = false;
    bool m_currentLine = false;
    bool m_follow = false;
    qsizetype m_maxLines = 0;
    QString m_syntax, m_syntaxTheme;
    qsizetype m_highlightLimit = 50 * 1024 * 1024;

    QFont m_font;
    qreal m_rowH = 16, m_cw = 8;
    QColor m_textColor, m_selectionColor, m_numberColor;
    bool m_textColorSet = false, m_selectionColorSet = false, m_numberColorSet = false;

    qreal m_contentX = 0, m_contentY = 0;
    qsizetype m_firstSignalled = -1, m_lastSignalled = -1;
    mutable qsizetype m_maxCols = 0;
    qreal m_lastContentW = -1, m_lastContentH = -1;

    mutable AtlasTextViewDetail::RowIndex m_rows;
    mutable bool m_rowsValid = false;
    // The line at the top of the view and how far into it (in rows), kept while
    // the rows are measured again after a resize, a font change or a wrap switch.
    qsizetype m_anchorLine = -1;
    qreal m_anchorRows = 0;
    mutable std::unordered_map<qsizetype, std::unique_ptr<LineBox>> m_cache;
    mutable quint64 m_generation = 1; // bumps when width, font, wrap or tabs change

    std::vector<Decorations> m_layers;
    std::shared_ptr<const AtlasTextHighlighterInterface> m_highlighter;
    mutable std::vector<int> m_states; // the state each line starts in, from line 1

    bool m_dragging = false;
    QPointF m_lastMouse;
    QBasicTimer m_scrollTimer;
    qint64 m_lastDoubleClick = -1000000;
    qint64 m_pressTime = 0;
    int m_clicks = 0;
    bool m_pinned = false; // follow mode: the view sticks to the bottom
};
