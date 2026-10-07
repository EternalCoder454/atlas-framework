#include "textbuffer.h"

#include <QChar>
#include <QThread>
#include <QThreadPool>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstring>

namespace TelamonTextDetail {

namespace {

// Chunks smaller than this are checked on the calling thread: a task costs more.
constexpr qsizetype InlineLimit = 32 * 1024;
// A larger chunk is cut into ranges of about this size, one task each.
constexpr qsizetype TaskRange = 1024 * 1024;
// Small chunks are gathered until they make a piece of at least this size.
constexpr qsizetype PendingTarget = 64 * 1024;
// In a range with invalid bytes, a valid run this long stays a reference into
// the chunk; shorter ones are copied next to the replacement characters.
constexpr qsizetype KeepRun = 4096;
// The size of an add-buffer block. Larger insertions get a block of their own.
constexpr qsizetype AddBlockSize = 64 * 1024;
const char Replacement[] = "\xEF\xBF\xBD";

std::atomic<TaskHook> g_taskHook{nullptr};

// A few threads of our own: loading must not starve (or wait on) the global
// pool that the application's other work uses. At least two, so that a range
// that is slow does not hold up the ones behind it on a one-core machine.
QThreadPool *loadPool()
{
    static QThreadPool pool;
    static const bool configured = [] {
        pool.setMaxThreadCount(std::max(2, std::min(4, QThread::idealThreadCount())));
        return true;
    }();
    Q_UNUSED(configured);
    return &pool;
}

std::shared_ptr<const Block> wrapBytes(QByteArray bytes)
{
    auto b = std::make_shared<Block>();
    b->bytes = std::move(bytes);
    b->ptr = b->bytes.constData();
    return b;
}

// The UTF-8 of `s`, where a lone surrogate becomes U+FFFD (written out here,
// not left to QString::toUtf8).
QByteArray utf8Of(const QString &s)
{
    const qsizetype n = s.size();
    const QChar *d = s.constData();
    auto loneAt = [&](qsizetype i) {
        const char16_t c = d[i].unicode();
        if (QChar::isHighSurrogate(c))
            return !(i + 1 < n && QChar::isLowSurrogate(d[i + 1].unicode()));
        return QChar::isLowSurrogate(c);
    };
    qsizetype first = -1;
    for (qsizetype i = 0; i < n; ++i) {
        if (QChar::isHighSurrogate(d[i].unicode()) && !loneAt(i)) {
            ++i; // a whole pair
        } else if (loneAt(i)) {
            first = i;
            break;
        }
    }
    if (first < 0)
        return s.toUtf8();
    QString fixed = s;
    QChar *w = fixed.data();
    for (qsizetype i = first; i < n; ++i) {
        if (QChar::isHighSurrogate(w[i].unicode()) && i + 1 < n && QChar::isLowSurrogate(w[i + 1].unicode()))
            ++i;
        else if (QChar::isHighSurrogate(w[i].unicode()) || QChar::isLowSurrogate(w[i].unicode()))
            w[i] = QChar(char16_t(0xFFFD));
    }
    return fixed.toUtf8();
}

// Checks [from, to) of `block` and cuts it into pieces. Invalid sequences
// (including one cut off by `to`) become U+FFFD. Long valid runs stay
// references into `block`; only the short stretches around the bad bytes are
// copied.
JobResult processRange(const std::shared_ptr<const Block> &block, qsizetype from, qsizetype to)
{
    JobResult res;
    const char *p = block->ptr;
    qsizetype i = from, runStart = from;
    QByteArray out;
    auto flushOut = [&] {
        if (out.isEmpty())
            return;
        const auto b = wrapBytes(std::move(out));
        out = QByteArray();
        appendPieces(b, 0, b->bytes.size(), res.pieces);
    };
    // [runStart, end) is valid text.
    auto endRun = [&](qsizetype end) {
        const qsizetype len = end - runStart;
        if (len <= 0)
            return;
        if (len >= KeepRun) {
            flushOut();
            appendPieces(block, runStart, len, res.pieces);
        } else {
            out.append(p + runStart, len);
        }
    };
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
        res.invalid = true;
        endRun(i);
        out.append(Replacement, 3);
        i += std::max(1, r.len);
        runStart = i;
    }
    if (!res.invalid) {
        appendPieces(block, from, to - from, res.pieces);
    } else {
        endRun(to);
        flushOut();
    }
    return res;
}

} // namespace

struct LoadState {
    std::atomic<qint64> bytesIn{0};
    std::atomic<qint64> bytesDone{0};
    std::atomic<bool> cancelled{false};
};

