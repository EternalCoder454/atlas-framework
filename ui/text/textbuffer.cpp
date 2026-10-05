#include "textbuffer.h"

#include <QThreadPool>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstring>

namespace AtlasTextDetail {

namespace {

// Chunks smaller than this are checked on the calling thread: a task costs more.
constexpr qsizetype InlineLimit = 32 * 1024;
// The size of an add-buffer block. Larger insertions get a block of their own.
constexpr qsizetype AddBlockSize = 64 * 1024;
const char Replacement[] = "\xEF\xBF\xBD";

std::shared_ptr<const Block> wrapBytes(QByteArray bytes)
{
    auto b = std::make_shared<Block>();
    b->bytes = std::move(bytes);
    b->ptr = b->bytes.constData();
    return b;
}

// Checks [from, to) of `block` and cuts it into pieces. Invalid sequences
// (including one cut off by `to`) are replaced, which copies the range.
JobResult processRange(const std::shared_ptr<const Block> &block, qsizetype from, qsizetype to)
{
    JobResult res;
    const char *p = block->ptr;
    qsizetype i = from, copied = from;
    QByteArray out;
    while (i < to) {
        // Eight ASCII bytes at a time.
        while (i + 8 <= to) {
            quint64 w;
            std::memcpy(&w, p + i, 8);
            if (w & 0x8080808080808080ULL)
                break;
            i += 8;
        }
        if (i >= to)
            break;
        if (uchar(p[i]) < 0x80) {
            ++i;
            continue;
        }
        const SeqResult r = checkUtf8Sequence(reinterpret_cast<const uchar *>(p) + i, to - i);
        if (r.kind == SeqKind::Valid) {
            i += r.len;
            continue;
        }
        if (!res.invalid) {
            res.invalid = true;
            out.reserve(to - from + 16);
        }
        out.append(p + copied, i - copied);
        out.append(Replacement, 3);
        i += std::max(1, r.len);
        copied = i;
    }
    if (res.invalid) {
        out.append(p + copied, to - copied);
        const auto b = wrapBytes(std::move(out));
        appendPieces(b, 0, b->bytes.size(), res.pieces);
    } else {
        appendPieces(block, from, to - from, res.pieces);
    }
    return res;
}

} // namespace

struct LoadState {
    std::atomic<qint64> bytesIn{0};
    std::atomic<qint64> bytesDone{0};
};

SeqResult checkUtf8Sequence(const uchar *p, qsizetype avail)
{
    if (avail <= 0)
        return {SeqKind::Incomplete, 0};
    const uchar b0 = p[0];
    if (b0 < 0x80)
        return {SeqKind::Valid, 1};
    int need = 0;
    uchar lo = 0x80, hi = 0xBF;
    if (b0 >= 0xC2 && b0 <= 0xDF) {
        need = 2;
    } else if (b0 >= 0xE0 && b0 <= 0xEF) {
        need = 3;
        if (b0 == 0xE0)
            lo = 0xA0;
        else if (b0 == 0xED)
            hi = 0x9F;
    } else if (b0 >= 0xF0 && b0 <= 0xF4) {
        need = 4;
        if (b0 == 0xF0)
            lo = 0x90;
        else if (b0 == 0xF4)
            hi = 0x8F;
    } else {
        return {SeqKind::Invalid, 1};
    }
    for (int j = 1; j < need; ++j) {
        if (j >= avail)
            return {SeqKind::Incomplete, int(avail)};
        const uchar c = p[j];
        const uchar l = j == 1 ? lo : uchar(0x80);
        const uchar h = j == 1 ? hi : uchar(0xBF);
        if (c < l || c > h)
            return {SeqKind::Invalid, j};
    }
    return {SeqKind::Valid, need};
}

TextBuffer::TextBuffer() : m_state(std::make_shared<LoadState>()), m_notifier(std::make_shared<Notifier>()) {}

TextBuffer::~TextBuffer() = default;

void TextBuffer::setLoadNotify(std::function<void()> notify)
{
    QMutexLocker lock(&m_notifier->mutex);
    m_notifier->fn = std::move(notify);
}

void TextBuffer::beginLoad()
{
    m_slots.clear(); // results of an unfinished load are dropped
    m_state = std::make_shared<LoadState>();
    m_tree = TextTree();
    ++m_revision;
    m_loading = true;
    m_inputDone = false;
    m_hadInvalid = false;
    m_loadFailed = false;
    m_carry.clear();
}

void TextBuffer::pushImmediate(std::vector<Piece> pieces)
{
    std::promise<JobResult> pr;
    JobResult r;
    r.pieces = std::move(pieces);
    Slot s;
    s.result = pr.get_future();
    pr.set_value(std::move(r));
    m_slots.push_back(std::move(s));
}

void TextBuffer::appendData(const char *data, qsizetype size)
{
    if (data && size > 0)
        appendData(QByteArray(data, size));
}

void TextBuffer::appendData(const QByteArray &chunk)
{
    if (!m_loading || m_inputDone || chunk.isEmpty())
        return;
    const qsizetype n = chunk.size();
    m_state->bytesIn += n;
    qsizetype from = 0;

    // A character left over from the last chunk: finish it, or replace it.
    if (!m_carry.isEmpty()) {
        QByteArray tmp = m_carry;
        tmp.append(chunk.constData(), std::min<qsizetype>(3, n));
        const SeqResult r = checkUtf8Sequence(reinterpret_cast<const uchar *>(tmp.constData()), tmp.size());
        if (r.kind == SeqKind::Incomplete) {
            m_carry = tmp;
            m_state->bytesDone += n;
            return;
        }
        const qsizetype used = std::max<qsizetype>(0, r.len - m_carry.size());
        std::vector<Piece> v;
        if (r.kind == SeqKind::Valid) {
            appendPieces(wrapBytes(tmp.left(r.len)), 0, r.len, v);
        } else {
            appendPieces(wrapBytes(QByteArray(Replacement, 3)), 0, 3, v);
            m_hadInvalid = true;
        }
        pushImmediate(std::move(v));
        m_carry.clear();
        from = used;
        m_state->bytesDone += used;
    }

    // A character cut off at the end waits for the next chunk.
    qsizetype to = n;
    for (qsizetype k = 1; k <= 3 && k <= to - from; ++k) {
        const uchar c = uchar(chunk[to - k]);
        if ((c & 0xC0) == 0x80)
            continue;
        if (c >= 0xC0) {
            const SeqResult r = checkUtf8Sequence(reinterpret_cast<const uchar *>(chunk.constData()) + to - k, k);
            if (r.kind == SeqKind::Incomplete) {
                m_carry = chunk.mid(to - k, k);
                to -= k;
                m_state->bytesDone += k;
            }
        }
        break;
    }
    if (to <= from)
        return;

    const auto block = wrapBytes(chunk);
    if (to - from < InlineLimit) {
        JobResult r = processRange(block, from, to);
        m_state->bytesDone += to - from;
        if (r.invalid)
            m_hadInvalid = true;
        pushImmediate(std::move(r.pieces));
        return;
    }
    auto promise = std::make_shared<std::promise<JobResult>>();
    Slot s;
    s.result = promise->get_future();
    m_slots.push_back(std::move(s));
    auto state = m_state;
    auto notifier = m_notifier;
    QThreadPool::globalInstance()->start([=]() {
        JobResult r;
        try {
            r = processRange(block, from, to);
        } catch (...) {
            r = JobResult();
            r.failed = true;
        }
        state->bytesDone += to - from;
        promise->set_value(std::move(r));
        std::function<void()> fn;
        {
            QMutexLocker lock(&notifier->mutex);
            fn = notifier->fn;
        }
        if (fn)
            fn();
    });
}

bool TextBuffer::pollLoad()
{
    if (!m_loading)
        return true;
    std::vector<Piece> batch;
    while (!m_slots.empty() && m_slots.front().result.wait_for(std::chrono::seconds(0)) == std::future_status::ready) {
        JobResult r;
        try {
            r = m_slots.front().result.get();
        } catch (...) {
            r.failed = true;
        }
        m_slots.pop_front();
        if (r.failed)
            m_loadFailed = true;
        if (r.invalid)
            m_hadInvalid = true;
        batch.insert(batch.end(), std::make_move_iterator(r.pieces.begin()), std::make_move_iterator(r.pieces.end()));
    }
    if (!batch.empty()) {
        m_tree = m_tree.withInserted(m_tree.length(), std::move(batch));
        ++m_revision;
    }
    if (m_inputDone && m_slots.empty()) {
        m_loading = false;
        return true;
    }
    return false;
}

bool TextBuffer::endLoad(bool wait)
{
    if (!m_loading)
        return true;
    if (!m_inputDone) {
        if (!m_carry.isEmpty()) {
            std::vector<Piece> v;
            appendPieces(wrapBytes(QByteArray(Replacement, 3)), 0, 3, v);
            pushImmediate(std::move(v));
            m_hadInvalid = true;
            m_carry.clear();
        }
        m_inputDone = true;
    }
    if (wait) {
        for (Slot &s : m_slots) {
            if (s.result.valid())
                s.result.wait();
        }
    }
    return pollLoad();
}

double TextBuffer::loadProgress() const
{
    if (!m_loading)
        return 1.0;
    const qint64 in = m_state->bytesIn.load();
    if (in <= 0)
        return 0.0;
    return std::min(1.0, double(m_state->bytesDone.load()) / double(in));
}

void TextBuffer::setText(const QString &text)
{
    beginLoad();
    appendData(text.toUtf8());
    endLoad(true);
}

// ---- Editing ----

std::vector<Piece> TextBuffer::addPieces(const QByteArray &u8)
{
    std::vector<Piece> v;
    if (u8.isEmpty())
        return v;
    if (u8.size() >= AddBlockSize) {
        const auto b = wrapBytes(u8);
        appendPieces(b, 0, u8.size(), v);
        return v;
    }
    if (!m_add || m_addUsed + u8.size() > AddBlockSize) {
        auto b = std::make_shared<Block>();
        b->bytes = QByteArray(AddBlockSize, Qt::Uninitialized);
        m_addWrite = b->bytes.data(); // the only detach: nothing shares it yet
        b->ptr = m_addWrite;
        m_add = std::move(b);
        m_addUsed = 0;
    }
    std::memcpy(m_addWrite + m_addUsed, u8.constData(), size_t(u8.size()));
    v.push_back(makePiece(m_add, m_addUsed, u8.size()));
    m_addUsed += u8.size();
    return v;
}

TextBuffer::Change TextBuffer::applyInsert(qsizetype position, std::vector<Piece> pieces)
{
    Change c;
    c.ok = true;
    c.position = position;
    for (const Piece &p : pieces)
        c.insertedLength += p.agg.u16;
    if (pieces.empty())
        return c;
    c.inserted = pieces;
    m_tree = m_tree.withInserted(position, std::move(pieces));
    ++m_revision;
    return c;
}

TextBuffer::Change TextBuffer::insert(qsizetype position, const QString &text)
{
    if (m_loading)
        return Change();
    position = m_tree.alignDown(position);
    if (text.isEmpty()) {
        Change c;
        c.ok = true;
        c.position = position;
        return c;
    }
    return applyInsert(position, addPieces(text.toUtf8()));
}

TextBuffer::Change TextBuffer::insertPieces(qsizetype position, std::vector<Piece> pieces)
{
    if (m_loading)
        return Change();
    return applyInsert(m_tree.alignDown(position), std::move(pieces));
}

TextBuffer::Change TextBuffer::remove(qsizetype start, qsizetype end)
{
    return replace(start, end, QString());
}

TextBuffer::Change TextBuffer::replace(qsizetype start, qsizetype end, const QString &text)
{
    if (m_loading)
        return Change();
    if (start > end)
        std::swap(start, end);
    // An empty range removes nothing, even inside a surrogate pair.
    const bool empty = start == end;
    start = m_tree.alignDown(start);
    end = empty ? start : m_tree.alignUp(end);
    Change c;
    c.ok = true;
    c.position = start;
    bool touched = false;
    if (end > start) {
        c.removedLength = end - start;
        m_tree = m_tree.withRemoved(start, end, &c.removed);
        touched = true;
    }
    if (!text.isEmpty()) {
        std::vector<Piece> ps = addPieces(text.toUtf8());
        for (const Piece &p : ps)
            c.insertedLength += p.agg.u16;
        c.inserted = ps;
        m_tree = m_tree.withInserted(start, std::move(ps));
        touched = true;
    }
    if (touched)
        ++m_revision;
    return c;
}

// ---- Line endings ----

AtlasText::LineEnding TextBuffer::lineEnding() const
{
    const LineBreakCounts c = m_tree.lineBreaks();
    const int kinds = (c.lf > 0) + (c.crlf > 0) + (c.cr > 0);
    if (kinds >= 2)
        return AtlasText::LineEnding::Mixed;
    if (c.crlf > 0)
        return AtlasText::LineEnding::CRLF;
    if (c.cr > 0)
        return AtlasText::LineEnding::CR;
    return AtlasText::LineEnding::LF;
}

AtlasText::LineEnding TextBuffer::dominantLineEnding() const
{
    const LineBreakCounts c = m_tree.lineBreaks();
    if (c.crlf > c.lf && c.crlf >= c.cr)
        return AtlasText::LineEnding::CRLF;
    if (c.cr > c.lf && c.cr > c.crlf)
        return AtlasText::LineEnding::CR;
    return AtlasText::LineEnding::LF;
}

TextBuffer::Change TextBuffer::convertLineEndings(AtlasText::LineEnding kind)
{
    Change c;
    if (m_loading || kind == AtlasText::LineEnding::Mixed)
        return c;
    c.ok = true;
    const LineBreakCounts counts = m_tree.lineBreaks();
    if (counts.lf + counts.crlf + counts.cr == 0 || lineEnding() == kind)
        return c;
    const char *eol = kind == AtlasText::LineEnding::CRLF ? "\r\n" : kind == AtlasText::LineEnding::CR ? "\r" : "\n";
    const int eolLen = kind == AtlasText::LineEnding::CRLF ? 2 : 1;

    std::vector<Piece> old = m_tree.pieces();
    std::vector<Piece> fresh;
    QByteArray out;
    out.reserve(MaxPiece);
    auto flush = [&] {
        if (out.isEmpty())
            return;
        const auto b = wrapBytes(std::move(out));
        appendPieces(b, 0, b->bytes.size(), fresh);
        out = QByteArray();
        out.reserve(MaxPiece);
    };
    bool lastCR = false;
    for (const Piece &p : old) {
        const char *d = p.data();
        for (qsizetype i = 0; i < p.len(); ++i) {
            const char ch = d[i];
            // Only cut at the start of a character, and well inside the limit.
            if (out.size() >= MaxPiece - 8 && (uchar(ch) & 0xC0) != 0x80)
                flush();
            if (ch == '\r' || ch == '\n') {
                if (ch == '\n' && lastCR) {
                    lastCR = false; // the second half of a CRLF
                    continue;
                }
                out.append(eol, eolLen);
                lastCR = ch == '\r';
                continue;
            }
            lastCR = false;
            out.append(ch);
        }
    }
    flush();

    c.position = 0;
    c.removedLength = m_tree.length();
    for (const Piece &p : fresh)
        c.insertedLength += p.agg.u16;
    c.removed = std::move(old);
    c.inserted = fresh;
    m_tree = TextTree::fromPieces(std::move(fresh));
    ++m_revision;
    return c;
}

} // namespace AtlasTextDetail
