// TelamonCodeCorePrivate: the C++ behind TelamonCodeEditor.qml. Not API: apps
// use TelamonCodeEditor (docs/reference/telamon-ui/telamon-code-editor.md).
// tools/apidump leaves types whose name ends in "Private" out of api/.
//
// It owns what a QML TextEdit cannot do well alone: the text with a size and a
// line-length bound (a text over them is not given to the TextEdit), a
// replacement of the text that keeps the caret, selection and scroll, the
// lazy syntax highlighting, the marked lines, and the line and column
// arithmetic. The TextEdit it works on is the `edit` property; its document
// is plain text only.
#pragma once

#include "codehighlighter.h"

#include <QColor>
#include <QElapsedTimer>
#include <QObject>
#include <QPointer>
#include <QQuickItem>
#include <QTextCursor>
#include <QTextDocument>
#include <QTimer>
#include <QVariantList>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

class TelamonCodeCorePrivate : public QObject
{
    Q_OBJECT
    QML_NAMED_ELEMENT(TelamonCodeCorePrivate)

    // The QML TextEdit that shows the text.
    Q_PROPERTY(QQuickItem *edit READ edit WRITE setEdit NOTIFY editChanged)
    Q_PROPERTY(QString text READ text WRITE setText NOTIFY textChanged)
    Q_PROPERTY(bool modified READ modified WRITE setModified NOTIFY modifiedChanged)
    Q_PROPERTY(int length READ length NOTIFY textChanged)
    Q_PROPERTY(int lineCount READ lineCount NOTIFY lineCountChanged)
    Q_PROPERTY(QString language READ language WRITE setLanguage NOTIFY syntaxChanged)
    Q_PROPERTY(QString fileName READ fileName WRITE setFileName NOTIFY syntaxChanged)
    Q_PROPERTY(QString syntaxName READ syntaxName NOTIFY syntaxChanged)
    // UTF-16 units; a text longer is shown read-only in a viewer instead.
    Q_PROPERTY(int maximumSize READ maximumSize WRITE setMaximumSize NOTIFY maximumSizeChanged)
    Q_PROPERTY(bool tooLarge READ tooLarge NOTIFY tooLargeChanged)
    // A text set from outside is put into the document a few lines at a time
    // from the event loop (the text engine takes about a second per MiB).
    Q_PROPERTY(bool loading READ loading NOTIFY loadingChanged)
    // Tests and tuning: the length from which a text is loaded in slices.
    Q_PROPERTY(int sliceLoadFrom READ sliceLoadFrom WRITE setSliceLoadFrom)
    // Why: 0 not too large, 1 more than maximumSize units, 2 a line longer than MaxEditableLine.
    Q_PROPERTY(int tooLargeReason READ tooLargeReason NOTIFY tooLargeChanged)
    Q_PROPERTY(int maxEditableLine READ maxEditableLine CONSTANT)
    Q_PROPERTY(QVariantMap syntaxPalette READ syntaxPalette WRITE setSyntaxPalette NOTIFY syntaxPaletteChanged)
    Q_PROPERTY(bool highlighting READ highlighting WRITE setHighlighting NOTIFY highlightingChanged)
    // Marks fade out smoothly (true) or stay and then go (false: reduced motion).
    Q_PROPERTY(bool animateMarks READ animateMarks WRITE setAnimateMarks NOTIFY animateMarksChanged)
    Q_PROPERTY(int markStepMs READ markStepMs WRITE setMarkStepMs NOTIFY markStepMsChanged)
    Q_PROPERTY(int markRevision READ markRevision NOTIFY marksChanged)

public:
    enum MarkKind { Added = 0, Changed = 1 };
    Q_ENUM(MarkKind)

    // A line longer than this many units makes a text too large to edit: the
    // text layout of one line that long is a stall.
    static constexpr int MaxEditableLine = 200'000;
    // A text longer than this many units is loaded in slices.
    static constexpr int SliceLoadFrom = 64 * 1024;

    explicit TelamonCodeCorePrivate(QObject *parent = nullptr);
    ~TelamonCodeCorePrivate() override;

    QQuickItem *edit() const { return m_edit; }
    void setEdit(QQuickItem *edit);
    QTextDocument *document() const { return m_doc; }

    QString text() const;
    void setText(const QString &text);
    bool modified() const;
    void setModified(bool modified);
    int length() const;
    int lineCount() const;
    QString language() const { return m_language; }
    void setLanguage(const QString &language);
    QString fileName() const { return m_fileName; }
    void setFileName(const QString &fileName);
    QString syntaxName() const { return m_syntaxName; }
    int maximumSize() const { return m_maximumSize; }
    void setMaximumSize(int units);
    bool tooLarge() const { return m_reason != 0; }
    bool loading() const { return m_loading; }
    int sliceLoadFrom() const { return m_sliceLoadFrom; }
    void setSliceLoadFrom(int units) { m_sliceLoadFrom = qMax(0, units); }
    int maxEditableLine() const { return MaxEditableLine; }
    int tooLargeReason() const { return m_reason; }
    QVariantMap syntaxPalette() const { return m_palette; }
    void setSyntaxPalette(const QVariantMap &palette);
    bool highlighting() const { return m_highlighting; }
    void setHighlighting(bool on);
    bool animateMarks() const { return m_animate; }
    void setAnimateMarks(bool animate);
    int markStepMs() const { return m_markStep; }
    void setMarkStepMs(int ms);
    int markRevision() const { return m_markRevision; }

