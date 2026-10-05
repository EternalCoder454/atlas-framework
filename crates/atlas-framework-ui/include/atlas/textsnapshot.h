// AtlasTextSnapshot: an immutable, versioned view of an AtlasTextView's text.
//
// This header is header-only and links against nothing. An app gets a snapshot
// from AtlasTextViewInterface::snapshot() (see textview.h). The handle below
// only forwards to AtlasTextSnapshotInterface, an abstract class that
// Atlas.Ui implements; the piece tree behind it is private and may change in
// any release. The API reference page for AtlasTextView in docs/reference is
// the description of the behaviour; this header documents the C++ contract.
//
// Units, as everywhere in AtlasTextView:
//   - "position" and "column" are UTF-16 code units, counted from 0;
//   - "line" is counted from 0; a line break (LF, CRLF or lone CR) belongs to
//     the line it ends, and CRLF is two positions;
//   - "byte" is an offset into the UTF-8 form of the text, which is how the
//     text is stored. The text is always valid UTF-8 (invalid input was
//     replaced with U+FFFD when it was loaded).
//
// Lifetime. A snapshot holds one version of the text alive and nothing else.
// The pointers in a Chunk stay valid for as long as any AtlasTextSnapshot
// handle to that version exists, even after the view is edited, saved, reloaded
// or destroyed. They are never valid after the last handle is gone: copy the
// handle (cheap), not the pointer, when the data must outlive the call.
//
// Threads. The data behind a snapshot is immutable, so every const method may
// run on any thread at once, and handles may be copied, moved and destroyed on
// any thread (the reference count is atomic). As with QString, one handle
// object must not be assigned or destroyed on one thread while another thread
// reads that same object: give each thread its own copy. A snapshot never
// calls back into the GUI thread and takes no lock the GUI thread holds. The
// visitor callback runs on the calling thread.
//
// Versioning. The interface is published once and never changes. A release
// that needs more adds AtlasTextSnapshotInterface2 deriving from it (IID /2);
// an app built against /1 keeps working. A handle checks abiVersion() when it
// is built and is null (isNull()) if the implementation is older than the
// header, so a newer app on an older Atlas.Ui fails safely, not by crashing.
#pragma once

#include <QByteArray>
#include <QObject>
#include <QString>
#include <QtGlobal>

#include <functional>
#include <utility>

// The version of AtlasTextSnapshotInterface this header describes.
#define ATLAS_TEXTSNAPSHOT_ABI_VERSION 1

// One run of the text, stored contiguously in UTF-8. The pieces of the buffer
// are at most 64 KB; chunks come in text order and do not overlap or leave gaps.
// A chunk can be empty only when the whole text is empty (then there are none).
struct AtlasTextChunk {
    // The first byte of the chunk. Not null-terminated. Valid while a snapshot
    // handle to this version lives.
    const char *data = nullptr;
    // The number of bytes at `data`.
    qsizetype byteLength = 0;
    // The byte offset of `data[0]` in the whole text.
    qsizetype byteOffset = 0;
    // The UTF-16 position of `data[0]` in the whole text. A search over bytes
    // maps a hit to a position with this plus a count inside the chunk, or
    // with AtlasTextSnapshot::utf16AtByte.
    qsizetype utf16Offset = 0;
    // The number of UTF-16 units the chunk holds.
    qsizetype utf16Length = 0;
};

// The abstract class Atlas.Ui implements. Apps do not use it directly; they use
// AtlasTextSnapshot. The order of the virtuals is part of the ABI: never
// reorder, remove or change one. Reference counting is virtual so that the
// count and the object's layout stay inside Atlas.Ui.
class AtlasTextSnapshotInterface
{
public:
    // The ABI version the implementation supports (1 for this header). Always
    // the first virtual.
    virtual int abiVersion() const = 0;
    // Adds a reference. Atomic; any thread.
    virtual void ref() const = 0;
    // Drops a reference and destroys the snapshot at zero. Atomic; any thread.
    virtual void deref() const = 0;

    // The length in UTF-16 units.
    virtual qsizetype length() const = 0;
    // The length in UTF-8 bytes.
    virtual qsizetype byteLength() const = 0;
    // The number of lines: 1 plus the number of line breaks, so an empty text
    // has one empty line.
    virtual qsizetype lineCount() const = 0;
    // The edit counter of the view when the snapshot was taken. It grows with
    // every edit, undo and redo, and is never reused by one view, so a search
    // result can be tested for staleness by comparing revisions.
    virtual quint64 revision() const = 0;