namespace {

// One load task. `block` is released as soon as the task returns, cancelled or
// not.
void runTask(const std::shared_ptr<LoadState> &state, const std::shared_ptr<LoadNotifier> &notifier,
             const std::shared_ptr<std::promise<JobResult>> &promise, const std::shared_ptr<const Block> &block,
             qsizetype from, qsizetype to)
{
    if (state->cancelled.load(std::memory_order_acquire))
        return;
    JobResult r;
    try {
        if (const TaskHook hook = g_taskHook.load(std::memory_order_acquire))
            hook(block->ptr + from, to - from);
        r = processRange(block, from, to);
    } catch (...) {
        r = JobResult();
        r.failed = true;
    }
    if (state->cancelled.load(std::memory_order_acquire))
        return; // r goes out of scope here: the chunk is released at once
    state->bytesDone += to - from;
    try {
        promise->set_value(std::move(r));
    } catch (...) {
        return;
    }
    // The callback runs under the mutex: the buffer's destructor waits for it.
    try {
        QMutexLocker lock(&notifier->mutex);
        if (notifier->fn && !state->cancelled.load(std::memory_order_acquire))
            notifier->fn();
    } catch (...) {
        // a callback must not throw; nothing may escape a pool task
    }
}

} // namespace

void setTaskHookForTests(TaskHook hook)
{
    g_taskHook.store(hook, std::memory_order_release);
}

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


TextBuffer::TextBuffer() : m_state(std::make_shared<LoadState>()), m_notifier(std::make_shared<LoadNotifier>()) {}

TextBuffer::~TextBuffer()
{
    m_state->cancelled.store(true, std::memory_order_release);
    // Waits for a callback in progress; none starts after this.
    QMutexLocker lock(&m_notifier->mutex);
    m_notifier->fn = nullptr;
}

void TextBuffer::setLoadNotify(std::function<void()> notify)
{
    QMutexLocker lock(&m_notifier->mutex);
    m_notifier->fn = std::move(notify);
}

void TextBuffer::beginLoad()
{
    m_state->cancelled.store(true, std::memory_order_release); // the old tasks stop
    m_slots.clear(); // results of an unfinished load are dropped
    m_state = std::make_shared<LoadState>();
    m_tree = TextTree();
    ++m_revision;
    m_loading = true;
    m_inputDone = false;
    m_hadInvalid = false;
    m_loadFailed = false;
    m_carry.clear();
    m_pending.clear();
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

void TextBuffer::flushPending()
{
    if (m_pending.isEmpty())
        return;
    const auto block = wrapBytes(std::move(m_pending));
    m_pending = QByteArray();
    JobResult r = processRange(block, 0, block->bytes.size());
    if (r.invalid)
        m_hadInvalid = true;
    pushImmediate(std::move(r.pieces));
}

void TextBuffer::submitRange(const std::shared_ptr<const Block> &block, qsizetype from, qsizetype to)
{
    auto promise = std::make_shared<std::promise<JobResult>>();
    Slot s;
    s.result = promise->get_future();
    m_slots.push_back(std::move(s));
    loadPool()->start([state = m_state, notifier = m_notifier, promise, block, from, to]() {
        runTask(state, notifier, promise, block, from, to);
    });
}

void TextBuffer::failLoad()
{
    m_loadFailed = true;
    m_state->cancelled.store(true, std::memory_order_release);
    m_slots.clear();
    m_pending.clear();
    m_carry.clear();
    m_inputDone = true; // later chunks are ignored: the text stays a clean prefix
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
    try {
        appendImpl(chunk);
    } catch (...) {
        failLoad();
    }
}

void TextBuffer::appendImpl(const QByteArray &chunk)
{
    const qsizetype n = chunk.size();
    m_state->bytesIn += n;
    qsizetype from = 0;

    // A character left over from the last chunk: finish it, or replace it. Its
    // bytes join the pending run, so the order of the text is kept.
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
        if (r.kind == SeqKind::Valid) {
            m_pending.append(tmp.constData(), r.len);
        } else {
            m_pending.append(Replacement, 3);
            m_hadInvalid = true;
        }
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
    if (to <= from) {
        if (m_pending.size() >= PendingTarget)
            flushPending();
        return;
    }

    if (to - from < InlineLimit) {
        m_pending.append(chunk.constData() + from, to - from);
        m_state->bytesDone += to - from;
        if (m_pending.size() >= PendingTarget)
            flushPending();
        return;
    }

    // A large chunk: what is pending comes first, then one task a range.
    flushPending();
    const auto block = wrapBytes(chunk);
    const char *base = chunk.constData();
    for (qsizetype pos = from; pos < to;) {
        qsizetype end = to;
        if (pos + TaskRange < to) {
            // Cut at a character start; a run of stray continuation bytes (no
            // valid character has more than three) is cut where it falls.
            end = pos + TaskRange;
            qsizetype t = end;
            for (int k = 0; k < 3 && t > pos && (uchar(base[t]) & 0xC0) == 0x80; ++k)
                --t;
            if ((uchar(base[t]) & 0xC0) != 0x80)
                end = t;
        }
        submitRange(block, pos, end);
        pos = end;
    }
}

bool TextBuffer::takeReady()
{
    std::vector<Piece> batch;
    bool failed = false;
    while (!m_slots.empty() && m_slots.front().result.wait_for(std::chrono::seconds(0)) == std::future_status::ready) {
        JobResult r;
        try {
            r = m_slots.front().result.get();
        } catch (...) {
            r.failed = true;
        }
        m_slots.pop_front();
        if (r.failed) {
            failed = true;
            break; // nothing after the hole is taken
        }
        if (r.invalid)
            m_hadInvalid = true;
        batch.insert(batch.end(), std::make_move_iterator(r.pieces.begin()), std::make_move_iterator(r.pieces.end()));
    }
    if (!batch.empty()) {
        m_tree = m_tree.withInserted(m_tree.length(), std::move(batch));
        ++m_revision;
    }
    return failed;
}

bool TextBuffer::pollLoad()
{
    if (!m_loading)
        return true;
    if (takeReady())
        failLoad();
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
        try {
            if (!m_carry.isEmpty()) {
                m_pending.append(Replacement, 3);
                m_hadInvalid = true;
                m_carry.clear();
            }
            flushPending();
            m_inputDone = true;
        } catch (...) {
            failLoad();
        }
    }
    if (wait) {
        for (Slot &s : m_slots) {
            if (s.result.valid())
                s.result.wait();
        }
    }
    return pollLoad();
}

