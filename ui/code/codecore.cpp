// See codecore.h.
#include "codecore.h"

#include <QFileInfo>
#include <QQuickTextDocument>
#include <QTextBlock>
#include <QTextCursor>
#include <QTextLayout>
#include <QTextOption>

#include <KSyntaxHighlighting/Definition>
#include <KSyntaxHighlighting/Repository>
#include <KSyntaxHighlighting/Theme>

#include <QAbstractTextDocumentLayout>

#include <algorithm>
#include <cmath>
#include <limits>

namespace
{
using KSyntaxHighlighting::Theme;

// One repository for the process, made when the first language is looked up
// (reading the index of the definitions takes a moment).
KSyntaxHighlighting::Repository &repository()
{
    static KSyntaxHighlighting::Repository repo;
    return repo;
}

struct ScopedInternal {
    explicit ScopedInternal(int &counter)
        : m_counter(counter)
    {
        ++m_counter;
    }
    ~ScopedInternal() { --m_counter; }
    int &m_counter;
};

// Which of the editor's colours a KSyntaxHighlighting text style takes.
struct StyleGroup {
    Theme::TextStyle style;
    const char *group;
};
constexpr StyleGroup styleGroups[] = {
    {Theme::Keyword, "keyword"},
    {Theme::ControlFlow, "keyword"},
    {Theme::Function, "function"},
    {Theme::Operator, "operator"},
    {Theme::BuiltIn, "builtin"},
    {Theme::Extension, "builtin"},
    {Theme::Import, "builtin"},
    {Theme::Preprocessor, "preprocessor"},
    {Theme::Attribute, "attribute"},
    {Theme::Annotation, "attribute"},
    {Theme::Char, "string"},
    {Theme::String, "string"},
    {Theme::VerbatimString, "string"},
    {Theme::SpecialChar, "special"},
    {Theme::SpecialString, "special"},
    {Theme::DataType, "type"},
    {Theme::DecVal, "number"},
    {Theme::BaseN, "number"},
    {Theme::Float, "number"},
    {Theme::Constant, "constant"},
    {Theme::Comment, "comment"},
    {Theme::Documentation, "comment"},
    {Theme::CommentVar, "comment"},
    {Theme::RegionMarker, "comment"},
    {Theme::Information, "comment"},
    {Theme::Warning, "warning"},
    {Theme::Alert, "error"},
    {Theme::Error, "error"},
};

constexpr int MaxMarks = 20000;
constexpr int MaxMarkRanges = 10000;

// The text as the document will hold it: line breaks are U+000A (the document
// would treat CR, CRLF and U+2029 as breaks too, which would put its positions
// out of step with the string), and the two code points the document reads as
// frame markers are replaced.
QString normalized(const QString &text)
{
    bool dirty = false;
    for (const QChar ch : text) {
        const char16_t u = ch.unicode();
        if (u == u'\r' || u == 0x2029 || u == 0xFDD0 || u == 0xFDD1) {
            dirty = true;
            break;
        }
    }
    if (!dirty) {
        return text;
    }
    QString out;
    out.reserve(text.size());
    for (qsizetype i = 0; i < text.size(); ++i) {
        const char16_t u = text.at(i).unicode();
        if (u == u'\r') {
            if (i + 1 < text.size() && text.at(i + 1) == u'\n') {
                ++i;
            }
            out += u'\n';
        } else if (u == 0x2029) {
            out += u'\n';
        } else if (u == 0xFDD0 || u == 0xFDD1) {
            out += QChar(0xFFFD);
        } else {
            out += QChar(u);
        }
    }
    return out;
}
} // namespace

TelamonCodeCorePrivate::TelamonCodeCorePrivate(QObject *parent)
    : QObject(parent)
{
    m_clock.start();
    m_markTimer.setSingleShot(true);
    connect(&m_markTimer, &QTimer::timeout, this, &TelamonCodeCorePrivate::tickMarks);
    m_loadTimer.setSingleShot(true);
    connect(&m_loadTimer, &QTimer::timeout, this, &TelamonCodeCorePrivate::loadSlice);
}

TelamonCodeCorePrivate::~TelamonCodeCorePrivate() = default;

