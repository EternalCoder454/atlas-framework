// TelamonTextView's C++ API, for apps that drive the view from C++ (Telamon
// Notepad's Document, CodeEditor, LineTools and SpellCheck).
//
// Header-only and versioned, the way Qt's plugin interfaces are: nothing here
// is linked. The item (a QQuickItem in Telamon.Ui) implements
// TelamonTextViewInterface, and an app gets the interface from the item:
//
//     auto *view = qobject_cast<TelamonTextViewInterface *>(item);
//     if (!view) { /* an older or different Telamon.Ui: say so, don't crash */ }
//
// How this relates to QML. QML's TelamonTextView is the main surface: every
// property, method and signal of the QML type is also here, with the same
// meaning, units and defaults, and the reference page in docs/reference is the
// one place the behaviour is described. This header adds what QML cannot
// express without copying: snapshot(), chunked loading with raw bytes, typed
// decorations, and the highlighter hook. Setting a property here emits the
// same change signal QML sees, and the other way round. The signals are those
// of the QQuickItem (see "Signals" below): connect to them on the item.
//
// Units: positions and columns are UTF-16 code units, lines are 0-based (the
// same as textsnapshot.h). Out-of-range arguments are clamped, never an error.
//
// Threads. The item and everything on TelamonTextViewInterface belong to the GUI
// thread: call them from there only. To work on another thread, take a
// snapshot() on the GUI thread and hand the TelamonTextSnapshot over (it is safe
// anywhere, see textsnapshot.h). A TelamonTextHighlighterInterface is the
// exception: its highlightLine() runs on a worker thread.
//
// Versioning. A published interface never changes: not an order of virtuals,
// not a signature. A release that needs more adds TelamonTextViewInterface2
// (IID /2) deriving from this one, and the item implements both. Check
// interfaceVersion() when an app must run on more than one Telamon.Ui.
#pragma once

#include "textsnapshot.h"

#include <QColor>
#include <QList>
#include <QObject>
#include <QPoint>
#include <QRect>
#include <QString>
#include <QStringList>

#include <memory>

class QQuickItem;

// The version of TelamonTextViewInterface this header describes.
#define TELAMON_TEXTVIEW_INTERFACE_VERSION 1

namespace TelamonText {

// What the text uses to end lines. The values are part of the ABI and the
// order matches the QML enum.
enum class LineEnding : int {
    LF = 0,
    CRLF = 1,
    CR = 2,
    // Two or more kinds in one text. Never accepted by convertLineEndings().
    Mixed = 3,
};

// How a decoration range is drawn. The values are part of the ABI.
enum class DecorationStyle : int {
    Match = 0,
    CurrentMatch = 1,
    Bracket = 2,
    CurrentLine = 3,
    Error = 4,
    Warning = 5,
    Info = 6,
    // A wavy underline in the error colour, drawn as geometry.
    Spelling = 7,
};

// A half-open range of UTF-16 positions, start <= end.
struct Range {
    qsizetype start = 0;
    qsizetype end = 0;
};

// A line and a column, both 0-based, the column in UTF-16 units.
struct LineColumn {
    qsizetype line = 0;
    qsizetype column = 0;
};

// The look of one run of highlighted text. A format with every field default
// leaves the run in the view's normal style.
struct Format {
    // An invalid colour means "the view's own colour".
    QColor foreground;
    QColor background;
    bool bold = false;
    bool italic = false;
    bool underline = false;
    bool strikeOut = false;
    // The definition's name for the run, such as "Comment" or "Keyword",
    // returned by formatAt(). May be empty.
    QString name;
};

// A run inside one line: `length` units from column `start`.
struct FormatRun {
    qsizetype start = 0;
    qsizetype length = 0;
    Format format;
};

} // namespace TelamonText

// A highlighter an app plugs in with TelamonTextViewInterface::setHighlighter,
// such as Notepad's MarkdownHighlighter. The built-in KSyntaxHighlighting
// highlighter implements this same interface.
//
// The view highlights lines in order on a worker thread, ahead of the
// viewport. It keeps one integer state per line: the state a line ends in is
// the state the next line starts in, and when an edit changes a line's end
// state the following lines are highlighted again until the states agree.
// The order of virtuals is part of the ABI.
class TelamonTextHighlighterInterface
{
public:
    virtual ~TelamonTextHighlighterInterface() = default;

