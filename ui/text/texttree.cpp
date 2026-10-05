#include "texttree.h"

#include <algorithm>
#include <atomic>

namespace AtlasTextDetail {

namespace {

inline int seqLen(uchar b)
{
    return b < 0xC0 ? 1 : b < 0xE0 ? 2 : b < 0xF0 ? 3 : 4;
}

inline bool isContinuation(uchar b)
{
    return (b & 0xC0) == 0x80;
}

// The byte offset in the piece of UTF-16 unit `target`. A target inside a
// surrogate pair gives the pair's first byte (and sets *inside).
qsizetype bytesForUnits(const char *p, qsizetype len, qsizetype target, bool *inside = nullptr)
{
    qsizetype b = 0, u = 0;
    while (b < len && u < target) {
        const qsizetype l = std::min<qsizetype>(seqLen(uchar(p[b])), len - b);
        const qsizetype w = l == 4 ? 2 : 1;
        if (u + w > target) {
            if (inside)
                *inside = true;
            break;
        }
        u += w;
        b += l;
    }
    return b;
}

// The UTF-16 units before byte `target`; a character that `target` cuts is not
// counted.
qsizetype unitsForBytes(const char *p, qsizetype len, qsizetype target)
{
    qsizetype b = 0, u = 0;
    while (b < target && b < len) {
        const qsizetype l = std::min<qsizetype>(seqLen(uchar(p[b])), len - b);
        if (b + l > target)
            break;
        b += l;
        u += l == 4 ? 2 : 1;
    }
    return u;
}

// The breaks that end in the first `nb` bytes. A CR at the very end of the
// piece is not counted (see Agg::breaks).
qsizetype countBreaks(const char *p, qsizetype len, qsizetype nb)
{
    qsizetype n = 0;
    for (qsizetype i = 0; i < nb; ++i) {
        const char c = p[i];
        if (c == '\n')
            ++n;
        else if (c == '\r' && i + 1 < len && p[i + 1] != '\n')
            ++n;
    }
    return n;
}

// Where the k-th (1-based) break of the piece ends, in bytes and UTF-16 units.
void findBreak(const char *p, qsizetype len, qsizetype k, qsizetype *byteEnd, qsizetype *unitEnd)
{
    qsizetype n = 0, u = 0;
    for (qsizetype i = 0; i < len; ++i) {
        const uchar c = uchar(p[i]);
        if (c < 0x80) {
            ++u;
            if (c == '\n' || (c == '\r' && i + 1 < len && p[i + 1] != '\n')) {
                if (++n == k) {
                    *byteEnd = i + 1;
                    *unitEnd = u;
                    return;
                }
            }
        } else if (!isContinuation(c)) {
            u += c >= 0xF0 ? 2 : 1;
        }
    }
    *byteEnd = len;
    *unitEnd = u;
}

Agg foldAgg(const std::vector<Piece> &v)
{
    Agg a;
    for (const Piece &p : v)
        a = combine(a, p.agg);
    return a;
}

Agg foldAgg(const std::vector<Child> &v)
{
    Agg a;
    for (const Child &c : v)
        a = combine(a, c.agg);
    return a;
}

Child makeLeaf(std::vector<Piece> &&v)
{
    auto n = std::make_shared<Node>();
    n->leaf = true;
    n->agg = foldAgg(v);
    n->pieces = std::move(v);
    Child c;
    c.agg = n->agg;
    c.node = std::move(n);
    return c;
}

Child makeInternal(std::vector<Child> &&v)
{
    auto n = std::make_shared<Node>();
    n->leaf = false;
    n->agg = foldAgg(v);
    n->kids = std::move(v);
    Child c;
    c.agg = n->agg;
    c.node = std::move(n);
    return c;
}

qsizetype entryCount(const Node &n)
{
    return qsizetype(n.leaf ? n.pieces.size() : n.kids.size());
}

// Splits n items into the fewest groups of at most MaxFan, of nearly equal
// size (so every group has at least MinFan items when n > MaxFan).
template<class T>
std::vector<std::vector<T>> makeGroups(std::vector<T> &&items)
{
    std::vector<std::vector<T>> out;
    const size_t n = items.size();
    const size_t g = (n + MaxFan - 1) / MaxFan;
    if (g <= 1) {
        out.push_back(std::move(items));
        return out;
    }
    const size_t base = n / g, rem = n % g;
    size_t at = 0;
    for (size_t i = 0; i < g; ++i) {
        const size_t take = base + (i < rem ? 1 : 0);
        out.emplace_back(std::make_move_iterator(items.begin() + at), std::make_move_iterator(items.begin() + at + take));
        at += take;
    }
    return out;
}

// Stacks internal nodes above `level` until one is left.
NodePtr wrapUp(std::vector<Child> level)
{
    while (level.size() > 1) {
        auto groups = makeGroups(std::move(level));
        level.clear();
        for (auto &g : groups)
            level.push_back(makeInternal(std::move(g)));
    }
    return level.empty() ? NodePtr() : level.front().node;
}

bool tryMerge(Piece &a, const Piece &b)
{
    if (a.block.get() != b.block.get() || a.off + a.len() != b.off || a.len() + b.len() > MaxPiece)
        return false;
    a.agg = combine(a.agg, b.agg);
    a.agg.pieces = 1;
    return true;
}

void pushMerged(std::vector<Piece> &v, Piece p)
{
    if (!v.empty() && tryMerge(v.back(), p))
        return;
    v.push_back(std::move(p));
}

void rebalance(std::vector<Child> &kids);

std::vector<Child> insertRec(const Node &n, qsizetype pos, std::vector<Piece> &ps)
{
    std::vector<Child> out;
    if (n.leaf) {
        const size_t cnt = n.pieces.size();
        size_t idx = cnt - 1;
        qsizetype cum = 0;
        for (size_t i = 0; i < cnt; ++i) {
            if (i == cnt - 1 || pos <= cum + n.pieces[i].agg.u16) {
                idx = i;
                break;
            }
            cum += n.pieces[i].agg.u16;
        }
        const Piece &hit = n.pieces[idx];
        const qsizetype o = pos - cum;
        // 0: before the piece, 1: after it, 2: inside it.
        int where = 2;
        qsizetype cut = 0;
        if (o <= 0) {
            where = 0;
        } else if (o >= hit.agg.u16) {
            where = 1;
        } else {
            cut = bytesForUnits(hit.data(), hit.len(), o);
            if (cut <= 0)
                where = 0;
            else if (cut >= hit.len())
                where = 1;
        }
        std::vector<Piece> v;
        v.reserve(cnt + ps.size() + 2);
        for (size_t i = 0; i < idx; ++i)
            v.push_back(n.pieces[i]);
        if (where == 0) {
            for (Piece &p : ps)
                pushMerged(v, std::move(p));
            pushMerged(v, hit);
        } else if (where == 1) {
            v.push_back(hit);
            for (Piece &p : ps)
                pushMerged(v, std::move(p));
        } else {
            v.push_back(makePiece(hit.block, hit.off, cut));
            for (Piece &p : ps)
                pushMerged(v, std::move(p));
            pushMerged(v, makePiece(hit.block, hit.off + cut, hit.len() - cut));
        }
        for (size_t i = idx + 1; i < cnt; ++i)
            pushMerged(v, n.pieces[i]);
        auto groups = makeGroups(std::move(v));
        for (auto &g : groups)
            out.push_back(makeLeaf(std::move(g)));
        return out;
    }

    const size_t cnt = n.kids.size();
    size_t idx = cnt - 1;
    qsizetype cum = 0;
    for (size_t i = 0; i < cnt; ++i) {
        if (i == cnt - 1 || pos <= cum + n.kids[i].agg.u16) {
            idx = i;
            break;
        }
        cum += n.kids[i].agg.u16;
    }
    std::vector<Child> res = insertRec(*n.kids[idx].node, pos - cum, ps);
    std::vector<Child> nk;
    nk.reserve(cnt + res.size());
    for (size_t i = 0; i < idx; ++i)
        nk.push_back(n.kids[i]);
    for (Child &c : res)
        nk.push_back(std::move(c));
    for (size_t i = idx + 1; i < cnt; ++i)
        nk.push_back(n.kids[i]);
    // A merge of pieces can leave the rebuilt child with fewer than MinFan
    // entries: fold it into a sibling before the groups are cut.
    rebalance(nk);
    auto groups = makeGroups(std::move(nk));
    for (auto &g : groups)
        out.push_back(makeInternal(std::move(g)));
    return out;
}

void collect(const Node &n, std::vector<Piece> &out)
{
    if (n.leaf) {
        out.insert(out.end(), n.pieces.begin(), n.pieces.end());
        return;
    }
    for (const Child &c : n.kids)
        collect(*c.node, out);
}

// One or two nodes holding the entries of a and b (siblings, a first).
std::vector<Child> mergeTwo(const Child &a, const Child &b)
{
    std::vector<Child> out;
    if (a.node->leaf) {
        std::vector<Piece> v = a.node->pieces;
        v.insert(v.end(), b.node->pieces.begin(), b.node->pieces.end());
        if (v.size() <= size_t(MaxFan)) {
            out.push_back(makeLeaf(std::move(v)));
        } else {
            const size_t h = v.size() / 2;
            out.push_back(makeLeaf(std::vector<Piece>(v.begin(), v.begin() + h)));
            out.push_back(makeLeaf(std::vector<Piece>(v.begin() + h, v.end())));
        }
        return out;
    }
    std::vector<Child> v = a.node->kids;
    v.insert(v.end(), b.node->kids.begin(), b.node->kids.end());
    rebalance(v);
    if (v.size() <= size_t(MaxFan)) {
        out.push_back(makeInternal(std::move(v)));
    } else {
        const size_t h = v.size() / 2;
        out.push_back(makeInternal(std::vector<Child>(v.begin(), v.begin() + h)));
        out.push_back(makeInternal(std::vector<Child>(v.begin() + h, v.end())));
    }
    return out;
}

// Merges any node with fewer than MinFan entries into a neighbour, until none
// is left (or only one node remains).
void rebalance(std::vector<Child> &kids)
{
    for (;;) {
        bool changed = false;
        if (kids.size() > 1) {
            for (size_t i = 0; i < kids.size(); ++i) {
                if (entryCount(*kids[i].node) >= MinFan)
                    continue;
                const size_t lo = i + 1 < kids.size() ? i : i - 1;
                std::vector<Child> merged = mergeTwo(kids[lo], kids[lo + 1]);
                kids.erase(kids.begin() + lo, kids.begin() + lo + 2);
                kids.insert(kids.begin() + lo, merged.begin(), merged.end());
                changed = true;
                break;
            }
        }
        if (!changed)
            return;
    }
}

// Removes [a, b) (relative to n, 0 <= a < b <= n.u16). A null node in the
// result means nothing is left.
Child removeRec(const Node &n, qsizetype a, qsizetype b, std::vector<Piece> *removed)
{
    qsizetype cum = 0;
    if (n.leaf) {
        std::vector<Piece> v;
        for (const Piece &p : n.pieces) {
            const qsizetype s = cum, e = cum + p.agg.u16;
            cum = e;
            if (e <= a || s >= b) {
                pushMerged(v, p);
                continue;
            }
            const qsizetype lo = std::max(a, s) - s, hi = std::min(b, e) - s;
            if (lo == 0 && hi == p.agg.u16) {
                if (removed)
                    removed->push_back(p);
                continue;
            }
            const qsizetype bl = bytesForUnits(p.data(), p.len(), lo);
            const qsizetype bh = bytesForUnits(p.data(), p.len(), hi);
            if (bl > 0)
                pushMerged(v, makePiece(p.block, p.off, bl));
            if (bh > bl && removed)
                removed->push_back(makePiece(p.block, p.off + bl, bh - bl));
            if (bh < p.len())
                pushMerged(v, makePiece(p.block, p.off + bh, p.len() - bh));
        }
        if (v.empty())
            return Child();
        return makeLeaf(std::move(v));
    }
    std::vector<Child> nk;
    for (const Child &k : n.kids) {
        const qsizetype s = cum, e = cum + k.agg.u16;
        cum = e;
        if (e <= a || s >= b) {
            nk.push_back(k);
        } else if (a <= s && e <= b) {
            if (removed)
                collect(*k.node, *removed);
        } else {
            Child c = removeRec(*k.node, std::max(a, s) - s, std::min(b, e) - s, removed);
            if (c.node)
                nk.push_back(std::move(c));
        }
    }
    if (nk.empty())
        return Child();
    rebalance(nk);
    return makeInternal(std::move(nk));
}

// ---- Finding a place ----

enum class Metric { Bytes, U16, Piece, Break };

struct Before {
    qsizetype bytes = 0, u16 = 0, breaks = 0, pieces = 0;
};

struct Loc {
    const Piece *piece = nullptr;
    Before before; // up to the start of `piece`, or of the entry in `boundary`
    // Break metric only: the break asked for ends exactly at the start of the
    // entry where `before` stands (a lone CR that closed the previous entry).
    bool boundary = false;
};

// Finds the entry that holds `target`:
//  - Bytes, U16: the piece with the byte or unit `target` in it (the last piece
//    when `target` is at or past the end);
//  - Piece: the piece with that index;
//  - Break: the piece in which the target-th break (from 1) ends, or the
//    boundary case above.
// before.breaks counts every break that ends before the piece, including the
// ones a trailing CR of an earlier entry turns into at a seam.
Loc locate(const NodePtr &root, Metric m, qsizetype target)
{
    Loc loc;
    if (!root)
        return loc;
    const Node *n = root.get();
    Before acc;
    for (;;) {
        const size_t cnt = size_t(entryCount(*n));
        bool prevCR = false;
        bool descended = false;
        for (size_t i = 0; i < cnt; ++i) {
            const Agg &a = n->leaf ? n->pieces[i].agg : n->kids[i].agg;
            const qsizetype extra = (prevCR && !a.startsLF) ? 1 : 0;
            bool hit = i + 1 == cnt;
            if (!hit) {
                switch (m) {
                case Metric::Bytes:
                    hit = target < acc.bytes + a.bytes;
                    break;
                case Metric::U16:
                    hit = target < acc.u16 + a.u16;
                    break;
                case Metric::Piece:
                    hit = target < acc.pieces + a.pieces;
                    break;
                case Metric::Break:
                    hit = target <= acc.breaks + a.breaks() + extra;
                    break;
                }
            }
            if (hit) {
                if (m == Metric::Break && extra && target == acc.breaks + 1) {
                    loc.before = acc;
                    loc.boundary = true;
                    return loc;
                }
                acc.breaks += extra;
                if (n->leaf) {
                    loc.piece = &n->pieces[i];
                    loc.before = acc;
                    return loc;
                }
                n = n->kids[i].node.get();
                descended = true;
                break;
            }
            acc.bytes += a.bytes;
            acc.u16 += a.u16;
            acc.pieces += a.pieces;
            acc.breaks += a.breaks() + extra;
            prevCR = a.endsCR;
        }
        if (!descended)
            return loc; // not reached: the last entry always hits
    }
}

// Calls cb(piece, byteStart, u16Start) for the pieces from index `skip` on, in
// order, until it returns false.
template<class F>
bool walkFrom(const Node &n, qsizetype &skip, qsizetype &byteCum, qsizetype &u16Cum, F &cb)
{
    if (n.leaf) {
        for (const Piece &p : n.pieces) {
            if (skip > 0) {
                --skip;
            } else if (!cb(p, byteCum, u16Cum)) {
                return false;
            }
            byteCum += p.agg.bytes;
            u16Cum += p.agg.u16;
        }
        return true;
    }
    for (const Child &k : n.kids) {
        if (skip >= k.agg.pieces) {
            skip -= k.agg.pieces;
            byteCum += k.agg.bytes;
            u16Cum += k.agg.u16;
            continue;
        }
        if (!walkFrom(*k.node, skip, byteCum, u16Cum, cb))
            return false;
    }
    return true;
}

QString checkNode(const Node &n, bool isRoot, int depth, int *leafDepth, Agg *out)
{
    const qsizetype cnt = entryCount(n);
    if (cnt < 1 || cnt > MaxFan)
        return QStringLiteral("a node has %1 entries").arg(cnt);
    if (!isRoot && cnt < MinFan)
        return QStringLiteral("a non-root node has %1 entries (minimum %2)").arg(cnt).arg(MinFan);
    Agg sum;
    if (n.leaf) {
        if (*leafDepth < 0)
            *leafDepth = depth;
        else if (*leafDepth != depth)
            return QStringLiteral("leaves at depths %1 and %2").arg(*leafDepth).arg(depth);
        for (const Piece &p : n.pieces) {
            if (!p.block || p.off < 0 || p.agg.bytes < 1 || p.agg.bytes > MaxPiece)
                return QStringLiteral("a piece has %1 bytes (limit %2)").arg(p.agg.bytes).arg(MaxPiece);
            if (p.off + p.agg.bytes > p.block->bytes.size())
                return QStringLiteral("a piece reaches past its block");
            if (isContinuation(uchar(*p.data())))
                return QStringLiteral("a piece starts inside a character");
            if (computeAgg(p.data(), p.len()) != p.agg)
                return QStringLiteral("a piece's aggregates differ from its bytes");
            sum = combine(sum, p.agg);
        }
    } else {
        for (const Child &c : n.kids) {
            Agg sub;
            const QString err = checkNode(*c.node, false, depth + 1, leafDepth, &sub);
            if (!err.isEmpty())
                return err;
            if (!(c.agg == sub) || !(c.node->agg == sub))
                return QStringLiteral("an entry's aggregates differ from its subtree");
            sum = combine(sum, sub);
        }
    }
    if (!(sum == n.agg))
        return QStringLiteral("a node's aggregates differ from the sum of its entries");
    *out = sum;
    return QString();
}

// ---- The snapshot ----

class SnapshotImpl final : public AtlasTextSnapshotInterface
{
public:
    SnapshotImpl(TextTree t, quint64 r) : m_tree(std::move(t)), m_revision(r) {}