void TelamonCodeCorePrivate::setEdit(QQuickItem *edit)
{
    if (m_edit == edit) {
        return;
    }
    m_edit = edit;
    delete m_hl;
    m_hl = nullptr;
    m_doc = nullptr;
    if (edit) {
        const auto *qd = qobject_cast<QQuickTextDocument *>(qvariant_cast<QObject *>(edit->property("textDocument")));
        m_doc = qd ? qd->textDocument() : nullptr;
    }
    if (m_doc) {
        m_hl = new TelamonCodeHighlighter(m_doc, this);
        m_hl->setEnabled(m_highlighting);
        rebuildStyles();
        resolveSyntax();
        connect(m_doc, &QTextDocument::contentsChange, this, &TelamonCodeCorePrivate::onContentsChange);
        connect(m_doc, &QTextDocument::modificationChanged, this, &TelamonCodeCorePrivate::modifiedChanged);
        QAbstractTextDocumentLayout *layout = m_doc->documentLayout();
        connect(layout, &QAbstractTextDocumentLayout::documentSizeChanged, this, &TelamonCodeCorePrivate::layoutChanged);
        connect(layout, &QAbstractTextDocumentLayout::update, this, &TelamonCodeCorePrivate::layoutChanged);
        m_lastLineCount = m_doc->blockCount();
        if (m_hasPending) {
            m_hasPending = false;
            setText(m_pendingText);
            m_pendingText.clear();
        }
    }
    Q_EMIT editChanged();
}

// ---- The text --------------------------------------------------------------

QString TelamonCodeCorePrivate::plainText() const
{
    if (!m_doc) {
        return {};
    }
    // Block by block, not QTextDocument::toPlainText(), which turns a
    // non-breaking space into a plain one: a file saved from the editor must
    // keep its characters.
    QString out;
    out.reserve(m_doc->characterCount());
    bool first = true;
    for (QTextBlock b = m_doc->begin(); b.isValid(); b = b.next()) {
        if (!first) {
            out += u'\n';
        }
        first = false;
        out += b.text();
    }
    return out;
}

QString TelamonCodeCorePrivate::text() const
{
    if (!m_doc) {
        return m_pendingText;
    }
    if (m_loading) {
        return m_loadText;
    }
    return m_reason ? m_bigText : plainText();
}

int TelamonCodeCorePrivate::reasonFor(const QString &text) const
{
    if (text.size() > m_maximumSize) {
        return 1;
    }
    // The longest line: one pass over the text.
    qsizetype run = 0;
    for (const QChar ch : text) {
        if (ch == u'\n') {
            run = 0;
        } else if (++run > MaxEditableLine) {
            return 2;
        }
    }
    return 0;
}

void TelamonCodeCorePrivate::setText(const QString &input)
{
    if (!m_doc) {
        m_pendingText = input;
        m_hasPending = true;
        Q_EMIT textChanged();
        return;
    }
    const QString text = normalized(input);
    const int reason = reasonFor(text);
    ScopedInternal guard(m_internal);
    const int oldReason = m_reason;
    if (reason == 0 && oldReason == 0 && !m_loading && qsizetype(m_doc->characterCount()) - 1 == text.size() && plainText() == text) {
        // The same text again: it is a reload.
        m_doc->setModified(false);
        return;
    }
    cancelLoad();
    if (reason == 0 && text.size() > m_sliceLoadFrom) {
        m_reason = 0;
        m_bigText = QString();
        if (oldReason != 0) {
            Q_EMIT tooLargeChanged();
        }
        startLoad(text);
        return;
    }
    m_reason = reason;
    if (reason) {
        m_bigText = text;
        m_bigLines = int(std::count(text.cbegin(), text.cend(), u'\n')) + 1;
        m_doc->setPlainText(QString());
    } else {
        m_bigText = QString();
        m_doc->setPlainText(text);
    }
    m_doc->setModified(false);
    clearMarks();
    // A new document: the caret at the start.
    if (m_edit) {
        m_edit->setProperty("cursorPosition", 0);
    }
    Q_EMIT textLoaded();
    if (oldReason != reason) {
        Q_EMIT tooLargeChanged();
    }
    // contentsChange does not fire for an empty document made empty again.
    Q_EMIT textChanged();
    Q_EMIT lineCountChanged();
}