    // The state the first line starts in. Usually 0.
    virtual int initialState() const = 0;

    // Highlights one line. `startState` is the state at the start of the line;
    // `line` is its text without the line break. Append the runs to `runs`, in
    // column order and without overlaps (gaps are the normal style), and return
    // the state at the end of the line. The view stores one int per line and
    // only compares states for equality. Runs on a worker thread, possibly for
    // different views at once: it must be reentrant and must not touch the GUI
    // or QObjects of the GUI thread. It must not throw.
    virtual int highlightLine(int startState, const QString &line, QList<TelamonText::FormatRun> *runs) const = 0;
};

// The interface the item implements. Not a QObject; see the top of the file.
class TelamonTextViewInterface
{
protected:
    // Not deleted through this type: the item owns itself.
    virtual ~TelamonTextViewInterface() = default;

public:
    // TELAMON_TEXTVIEW_INTERFACE_VERSION as the item was built (always the
    // first virtual). 1 for this interface.
    virtual int interfaceVersion() const = 0;
    // The QQuickItem behind the interface. Use it to connect to the signals,
    // set the parent or anchors, and so on. Never null.
    virtual QQuickItem *item() = 0;

    // ---- The text ----

    // The whole text as a QString. Builds a copy, and only when this getter
    // is called: the QML `textChanged` signal does not build the string, so
    // listening to it costs nothing until a reader asks. Large files use
    // snapshot().
    virtual QString text() const = 0;
    // Replaces everything as one load, resets undo and clears `modified`.
    virtual void setText(const QString &text) = 0;
    // The length in UTF-16 units and the number of lines (at least 1).
    virtual qsizetype length() const = 0;
    virtual qsizetype lineCount() const = 0;
    // The text from `start` to `end`.
    virtual QString textInRange(qsizetype start, qsizetype end) const = 0;
    // The position nearest to `itemPoint` (item coordinates), for the context
    // menu, Ctrl+click on links, drop targets and the like. Clamped to the
    // text; GUI thread only.
    virtual qsizetype positionAt(const QPointF &itemPoint) const = 0;
    // The rectangle of the character at `position`, in item coordinates, for
    // popups placed at a word. At the end of the text it is the caret's
    // rectangle there. Empty when the line is not laid out yet (not visible).
    virtual QRectF rectangleAt(qsizetype position) const = 0;
    // The position of the first unit of `line`, and the line and column of
    // `position`.
    virtual qsizetype positionOfLine(qsizetype line) const = 0;
    virtual TelamonText::LineColumn lineColumn(qsizetype position) const = 0;

    // An immutable copy of the text, taken in O(1). It is the way to hand the
    // text to a worker thread, to save and to search. See textsnapshot.h.
    virtual TelamonTextSnapshot snapshot() const = 0;

    // ---- Loading and saving ----
    // beginLoad() empties the view, makes it read-only and sets `loading`.
    // appendData() adds text in order, as often as wanted, any chunk size.
    // endLoad() ends the load: the view is editable, `modified` is false, undo
    // is empty, and loaded() is emitted. A second beginLoad() before endLoad()
    // restarts the load. Saving is snapshot() plus the app's own writing;
    // markSaved() then clears `modified`.

    // Starts a load.
    virtual void beginLoad() = 0;
    // Adds UTF-8. Invalid sequences become U+FFFD and set `hadInvalidText`; a
    // sequence cut at the end of one call and finished in the next is fine.
    // The bytes are copied (or kept alive by the view): the caller's buffer is
    // free on return. Ignored outside a load.
    virtual void appendData(const char *utf8, qsizetype size) = 0;
    // Ends a load.
    virtual void endLoad() = 0;
    // For `follow` mode and after endLoad(): adds to the end with no undo
    // record, keeping the view at the bottom if it was there.
    virtual void appendText(const QString &text) = 0;
    // Clears `modified` after the app wrote the file. `revision` is the
    // snapshot revision that was saved; `modified` stays true if the text has
    // changed since.
    virtual void markSaved(quint64 revision) = 0;

    // The convenience overload for a QByteArray.
    void appendData(const QByteArray &utf8) { appendData(utf8.constData(), utf8.size()); }