    // ---- Text ----
    // Replaces the text from outside, touching only what differs, and keeps
    // the caret and the selection where they were (mapped by line and column
    // inside the part that changed). The undo history is cleared.
    Q_INVOKABLE void replacePreserving(const QString &text);

    // ---- Lines (0-based) and positions ----
    Q_INVOKABLE int lineOfPosition(int position) const;
    Q_INVOKABLE int columnOfPosition(int position) const;
    Q_INVOKABLE int positionOfLine(int line, int column = 0) const;
    Q_INVOKABLE int lineLength(int line) const;
    // The line at document y (the TextEdit's top padding is not in it), and the
    // top of a line.
    Q_INVOKABLE int lineAtY(qreal y) const;
    Q_INVOKABLE qreal lineTopY(int line) const;
    Q_INVOKABLE qreal lineHeight(int line) const;

    // ---- Keys ----
    // Indents (or outdents) the selected lines, or inserts one level of
    // indentation at the caret when nothing is selected and !unindent.
    Q_INVOKABLE void indent(bool unindent, int width, bool spaces);
    // Home: the first character that is not white space, then the start.
    Q_INVOKABLE void smartHome(bool extendSelection);

    // ---- Highlighting ----
    // The part of the document in view, as y positions in the document.
    Q_INVOKABLE void setViewport(qreal top, qreal bottom);
    // Tests: the colours set on a line as [{start, length, color, bold, italic}], whether the
    // reading is done, and reading it all now.
    Q_INVOKABLE QVariantList formatRuns(int line) const;
    Q_INVOKABLE bool highlightSettled() const;
    Q_INVOKABLE void highlightNow();

    // ---- Marks ----
    // `ranges`: line numbers (1-based) as a number, [first, last] or {first, last}.
    Q_INVOKABLE void markLines(const QVariantList &ranges, int kind, int fadeMs);
    Q_INVOKABLE void clearMarks();
    Q_INVOKABLE int markCount() const { return int(m_marks.size()); }
    // Tests: the marks as [{first, last, kind}], lines 1-based.
    Q_INVOKABLE QVariantList markSpans() const;

    struct MarkSpan {
        int firstBlock;
        int lastBlock;
        int kind;
        qreal alpha;
    };
    // The marks touching blocks [first, last], with their opacity now.
    QList<MarkSpan> marksIn(int firstBlock, int lastBlock) const;

Q_SIGNALS:
    void editChanged();
    void textChanged();
    // The user changed the text (typing, paste, drop, undo, indent), not the app.
    void textEdited();
    // The app set a new text (not setTextPreserving()): a new document.
    void textLoaded();
    void loadingChanged();
    // A text loaded in slices is all in the document.
    void loaded();
    void modifiedChanged();
    void lineCountChanged();
    void syntaxChanged();
    void maximumSizeChanged();
    void tooLargeChanged();
    void syntaxPaletteChanged();
    void highlightingChanged();
    void animateMarksChanged();
    void markStepMsChanged();
    void marksChanged();
    // The layout of the document changed (a size, a line moved): painters update.
    void layoutChanged();

private:
    struct Mark {
        QTextCursor range; // from the start of the first line to the end of the last
        int kind;
        qint64 created;
        int fadeMs;
    };

    QString plainText() const;
    void startLoad(const QString &text);
    void loadSlice();
    void cancelLoad();
    int reasonFor(const QString &text) const;
    void resolveSyntax();
    void rebuildStyles();
    void onContentsChange(int position, int removed, int added);
    void tickMarks();
    qreal markAlpha(const Mark &mark, qint64 now) const;
    int editInt(const char *property) const;
    void selectRange(int anchor, int cursor);
    QTextBlock blockFor(int line) const;

    QPointer<QQuickItem> m_edit;
    QPointer<QTextDocument> m_doc;
    TelamonCodeHighlighter *m_hl = nullptr;

    QString m_pendingText;
    bool m_hasPending = false;
    QString m_bigText;
    bool m_loading = false;
    int m_sliceLoadFrom = SliceLoadFrom;
    QString m_loadText;
    qsizetype m_loadPos = 0;
    quint64 m_loadGen = 0;
    qsizetype m_chunk = 16 * 1024;
    QTimer m_loadTimer;
    int m_bigLines = 1;
    int m_reason = 0;
    int m_maximumSize = 1024 * 1024;
    // >0 while the app (not the user) changes the document.
    int m_internal = 0;
    int m_lastLineCount = 1;

    QString m_language;
    QString m_fileName;
    QString m_syntaxName;
    QVariantMap m_palette;
    bool m_highlighting = true;

    QList<Mark> m_marks;
    QTimer m_markTimer;
    QElapsedTimer m_clock;
    bool m_animate = true;
    int m_markStep = 33;
    int m_markRevision = 0;
};
