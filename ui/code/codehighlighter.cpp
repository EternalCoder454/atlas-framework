// See codehighlighter.h.
#include "codehighlighter.h"

#include <QAbstractTextDocumentLayout>
#include <QTextBlockUserData>
#include <QTextDocument>

#include <KSyntaxHighlighting/Theme>

#include <algorithm>
#include <limits>

namespace
{
using KSyntaxHighlighting::State;

// Main-thread time a slice may take, and an edit may take before the slices
// carry on.
constexpr qint64 SliceNs = 6'000'000;
constexpr qint64 EditNs = 3'000'000;
// An edit or load this large makes every line stale at once, instead of the
// lines it touched one by one.
constexpr int BigChange = 100'000;

// What a line remembers: the state it ended in, and the generations of the
// reading and of the colours it holds (a generation that is not the current one
// is stale). `hasEnd` is false until the line was read once; a stale line keeps
// its old end state, to see whether reading it again changes anything.
class BlockData : public QTextBlockUserData
{
public:
    State end;
    quint32 stateGen = 0;
    quint32 formatGen = 0;
    bool hasEnd = false;
};

BlockData *dataOf(const QTextBlock &block)
{
    return dynamic_cast<BlockData *>(block.userData());
}

BlockData *ensureData(QTextBlock block)
{
    if (auto *data = dataOf(block)) {
        return data;
    }
    // Another kind of user data would be replaced: nothing else puts any on the
    // editor's document.
    auto *data = new BlockData;
    block.setUserData(data);
    return data;
}
} // namespace

TelamonCodeHighlighter::TelamonCodeHighlighter(QTextDocument *document, QObject *parent)
    : QObject(parent)
    , m_doc(document)
{
    m_timer.setSingleShot(true);
    m_timer.setInterval(0);
    connect(&m_timer, &QTimer::timeout, this, [this] { run(SliceNs); });
    if (m_doc) {
        connect(m_doc, &QTextDocument::contentsChange, this, &TelamonCodeHighlighter::onContentsChange);
        m_resume = QTextCursor(m_doc);
    }
}

TelamonCodeHighlighter::~TelamonCodeHighlighter()
{
    m_timer.stop();
    if (m_doc) {
        disconnect(m_doc, nullptr, this, nullptr);
        // Our data must not outlive us on blocks a later highlighter reads.
        for (QTextBlock b = m_doc->begin(); b.isValid(); b = b.next()) {
            if (dataOf(b)) {
                b.setUserData(nullptr);
            }
        }
    }
}

bool TelamonCodeHighlighter::usable() const
{
    return m_enabled && definition().isValid();
}

void TelamonCodeHighlighter::setDefinition(const KSyntaxHighlighting::Definition &def)
{
    AbstractHighlighter::setDefinition(def);
    invalidateAll();
}

void TelamonCodeHighlighter::setStyles(const QHash<int, QTextCharFormat> &styles)
{
    m_styles = styles;
    m_formats.clear();
    ++m_formatGen;
    kick();
}

void TelamonCodeHighlighter::setEnabled(bool enabled)
{
    if (m_enabled == enabled) {
        return;
    }
    m_enabled = enabled;
    invalidateAll();
}

void TelamonCodeHighlighter::setViewport(int firstBlock, int lastBlock)
{
    if (lastBlock < firstBlock) {
        std::swap(firstBlock, lastBlock);
    }
    const int first = std::max(0, firstBlock - Margin);
    const int last = std::max(first, lastBlock + Margin);
    if (first == m_applyFirst && last == m_applyLast) {
        return;
    }
    m_applyFirst = first;
    m_applyLast = last;
    kick();
}

void TelamonCodeHighlighter::invalidateAll()
{
    ++m_stateGen;
    ++m_formatGen;
    if (m_doc) {
        m_resume = QTextCursor(m_doc);
    }
    kick();
}

bool TelamonCodeHighlighter::settled() const
{
    return !m_timer.isActive() && !m_busy;
}

// Reads the lines in view now, for a moment (what changed shows in the next
// frame, with no flash of plain text), and the rest from the event loop.
void TelamonCodeHighlighter::kick()
{
    if (m_busy) {
        schedule();
        return;
    }
    m_timer.stop();
    run(EditNs);
}

void TelamonCodeHighlighter::schedule()
{
    if (!m_timer.isActive()) {
        m_timer.start();
    }
}