    // ---- Editing ----
    virtual bool readOnly() const = 0;
    virtual void setReadOnly(bool readOnly) = 0;
    // Each of these is one undo record unless inside beginEdit()/endEdit().
    // They do nothing when readOnly or loading. They keep the caret where an
    // edit before it would, and emit contentsChange() for each change.
    virtual void insert(qsizetype position, const QString &text) = 0;
    virtual void remove(qsizetype start, qsizetype end) = 0;
    virtual void replace(qsizetype start, qsizetype end, const QString &text) = 0;
    // Group changes into one undo record. They nest; the record closes at the
    // outermost endEdit(). A beginEdit() without endEdit() is the caller's bug.
    // contentsChange() is not grouped: inside a group it fires once per change,
    // as it happens, not once per group.
    virtual void beginEdit() = 0;
    virtual void endEdit() = 0;
    // Undo and redo restore the caret and the selection to what they were
    // before the record (undo) or after it (redo), as QTextDocument does, and
    // emit contentsChange() for each change they make.
    virtual void undo() = 0;
    virtual void redo() = 0;
    virtual bool canUndo() const = 0;
    virtual bool canRedo() const = 0;
    virtual int undoLimit() const = 0;
    virtual void setUndoLimit(int limit) = 0;
    // True when the text differs from the last load or markSaved().
    virtual bool modified() const = 0;
    // The kind of line break in the text (LF for an empty text, Mixed when
    // there are several). CRLF counts as two positions, so positions match the
    // file. convertLineEndings() rewrites every break to `kind` as one
    // compound edit, so one undo restores them; `kind` must not be Mixed, and
    // nothing happens if the text already uses only `kind`. A text kept as LF
    // only (as Notepad does) reports LF and is never converted.
    virtual TelamonText::LineEnding lineEnding() const = 0;
    virtual void convertLineEndings(TelamonText::LineEnding kind) = 0;

    // ---- Caret, selection, clipboard ----
    virtual qsizetype cursorPosition() const = 0;
    virtual void setCursorPosition(qsizetype position) = 0;
    virtual qsizetype selectionStart() const = 0;
    virtual qsizetype selectionEnd() const = 0;
    virtual QString selectedText() const = 0;
    // Selects [start, end); the caret goes to `end`. start > end selects
    // backwards.
    virtual void select(qsizetype start, qsizetype end) = 0;
    virtual void selectAll() = 0;
    virtual void cut() = 0;
    virtual void copy() = 0;
    virtual void paste() = 0;

    // ---- Display ----
    virtual bool wrap() const = 0;
    virtual void setWrap(bool wrap) = 0;
    // Width of a tab stop in space characters.
    virtual int tabWidth() const = 0;
    virtual void setTabWidth(int columns) = 0;
    virtual bool showLineNumbers() const = 0;
    virtual void setShowLineNumbers(bool show) = 0;
    virtual bool highlightCurrentLine() const = 0;
    virtual void setHighlightCurrentLine(bool highlight) = 0;
    // The first and last line that are at least partly visible.
    virtual qsizetype firstVisibleLine() const = 0;
    virtual qsizetype lastVisibleLine() const = 0;
    // Scrolls so that `position` is visible.
    virtual void ensureVisible(qsizetype position) = 0;
    // The y of the top of `line` in content coordinates.
    virtual qreal lineY(qsizetype line) const = 0;
    // The caret's rectangle in item coordinates, for popups placed by it.
    virtual QRectF cursorRectangle() const = 0;

    // ---- Tail mode ----
    virtual bool follow() const = 0;
    virtual void setFollow(bool follow) = 0;
    // 0 means no limit.
    virtual qsizetype maximumLines() const = 0;
    virtual void setMaximumLines(qsizetype lines) = 0;

    // ---- State of a load ----
    virtual bool loading() const = 0;
    // 0 to 1.
    virtual qreal loadProgress() const = 0;
    // True when the last load replaced invalid UTF-8.
    virtual bool hadInvalidText() const = 0;