// A big text goes into the document a slice at a time: the text engine lays
// out each line as it comes (about 70 microseconds a line), and all of a big
// text at once is a stall of a second a MiB. The text is the caller's from the
// start (`text` returns all of it); the editor is read-only until the end.
void TelamonCodeCorePrivate::startLoad(const QString &text)
{
    ++m_loadGen;
    m_loading = true;
    m_loadText = text;
    m_loadPos = 0;
    m_bigLines = int(std::count(text.cbegin(), text.cend(), u'\n')) + 1;
    m_doc->setUndoRedoEnabled(false);
    m_doc->setPlainText(QString());
    m_doc->setModified(false);
    clearMarks();
    if (m_edit) {
        m_edit->setProperty("cursorPosition", 0);
    }
    Q_EMIT loadingChanged();
    Q_EMIT textLoaded();
    Q_EMIT textChanged();
    Q_EMIT lineCountChanged();
    loadSlice();
}

void TelamonCodeCorePrivate::loadSlice()
{
    if (!m_loading || !m_doc) {
        return;
    }
    ScopedInternal guard(m_internal);
    QElapsedTimer slice;
    slice.start();
    const quint64 generation = m_loadGen;
    const qsizetype length = m_loadText.size();
    do {
        QElapsedTimer one;
        one.start();
        qsizetype end = std::min(length, m_loadPos + m_chunk);
        if (end < length) {
            // To the end of the line, so every piece is whole lines.
            const qsizetype newline = m_loadText.indexOf(u'\n', end - 1);
            end = newline < 0 ? length : newline + 1;
        }
        QTextCursor c(m_doc);
        c.movePosition(QTextCursor::End);
        c.insertText(m_loadText.mid(m_loadPos, end - m_loadPos));
        if (generation != m_loadGen) {
            // A handler of the change set another text: its load is the one that goes on.
            return;
        }
        // About 4 ms a piece.
        const double took = std::max(0.2, double(one.nsecsElapsed()) / 1e6);
        m_chunk = std::clamp<qsizetype>(qsizetype((double(m_chunk) + double(m_chunk) * 4.0 / took) / 2), 2 * 1024, 256 * 1024);
        if (m_loadPos == 0 && m_edit) {
            // The text field's caret was at the start of the empty text, and
            // the first piece pushed it to its end.
            m_edit->setProperty("cursorPosition", 0);
        }
        m_loadPos = end;
    } while (m_loadPos < length && slice.elapsed() < 6);
    if (m_loadPos < length) {
        m_loadTimer.start(0);
        return;
    }
    m_loading = false;
    m_loadText = QString();
    m_doc->setUndoRedoEnabled(true);
    m_doc->setModified(false);
    Q_EMIT loadingChanged();
    Q_EMIT loaded();
}

void TelamonCodeCorePrivate::cancelLoad()
{
    if (!m_loading) {
        return;
    }
    ++m_loadGen;
    m_loadTimer.stop();
    m_loading = false;
    m_loadText = QString();
    if (m_doc) {
        m_doc->setUndoRedoEnabled(true);
    }
    Q_EMIT loadingChanged();
}

bool TelamonCodeCorePrivate::modified() const
{
    return m_doc && m_reason == 0 && !m_loading && m_doc->isModified();
}

void TelamonCodeCorePrivate::setModified(bool modified)
{
    if (m_doc && m_reason == 0) {
        m_doc->setModified(modified);
    }
}

int TelamonCodeCorePrivate::length() const
{
    if (!m_doc) {
        return int(m_pendingText.size());
    }
    if (m_loading) {
        return int(m_loadText.size());
    }
    return m_reason ? int(m_bigText.size()) : std::max(0, m_doc->characterCount() - 1);
}

int TelamonCodeCorePrivate::lineCount() const
{
    if (!m_doc) {
        return 1;
    }
    if (m_reason || m_loading) {
        return m_bigLines;
    }
    return std::max(1, m_doc->blockCount());
}

void TelamonCodeCorePrivate::setMaximumSize(int units)
{
    units = std::clamp(units, 1024, 256 * 1024 * 1024);
    if (units == m_maximumSize) {
        return;
    }
    m_maximumSize = units;
    Q_EMIT maximumSizeChanged();
    // The text on show is judged again under the new limit.
    if (m_doc) {
        const QString current = text();
        const int reason = reasonFor(current);
        if (reason != m_reason) {
            const bool wasModified = modified();
            setText(current);
            if (wasModified && reason == 0) {
                m_doc->setModified(true);
            }
        }
    }
}