void TelamonCodeHighlighter::runNow(qint64 budgetNs)
{
    m_timer.stop();
    for (int guard = 0; guard < 100000; ++guard) {
        run(budgetNs > 0 ? budgetNs : std::numeric_limits<qint64>::max());
        if (settled() || budgetNs > 0) {
            break;
        }
    }
}

// The same mapping from KSyntaxHighlighting's text styles to our formats for
// every format with that style.
const TelamonCodeHighlighter::Style &TelamonCodeHighlighter::styleFor(const KSyntaxHighlighting::Format &format)
{
    const int id = format.id();
    if (auto it = m_formats.constFind(id); it != m_formats.cend()) {
        return *it;
    }
    Style s;
    s.format = m_styles.value(int(format.textStyle()));
    s.plain = s.format == QTextCharFormat();
    return *m_formats.insert(id, s);
}

void TelamonCodeHighlighter::applyFormat(int offset, int length, const KSyntaxHighlighting::Format &format)
{
    if (!m_collect || length <= 0 || !format.isValid()) {
        return;
    }
    const Style &s = styleFor(format);
    if (s.plain) {
        return;
    }
    // Neighbours with the same look are one range.
    if (!m_ranges.isEmpty()) {
        QTextLayout::FormatRange &last = m_ranges.last();
        if (last.start + last.length == offset && last.format == s.format) {
            last.length += length;
            return;
        }
    }
    QTextLayout::FormatRange r;
    r.start = offset;
    r.length = length;
    r.format = s.format;
    m_ranges.append(r);
}

void TelamonCodeHighlighter::process(const QTextBlock &block, bool apply)
{
    BlockData *data = ensureData(block);
    State in;
    if (const QTextBlock prev = block.previous(); prev.isValid()) {
        if (const auto *pd = dataOf(prev)) {
            in = pd->end;
        }
    }
    State end = in;
    m_ranges.clear();
    // block.length() counts the paragraph separator.
    if (usable() && block.length() - 1 <= MaxLineLength) {
        m_collect = apply;
        end = highlightLine(block.text(), in);
        m_collect = false;
    }

    if (apply) {
        QTextLayout *layout = block.layout();
        const QList<QTextLayout::FormatRange> old = layout->formats();
        // While the input method composes text in the line, its formats (the
        // underline) stay and ours move past it (what QSyntaxHighlighter does).
        if (const int preeditLength = layout->preeditAreaText().size(); preeditLength > 0) {
            const int preedit = layout->preeditAreaPosition();
            QList<QTextLayout::FormatRange> ranges;
            for (const QTextLayout::FormatRange &r : old) {
                if (r.start >= preedit && r.start + r.length <= preedit + preeditLength) {
                    ranges.append(r);
                }
            }
            for (QTextLayout::FormatRange r : std::as_const(m_ranges)) {
                if (r.start >= preedit) {
                    r.start += preeditLength;
                } else if (r.start + r.length >= preedit) {
                    r.length += preeditLength;
                }
                ranges.append(r);
            }
            m_ranges = std::move(ranges);
        }
        // Plain before and after: the layout has nothing to learn.
        if (!m_ranges.isEmpty() || !old.isEmpty()) {
            layout->setFormats(m_ranges);
            // Tells a Qt Quick TextEdit that this line's nodes are stale: it
            // keeps the nodes of every line it was not told of (a change of
            // formats alone is no change of text).
            Q_EMIT m_doc->documentLayout()->updateBlock(block);
            if (m_dirtyFrom < 0) {
                m_dirtyFrom = block.position();
            } else {
                m_dirtyFrom = std::min(m_dirtyFrom, block.position());
            }
            m_dirtyEnd = std::max(m_dirtyEnd, block.position() + block.length());
        }
        data->formatGen = m_formatGen;
    }

    const bool changed = !data->hasEnd || !(data->end == end);
    data->end = end;
    data->hasEnd = true;
    data->stateGen = m_stateGen;
    if (!apply && changed) {
        data->formatGen = 0;
    }
    if (changed) {
        // The next line was read from a state that is not this line's end now.
        const QTextBlock next = block.next();
        if (next.isValid()) {
            BlockData *nd = ensureData(next);
            nd->stateGen = 0;
            nd->formatGen = 0;
            // Every line before the resume point is fresh: keep it so.
            if (m_resume.position() > next.position()) {
                m_resume.setPosition(next.position());
            }
        }
    }
}

