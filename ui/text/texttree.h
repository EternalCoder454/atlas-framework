// The piece tree behind AtlasTextView (1.5.0 item 38, step 1a). Pure QtCore: no
// QQuickItem here. docs/textview-design-1.5.md ("The buffer") is the design.
//
// The text is UTF-8 in immutable Blocks (loaded chunks, and the append-only add
// buffer). A Piece is a run of a Block of at most 64 KB. Pieces sit in the
// leaves of a persistent, reference-counted B-tree (at most 64 entries a node,
// at least 32 except in the root). Every entry carries aggregates (bytes,
// UTF-16 units, pieces, line breaks), so every conversion is O(log n) plus one
// scan inside one piece. An edit copies only the path from the root to the
// changed leaves; a TextTree is one shared_ptr to a root, so copying one is O(1)
// and any const method may run on any thread while the owner edits another
// version.
//
// Line breaks. LF, CRLF and lone CR each count as one break, and a break belongs
// to the line it ends: it "ends" after the LF, or after a CR that no LF follows.
// A CR at the end of a piece cannot know its successor, so aggregates keep the
// counts of LF, CR and CRLF pairs and the first/last character flags, and the
// join of two entries fixes the seam (see combine()). Nothing here ever needs
// the pieces of a CRLF to be adjacent.
#pragma once

#include <QByteArray>
#include <QString>
#include <QtGlobal>

#include <atlas/textsnapshot.h>

#include <memory>
#include <vector>

namespace AtlasTextDetail {

constexpr int MaxFan = 64;
constexpr int MinFan = 32;
// The most bytes in one piece.
constexpr qsizetype MaxPiece = 64 * 1024;

// Immutable bytes. For the add buffer the bytes after the used part are
// written once, by the owner thread, before any piece refers to them; no
// reader looks at them before that.
struct Block {
    QByteArray bytes;
    const char *ptr = nullptr;
};

struct Agg {
    qsizetype bytes = 0;
    qsizetype u16 = 0;
    qsizetype pieces = 0;
    qsizetype lf = 0;   // LF characters
    qsizetype cr = 0;   // CR characters
    qsizetype crlf = 0; // CR immediately followed by LF
    bool startsLF = false;
    bool endsCR = false;

    // Breaks that end inside this run: a trailing CR is not counted, because
    // what follows it decides (the parent counts it, see TextTree).
    qsizetype breaks() const { return lf + cr - crlf - (endsCR ? 1 : 0); }
    friend bool operator==(const Agg &a, const Agg &b) = default;
};

// The aggregates of a followed by b.
Agg combine(const Agg &a, const Agg &b);
// The aggregates of a run of valid UTF-8 (pieces = 1; all zero if empty).
Agg computeAgg(const char *p, qsizetype len);

struct Piece {
    std::shared_ptr<const Block> block;
    qsizetype off = 0;
    Agg agg;

    const char *data() const { return block->ptr + off; }
    qsizetype len() const { return agg.bytes; }
};

struct Node;
using NodePtr = std::shared_ptr<const Node>;

struct Child {
    NodePtr node;
    Agg agg;
};

struct Node {
    bool leaf = true;
    Agg agg;
    std::vector<Piece> pieces; // leaf
    std::vector<Child> kids;   // internal
};

// A piece of `block` from byte `off` for `len` bytes. `len` must be on UTF-8
// character boundaries and in 1..MaxPiece.
Piece makePiece(const std::shared_ptr<const Block> &block, qsizetype off, qsizetype len);
// Cuts [off, off + len) of a block into pieces of at most MaxPiece, on
// character boundaries.
void appendPieces(const std::shared_ptr<const Block> &block, qsizetype off, qsizetype len, std::vector<Piece> &out);

struct LineBreakCounts {
    qsizetype lf = 0;
    qsizetype crlf = 0;
    qsizetype cr = 0;
};

class TextTree
{
public:
    TextTree() = default;

    static TextTree fromPieces(std::vector<Piece> pieces);
    std::vector<Piece> pieces() const;

    // ---- Size. O(1). ----
    qsizetype length() const { return m_root ? m_root->agg.u16 : 0; }
    qsizetype byteLength() const { return m_root ? m_root->agg.bytes : 0; }
    qsizetype pieceCount() const { return m_root ? m_root->agg.pieces : 0; }
    // 1 plus the breaks; an empty text has one empty line.
    qsizetype lineCount() const;
    LineBreakCounts lineBreaks() const;
    bool isEmpty() const { return !m_root; }

    // ---- Conversions. All clamp their argument, all O(log n). ----
    qsizetype lineStart(qsizetype line) const;
    qsizetype lineStartByte(qsizetype line) const;
    qsizetype lineAt(qsizetype position) const;
    qsizetype lineAtByte(qsizetype offset) const;
    qsizetype utf16AtByte(qsizetype offset) const;
    qsizetype byteAtUtf16(qsizetype position) const;

    // True when `position` is between the two halves of a surrogate pair.
    bool insideSurrogatePair(qsizetype position) const;
    // `position` moved to the start of its pair, or to the end of it.
    qsizetype alignDown(qsizetype position) const;
    qsizetype alignUp(qsizetype position) const;

    // ---- Reading. Cost is proportional to the range. ----
    QString text(qsizetype start, qsizetype end) const;
    QByteArray utf8(qsizetype start, qsizetype end) const;

    // ---- Chunks (pieces), in order. ----
    qsizetype chunkCount() const { return pieceCount(); }
    AtlasTextChunk chunkAt(qsizetype index) const;
    qsizetype chunkIndexAtByte(qsizetype offset) const;

    // ---- New versions. The receiver is unchanged. ----
    // Puts `pieces` (all non-empty, in order) at `position`, which must be on a
    // character boundary. Pieces that continue the one before them in the same
    // block are merged into it.
    TextTree withInserted(qsizetype position, std::vector<Piece> pieces) const;
    // Removes [start, end) (on character boundaries) and appends the removed
    // runs, as pieces of the same blocks, to *removed if it is not null.
    TextTree withRemoved(qsizetype start, qsizetype end, std::vector<Piece> *removed) const;

    // Empty when the tree is sound; else the first broken invariant: aggregates
    // equal what the bytes say, every leaf at one depth, 1..64 entries a node
    // (32..64 below the root), pieces of 1..64 KB starting on a character.
    QString validate() const;
    // The depth of the leaves (0 for an empty tree, 1 for a single leaf).
    int height() const;

    friend bool operator==(const TextTree &a, const TextTree &b) { return a.m_root == b.m_root; }

private:
    explicit TextTree(NodePtr root) : m_root(std::move(root)) {}
    NodePtr m_root;
};

// The AtlasTextSnapshotInterface over one version of the tree. `revision` is the
// owner's edit counter. The returned handle holds the only reference.
AtlasTextSnapshot makeSnapshot(const TextTree &tree, quint64 revision);

} // namespace AtlasTextDetail