void TelamonCodeCorePrivate::onContentsChange(int, int, int)
{
    if (m_internal == 0) {
        Q_EMIT textEdited();
    }
    Q_EMIT textChanged();
    const int lines = m_doc ? m_doc->blockCount() : 1;
    if (lines != m_lastLineCount) {
        m_lastLineCount = lines;
        Q_EMIT lineCountChanged();
    }
}

int TelamonCodeCorePrivate::editInt(const char *property) const
{
    return m_edit ? m_edit->property(property).toInt() : 0;
}

void TelamonCodeCorePrivate::selectRange(int anchor, int cursor)
{
    if (!m_edit) {
        return;
    }
    if (anchor == cursor) {
        m_edit->setProperty("cursorPosition", cursor);
    } else {
        QMetaObject::invokeMethod(m_edit, "select", Q_ARG(int, anchor), Q_ARG(int, cursor));
    }
}

void TelamonCodeCorePrivate::replacePreserving(const QString &input)
{
    if (!m_doc) {
        setText(input);
        return;
    }
    const QString text = normalized(input);
    if (m_loading || m_reason || reasonFor(text)) {
        // Too large to edit, or it was: nothing to keep.
        setText(text);
        return;
    }
    const QString old = plainText();
    if (old == text) {
        return;
    }

    qsizetype prefix = 0;
    const qsizetype common = std::min(old.size(), text.size());
    while (prefix < common && old.at(prefix) == text.at(prefix)) {
        ++prefix;
    }
    // Never cut a surrogate pair in two.
    if (prefix > 0 && prefix < common && old.at(prefix - 1).isHighSurrogate()) {
        --prefix;
    }
    qsizetype suffix = 0;
    while (suffix < common - prefix && old.at(old.size() - 1 - suffix) == text.at(text.size() - 1 - suffix)) {
        ++suffix;
    }
    if (suffix > 0 && old.at(old.size() - suffix).isLowSurrogate()) {
        --suffix;
    }
    const qsizetype oldEnd = old.size() - suffix;
    const qsizetype newEnd = text.size() - suffix;

    // The caret and the selection stay at the same line and column (clamped to
    // the new text): a predictable place for the reader when text arrives.
    struct Spot {
        int line = 0;
        int column = 0;
    };
    auto spotOf = [&](int p) {
        const QTextBlock b = m_doc->findBlock(std::clamp(p, 0, std::max(0, m_doc->characterCount() - 1)));
        return Spot{b.blockNumber(), p - b.position()};
    };
    const int cursor = editInt("cursorPosition");
    const int selStart = editInt("selectionStart");
    const int selEnd = editInt("selectionEnd");
    const Spot cursorSpot = spotOf(cursor);
    const Spot startSpot = spotOf(selStart);
    const Spot endSpot = spotOf(selEnd);
    const bool hadSelection = selStart != selEnd;
    const bool cursorAtEnd = cursor == selEnd;

    auto resolve = [&](const Spot &s) { return positionOfLine(s.line, s.column); };
    auto restore = [&] {
        if (hadSelection) {
            const int a = resolve(startSpot);
            const int b = resolve(endSpot);
            if (cursorAtEnd) {
                selectRange(a, b);
            } else {
                selectRange(b, a);
            }
        } else {
            selectRange(resolve(cursorSpot), resolve(cursorSpot));
        }
    };

    if (newEnd - prefix > m_sliceLoadFrom) {
        // A change this big is a new text: loaded in slices, as setText() does,
        // not in one stall. (`modified` is false once it is in.)
        setText(text);
        restore();
        return;
    }

    {
        ScopedInternal guard(m_internal);
        const bool undo = m_doc->isUndoRedoEnabled();
        // The undo history is gone either way: an edit from outside is not
        // something to undo step by step.
        m_doc->setUndoRedoEnabled(false);
        QTextCursor c(m_doc);
        c.setPosition(int(prefix));
        c.setPosition(int(oldEnd), QTextCursor::KeepAnchor);
        const QString middle = text.mid(prefix, newEnd - prefix);
        if (middle.isEmpty()) {
            c.removeSelectedText();
        } else {
            c.insertText(middle);
        }
        m_doc->setUndoRedoEnabled(undo);
        if (qsizetype(m_doc->characterCount()) - 1 != text.size()) {
            // The document read the text another way than the string: set it whole.
            m_doc->setPlainText(text);
        }
        m_doc->setModified(true);
    }

    restore();
}