    // ---- Decorations ----
    // Replaces the layer named `layer` with `ranges`, all drawn in `style`. An
    // empty list clears the layer. Positions shift with edits; a range whose
    // text is deleted disappears (and the layer's contents then differ from
    // what was set). Only ranges in visible lines cost anything.
    virtual void setDecorations(const QString &layer, const QList<TelamonText::Range> &ranges, TelamonText::DecorationStyle style) = 0;
    // Replaces only the ranges of `layer` that lie inside `region`, leaving
    // the rest of the layer alone; `ranges` (all in `style`) are clipped to
    // `region`. For find-all and spelling, which set the visible range again
    // on visibleRangeChanged(). Ships in step 3: the slot is in the interface from
    // the start, but until step 3 lands it does nothing, so an app uses
    // setDecorations() meanwhile.
    virtual void replaceDecorations(const QString &layer, const TelamonText::Range &region, const QList<TelamonText::Range> &ranges,
                                    TelamonText::DecorationStyle style) = 0;
    // Removes one layer. Unknown names are ignored.
    virtual void clearDecorations(const QString &layer) = 0;

    // ---- Highlighting ----
    // The name of the KSyntaxHighlighting definition ("C++", "Rust", ...), or
    // "" for none. An unknown name selects none.
    virtual QString syntax() const = 0;
    virtual void setSyntax(const QString &name) = 0;
    // The theme the built-in highlighter uses. By default (empty name) it
    // follows the Telamon.Ui light/dark palette on its own and switches with it.
    // A KSyntaxHighlighting theme name overrides that; an empty name goes back
    // to following the palette. An unknown name is ignored.
    virtual QString syntaxTheme() const = 0;
    virtual void setSyntaxTheme(const QString &name) = 0;
    // The definition that fits a file name and the file's first line (for
    // shebangs and modelines), or "" when none does.
    virtual QString syntaxForFile(const QString &fileName, const QString &firstLine) const = 0;
    // Highlighting is skipped on lines longer than this many UTF-16 units.
    virtual qsizetype highlightLimit() const = 0;
    virtual void setHighlightLimit(qsizetype units) = 0;
    // Plugs in a highlighter in place of the built-in one, or restores the
    // built-in one with nullptr. The view keeps the shared pointer until it is
    // replaced or the view is destroyed, and calls it on a worker thread.
    // Setting one restyles the whole text.
    //
    // The view only stores the int states and compares them for equality, so an
    // app can intern richer states (a stack, a block kind) as ints in its own
    // table. Equal states must mean equal behaviour on the following lines.
    virtual void setHighlighter(std::shared_ptr<const TelamonTextHighlighterInterface> highlighter) = 0;
    // Highlights lines [firstLine, lastLine] again with the current
    // highlighter, without replacing it. For when its output depends on
    // outside state (the theme, a dictionary, the caret line). Lines after
    // lastLine follow if their start state changed. Clamped; GUI thread only.
    virtual void rehighlight(qsizetype firstLine, qsizetype lastLine) = 0;
    // All lines.
    virtual void rehighlight() = 0;
    // The format at `position`: the name and look the highlighter gave it. The
    // result is default (empty name) where the text is not highlighted yet.
    virtual TelamonText::Format formatAt(qsizetype position) const = 0;
};

// Signals. They are signals of the item (a QObject), not of this interface:
// connect to `view->item()`. Their signatures are part of the contract.
//
//   void contentsChange(qsizetype position, qsizetype removed, qsizetype added);
//       Before the property-changed signals of the same edit. Fires for every
//       change, user's or the app's, so it is the hook for a document model.
//       `position` is in the text after the change; `removed` units were
//       there before and `added` are there now, as in QTextDocument. Inside
//       beginEdit()/endEdit() it fires once per change, not once per group.
//   void textEdited();
//       User edits only (keys, paste, drop, IME), not setText() or insert().
//   void visibleRangeChanged();
//       The first or last visible line changed (scroll, wrap, resize, edit).
//   void loaded();
//       endLoad() finished.
//
// All four are delivered on the GUI thread. With the Qt 6 pointer-to-member
// syntax the item's own class is not public, so use the string form:
//
//   QObject::connect(view->item(), SIGNAL(contentsChange(qsizetype,qsizetype,qsizetype)), ...);
//
// The other signals are the QML properties' NOTIFY signals (`textChanged`,
// `cursorPositionChanged`, `modifiedChanged`, ...), named as in QML.

Q_DECLARE_INTERFACE(TelamonTextViewInterface, "net.eterneon.Telamon.TextView/1")
Q_DECLARE_INTERFACE(TelamonTextHighlighterInterface, "net.eterneon.Telamon.TextHighlighter/1")