    // The position of the first unit of `line`; clamped to [0, lineCount()-1].
    virtual qsizetype lineStart(qsizetype line) const = 0;
    // The byte offset of the first byte of `line`; same clamping.
    virtual qsizetype lineStartByte(qsizetype line) const = 0;
    // The line holding `position`; clamped to [0, length()].
    virtual qsizetype lineAt(qsizetype position) const = 0;
    // The line holding the byte at `offset`; clamped to [0, byteLength()].
    virtual qsizetype lineAtByte(qsizetype offset) const = 0;
    // UTF-16 position of the character that starts at (or contains) `offset`.
    // O(log n). Clamped to [0, byteLength()].
    virtual qsizetype utf16AtByte(qsizetype offset) const = 0;
    // The byte offset of `position`. A position inside a surrogate pair gives
    // the offset of the pair's first byte. O(log n). Clamped to [0, length()].
    virtual qsizetype byteAtUtf16(qsizetype position) const = 0;

    // The text from `start` to `end` (UTF-16 positions, clamped, end exclusive)
    // as a QString. Copies; cost is proportional to the range.
    virtual QString text(qsizetype start, qsizetype end) const = 0;
    // The bytes from `start` to `end` (byte offsets, clamped), as UTF-8. Copies.
    virtual QByteArray utf8(qsizetype start, qsizetype end) const = 0;

    // The number of chunks. O(1).
    virtual qsizetype chunkCount() const = 0;
    // The chunk at `index` in [0, chunkCount()); an empty chunk if out of range.
    // O(log n), no copy.
    virtual AtlasTextChunk chunkAt(qsizetype index) const = 0;
    // The index of the chunk holding byte `offset`, clamped. O(log n).
    virtual qsizetype chunkIndexAtByte(qsizetype offset) const = 0;

protected:
    // Not deleted through this type: deref() does it.
    ~AtlasTextSnapshotInterface() = default;
};

Q_DECLARE_INTERFACE(AtlasTextSnapshotInterface, "net.eterneon.Atlas.TextSnapshot/1")

// The value class apps hold. Copying costs one atomic increment.
class AtlasTextSnapshot
{
public:
    // A null snapshot: everything below returns an empty or zero result.
    AtlasTextSnapshot() noexcept = default;

    // Adopts `impl`, taking a new reference. Atlas.Ui calls this; apps get a
    // snapshot from AtlasTextViewInterface::snapshot(). A null `impl`, or one
    // whose abiVersion() is below ATLAS_TEXTSNAPSHOT_ABI_VERSION, gives a null
    // snapshot.
    explicit AtlasTextSnapshot(const AtlasTextSnapshotInterface *impl) noexcept
    {
        if (impl && impl->abiVersion() >= ATLAS_TEXTSNAPSHOT_ABI_VERSION) {
            impl->ref();
            m_impl = impl;
        }
    }
    AtlasTextSnapshot(const AtlasTextSnapshot &other) noexcept : m_impl(other.m_impl)
    {
        if (m_impl)
            m_impl->ref();
    }
    AtlasTextSnapshot(AtlasTextSnapshot &&other) noexcept : m_impl(std::exchange(other.m_impl, nullptr)) {}
    AtlasTextSnapshot &operator=(const AtlasTextSnapshot &other) noexcept
    {
        AtlasTextSnapshot tmp(other);
        swap(tmp);
        return *this;
    }
    AtlasTextSnapshot &operator=(AtlasTextSnapshot &&other) noexcept
    {
        AtlasTextSnapshot tmp(std::move(other));
        swap(tmp);
        return *this;
    }
    ~AtlasTextSnapshot()
    {
        if (m_impl)
            m_impl->deref();
    }
    // Swaps two handles.
    void swap(AtlasTextSnapshot &other) noexcept { std::swap(m_impl, other.m_impl); }

    // True for a default-constructed snapshot, or one the implementation was
    // too old for. A null snapshot is safe to use and reads as empty.
    bool isNull() const noexcept { return !m_impl; }
    // True when both handles hold the same version of the text.
    bool isSameVersion(const AtlasTextSnapshot &other) const noexcept { return m_impl == other.m_impl; }