// ---- Lines -----------------------------------------------------------------

QTextBlock TelamonCodeCorePrivate::blockFor(int line) const
{
    if (!m_doc) {
        return {};
    }
    return m_doc->findBlockByNumber(std::clamp(line, 0, std::max(0, m_doc->blockCount() - 1)));
}

int TelamonCodeCorePrivate::lineOfPosition(int position) const
{
    if (!m_doc) {
        return 0;
    }
    return m_doc->findBlock(std::clamp(position, 0, std::max(0, m_doc->characterCount() - 1))).blockNumber();
}

int TelamonCodeCorePrivate::columnOfPosition(int position) const
{
    if (!m_doc) {
        return 0;
    }
    const int p = std::clamp(position, 0, std::max(0, m_doc->characterCount() - 1));
    return p - m_doc->findBlock(p).position();
}

int TelamonCodeCorePrivate::positionOfLine(int line, int column) const
{
    const QTextBlock b = blockFor(line);
    if (!b.isValid()) {
        return 0;
    }
    return b.position() + std::clamp(column, 0, std::max(0, b.length() - 1));
}

int TelamonCodeCorePrivate::lineLength(int line) const
{
    const QTextBlock b = blockFor(line);
    return b.isValid() ? std::max(0, b.length() - 1) : 0;
}

qreal TelamonCodeCorePrivate::lineTopY(int line) const
{
    const QTextBlock b = blockFor(line);
    return b.isValid() ? m_doc->documentLayout()->blockBoundingRect(b).top() : 0;
}

qreal TelamonCodeCorePrivate::lineHeight(int line) const
{
    const QTextBlock b = blockFor(line);
    return b.isValid() ? m_doc->documentLayout()->blockBoundingRect(b).height() : 0;
}

int TelamonCodeCorePrivate::lineAtY(qreal y) const
{
    if (!m_doc || m_doc->blockCount() <= 1) {
        return 0;
    }
    // The last line whose top is not below y.
    int lo = 0;
    int hi = m_doc->blockCount() - 1;
    QAbstractTextDocumentLayout *layout = m_doc->documentLayout();
    while (lo < hi) {
        const int mid = lo + (hi - lo + 1) / 2;
        if (layout->blockBoundingRect(m_doc->findBlockByNumber(mid)).top() <= y) {
            lo = mid;
        } else {
            hi = mid - 1;
        }
    }
    return lo;
}

// ---- Keys ------------------------------------------------------------------

void TelamonCodeCorePrivate::indent(bool unindent, int width, bool spaces)
{
    if (!m_doc || !m_edit || m_reason || m_loading) {
        return;
    }
    width = std::clamp(width, 1, 16);
    const int cursor = editInt("cursorPosition");
    const int s = editInt("selectionStart");
    const int e = editInt("selectionEnd");
    QTextCursor c(m_doc);

    if (s == e && !unindent) {
        const QTextBlock b = m_doc->findBlock(cursor);
        const int column = cursor - b.position();
        c.setPosition(cursor);
        c.insertText(spaces ? QString(width - column % width, u' ') : QString(u'\t'));
        return;
    }

    const QTextBlock first = m_doc->findBlock(s);
    QTextBlock last = m_doc->findBlock(e);
    // A selection that ends at the start of a line does not take that line.
    if (e > s && e == last.position()) {
        last = last.previous();
    }
    const QString unit = spaces ? QString(width, u' ') : QString(u'\t');
    int removedOnCursorLine = 0;
    c.beginEditBlock();
    for (QTextBlock b = first; b.isValid(); b = b.next()) {
        if (!unindent) {
            // An empty line gets no trailing white space.
            if (b.length() > 1) {
                c.setPosition(b.position());
                c.insertText(unit);
            }
        } else {
            const QString line = b.text();
            int n = 0;
            if (line.startsWith(u'\t')) {
                n = 1;
            } else {
                while (n < width && n < line.size() && line.at(n) == u' ') {
                    ++n;
                }
            }
            if (n > 0) {
                c.setPosition(b.position());
                c.setPosition(b.position() + n, QTextCursor::KeepAnchor);
                c.removeSelectedText();
                if (s == e) {
                    removedOnCursorLine = n;
                }
            }
        }
        if (b == last) {
            break;
        }
    }
    c.endEditBlock();
    if (s == e) {
        const int lineStart = first.position();
        const int p = std::max(lineStart, cursor - removedOnCursorLine);
        selectRange(p, p);
    } else {
        selectRange(first.position(), last.position() + std::max(0, last.length() - 1));
    }
}

