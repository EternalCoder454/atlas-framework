// The text buffer behind AtlasTextView (1.5.0 item 38, step 1a): a TextTree plus
// loading, editing and line endings. Pure QtCore, no QQuickItem.
//
// Threads. A TextBuffer belongs to one thread (the GUI thread in the view): all
// its methods, apart from setLoadNotify's callback, run there. What crosses
// threads is a snapshot (see snapshot()): immutable, O(1) to take, readable from
// anywhere while the buffer is edited. Loading counts and checks the text on
// the workers of a small private QThreadPool, which touch only their own range.
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

// The callback of setLoadNotify() and the mutex that guards it. Shared with the
// workers, so it outlives the buffer while a task still holds it.
struct LoadNotifier {
    QMutex mutex;
    std::function<void()> fn;
};

// Test hook: called on a worker before it checks a range (data = its first
// byte, size = its length). It may block, or throw to simulate a failed task.
// nullptr (the default) turns it off.
using TaskHook = void (*)(const char *data, qsizetype size);
void setTaskHookForTests(TaskHook hook);

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
    // bytes of a chunk of 32 KB or more are not copied: the buffer keeps a
    // reference to the QByteArray, so it must own its memory (not
    // QByteArray::fromRawData). Smaller chunks are gathered into one buffer
    // (about 64 KB) before they become a piece. A chunk of 32 KB or more is
    // cut into ranges of about 1 MB; counting runs on worker threads, one task
    // for each range. pollLoad() takes finished ranges, in order, into the
    // text, so the text grows while loading. endLoad() says no more data
    // comes; with wait it blocks until everything is in and returns true.
    // Edits are refused until the load is finished. Never call endLoad(true)
    // from a pool thread (the workers are few; it could wait for itself).
    // When a worker fails (out of memory) the load is marked failed, later
    // ranges are dropped, and the text is the clean prefix before the failure.
    void beginLoad();
    void appendData(const QByteArray &utf8);
    void appendData(const char *data, qsizetype size);
    bool endLoad(bool wait = true);
    // Takes the chunks that are ready. True when the load is finished.
    bool pollLoad();
    // Stops the load now: unfinished tasks are cancelled (they release their
    // memory and notify nobody) and the text is emptied. loadFailed() is false.
    void cancelLoad();
    // Stops the load now but keeps the text that is already in order: the
    // ranges finished so far, up to the first unfinished one. `failed` sets
    // loadFailed(). Does nothing when no load is running.
    void abortLoad(bool failed);
    bool loading() const { return m_loading; }
    // The share of the bytes given so far that has been checked and counted.
    double loadProgress() const;
    bool hadInvalidText() const { return m_hadInvalid; }
    // True when a worker ran out of memory: the text is incomplete.
    bool loadFailed() const { return m_loadFailed; }
    // Called on a worker thread whenever a range finishes (never inline from
    // appendData), so the owner can schedule pollLoad() on its own thread. The
    // callback runs with the notifier's mutex held, which is what makes it safe
    // to destroy the buffer: ~TextBuffer() and setLoadNotify() wait for a call
    // in progress, and none starts afterwards. So it must only post (for
    // example a queued QMetaObject::invokeMethod through a QPointer), and must
    // never block on the GUI thread, call into the buffer, or throw (a
    // throw is swallowed). Tasks of a cancelled load do not call it.
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
    // The kind that has the most breaks. Ties: LF wins over both others, CRLF
    // wins over CR; LF when there are no breaks.
    AtlasText::LineEnding dominantLineEnding() const;
    // Rewrites every break as `kind`, as one change covering the whole text.
    // Nothing happens (ok, unchanged) when the text already uses only `kind`;
    // `kind` Mixed is refused.
    Change convertLineEndings(AtlasText::LineEnding kind);

private:
    struct Slot {
        std::future<JobResult> result;
    };

    void appendImpl(const QByteArray &utf8);
    void pushImmediate(std::vector<Piece> pieces);
    void flushPending();
    void submitRange(const std::shared_ptr<const Block> &block, qsizetype from, qsizetype to);
    // Takes the finished slots, in order, into the tree. True when one failed.
    bool takeReady();
    void failLoad();
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
    QByteArray m_pending; // small chunks gathered, not yet a piece
    std::deque<Slot> m_slots;
    std::shared_ptr<LoadState> m_state;
    std::shared_ptr<LoadNotifier> m_notifier;
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