void TelamonCodeHighlighter::flushDirty()
{
    if (m_dirtyFrom >= 0 && m_doc) {
        const int from = std::min(m_dirtyFrom, m_doc->characterCount());
        const int end = std::min(m_dirtyEnd, m_doc->characterCount());
        m_busy = true;
        m_doc->markContentsDirty(from, std::max(0, end - from));
        m_busy = false;
    }
    m_dirtyFrom = -1;
    m_dirtyEnd = 0;
}

void TelamonCodeHighlighter::run(qint64 budgetNs)
{
    if (!m_doc || m_busy) {
        return;
    }
    m_busy = true;
    QElapsedTimer clock;
    clock.start();
    bool more = false;
    const int blocks = m_doc->blockCount();
    const int wantLast = std::min(m_applyLast, blocks - 1);
    const int applyFirst = m_applyFirst;
    const int applyLast = m_applyLast;

    if (usable()) {
        // 1. Read the lines that are stale, in order, as far as the end of the
        // viewport. A fresh line is passed over: its end state is right.
        QTextBlock block = m_resume.isNull() ? m_doc->begin() : m_resume.block();
        // The line before has to be read: its end is this line's start.
        for (QTextBlock before = block.previous(); before.isValid(); before = block.previous()) {
            const BlockData *bd = dataOf(before);
            if (bd && bd->stateGen == m_stateGen) {
                break;
            }
            block = before;
        }
        int n = block.isValid() ? block.blockNumber() : blocks;
        int count = 0;
        while (block.isValid() && n <= wantLast) {
            const BlockData *data = dataOf(block);
            if (!data || data->stateGen != m_stateGen) {
                process(block, n >= applyFirst && n <= applyLast);
                if ((++count & 7) == 0 && clock.nsecsElapsed() > budgetNs) {
                    block = block.next();
                    more = true;
                    break;
                }
            }
            block = block.next();
            ++n;
        }
        if (block.isValid()) {
            m_resume.setPosition(block.position());
        } else {
            m_resume.setPosition(std::max(0, m_doc->characterCount() - 1));
        }

        // 2. Set the colours of the lines in view that have none (scrolled to,
        // or a new theme). Every line above them has its state now.
        if (!more) {
            QTextBlock b = m_doc->findBlockByNumber(std::min(applyFirst, blocks - 1));
            for (int i = std::min(applyFirst, blocks - 1); b.isValid() && i <= wantLast; ++i, b = b.next()) {
                const BlockData *data = dataOf(b);
                if (data && data->stateGen == m_stateGen && data->formatGen != m_formatGen) {
                    process(b, true);
                    // Reading it again moved a state: the lines after it are
                    // stale now, so another turn.
                    if (const BlockData *nd = dataOf(b.next()); nd && nd->stateGen != m_stateGen) {
                        more = true;
                    }
                    if (clock.nsecsElapsed() > budgetNs) {
                        more = true;
                        break;
                    }
                }
            }
        }
    } else {
        // Plain text: clear the colours of the lines in view, nothing is read.
        QTextBlock b = m_doc->findBlockByNumber(std::min(applyFirst, blocks - 1));
        for (int i = std::min(applyFirst, blocks - 1); b.isValid() && i <= wantLast; ++i, b = b.next()) {
            const BlockData *data = dataOf(b);
            if (!data || data->formatGen != m_formatGen) {
                process(b, true);
            }
        }
    }

    flushDirty();
    m_busy = false;
    if (more) {
        schedule();
    }
}

// An edit: its lines are read again at once (a few milliseconds' worth), the
// rest by the slices.
void TelamonCodeHighlighter::onContentsChange(int position, int removed, int added)
{
    if (m_busy || !m_doc) {
        return;
    }
    if (removed + added > BigChange) {
        invalidateAll();
        run(EditNs);
        return;
    }
    const int last = std::max(0, std::min(position + added, m_doc->characterCount() - 1));
    QTextBlock first = m_doc->findBlock(std::min(position, last));
    if (!first.isValid()) {
        return;
    }
    const QTextBlock lastBlock = m_doc->findBlock(last);
    for (QTextBlock b = first; b.isValid(); b = b.next()) {
        BlockData *d = ensureData(b);
        d->stateGen = 0;
        d->formatGen = 0;
        if (b == lastBlock) {
            break;
        }
    }
    // The line after the change was read from a state that is gone.
    if (const QTextBlock after = lastBlock.next(); after.isValid()) {
        BlockData *d = ensureData(after);
        d->stateGen = 0;
        d->formatGen = 0;
    }
    if (m_resume.isNull() || m_resume.position() > first.position()) {
        m_resume.setPosition(first.position());
    }
    run(EditNs);
}