void TelamonCodeCorePrivate::smartHome(bool extendSelection)
{
    if (!m_doc || !m_edit) {
        return;
    }
    const int cursor = editInt("cursorPosition");
    const int s = editInt("selectionStart");
    const int e = editInt("selectionEnd");
    const QTextBlock b = m_doc->findBlock(cursor);
    const QString line = b.text();
    int firstText = 0;
    while (firstText < line.size() && (line.at(firstText) == u' ' || line.at(firstText) == u'\t')) {
        ++firstText;
    }
    int target = b.position() + firstText;
    if (firstText >= line.size() || cursor - b.position() == firstText) {
        // A blank line, or already at the first character: the start.
        target = b.position();
    }
    if (extendSelection) {
        const int anchor = (s == e) ? cursor : (cursor == e ? s : e);
        selectRange(anchor, target);
    } else {
        selectRange(target, target);
    }
}

// ---- Syntax ----------------------------------------------------------------

void TelamonCodeCorePrivate::setLanguage(const QString &language)
{
    if (language == m_language) {
        return;
    }
    m_language = language;
    resolveSyntax();
}

void TelamonCodeCorePrivate::setFileName(const QString &fileName)
{
    if (fileName == m_fileName) {
        return;
    }
    m_fileName = fileName;
    resolveSyntax();
}

void TelamonCodeCorePrivate::resolveSyntax()
{
    KSyntaxHighlighting::Definition def;
    const QString language = m_language.trimmed().left(256);
    if (!language.isEmpty()) {
        KSyntaxHighlighting::Repository &repo = repository();
        def = repo.definitionForName(language);
        if (!def.isValid()) {
            // "c++", "RUST", "js": the name, or an alternative name, any case.
            const auto all = repo.definitions();
            for (const KSyntaxHighlighting::Definition &d : all) {
                if (d.name().compare(language, Qt::CaseInsensitive) == 0 || d.translatedName().compare(language, Qt::CaseInsensitive) == 0) {
                    def = d;
                    break;
                }
                const QStringList alternatives = d.alternativeNames();
                for (const QString &alt : alternatives) {
                    if (alt.compare(language, Qt::CaseInsensitive) == 0) {
                        def = d;
                        break;
                    }
                }
                if (def.isValid()) {
                    break;
                }
            }
        }
        if (!def.isValid() && language.size() <= 16 && !language.contains(u'/') && !language.contains(u' ')) {
            // An extension: "py", "rs", ".cpp".
            const QString ext = language.startsWith(u'.') ? language.mid(1) : language;
            if (!ext.isEmpty()) {
                def = repo.definitionForFileName(QStringLiteral("x.") + ext);
            }
        }
        if (!def.isValid() && language.contains(u'/')) {
            def = repo.definitionForMimeType(language);
        }
    }
    if (!def.isValid() && !m_fileName.isEmpty()) {
        const QString name = QFileInfo(m_fileName.left(4096)).fileName();
        if (!name.isEmpty()) {
            def = repository().definitionForFileName(name);
        }
    }
    const QString name = def.isValid() ? def.name() : QString();
    if (m_hl) {
        m_hl->setDefinition(def);
    }
    m_syntaxName = name;
    Q_EMIT syntaxChanged();
}

void TelamonCodeCorePrivate::setSyntaxPalette(const QVariantMap &palette)
{
    m_palette = palette;
    rebuildStyles();
    Q_EMIT syntaxPaletteChanged();
}