    // The length in UTF-16 units.
    qsizetype length() const { return m_impl ? m_impl->length() : 0; }
    // The length in UTF-8 bytes.
    qsizetype byteLength() const { return m_impl ? m_impl->byteLength() : 0; }
    // The number of lines (at least 1 for a non-null snapshot, 0 when null).
    qsizetype lineCount() const { return m_impl ? m_impl->lineCount() : 0; }
    // The view's edit counter when the snapshot was taken (0 when null).
    quint64 revision() const { return m_impl ? m_impl->revision() : 0; }

    // Line index. Positions are UTF-16 units, offsets are UTF-8 bytes; see the
    // top of this file. Out-of-range arguments are clamped, never an error.
    qsizetype lineStart(qsizetype line) const { return m_impl ? m_impl->lineStart(line) : 0; }
    qsizetype lineStartByte(qsizetype line) const { return m_impl ? m_impl->lineStartByte(line) : 0; }
    qsizetype lineAt(qsizetype position) const { return m_impl ? m_impl->lineAt(position) : 0; }
    qsizetype lineAtByte(qsizetype offset) const { return m_impl ? m_impl->lineAtByte(offset) : 0; }
    // The end of `line` without its line break, in UTF-16 units.
    qsizetype lineEnd(qsizetype line) const
    {
        if (!m_impl)
            return 0;
        const qsizetype n = m_impl->lineCount();
        if (line < 0)
            line = 0;
        if (line >= n - 1)
            return m_impl->length();
        qsizetype end = m_impl->lineStart(line + 1);
        // Step back over the break: LF, CR, or CRLF.
        const QString tail = m_impl->text(end - 2 < 0 ? 0 : end - 2, end);
        if (tail.endsWith(QLatin1String("\r\n")))
            return end - 2;
        return end - 1;
    }

    // Offset maps between bytes and UTF-16 positions, O(log n).
    qsizetype utf16AtByte(qsizetype offset) const { return m_impl ? m_impl->utf16AtByte(offset) : 0; }
    qsizetype byteAtUtf16(qsizetype position) const { return m_impl ? m_impl->byteAtUtf16(position) : 0; }

    // The text in [start, end) as a QString. Copies. The whole text is
    // text(0, length()); avoid it for large files, use visitChunks instead.
    QString text(qsizetype start, qsizetype end) const { return m_impl ? m_impl->text(start, end) : QString(); }
    // The whole text as a QString. Copies all of it.
    QString text() const { return m_impl ? m_impl->text(0, m_impl->length()) : QString(); }
    // The bytes in [start, end) as UTF-8. Copies.
    QByteArray utf8(qsizetype start, qsizetype end) const { return m_impl ? m_impl->utf8(start, end) : QByteArray(); }

    // The number of chunks, and one chunk by index. Pointers in a chunk stay
    // valid while this handle (or any copy) lives. No copying.
    qsizetype chunkCount() const { return m_impl ? m_impl->chunkCount() : 0; }
    AtlasTextChunk chunkAt(qsizetype index) const { return m_impl ? m_impl->chunkAt(index) : AtlasTextChunk(); }
    // The index of the chunk holding byte `offset`.
    qsizetype chunkIndexAtByte(qsizetype offset) const { return m_impl ? m_impl->chunkIndexAtByte(offset) : 0; }

    // Walks the chunks in order, from the one holding byte `fromByte` (0 for
    // the first), without copying. `visit` returns true to continue and false
    // to stop. It runs on the calling thread and must not throw. The chunk
    // pointers it receives are valid for the whole walk and after it, while
    // this handle lives. This is how Notepad hands the text to Rust: pass
    // chunk.data and chunk.byteLength to the C ABI call, in order.
    template<typename F>
    void visitChunks(F &&visit, qsizetype fromByte = 0) const
    {
        if (!m_impl)
            return;
        const qsizetype n = m_impl->chunkCount();
        for (qsizetype i = fromByte > 0 ? m_impl->chunkIndexAtByte(fromByte) : 0; i < n; ++i) {
            if (!visit(m_impl->chunkAt(i)))
                return;
        }
    }

    friend bool operator==(const AtlasTextSnapshot &a, const AtlasTextSnapshot &b) noexcept { return a.m_impl == b.m_impl; }
    friend bool operator!=(const AtlasTextSnapshot &a, const AtlasTextSnapshot &b) noexcept { return a.m_impl != b.m_impl; }

private:
    const AtlasTextSnapshotInterface *m_impl = nullptr;
};

Q_DECLARE_METATYPE(AtlasTextSnapshot)
