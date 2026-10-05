// The text buffer behind AtlasTextView (1.5.0 item 38, step 1a): a TextTree plus
// loading, editing and line endings. Pure QtCore, no QQuickItem.
//
// Threads. A TextBuffer belongs to one thread (the GUI thread in the view): all
// its methods, apart from setLoadNotify's callback, run there. What crosses
// threads is a snapshot (see snapshot()): immutable, O(1) to take, readable from
// anywhere while the buffer is edited. Loading counts and checks the text on
// QThreadPool workers, which touch only their own chunk.
#pragma once

#include "texttree.h"

#include <atlas/textview.h>

#include <deque>
#include <functional>
#include <future>
#include <memory>
#include <vector>

#include <QByteArray>
#include <QMutex>
#include <QString>

namespace AtlasTextDetail {

struct LoadState;

// What one load task hands back.
struct JobResult {
    std::vector<Piece> pieces;
    bool invalid = false;
    bool failed = false;
};

class TextBuffer
{
public:
    // What an edit did: enough for step 2's undo records (the removed and the
    // inserted runs are references into blocks, not copies of the text). To undo
    // an edit, remove `insertedLength` units at `position`, then insert `removed`
    // there with insertPieces().
    struct Change {
        bool ok = false; // false: refused (the buffer is loading)
        qsizetype position = 0;
        qsizetype removedLength = 0;  // UTF-16 units
        qsizetype insertedLength = 0; // UTF-16 units
        std::vector<Piece> removed;
        std::vector<Piece> inserted;
        // True when the text changed.
        bool changed() const { return removedLength > 0 || insertedLength > 0; }
    };

    TextBuffer();
    ~TextBuffer();
    TextBuffer(const TextBuffer &) = delete;
    TextBuffer &operator=(const TextBuffer &) = delete;

    const TextTree &tree() const { return m_tree; }
    // The text as it is now. O(1); see AtlasTextSnapshot for what it may do.
    AtlasTextSnapshot snapshot() const { return makeSnapshot(m_tree, m_revision); }
    // Grows with every edit, load step and conversion; never reused.
    quint64 revision() const { return m_revision; }

    // ---- Loading ----
    // beginLoad() drops the text (snapshots keep their version) and starts a
    // load. appendData() takes UTF-8 of any size, cut anywhere: a character
    // split across two calls is put back together. Invalid UTF-8 becomes U+FFFD
    // (one for each maximal invalid subpart) and sets hadInvalidText(). The
    // bytes are not copied: the buffer keeps a reference to the QByteArray, so
    // it must own its memory (not QByteArray::fromRawData). Counting runs on
    // worker threads; pollLoad() takes finished chunks, in order, into the
    // text, so the text grows while loading. endLoad() says no more data
    // comes; with wait it blocks until everything is in and returns true.
    // Edits are refused until the load is finished.
    void beginLoad();
    void appendData(const QByteArray &utf8);
    void appendData(const char *data, qsizetype size);
    bool endLoad(bool wait = true);
    // Takes the chunks that are ready. True when the load is finished.
    bool pollLoad();
    bool loading() const { return m_loading; }
    // The share of the bytes given so far that has been checked and counted.
    double loadProgress() const;
    bool hadInvalidText() const { return m_hadInvalid; }
    // True when a worker ran out of memory: the text is incomplete.
    bool loadFailed() const { return m_loadFailed; }
    // Called on a worker thread whenever a chunk finishes, so the owner can
    // schedule pollLoad() on its own thread. It must be thread-safe and quick.
    void setLoadNotify(std::function<void()> notify);
    // A whole-text replacement as one synchronous load.
    void setText(const QString &text);

    // ---- Editing (UTF-16 positions, clamped) ----
    // A position inside a surrogate pair moves to the start of the pair, so no
    // edit ever splits one (a remove widens to whole pairs). Lone surrogates in
    // `text` become U+FFFD, as in any UTF-8 text.
    Change insert(qsizetype position, const QString &text);
    Change remove(qsizetype start, qsizetype end);
    Change replace(qsizetype start, qsizetype end, const QString &text);
    // Puts existing pieces back (undo's second half).
    Change insertPieces(qsizetype position, std::vector<Piece> pieces);

    // ---- Line endings ----
    // LF for an empty text; Mixed when two kinds or more are present.
    AtlasText::LineEnding lineEnding() const;
    // The kind that has the most breaks (LF on a tie or when there are none).
    AtlasText::LineEnding dominantLineEnding() const;
    // Rewrites every break as `kind`, as one change covering the whole text.
    // Nothing happens (ok, unchanged) when the text already uses only `kind`;
    // `kind` Mixed is refused.
    Change convertLineEndings(AtlasText::LineEnding kind);

private:
    struct Slot {
        std::future<JobResult> result;
    };

    void pushImmediate(std::vector<Piece> pieces);
    std::vector<Piece> addPieces(const QByteArray &utf8);
    Change applyInsert(qsizetype position, std::vector<Piece> pieces);

    TextTree m_tree;
    quint64 m_revision = 0;

    // The add buffer: a fixed block that typed text is copied into.
    std::shared_ptr<Block> m_add;
    char *m_addWrite = nullptr;
    qsizetype m_addUsed = 0;

    bool m_loading = false;
    bool m_inputDone = false;
    bool m_hadInvalid = false;
    bool m_loadFailed = false;
    QByteArray m_carry; // the start of a character the next chunk completes
    std::deque<Slot> m_slots;
    std::shared_ptr<LoadState> m_state;
    struct Notifier {
        QMutex mutex;
        std::function<void()> fn;
    };
    std::shared_ptr<Notifier> m_notifier;
};

// UTF-8 checking, exposed for the tests.
enum class SeqKind { Valid, Invalid, Incomplete };
struct SeqResult {
    SeqKind kind;
    int len; // Valid: the bytes of the sequence. Invalid: the maximal invalid
             // subpart (to be replaced by one U+FFFD). Incomplete: the bytes
             // available, all of them a valid start.
};
SeqResult checkUtf8Sequence(const uchar *p, qsizetype avail);

} // namespace AtlasTextDetail