void TelamonCodeCorePrivate::rebuildStyles()
{
    QHash<int, QTextCharFormat> styles;
    for (const StyleGroup &g : styleGroups) {
        const auto it = m_palette.constFind(QLatin1String(g.group));
        if (it == m_palette.cend()) {
            continue;
        }
        const QVariantMap entry = it->toMap();
        QTextCharFormat f;
        const QColor color = entry.value(QStringLiteral("color")).value<QColor>();
        if (color.isValid()) {
            f.setForeground(color);
        }
        if (entry.value(QStringLiteral("bold")).toBool()) {
            f.setFontWeight(QFont::Bold);
        }
        if (entry.value(QStringLiteral("italic")).toBool()) {
            f.setFontItalic(true);
        }
        if (entry.value(QStringLiteral("underline")).toBool()) {
            f.setFontUnderline(true);
        }
        if (f != QTextCharFormat()) {
            styles.insert(int(g.style), f);
        }
    }
    if (m_hl) {
        m_hl->setStyles(styles);
    }
}

void TelamonCodeCorePrivate::setHighlighting(bool on)
{
    if (on == m_highlighting) {
        return;
    }
    m_highlighting = on;
    if (m_hl) {
        m_hl->setEnabled(on);
    }
    Q_EMIT highlightingChanged();
}

void TelamonCodeCorePrivate::setViewport(qreal top, qreal bottom)
{
    if (!m_hl || !m_doc || !std::isfinite(top) || !std::isfinite(bottom)) {
        return;
    }
    m_hl->setViewport(lineAtY(top), lineAtY(std::max(top, bottom)));
}

QVariantList TelamonCodeCorePrivate::formatRuns(int line) const
{
    QVariantList out;
    const QTextBlock b = blockFor(line);
    if (!b.isValid()) {
        return out;
    }
    const auto formats = b.layout()->formats();
    for (const QTextLayout::FormatRange &r : formats) {
        QVariantMap m;
        m.insert(QStringLiteral("start"), r.start);
        m.insert(QStringLiteral("length"), r.length);
        m.insert(QStringLiteral("color"), r.format.foreground().color().name());
        m.insert(QStringLiteral("bold"), r.format.fontWeight() >= QFont::Bold);
        m.insert(QStringLiteral("italic"), r.format.fontItalic());
        out.append(m);
    }
    return out;
}

bool TelamonCodeCorePrivate::highlightSettled() const
{
    return !m_hl || m_hl->settled();
}

void TelamonCodeCorePrivate::highlightNow()
{
    if (m_hl) {
        m_hl->runNow();
    }
}

// ---- Marks -----------------------------------------------------------------

namespace
{
// A line number from a JS value: a number, a numeric string.
bool lineFrom(const QVariant &v, int *out)
{
    bool ok = false;
    const double d = v.toDouble(&ok);
    if (!ok || !std::isfinite(d) || d < 1 || d > 2147483647.0) {
        return false;
    }
    *out = int(d);
    return true;
}
} // namespace