void TextBuffer::cancelLoad()
{
    if (!m_loading)
        return;
    m_state->cancelled.store(true, std::memory_order_release);
    m_slots.clear();
    m_pending.clear();
    m_carry.clear();
    m_tree = TextTree();
    ++m_revision;
    m_loading = false;
    m_inputDone = true;
    m_hadInvalid = false;
    m_loadFailed = false;
}

void TextBuffer::abortLoad(bool failed)
{
    if (!m_loading)
        return;
    m_state->cancelled.store(true, std::memory_order_release);
    bool bad = takeReady();
    // The pending run is the newest text: it joins only if nothing before it
    // is missing.
    if (!bad && m_slots.empty()) {
        try {
            if (!m_inputDone)
                flushPending();
            bad = takeReady();
        } catch (...) {
            bad = true;
        }
    }
    m_slots.clear();
    m_pending.clear();
    m_carry.clear();
    m_inputDone = true;
    m_loading = false;
    if (failed || bad)
        m_loadFailed = true;
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
    appendData(utf8Of(text));
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
    return applyInsert(position, addPieces(utf8Of(text)));
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
        std::vector<Piece> ps = addPieces(utf8Of(text));
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

TelamonText::LineEnding TextBuffer::lineEnding() const
{
    const LineBreakCounts c = m_tree.lineBreaks();
    const int kinds = (c.lf > 0) + (c.crlf > 0) + (c.cr > 0);
    if (kinds >= 2)
        return TelamonText::LineEnding::Mixed;
    if (c.crlf > 0)
        return TelamonText::LineEnding::CRLF;
    if (c.cr > 0)
        return TelamonText::LineEnding::CR;
    return TelamonText::LineEnding::LF;
}

TelamonText::LineEnding TextBuffer::dominantLineEnding() const
{
    const LineBreakCounts c = m_tree.lineBreaks();
    if (c.crlf > c.lf && c.crlf >= c.cr)
        return TelamonText::LineEnding::CRLF;
    if (c.cr > c.lf && c.cr > c.crlf)
        return TelamonText::LineEnding::CR;
    return TelamonText::LineEnding::LF;
}

TextBuffer::Change TextBuffer::convertLineEndings(TelamonText::LineEnding kind)
{
    Change c;
    if (m_loading || kind == TelamonText::LineEnding::Mixed)
        return c;
    c.ok = true;
    const LineBreakCounts counts = m_tree.lineBreaks();
    if (counts.lf + counts.crlf + counts.cr == 0 || lineEnding() == kind)
        return c;
    const char *eol = kind == TelamonText::LineEnding::CRLF ? "\r\n" : kind == TelamonText::LineEnding::CR ? "\r" : "\n";
    const int eolLen = kind == TelamonText::LineEnding::CRLF ? 2 : 1;

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

} // namespace TelamonTextDetail