    int abiVersion() const override { return ATLAS_TEXTSNAPSHOT_ABI_VERSION; }
    void ref() const override { m_ref.fetch_add(1, std::memory_order_relaxed); }
    void deref() const override
    {
        if (m_ref.fetch_sub(1, std::memory_order_acq_rel) == 1)
            delete this;
    }
    qsizetype length() const override { return m_tree.length(); }
    qsizetype byteLength() const override { return m_tree.byteLength(); }
    qsizetype lineCount() const override { return m_tree.lineCount(); }
    quint64 revision() const override { return m_revision; }
    qsizetype lineStart(qsizetype line) const override { return m_tree.lineStart(line); }
    qsizetype lineStartByte(qsizetype line) const override { return m_tree.lineStartByte(line); }
    qsizetype lineAt(qsizetype position) const override { return m_tree.lineAt(position); }
    qsizetype lineAtByte(qsizetype offset) const override { return m_tree.lineAtByte(offset); }
    qsizetype utf16AtByte(qsizetype offset) const override { return m_tree.utf16AtByte(offset); }
    qsizetype byteAtUtf16(qsizetype position) const override { return m_tree.byteAtUtf16(position); }
    QString text(qsizetype start, qsizetype end) const override { return m_tree.text(start, end); }
    QByteArray utf8(qsizetype start, qsizetype end) const override { return m_tree.utf8(start, end); }
    qsizetype chunkCount() const override { return m_tree.chunkCount(); }
    AtlasTextChunk chunkAt(qsizetype index) const override { return m_tree.chunkAt(index); }
    qsizetype chunkIndexAtByte(qsizetype offset) const override { return m_tree.chunkIndexAtByte(offset); }

private:
    TextTree m_tree;
    quint64 m_revision;
    mutable std::atomic<int> m_ref{0};
};

} // namespace

Agg combine(const Agg &a, const Agg &b)
{
    if (a.bytes == 0)
        return b;
    if (b.bytes == 0)
        return a;
    Agg r;
    r.bytes = a.bytes + b.bytes;
    r.u16 = a.u16 + b.u16;
    r.pieces = a.pieces + b.pieces;
    r.lf = a.lf + b.lf;
    r.cr = a.cr + b.cr;
    r.crlf = a.crlf + b.crlf + ((a.endsCR && b.startsLF) ? 1 : 0);
    r.startsLF = a.startsLF;
    r.endsCR = b.endsCR;
    return r;
}

Agg computeAgg(const char *p, qsizetype len)
{
    Agg a;
    if (len <= 0)
        return a;
    a.bytes = len;
    a.pieces = 1;
    bool prevCR = false;
    for (qsizetype i = 0; i < len; ++i) {
        const uchar c = uchar(p[i]);
        if (c < 0x80) {
            ++a.u16;
            if (c == '\n') {
                ++a.lf;
                if (prevCR)
                    ++a.crlf;
            }
            prevCR = c == '\r';
            if (prevCR)
                ++a.cr;
        } else {
            prevCR = false;
            if (!isContinuation(c))
                a.u16 += c >= 0xF0 ? 2 : 1;
        }
    }
    a.startsLF = p[0] == '\n';
    a.endsCR = p[len - 1] == '\r';
    return a;
}

Piece makePiece(const std::shared_ptr<const Block> &block, qsizetype off, qsizetype len)
{
    Piece p;
    p.block = block;
    p.off = off;
    p.agg = computeAgg(block->ptr + off, len);
    return p;
}

void appendPieces(const std::shared_ptr<const Block> &block, qsizetype off, qsizetype len, std::vector<Piece> &out)
{
    const char *base = block->ptr;
    qsizetype pos = off;
    const qsizetype end = off + len;
    while (pos < end) {
        qsizetype cut = std::min(pos + MaxPiece, end);
        // Back up to the start of a character; a piece is never empty.
        while (cut < end && cut > pos + 1 && isContinuation(uchar(base[cut])))
            --cut;
        out.push_back(makePiece(block, pos, cut - pos));
        pos = cut;
    }
}

TextTree TextTree::fromPieces(std::vector<Piece> pieces)
{
    if (pieces.empty())
        return TextTree();
    auto groups = makeGroups(std::move(pieces));
    std::vector<Child> leaves;
    leaves.reserve(groups.size());
    for (auto &g : groups)
        leaves.push_back(makeLeaf(std::move(g)));
    return TextTree(wrapUp(std::move(leaves)));
}

std::vector<Piece> TextTree::pieces() const
{
    std::vector<Piece> v;
    if (m_root) {
        v.reserve(size_t(m_root->agg.pieces));
        collect(*m_root, v);
    }
    return v;
}

qsizetype TextTree::lineCount() const
{
    if (!m_root)
        return 1;
    return 1 + m_root->agg.breaks() + (m_root->agg.endsCR ? 1 : 0);
}

LineBreakCounts TextTree::lineBreaks() const
{
    LineBreakCounts c;
    if (m_root) {
        c.crlf = m_root->agg.crlf;
        c.lf = m_root->agg.lf - m_root->agg.crlf;
        c.cr = m_root->agg.cr - m_root->agg.crlf;
    }
    return c;
}

qsizetype TextTree::lineStart(qsizetype line) const
{
    const qsizetype last = lineCount() - 1;
    line = std::clamp<qsizetype>(line, 0, last);
    if (line == 0)
        return 0;
    if (line > m_root->agg.breaks())
        return length(); // only a trailing CR makes this line
    const Loc loc = locate(m_root, Metric::Break, line);
    if (loc.boundary || !loc.piece)
        return loc.before.u16;
    qsizetype be = 0, ue = 0;
    findBreak(loc.piece->data(), loc.piece->len(), line - loc.before.breaks, &be, &ue);
    return loc.before.u16 + ue;
}

qsizetype TextTree::lineStartByte(qsizetype line) const
{
    const qsizetype last = lineCount() - 1;
    line = std::clamp<qsizetype>(line, 0, last);
    if (line == 0)
        return 0;
    if (line > m_root->agg.breaks())
        return byteLength();
    const Loc loc = locate(m_root, Metric::Break, line);
    if (loc.boundary || !loc.piece)
        return loc.before.bytes;
    qsizetype be = 0, ue = 0;
    findBreak(loc.piece->data(), loc.piece->len(), line - loc.before.breaks, &be, &ue);
    return loc.before.bytes + be;
}

qsizetype TextTree::lineAt(qsizetype position) const
{
    if (position <= 0)
        return 0;
    if (position >= length())
        return lineCount() - 1;
    const Loc loc = locate(m_root, Metric::U16, position);
    const Piece &p = *loc.piece;
    const qsizetype nb = bytesForUnits(p.data(), p.len(), position - loc.before.u16);
    return loc.before.breaks + countBreaks(p.data(), p.len(), nb);
}

qsizetype TextTree::lineAtByte(qsizetype offset) const
{
    if (offset <= 0)
        return 0;
    if (offset >= byteLength())
        return lineCount() - 1;
    const Loc loc = locate(m_root, Metric::Bytes, offset);
    const Piece &p = *loc.piece;
    return loc.before.breaks + countBreaks(p.data(), p.len(), offset - loc.before.bytes);
}

qsizetype TextTree::utf16AtByte(qsizetype offset) const
{
    if (offset <= 0)
        return 0;
    if (offset >= byteLength())
        return length();
    const Loc loc = locate(m_root, Metric::Bytes, offset);
    const Piece &p = *loc.piece;
    return loc.before.u16 + unitsForBytes(p.data(), p.len(), offset - loc.before.bytes);
}

qsizetype TextTree::byteAtUtf16(qsizetype position) const
{
    if (position <= 0)
        return 0;
    if (position >= length())
        return byteLength();
    const Loc loc = locate(m_root, Metric::U16, position);
    const Piece &p = *loc.piece;
    return loc.before.bytes + bytesForUnits(p.data(), p.len(), position - loc.before.u16);
}

bool TextTree::insideSurrogatePair(qsizetype position) const
{
    if (position <= 0 || position >= length())
        return false;
    const Loc loc = locate(m_root, Metric::U16, position);
    const Piece &p = *loc.piece;
    bool inside = false;
    bytesForUnits(p.data(), p.len(), position - loc.before.u16, &inside);
    return inside;
}

qsizetype TextTree::alignDown(qsizetype position) const
{
    position = std::clamp<qsizetype>(position, 0, length());
    return insideSurrogatePair(position) ? position - 1 : position;
}

qsizetype TextTree::alignUp(qsizetype position) const
{
    position = std::clamp<qsizetype>(position, 0, length());
    return insideSurrogatePair(position) ? position + 1 : position;
}

QString TextTree::text(qsizetype start, qsizetype end) const
{
    start = std::clamp<qsizetype>(start, 0, length());
    end = std::clamp<qsizetype>(end, 0, length());
    QString out;
    if (start >= end)
        return out;
    out.reserve(end - start);
    const Loc loc = locate(m_root, Metric::U16, start);
    qsizetype skip = loc.before.pieces, bc = 0, uc = 0;
    auto cb = [&](const Piece &p, qsizetype, qsizetype us) {
        if (us >= end)
            return false;
        const qsizetype lo = std::max(start, us) - us;
        const qsizetype hi = std::min(end, us + p.agg.u16) - us;
        const QString s = QString::fromUtf8(p.data(), p.len());
        if (lo == 0 && hi == p.agg.u16)
            out.append(s);
        else
            out.append(QStringView(s).mid(lo, hi - lo));
        return true;
    };
    walkFrom(*m_root, skip, bc, uc, cb);
    return out;
}

QByteArray TextTree::utf8(qsizetype start, qsizetype end) const
{
    start = std::clamp<qsizetype>(start, 0, byteLength());
    end = std::clamp<qsizetype>(end, 0, byteLength());
    QByteArray out;
    if (start >= end)
        return out;
    out.reserve(end - start);
    const Loc loc = locate(m_root, Metric::Bytes, start);
    qsizetype skip = loc.before.pieces, bc = 0, uc = 0;
    auto cb = [&](const Piece &p, qsizetype bs, qsizetype) {
        if (bs >= end)
            return false;
        const qsizetype lo = std::max(start, bs) - bs;
        const qsizetype hi = std::min(end, bs + p.len()) - bs;
        out.append(p.data() + lo, hi - lo);
        return true;
    };
    walkFrom(*m_root, skip, bc, uc, cb);
    return out;
}

AtlasTextChunk TextTree::chunkAt(qsizetype index) const
{
    AtlasTextChunk c;
    if (index < 0 || index >= pieceCount())
        return c;
    const Loc loc = locate(m_root, Metric::Piece, index);
    const Piece &p = *loc.piece;
    c.data = p.data();
    c.byteLength = p.len();
    c.byteOffset = loc.before.bytes;
    c.utf16Offset = loc.before.u16;
    c.utf16Length = p.agg.u16;
    return c;
}

qsizetype TextTree::chunkIndexAtByte(qsizetype offset) const
{
    if (!m_root)
        return 0;
    offset = std::clamp<qsizetype>(offset, 0, byteLength());
    return locate(m_root, Metric::Bytes, offset).before.pieces;
}

TextTree TextTree::withInserted(qsizetype position, std::vector<Piece> pieces) const
{
    if (pieces.empty())
        return *this;
    if (!m_root)
        return fromPieces(std::move(pieces));
    position = std::clamp<qsizetype>(position, 0, length());
    std::vector<Child> res = insertRec(*m_root, position, pieces);
    NodePtr root = wrapUp(std::move(res));
    while (root && !root->leaf && root->kids.size() == 1)
        root = root->kids.front().node;
    return TextTree(std::move(root));
}

TextTree TextTree::withRemoved(qsizetype start, qsizetype end, std::vector<Piece> *removed) const
{
    start = std::clamp<qsizetype>(start, 0, length());
    end = std::clamp<qsizetype>(end, 0, length());
    if (start >= end)
        return *this;
    Child c = removeRec(*m_root, start, end, removed);
    NodePtr root = std::move(c.node);
    while (root && !root->leaf && root->kids.size() == 1)
        root = root->kids.front().node;
    return TextTree(std::move(root));
}

QString TextTree::validate() const
{
    if (!m_root)
        return QString();
    int leafDepth = -1;
    Agg sum;
    return checkNode(*m_root, true, 1, &leafDepth, &sum);
}

int TextTree::height() const
{
    int h = 0;
    for (const Node *n = m_root.get(); n; n = n->leaf ? nullptr : n->kids.front().node.get())
        ++h;
    return h;
}

AtlasTextSnapshot makeSnapshot(const TextTree &tree, quint64 revision)
{
    // The handle takes the one reference; nothing else owns the object.
    return AtlasTextSnapshot(new SnapshotImpl(tree, revision));
}

} // namespace AtlasTextDetail