void TelamonCodeCorePrivate::markLines(const QVariantList &ranges, int kind, int fadeMs)
{
    if (!m_doc || m_reason || m_loading) {
        return;
    }
    kind = std::clamp(kind, 0, 1);
    fadeMs = std::clamp(fadeMs, 0, 600'000);
    const int lines = lineCount();
    const qint64 now = m_clock.elapsed();
    bool added = false;
    int seen = 0;
    for (const QVariant &item : ranges) {
        if (++seen > MaxMarkRanges || m_marks.size() >= MaxMarks) {
            break;
        }
        int first = 0;
        int last = 0;
        bool ok = false;
        if (item.typeId() == QMetaType::QVariantList) {
            const QVariantList pair = item.toList();
            if (pair.size() == 1) {
                ok = lineFrom(pair.at(0), &first);
                last = first;
            } else if (pair.size() >= 2) {
                ok = lineFrom(pair.at(0), &first) && lineFrom(pair.at(1), &last);
            }
        } else if (item.typeId() == QMetaType::QVariantMap) {
            const QVariantMap map = item.toMap();
            const QVariant a = map.contains(QStringLiteral("first")) ? map.value(QStringLiteral("first")) : map.value(QStringLiteral("from"));
            const QVariant b = map.contains(QStringLiteral("last")) ? map.value(QStringLiteral("last")) : map.value(QStringLiteral("to"));
            ok = lineFrom(a, &first);
            if (ok) {
                if (b.isValid() && !b.isNull()) {
                    ok = lineFrom(b, &last);
                } else {
                    last = first;
                }
            }
        } else {
            ok = lineFrom(item, &first);
            last = first;
        }
        if (!ok) {
            continue;
        }
        if (last < first) {
            std::swap(first, last);
        }
        if (first > lines) {
            continue;
        }
        last = std::min(last, lines);
        const QTextBlock fb = blockFor(first - 1);
        const QTextBlock lb = blockFor(last - 1);
        QTextCursor c(m_doc);
        c.setPosition(fb.position());
        c.setPosition(lb.position() + std::max(0, lb.length() - 1), QTextCursor::KeepAnchor);
        m_marks.append(Mark{c, kind, now, fadeMs});
        added = true;
    }
    if (added) {
        ++m_markRevision;
        Q_EMIT marksChanged();
        tickMarks();
    }
}

void TelamonCodeCorePrivate::clearMarks()
{
    if (m_marks.isEmpty()) {
        return;
    }
    m_marks.clear();
    m_markTimer.stop();
    ++m_markRevision;
    Q_EMIT marksChanged();
}

qreal TelamonCodeCorePrivate::markAlpha(const Mark &mark, qint64 now) const
{
    if (mark.fadeMs <= 0) {
        return 1;
    }
    const qint64 elapsed = now - mark.created;
    if (elapsed >= mark.fadeMs) {
        return 0;
    }
    return m_animate ? 1.0 - double(elapsed) / double(mark.fadeMs) : 1.0;
}

// Drops the marks that have faded out and sets the next tick: every step while
// something fades, or once at the end of the shortest wait with reduced motion.
void TelamonCodeCorePrivate::tickMarks()
{
    const qint64 now = m_clock.elapsed();
    bool removed = false;
    bool fading = false;
    qint64 nextEnd = std::numeric_limits<qint64>::max();
    for (qsizetype i = m_marks.size() - 1; i >= 0; --i) {
        const Mark &m = m_marks.at(i);
        if (m.fadeMs <= 0) {
            continue;
        }
        if (now - m.created >= m.fadeMs) {
            m_marks.removeAt(i);
            removed = true;
        } else {
            fading = true;
            nextEnd = std::min(nextEnd, m.created + m.fadeMs);
        }
    }
    if (fading) {
        const int wait = m_animate ? m_markStep : int(std::clamp<qint64>(nextEnd - now, 1, 600'000));
        m_markTimer.start(wait);
    } else {
        m_markTimer.stop();
    }
    if (removed || (fading && m_animate)) {
        ++m_markRevision;
        Q_EMIT marksChanged();
    }
}

void TelamonCodeCorePrivate::setAnimateMarks(bool animate)
{
    if (animate == m_animate) {
        return;
    }
    m_animate = animate;
    Q_EMIT animateMarksChanged();
    tickMarks();
}

void TelamonCodeCorePrivate::setMarkStepMs(int ms)
{
    ms = std::clamp(ms, 10, 1000);
    if (ms == m_markStep) {
        return;
    }
    m_markStep = ms;
    Q_EMIT markStepMsChanged();
}

QVariantList TelamonCodeCorePrivate::markSpans() const
{
    QVariantList out;
    if (!m_doc) {
        return out;
    }
    for (const Mark &m : m_marks) {
        QVariantMap map;
        map.insert(QStringLiteral("first"), m_doc->findBlock(m.range.selectionStart()).blockNumber() + 1);
        map.insert(QStringLiteral("last"), m_doc->findBlock(m.range.selectionEnd()).blockNumber() + 1);
        map.insert(QStringLiteral("kind"), m.kind);
        out.append(map);
    }
    return out;
}

QList<TelamonCodeCorePrivate::MarkSpan> TelamonCodeCorePrivate::marksIn(int firstBlock, int lastBlock) const
{
    QList<MarkSpan> out;
    if (!m_doc) {
        return out;
    }
    const qint64 now = m_clock.elapsed();
    for (const Mark &m : m_marks) {
        const qreal alpha = markAlpha(m, now);
        if (alpha <= 0) {
            continue;
        }
        const int fb = m_doc->findBlock(m.range.selectionStart()).blockNumber();
        const int lb = m_doc->findBlock(m.range.selectionEnd()).blockNumber();
        if (lb < firstBlock || fb > lastBlock) {
            continue;
        }
        out.append(MarkSpan{fb, lb, m.kind, alpha});
    }
    return out;
}
