// The text buffer behind TelamonTextView (ui/text): the piece tree against a
// QString model, loading, line endings and snapshots. Pure QtCore.
#include "textbuffer.h"

#include <QRandomGenerator>
#include <QtTest>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstring>
#include <functional>
#include <mutex>
#include <new>
#include <thread>

using namespace TelamonTextDetail;
using LE = TelamonText::LineEnding;

// ---- The model ----

namespace {

struct Model {
    QList<qsizetype> ends; // where each break ends
    qsizetype lfOnly = 0, crlf = 0, crOnly = 0;
    QList<qsizetype> byteOfUnit; // size n + 1
    QList<qsizetype> unitOfByte; // size B + 1
    QByteArray u8;
};

Model buildModel(const QString &s)
{
    Model m;
    const qsizetype n = s.size();
    for (qsizetype i = 0; i < n; ++i) {
        if (s[i] == u'\n') {
            m.ends.append(i + 1);
            ++m.lfOnly;
        } else if (s[i] == u'\r') {
            if (i + 1 < n && s[i + 1] == u'\n') {
                m.ends.append(i + 2);
                ++m.crlf;
                ++i;
            } else {
                m.ends.append(i + 1);
                ++m.crOnly;
            }
        }
    }
    // A CRLF was counted as an LF above (the loop skips its CR): that is right
    // for ends, but lfOnly then holds LFs without a CR before them only.
    m.u8 = s.toUtf8();
    m.byteOfUnit.resize(n + 1);
    m.unitOfByte.resize(m.u8.size() + 1);
    qsizetype b = 0;
    for (qsizetype i = 0; i < n;) {
        const bool pair = s[i].isHighSurrogate() && i + 1 < n && s[i + 1].isLowSurrogate();
        const int w = pair ? 2 : 1;
        const char32_t cp = pair ? QChar::surrogateToUcs4(s[i], s[i + 1]) : s[i].unicode();
        const int len = cp < 0x80 ? 1 : cp < 0x800 ? 2 : cp < 0x10000 ? 3 : 4;
        for (int u = 0; u < w; ++u)
            m.byteOfUnit[i + u] = b;
        for (int k = 0; k < len; ++k)
            m.unitOfByte[b + k] = i;
        b += len;
        i += w;
    }
    m.byteOfUnit[n] = b;
    m.unitOfByte[b] = n;
    return m;
}

qsizetype modelLineAt(const Model &m, qsizetype pos)
{
    return std::upper_bound(m.ends.begin(), m.ends.end(), pos) - m.ends.begin();
}

bool pairInside(const QString &s, qsizetype p)
{
    return p > 0 && p < s.size() && s[p - 1].isHighSurrogate() && s[p].isLowSurrogate();
}

// What an edit of [a, b) really covers: whole surrogate pairs. An empty range
// covers nothing (the position still moves to the start of a pair).
std::pair<qsizetype, qsizetype> widen(const QString &s, qsizetype a, qsizetype b)
{
    if (a == b) {
        const qsizetype p = pairInside(s, a) ? a - 1 : a;
        return {p, p};
    }
    return {pairInside(s, a) ? a - 1 : a, pairInside(s, b) ? b + 1 : b};
}

QString err(const char *what, qsizetype got, qsizetype want, qsizetype arg = -1)
{
    return QStringLiteral("%1: got %2, want %3 (argument %4)").arg(QLatin1String(what)).arg(got).arg(want).arg(arg);
}

// Everything the tree says, against the model. Empty string when it all agrees.
QString compareAll(const TextTree &t, const QString &s, QRandomGenerator &rng, bool full)
{
    const QString v = t.validate();
    if (!v.isEmpty())
        return QStringLiteral("invalid tree: ") + v;
    const Model m = buildModel(s);
    const qsizetype n = s.size(), B = m.u8.size();
    if (t.length() != n)
        return err("length", t.length(), n);
    if (t.byteLength() != B)
        return err("byteLength", t.byteLength(), B);
    if (t.lineCount() != m.ends.size() + 1)
        return err("lineCount", t.lineCount(), m.ends.size() + 1);
    const LineBreakCounts lb = t.lineBreaks();
    if (lb.lf != m.lfOnly || lb.crlf != m.crlf || lb.cr != m.crOnly)
        return QStringLiteral("line break counts %1/%2/%3, want %4/%5/%6").arg(lb.lf).arg(lb.crlf).arg(lb.cr).arg(m.lfOnly).arg(m.crlf).arg(m.crOnly);
    if (t.text(0, n) != s)
        return QStringLiteral("text differs");
    if (t.utf8(0, B) != m.u8)
        return QStringLiteral("utf8 differs");

    // The conversions.
    QList<qsizetype> positions{0, n, n > 0 ? n - 1 : 0};
    QList<qsizetype> offsets{0, B, B > 0 ? B - 1 : 0};
    const int count = full ? 600 : 12;
    for (int i = 0; i < count && n > 0; ++i) {
        positions.append(full && n <= 600 ? i : qsizetype(rng.bounded(quint32(n + 1))));
        offsets.append(full && B <= 600 ? i : qsizetype(rng.bounded(quint32(B + 1))));
    }
    for (qsizetype p : positions) {
        if (p < 0 || p > n)
            continue;
        if (t.lineAt(p) != modelLineAt(m, p))
            return err("lineAt", t.lineAt(p), modelLineAt(m, p), p);
        if (t.byteAtUtf16(p) != m.byteOfUnit[p])
            return err("byteAtUtf16", t.byteAtUtf16(p), m.byteOfUnit[p], p);
        if (t.insideSurrogatePair(p) != pairInside(s, p))
            return err("insideSurrogatePair", t.insideSurrogatePair(p), pairInside(s, p), p);
    }
    for (qsizetype b : offsets) {
        if (b < 0 || b > B)
            continue;
        if (t.utf16AtByte(b) != m.unitOfByte[b])
            return err("utf16AtByte", t.utf16AtByte(b), m.unitOfByte[b], b);
        if (t.lineAtByte(b) != modelLineAt(m, m.unitOfByte[b]))
            return err("lineAtByte", t.lineAtByte(b), modelLineAt(m, m.unitOfByte[b]), b);
    }
    const qsizetype lines = m.ends.size() + 1;
    QList<qsizetype> ks{0, lines - 1, lines > 1 ? 1 : 0};
    for (int i = 0; i < (full ? 400 : 12); ++i)
        ks.append(full && lines <= 400 ? i : qsizetype(rng.bounded(quint32(lines))));
    for (qsizetype k : ks) {
        if (k < 0 || k >= lines)
            continue;
        const qsizetype want = k == 0 ? 0 : m.ends[k - 1];
        if (t.lineStart(k) != want)
            return err("lineStart", t.lineStart(k), want, k);
        if (t.lineStartByte(k) != m.byteOfUnit[want])
            return err("lineStartByte", t.lineStartByte(k), m.byteOfUnit[want], k);
    }
    if (t.lineStart(-5) != 0 || t.lineStart(lines + 5) != t.lineStart(lines - 1))
        return QStringLiteral("lineStart does not clamp");
    for (int i = 0; i < (full ? 40 : 6); ++i) {
        const qsizetype a = qsizetype(rng.bounded(quint32(n + 1))), b = qsizetype(rng.bounded(quint32(n + 1)));
        const qsizetype lo = std::min(a, b), hi = std::max(a, b);
        if (t.text(lo, hi) != s.mid(lo, hi - lo))
            return QStringLiteral("text(%1, %2) differs").arg(lo).arg(hi);
    }
    if (full) {
        qsizetype bytes = 0, units = 0;
        for (qsizetype i = 0; i < t.chunkCount(); ++i) {
            const TelamonTextChunk c = t.chunkAt(i);
            if (c.byteOffset != bytes || c.utf16Offset != units || c.byteLength < 1 || c.byteLength > MaxPiece)
                return QStringLiteral("chunk %1 is out of place").arg(i);
            if (std::memcmp(c.data, m.u8.constData() + bytes, size_t(c.byteLength)) != 0)
                return QStringLiteral("chunk %1 has wrong bytes").arg(i);
            if (t.chunkIndexAtByte(bytes) != i || t.chunkIndexAtByte(bytes + c.byteLength - 1) != i)
                return QStringLiteral("chunkIndexAtByte wrong at chunk %1").arg(i);
            bytes += c.byteLength;
            units += c.utf16Length;
        }
        if (bytes != B || units != n)
            return QStringLiteral("chunks do not add up");
    }
    return QString();
}

QString randomText(QRandomGenerator &rng, int tokens)
{
    static const QStringList toks = {
        QStringLiteral("a"),      QStringLiteral("bc"),   QStringLiteral(" "),      QStringLiteral("\n"),
        QStringLiteral("\r"),     QStringLiteral("\r\n"), QStringLiteral("\xE9"),   QStringLiteral("中"),
        QString::fromUtf8("\xF0\x9F\x98\x80"), QStringLiteral("x\ny"), QStringLiteral("\n\n"), QStringLiteral("\r\r"),
    };
    QString s;
    for (int i = 0; i < tokens; ++i)
        s += toks[rng.bounded(quint32(toks.size()))];
    return s;
}

QString makeString(const QByteArray &u8)
{
    return QString::fromUtf8(u8);
}

std::shared_ptr<const Block> blockOf(const QByteArray &bytes)
{
    auto b = std::make_shared<Block>();
    b->bytes = bytes;
    b->ptr = b->bytes.constData();
    return b;
}

// One piece for every byte (ASCII text only), all from one block.
TextTree treeOfBytes(const QByteArray &raw)
{
    const auto block = blockOf(raw);
    std::vector<Piece> ps;
    ps.reserve(size_t(raw.size()));
    for (qsizetype i = 0; i < raw.size(); ++i)
        ps.push_back(makePiece(block, i, 1));
    return TextTree::fromPieces(std::move(ps));
}

// The task hook of the load tests: a chunk that starts with 'A' waits while the
// gate is closed; one that starts with g_throwOn fails as if out of memory.
std::atomic<bool> g_gateClosed{false};
std::atomic<int> g_throwOn{-1};
std::atomic<int> g_delayMs{0};

void testHook(const char *data, qsizetype)
{
    const int first = uchar(data[0]);
    if (first == 'A') {
        for (int i = 0; i < 10000 && g_gateClosed.load(); ++i)
            QThread::msleep(1);
    }
    if (first == g_throwOn.load())
        throw std::bad_alloc();
    if (g_delayMs.load() > 0)
        QThread::msleep(unsigned(g_delayMs.load()));
}

bool waitUntil(const std::function<bool()> &done, int ms = 10000)
{
    QElapsedTimer t;
    t.start();
    while (!done()) {
        if (t.elapsed() > ms)
            return false;
        QThread::msleep(2);
    }
    return true;
}

} // namespace

class TestTextBuffer : public QObject
{
    Q_OBJECT

private slots:
    void init();
    void cleanup();
    void emptyBuffer();
    void fuzzTree_data();
    void fuzzTree();
    void deepTree();
    void bigPieces();
    void typingMerges();
    void surrogateEdits();
    void crlfAcrossEdits();
    void undoPieces();
    void insertPiecesContiguous();
    void removeAcrossLevels();
    void lineSeamsManyPieces();
    void loneSurrogateInInsert();

    void loadChunkBoundaries();
    void loadCrlfBoundary();
    void loadInvalid_data();
    void loadInvalid();
    void loadEmpty();
    void loadOneMegabyte();
    void loadEditsRefused();
    void loadRestart();
    void loadWorkerBoundaries();
    void destroyWithTasks();
    void beginLoadWhileWorkersRun();
    void cancelledTasksSilent();
    void loadFailure();
    void abortLoad();
    void outOfOrderFinish();
    void notifyPerRange();

    void lineEndingDetection();
    void lineEndingConversion();
    void convertFlushBetweenCrLf();
    void dominantTies();
    void lineEndingBig();

    void snapshotIsFrozen();
    void snapshotQueries();
    void snapshotNull();
    void snapshotThreads();
};

void TestTextBuffer::init()
{
    g_gateClosed = false;
    g_throwOn = -1;
    g_delayMs = 0;
    setTaskHookForTests(testHook);
}

void TestTextBuffer::cleanup()
{
    g_gateClosed = false; // lets a blocked task go
    g_throwOn = -1;
    g_delayMs = 0;
    setTaskHookForTests(nullptr);
}

void TestTextBuffer::emptyBuffer()
{
    TextBuffer b;
    QCOMPARE(b.tree().length(), qsizetype(0));
    QCOMPARE(b.tree().byteLength(), qsizetype(0));
    QCOMPARE(b.tree().lineCount(), qsizetype(1));
    QCOMPARE(b.tree().lineStart(0), qsizetype(0));
    QCOMPARE(b.tree().lineStart(7), qsizetype(0));
    QCOMPARE(b.tree().lineAt(5), qsizetype(0));
    QCOMPARE(b.tree().chunkCount(), qsizetype(0));
    QCOMPARE(b.tree().chunkAt(0).byteLength, qsizetype(0));
    QCOMPARE(b.tree().utf16AtByte(3), qsizetype(0));
    QVERIFY(b.tree().text(0, 10).isEmpty());
    QVERIFY(b.tree().validate().isEmpty());
    QVERIFY(b.lineEnding() == LE::LF);
    QRandomGenerator rng(1);
    QVERIFY2(compareAll(b.tree(), QString(), rng, true).isEmpty(), "empty model");
    const TelamonTextSnapshot s = b.snapshot();
    QVERIFY(!s.isNull());
    QCOMPARE(s.lineCount(), qsizetype(1));
    // Removing from nothing, inserting nothing.
    QVERIFY(b.remove(0, 10).ok);
    QVERIFY(!b.remove(0, 10).changed());
    QVERIFY(!b.insert(0, QString()).changed());
    QCOMPARE(b.revision(), quint64(0));
}

void TestTextBuffer::fuzzTree_data()
{
    QTest::addColumn<quint32>("seed");
    for (quint32 seed : {1u, 2u, 3u, 0xC0FFEEu, 12345u})
        QTest::newRow(qPrintable(QString::number(seed))) << seed;
}

void TestTextBuffer::fuzzTree()
{
    QFETCH(quint32, seed);
    QRandomGenerator rng(seed);
    TextBuffer buf;
    QString model;
    int maxHeight = 0;
    qsizetype maxPieces = 0;
    for (int step = 0; step < 10000; ++step) {
        const quint32 op = rng.bounded(100);
        const qsizetype n = model.size();
        QString what;
        if (n > 40000 || (op >= 96 && n > 10)) {
            // A large removal.
            qsizetype a = qsizetype(rng.bounded(quint32(n + 1)));
            qsizetype b = std::min<qsizetype>(n, a + qsizetype(rng.bounded(quint32(n / 3 + 1))));
            what = QStringLiteral("remove %1..%2").arg(a).arg(b);
            const auto [ra, rb] = widen(model, a, b);
            const auto c = buf.remove(a, b);
            QVERIFY2(c.ok && c.position == ra && c.removedLength == rb - ra && c.insertedLength == 0, qPrintable(what));
            model.remove(ra, rb - ra);
        } else if (op < 62) {
            // An insert, mostly small, sometimes empty or huge.
            const quint32 kind = rng.bounded(100);
            const int tokens = kind < 4 ? 0 : kind < 6 ? int(rng.bounded(1500u)) + 500 : int(rng.bounded(6u)) + 1;
            const QString text = randomText(rng, tokens);
            qsizetype p = qsizetype(rng.bounded(quint32(n + 1)));
            what = QStringLiteral("insert %1 units at %2").arg(text.size()).arg(p);
            const qsizetype rp = widen(model, p, p).first;
            const auto c = buf.insert(p, text);
            QVERIFY2(c.ok && c.position == rp && c.insertedLength == text.size() && c.removedLength == 0, qPrintable(what));
            model.insert(rp, text);
        } else if (op < 70) {
            // A replace.
            const qsizetype a = qsizetype(rng.bounded(quint32(n + 1)));
            const qsizetype b = std::min<qsizetype>(n, a + qsizetype(rng.bounded(30u)));
            const QString text = randomText(rng, int(rng.bounded(4u)));
            what = QStringLiteral("replace %1..%2 by %3 units").arg(a).arg(b).arg(text.size());
            const auto [ra, rb] = widen(model, a, b);
            const auto c = buf.replace(a, b, text);
            QVERIFY2(c.ok && c.position == ra && c.removedLength == rb - ra && c.insertedLength == text.size(), qPrintable(what));
            model.replace(ra, rb - ra, text);
        } else {
            // A small removal; every eighth is put back from its pieces.
            const qsizetype a = qsizetype(rng.bounded(quint32(n + 1)));
            const qsizetype b = std::min<qsizetype>(n, a + qsizetype(rng.bounded(30u)));
            what = QStringLiteral("remove %1..%2").arg(a).arg(b);
            const auto [ra, rb] = widen(model, a, b);
            const QString gone = model.mid(ra, rb - ra);
            auto c = buf.remove(a, b);
            QVERIFY2(c.ok && c.removedLength == rb - ra, qPrintable(what));
            model.remove(ra, rb - ra);
            if (rng.bounded(8u) == 0 && !gone.isEmpty()) {
                const auto back = buf.insertPieces(ra, c.removed);
                QVERIFY2(back.insertedLength == gone.size(), "reinsert");
                model.insert(ra, gone);
                what += QStringLiteral(", put back");
            }
        }
        maxHeight = std::max(maxHeight, buf.tree().height());
        maxPieces = std::max(maxPieces, buf.tree().pieceCount());
        // The invariants after every step; the model (O(n) to build) every 20th.
        const QString v = buf.tree().validate();
        QVERIFY2(v.isEmpty() && buf.tree().length() == model.size(),
                 qPrintable(QStringLiteral("seed %1 step %2 after %3: invalid tree: %4").arg(seed).arg(step).arg(what, v)));
        if (step % 20 == 0 || step % 250 == 0 || step == 9999) {
            const QString e = compareAll(buf.tree(), model, rng, step % 250 == 0 || step == 9999);
            QVERIFY2(e.isEmpty(), qPrintable(QStringLiteral("seed %1 step %2 after %3: %4").arg(seed).arg(step).arg(what, e)));
        }
    }
    qInfo() << "seed" << seed << "max pieces" << maxPieces << "max height" << maxHeight << "final length" << model.size();
    QVERIFY(maxPieces > 64);
}

void TestTextBuffer::deepTree()
{
    // Thousands of scattered one-character edits: three levels, then back to
    // nothing with the invariants holding all the way down.
    QRandomGenerator rng(77);
    TextBuffer buf;
    QString model;
    const QStringList toks = {QStringLiteral("a"), QStringLiteral("\n"), QStringLiteral("\r"), QStringLiteral("b")};
    for (int i = 0; i < 12000; ++i) {
        const qsizetype p = qsizetype(rng.bounded(quint32(model.size() + 1)));
        // Alternate sides so that pieces do not merge into each other.
        const QString t = toks[rng.bounded(quint32(toks.size()))];
        buf.insert(p, t);
        model.insert(p, t);
        if (i % 1000 == 0) {
            const QString v = buf.tree().validate();
            QVERIFY2(v.isEmpty(), qPrintable(v));
        }
    }
    QVERIFY2(buf.tree().height() >= 3, qPrintable(QString::number(buf.tree().height())));
    QString e = compareAll(buf.tree(), model, rng, true);
    QVERIFY2(e.isEmpty(), qPrintable(e));
    int step = 0;
    while (!model.isEmpty()) {
        const qsizetype a = qsizetype(rng.bounded(quint32(model.size())));
        const qsizetype len = qsizetype(rng.bounded(quint32(std::min<qsizetype>(40, model.size() - a)))) + 1;
        buf.remove(a, a + len);
        model.remove(a, len);
        if (++step % 40 == 0 || model.size() < 50) {
            e = compareAll(buf.tree(), model, rng, false);
            QVERIFY2(e.isEmpty(), qPrintable(e));
        }
    }
    QVERIFY(buf.tree().isEmpty());
    QCOMPARE(buf.tree().height(), 0);
    // Taking a big range out at once.
    for (int i = 0; i < 6000; ++i) {
        buf.insert(buf.tree().length() / 2, QStringLiteral("ab\n"));
    }
    const qsizetype h = buf.tree().height();
    const auto c = buf.remove(10, buf.tree().length() - 10);
    QCOMPARE(c.removedLength, qsizetype(18000 - 20));
    QCOMPARE(buf.tree().length(), qsizetype(20));
    QVERIFY(buf.tree().validate().isEmpty());
    QVERIFY(buf.tree().height() <= h);
}

void TestTextBuffer::bigPieces()
{
    // A 300 KB insert is cut into pieces of at most 64 KB, and an edit in the
    // middle of one keeps the limit.
    QRandomGenerator rng(5);
    QString big;
    while (big.size() < 300000)
        big += randomText(rng, 50);
    TextBuffer buf;
    buf.insert(0, big);
    QVERIFY(buf.tree().pieceCount() >= 5);
    QVERIFY2(buf.tree().validate().isEmpty(), qPrintable(buf.tree().validate()));
    QString model = big;
    for (int i = 0; i < 20; ++i) {
        const qsizetype p = qsizetype(rng.bounded(quint32(model.size() + 1)));
        const QString t = randomText(rng, 5);
        buf.insert(p, t);
        model.insert(widen(model, p, p).first, t);
    }
    const QString e = compareAll(buf.tree(), model, rng, true);
    QVERIFY2(e.isEmpty(), qPrintable(e));
}

void TestTextBuffer::typingMerges()
{
    // Typing at the end of the text, one character at a time, stays a handful
    // of pieces: each keystroke extends the last one.
    TextBuffer buf;
    QString model;
    for (int i = 0; i < 200000; ++i) {
        const QString t(QChar(u'a' + i % 26));
        buf.insert(buf.tree().length(), t);
        model += t;
    }
    QVERIFY2(buf.tree().pieceCount() <= 8, qPrintable(QString::number(buf.tree().pieceCount())));
    QVERIFY2(buf.tree().validate().isEmpty(), qPrintable(buf.tree().validate()));
    QVERIFY(buf.tree().text(0, buf.tree().length()) == model);
    // And in the middle.
    buf.insert(100, QStringLiteral("X"));
    buf.insert(101, QStringLiteral("Y"));
    buf.insert(102, QStringLiteral("Z"));
    model.insert(100, QStringLiteral("XYZ"));
    QVERIFY(buf.tree().text(0, buf.tree().length()) == model);
    QVERIFY2(buf.tree().pieceCount() <= 12, qPrintable(QString::number(buf.tree().pieceCount())));
}

void TestTextBuffer::surrogateEdits()
{
    TextBuffer buf;
    const QString smile = QString::fromUtf8("\xF0\x9F\x98\x80");
    buf.insert(0, QStringLiteral("a") + smile + QStringLiteral("b"));
    QCOMPARE(buf.tree().length(), qsizetype(4));
    QVERIFY(buf.tree().insideSurrogatePair(2));
    QVERIFY(!buf.tree().insideSurrogatePair(1));
    QVERIFY(!buf.tree().insideSurrogatePair(3));
    // An insert inside the pair goes before it.
    auto c = buf.insert(2, QStringLiteral("X"));
    QCOMPARE(c.position, qsizetype(1));
    QCOMPARE(buf.tree().text(0, buf.tree().length()), QStringLiteral("aX") + smile + QStringLiteral("b"));
    // A remove that starts or ends inside one takes the whole pair.
    c = buf.remove(3, 4); // the low half of the pair... widened to both
    QCOMPARE(c.position, qsizetype(2));
    QCOMPARE(c.removedLength, qsizetype(2));
    QCOMPARE(buf.tree().text(0, buf.tree().length()), QStringLiteral("aXb"));
    // Byte offsets of positions inside a pair give its first byte.
    buf.insert(0, smile);
    QCOMPARE(buf.tree().byteAtUtf16(1), qsizetype(0));
    QCOMPARE(buf.tree().byteAtUtf16(2), qsizetype(4));
    QCOMPARE(buf.tree().utf16AtByte(2), qsizetype(0));
    QCOMPARE(buf.tree().utf16AtByte(4), qsizetype(2));
    QCOMPARE(buf.tree().alignDown(1), qsizetype(0));
    QCOMPARE(buf.tree().alignUp(1), qsizetype(2));
    // A lone surrogate in an insert becomes U+FFFD, one unit.
    QString lone;
    lone += QChar(0xD800);
    buf.insert(buf.tree().length(), lone);
    QCOMPARE(buf.tree().text(buf.tree().length() - 1, buf.tree().length()), QString(QChar(0xFFFD)));
    QVERIFY(buf.tree().validate().isEmpty());
}

void TestTextBuffer::crlfAcrossEdits()
{
    TextBuffer buf;
    buf.insert(0, QStringLiteral("x\ry"));
    QCOMPARE(buf.tree().lineCount(), qsizetype(2)); // lone CR is a break
    buf.insert(2, QStringLiteral("\n")); // "x\r\ny": the CR and LF are in two pieces
    QCOMPARE(buf.tree().lineCount(), qsizetype(2));
    QCOMPARE(buf.tree().lineStart(1), qsizetype(3));
    QCOMPARE(buf.tree().lineAt(2), qsizetype(0)); // between CR and LF: still line 0
    QCOMPARE(buf.tree().lineAt(3), qsizetype(1));
    QVERIFY(buf.lineEnding() == LE::CRLF);
    // Cut the LF out again: the CR is a lone break once more.
    buf.remove(2, 3);
    QCOMPARE(buf.tree().lineCount(), qsizetype(2));
    QCOMPARE(buf.tree().lineStart(1), qsizetype(2));
    QVERIFY(buf.lineEnding() == LE::CR);
    // A CR at the very end: its line exists, and starts at the end.
    buf.remove(0, buf.tree().length());
    buf.insert(0, QStringLiteral("ab\r"));
    QCOMPARE(buf.tree().lineCount(), qsizetype(2));
    QCOMPARE(buf.tree().lineStart(1), qsizetype(3));
    QCOMPARE(buf.tree().lineAt(3), qsizetype(1));
    QCOMPARE(buf.tree().lineAt(2), qsizetype(0));
    // ... until an LF arrives.
    buf.insert(3, QStringLiteral("\n"));
    QCOMPARE(buf.tree().lineCount(), qsizetype(2));
    QCOMPARE(buf.tree().lineStart(1), qsizetype(4));
    QVERIFY(buf.tree().validate().isEmpty());
}

void TestTextBuffer::undoPieces()
{
    // What a Change returns is enough to undo it, with no copy of the text.
    TextBuffer buf;
    buf.insert(0, QStringLiteral("hello wide world\n"));
    const QString before = buf.tree().text(0, buf.tree().length());
    const auto c = buf.replace(6, 10, QStringLiteral("big"));
    QCOMPARE(buf.tree().text(0, buf.tree().length()), QStringLiteral("hello big world\n"));
    QCOMPARE(c.removedLength, qsizetype(4));
    QCOMPARE(c.insertedLength, qsizetype(3));
    buf.remove(c.position, c.position + c.insertedLength);
    buf.insertPieces(c.position, c.removed);
    QCOMPARE(buf.tree().text(0, buf.tree().length()), before);
    QVERIFY(buf.tree().validate().isEmpty());
}


void TestTextBuffer::insertPiecesContiguous()
{
    // Pieces that continue their neighbours in the same block merge back.
    TextBuffer b;
    b.insert(0, QStringLiteral("abcdef"));
    QCOMPARE(b.tree().pieceCount(), qsizetype(1));
    auto c = b.remove(2, 4);
    QCOMPARE(b.tree().pieceCount(), qsizetype(2));
    b.insertPieces(2, c.removed);
    QCOMPARE(b.tree().pieceCount(), qsizetype(1));
    QCOMPARE(b.tree().text(0, 6), QStringLiteral("abcdef"));
    QVERIFY2(b.tree().validate().isEmpty(), qPrintable(b.tree().validate()));
    c = b.remove(0, 2);
    b.insertPieces(0, c.removed);
    QCOMPARE(b.tree().pieceCount(), qsizetype(1));
    c = b.remove(4, 6);
    b.insertPieces(4, c.removed);
    QCOMPARE(b.tree().pieceCount(), qsizetype(1));
    // Many times, with a validate after each.
    QRandomGenerator rng(8);
    for (int i = 0; i < 300; ++i) {
        const qsizetype a = qsizetype(rng.bounded(6u));
        const qsizetype e = a + 1 + qsizetype(rng.bounded(quint32(6 - a)));
        c = b.remove(a, e);
        QVERIFY(c.changed());
        const auto back = b.insertPieces(a, c.removed);
        QCOMPARE(back.insertedLength, e - a);
        QVERIFY2(b.tree().validate().isEmpty(), qPrintable(b.tree().validate()));
        QCOMPARE(b.tree().text(0, 6), QStringLiteral("abcdef"));
        QCOMPARE(b.tree().pieceCount(), qsizetype(1));
    }
}

void TestTextBuffer::removeAcrossLevels()
{
    // 6000 one-byte pieces of one block: three levels. Every removal also merges
    // the contiguous pieces of the leaves it touches, so nodes drop below the
    // minimum and are folded into their neighbours; validate() after each step.
    QRandomGenerator rng(4242);
    static const char alpha[] = "ab \r\n";
    QByteArray raw;
    for (int i = 0; i < 6000; ++i)
        raw.append(alpha[rng.bounded(5u)]);
    TextTree t = treeOfBytes(raw);
    QString model = QString::fromLatin1(raw);
    QVERIFY2(t.height() >= 3, qPrintable(QString::number(t.height())));
    QVERIFY2(t.validate().isEmpty(), qPrintable(t.validate()));
    for (int step = 0; step < 900 && !model.isEmpty(); ++step) {
        const qsizetype a = qsizetype(rng.bounded(quint32(model.size())));
        const quint32 most = quint32(std::min<qsizetype>(model.size() - a, step % 10 == 0 ? 800 : 40));
        const qsizetype len = 1 + qsizetype(rng.bounded(most));
        const QString gone = model.mid(a, len);
        std::vector<Piece> removed;
        t = t.withRemoved(a, a + len, &removed);
        model.remove(a, len);
        QVERIFY2(t.validate().isEmpty(), qPrintable(QStringLiteral("step %1: %2").arg(step).arg(t.validate())));
        if (step % 5 == 0 && !removed.empty()) {
            t = t.withInserted(a, removed);
            model.insert(a, gone);
            QVERIFY2(t.validate().isEmpty(), qPrintable(QStringLiteral("step %1 (put back): %2").arg(step).arg(t.validate())));
        }
        if (step % 25 == 0) {
            const QString e = compareAll(t, model, rng, false);
            QVERIFY2(e.isEmpty(), qPrintable(QStringLiteral("step %1: %2").arg(step).arg(e)));
        }
    }
    QString e = compareAll(t, model, rng, true);
    QVERIFY2(e.isEmpty(), qPrintable(e));
    // Everything out, down to nothing.
    t = t.withRemoved(0, t.length(), nullptr);
    QVERIFY(t.isEmpty());
}

void TestTextBuffer::lineSeamsManyPieces()
{
    // One piece for every byte, so a CR can end one leaf and its LF start the
    // next (groups of 50 for 200 pieces). Then a lone CR at the same seams.
    QRandomGenerator rng(6);
    for (int variant = 0; variant < 3; ++variant) {
        QByteArray raw;
        for (int i = 0; i < 200; ++i)
            raw.append(rng.bounded(2u) ? 'a' : 'b');
        for (int seam : {49, 99, 149}) {
            raw[seam] = '\r';
            raw[seam + 1] = variant == 0 ? '\n' : variant == 1 ? 'q' : '\r';
        }
        raw[24] = '\r';
        raw[25] = 'x';
        const TextTree t = treeOfBytes(raw);
        QVERIFY(t.height() >= 2);
        const QString s = QString::fromLatin1(raw);
        const QString e = compareAll(t, s, rng, true);
        QVERIFY2(e.isEmpty(), qPrintable(QStringLiteral("variant %1: %2").arg(variant).arg(e)));
    }
    // Dense and random over three levels.
    QByteArray raw;
    static const char alpha[] = "a\r\n\r\n";
    for (int i = 0; i < 5000; ++i)
        raw.append(alpha[rng.bounded(5u)]);
    const TextTree t = treeOfBytes(raw);
    QVERIFY(t.height() >= 3);
    const QString e = compareAll(t, QString::fromLatin1(raw), rng, true);
    QVERIFY2(e.isEmpty(), qPrintable(e));
}

void TestTextBuffer::loneSurrogateInInsert()
{
    const QString smile = QString::fromUtf8("\xF0\x9F\x98\x80");
    const QString fffd(QChar(0xFFFD));
    QString s = QStringLiteral("ab");
    s += QChar(0xD800);
    s += QStringLiteral("cd");
    s += QChar(0xDC00);
    s += smile;
    s += QChar(0xD83D); // a high half at the very end
    TextBuffer b;
    b.insert(0, QStringLiteral("xy"));
    const auto c = b.insert(1, s);
    const QString want = QStringLiteral("x") + QStringLiteral("ab") + fffd + QStringLiteral("cd") + fffd + smile + fffd + QStringLiteral("y");
    QCOMPARE(b.tree().text(0, b.tree().length()), want);
    QCOMPARE(c.insertedLength, s.size());
    QVERIFY(b.tree().validate().isEmpty());
    QVERIFY(!b.tree().utf8(0, b.tree().byteLength()).contains('?'));
    // Replace and setText take the same road.
    b.replace(0, 1, QString(QChar(0xDE00)));
    QCOMPARE(b.tree().text(0, 1), fffd);
    b.setText(s);
    QCOMPARE(b.tree().text(0, b.tree().length()), QStringLiteral("ab") + fffd + QStringLiteral("cd") + fffd + smile + fffd);
}

// ---- Loading ----

static QByteArray mixedSample()
{
    return QByteArray("h\xC3\xA9llo\r\n\xE4\xB8\xAD\xE6\x96\x87\xF0\x9F\x98\x80\nx\rend");
}

void TestTextBuffer::loadChunkBoundaries()
{
    const QByteArray data = mixedSample();
    const QString want = makeString(data);
    for (int size = 1; size <= 9; ++size) {
        TextBuffer b;
        b.beginLoad();
        QVERIFY(b.loading());
        for (qsizetype i = 0; i < data.size(); i += size)
            b.appendData(data.mid(i, size));
        QVERIFY(b.endLoad());
        QVERIFY(!b.loading());
        QVERIFY2(!b.hadInvalidText(), qPrintable(QString::number(size)));
        QVERIFY2(b.tree().text(0, b.tree().length()) == want, qPrintable(QString::number(size)));
        QRandomGenerator rng(size);
        const QString e = compareAll(b.tree(), want, rng, true);
        QVERIFY2(e.isEmpty(), qPrintable(QStringLiteral("chunk size %1: %2").arg(size).arg(e)));
        QCOMPARE(b.tree().lineCount(), qsizetype(4));
        QVERIFY(b.lineEnding() == LE::Mixed);
    }
    // The raw pointer form, and a zero-length chunk in the middle.
    TextBuffer b;
    b.beginLoad();
    b.appendData(data.constData(), 7);
    b.appendData(QByteArray());
    b.appendData(data.constData() + 7, data.size() - 7);
    b.endLoad();
    QVERIFY(b.tree().text(0, b.tree().length()) == want);
}

void TestTextBuffer::loadCrlfBoundary()
{
    // The CR ends one chunk and the LF starts the next.
    TextBuffer b;
    b.beginLoad();
    b.appendData(QByteArray("a\r"));
    b.appendData(QByteArray("\nb\r"));
    b.appendData(QByteArray("\rc\r"));
    b.appendData(QByteArray("d"));
    QVERIFY(b.endLoad());
    const QString want = QStringLiteral("a\r\nb\r\rc\rd");
    QVERIFY(b.tree().text(0, b.tree().length()) == want);
    QCOMPARE(b.tree().lineCount(), qsizetype(5));
    QCOMPARE(b.tree().lineStart(1), qsizetype(3));
    QCOMPARE(b.tree().lineStart(2), qsizetype(5));
    QCOMPARE(b.tree().lineStart(3), qsizetype(6));
    QCOMPARE(b.tree().lineStart(4), qsizetype(8));
    QCOMPARE(b.tree().lineAt(1), qsizetype(0));
    QCOMPARE(b.tree().lineAt(2), qsizetype(0)); // between CR and LF
    QCOMPARE(b.tree().lineAt(3), qsizetype(1));
    // Small chunks are gathered into one piece; the seams are tested on purpose
    // in lineSeamsManyPieces().
    QCOMPARE(b.tree().pieceCount(), qsizetype(1));
    QRandomGenerator rng(3);
    QVERIFY2(compareAll(b.tree(), want, rng, true).isEmpty(), "crlf boundary");
    // CR at the very end of the load.
    b.beginLoad();
    b.appendData(QByteArray("x\r"));
    b.endLoad();
    QCOMPARE(b.tree().lineCount(), qsizetype(2));
    QCOMPARE(b.tree().lineStart(1), qsizetype(2));
}

void TestTextBuffer::loadInvalid_data()
{
    QTest::addColumn<QByteArray>("input");
    QTest::addColumn<QString>("expected");
    const QString fffd(QChar(0xFFFD));
    QTest::newRow("stray byte") << QByteArray("ab\xFF"
                                              "z")
                                << QStringLiteral("ab") + fffd + QStringLiteral("z");
    QTest::newRow("cut lead at end") << QByteArray("a\xC3") << QStringLiteral("a") + fffd;
    QTest::newRow("cut 3-byte at end") << QByteArray("a\xE2\x82") << QStringLiteral("a") + fffd;
    QTest::newRow("cut 3-byte before ascii") << QByteArray("\xE2\x82"
                                                           "A")
                                             << fffd + QStringLiteral("A");
    QTest::newRow("overlong") << QByteArray("\xC0\x80") << fffd + fffd;
    QTest::newRow("surrogate encoding") << QByteArray("\xED\xA0\x80") << fffd + fffd + fffd;
    QTest::newRow("beyond U+10FFFF") << QByteArray("\xF4\x90\x80\x80") << fffd + fffd + fffd + fffd;
    QTest::newRow("cut 4-byte at end") << QByteArray("\xF0\x9F\x98") << fffd;
    QTest::newRow("lone continuation") << QByteArray("\x80"
                                                     "x")
                                       << fffd + QStringLiteral("x");
    QTest::newRow("valid then invalid") << QByteArray("\xF0\x9F\x98\x80\xFF\xC3\xA9") << QString::fromUtf8("\xF0\x9F\x98\x80") + fffd + QStringLiteral("\xE9");
    QTest::newRow("long run") << (QByteArray(40000, 'a') + QByteArray("\xFF") + QByteArray(40000, 'b'))
                              << (QString(40000, u'a') + fffd + QString(40000, u'b'));
}

void TestTextBuffer::loadInvalid()
{
    QFETCH(QByteArray, input);
    QFETCH(QString, expected);
    for (int size : {0, 1, 2, 3, 4, 5, 17, 33000}) {
        TextBuffer b;
        b.beginLoad();
        if (size == 0) {
            b.appendData(input);
        } else {
            for (qsizetype i = 0; i < input.size(); i += size)
                b.appendData(input.mid(i, size));
        }
        QVERIFY(b.endLoad());
        QVERIFY2(b.hadInvalidText(), qPrintable(QString::number(size)));
        const QString got = b.tree().text(0, b.tree().length());
        QVERIFY2(got == expected, qPrintable(QStringLiteral("chunk size %1").arg(size)));
        QVERIFY(b.tree().validate().isEmpty());
        QCOMPARE(b.tree().byteLength(), qsizetype(expected.toUtf8().size()));
    }
}

void TestTextBuffer::loadEmpty()
{
    TextBuffer b;
    b.beginLoad();
    QVERIFY(b.loading());
    QCOMPARE(b.loadProgress(), 0.0);
    QVERIFY(b.endLoad());
    QVERIFY(!b.loading());
    QCOMPARE(b.loadProgress(), 1.0);
    QCOMPARE(b.tree().length(), qsizetype(0));
    QCOMPARE(b.tree().lineCount(), qsizetype(1));
    QCOMPARE(b.tree().chunkCount(), qsizetype(0));
    QVERIFY(!b.hadInvalidText());
    QVERIFY(!b.loadFailed());
    QVERIFY(b.tree().validate().isEmpty());
    // Empty chunks only.
    b.beginLoad();
    b.appendData(QByteArray());
    b.appendData(nullptr, 0);
    QVERIFY(b.endLoad());
    QCOMPARE(b.tree().length(), qsizetype(0));
    // endLoad with no load running is harmless.
    QVERIFY(b.endLoad());
    // setText.
    b.setText(QString());
    QVERIFY(b.tree().isEmpty());
    b.setText(QStringLiteral("a\nb"));
    QCOMPARE(b.tree().lineCount(), qsizetype(2));
}

void TestTextBuffer::loadOneMegabyte()
{
    // About 1 MB of generated lines, with multibyte characters, cut into chunks
    // that fall inside characters and inside CRLF, counted on worker threads.
    QByteArray data;
    QList<qsizetype> newlines;
    QRandomGenerator rng(99);
    int line = 0;
    while (data.size() < 1000000) {
        data += "line " + QByteArray::number(line++) + " \xC3\xA9\xE4\xB8\xAD\xF0\x9F\x98\x80 text ";
        data += QByteArray(int(rng.bounded(60u)), 'x');
        data += (line % 3 == 0) ? "\r\n" : "\n";
        newlines.append(data.size() - 1);
    }
    for (qsizetype chunk : {qsizetype(100000), qsizetype(65536), qsizetype(33333), qsizetype(4097)}) {
        TextBuffer b;
        std::atomic<int> notified{0};
        b.setLoadNotify([&notified] { ++notified; });
        b.beginLoad();
        for (qsizetype i = 0; i < data.size(); i += chunk)
            b.appendData(data.mid(i, chunk));
        // Small chunks are all checked on this thread, so nothing is left to
        // wait for; with workers the answer is whatever the state says.
        const bool finished = b.endLoad(false);
        QCOMPARE(finished, !b.loading());
        if (chunk < 32768)
            QVERIFY(finished);
        // Poll to the end; the text only grows meanwhile.
        qsizetype last = 0;
        QElapsedTimer timer;
        timer.start();
        while (!b.pollLoad()) {
            QVERIFY(b.tree().byteLength() >= last);
            last = b.tree().byteLength();
            QVERIFY2(timer.elapsed() < 60000, "load did not finish");
            QThread::msleep(2);
        }
        QVERIFY(!b.hadInvalidText());
        QVERIFY(!b.loadFailed());
        QCOMPARE(b.loadProgress(), 1.0);
        const TextTree &t = b.tree();
        QVERIFY2(t.validate().isEmpty(), qPrintable(t.validate()));
        QCOMPARE(t.byteLength(), data.size());
        QVERIFY(t.utf8(0, t.byteLength()) == data);
        QCOMPARE(t.lineCount(), qsizetype(newlines.size() + 1));
        QVERIFY(t.pieceCount() >= data.size() / MaxPiece);
        for (int i = 0; i < 300; ++i) {
            const qsizetype k = qsizetype(rng.bounded(quint32(newlines.size())));
            QCOMPARE(t.lineStartByte(k + 1), newlines[k] + 1);
            QCOMPARE(t.lineAtByte(newlines[k]), k); // the LF is inside line k
            QCOMPARE(t.lineAtByte(newlines[k] + 1), k + 1);
            const qsizetype off = newlines[k] + 1;
            QCOMPARE(t.utf16AtByte(off), QString::fromUtf8(data.constData(), off).size());
            QCOMPARE(t.lineStart(k + 1), QString::fromUtf8(data.constData(), off).size());
        }
        QVERIFY(t.text(0, t.length()) == QString::fromUtf8(data));
        if (chunk >= 32768)
            QVERIFY2(notified.load() >= 1, "no notification from the workers");
        QVERIFY(b.lineEnding() == LE::Mixed);
    }
    // The same with one invalid byte near the end: a worker copies its chunk.
    QByteArray bad = data;
    bad[bad.lastIndexOf("text ") + 2] = char(0xFF); // an ASCII byte
    TextBuffer b;
    b.beginLoad();
    for (qsizetype i = 0; i < bad.size(); i += 70001)
        b.appendData(bad.mid(i, 70001));
    QVERIFY(b.endLoad());
    QVERIFY(b.hadInvalidText());
    QCOMPARE(b.tree().byteLength(), bad.size() + 2);
    QVERIFY(b.tree().validate().isEmpty());
}

void TestTextBuffer::loadEditsRefused()
{
    TextBuffer b;
    b.insert(0, QStringLiteral("abc"));
    b.beginLoad();
    QVERIFY(b.tree().isEmpty()); // the old text is gone from the buffer
    QVERIFY(!b.insert(0, QStringLiteral("x")).ok);
    QVERIFY(!b.remove(0, 1).ok);
    QVERIFY(!b.replace(0, 0, QStringLiteral("y")).ok);
    QVERIFY(!b.convertLineEndings(LE::LF).ok);
    b.appendData(QByteArray("123"));
    QVERIFY(b.endLoad());
    QVERIFY(b.insert(0, QStringLiteral("x")).ok);
    QCOMPARE(b.tree().text(0, b.tree().length()), QStringLiteral("x123"));
}

void TestTextBuffer::loadRestart()
{
    // A new load drops the unfinished one, and a snapshot keeps its version.
    TextBuffer b;
    b.beginLoad();
    b.appendData(QByteArray(200000, 'a'));
    b.appendData(QByteArray("tail"));
    const TelamonTextSnapshot before = b.snapshot();
    b.beginLoad();
    b.appendData(QByteArray("new"));
    QVERIFY(b.endLoad());
    QCOMPARE(b.tree().text(0, b.tree().length()), QStringLiteral("new"));
    QVERIFY(before.length() <= 200004);
    QVERIFY(before.revision() < b.revision());
    QVERIFY(b.tree().validate().isEmpty());
}

void TestTextBuffer::loadWorkerBoundaries()
{
    // Ranges of worker size: a 4-byte character and a CRLF cut by the chunk
    // boundary, and the same cut by the 1 MB range boundary inside one chunk.
    const QByteArray smile("\xF0\x9F\x98\x80");
    for (int split = 1; split <= 3; ++split) {
        TextBuffer b;
        b.beginLoad();
        b.appendData(QByteArray(40000, 'a') + smile.left(split));
        b.appendData(smile.mid(split) + QByteArray(40000, 'b'));
        QVERIFY(b.endLoad());
        QVERIFY(!b.hadInvalidText());
        const QString want = QString(40000, u'a') + QString::fromUtf8(smile) + QString(40000, u'b');
        QVERIFY2(b.tree().text(0, b.tree().length()) == want, qPrintable(QString::number(split)));
        QVERIFY(b.tree().validate().isEmpty());
    }
    {
        TextBuffer b;
        b.beginLoad();
        b.appendData(QByteArray(40000, 'a') + "\r");
        b.appendData("\n" + QByteArray(40000, 'b'));
        QVERIFY(b.endLoad());
        QCOMPARE(b.tree().lineCount(), qsizetype(2));
        QCOMPARE(b.tree().lineStart(1), qsizetype(40002));
        QCOMPARE(b.tree().lineAt(40001), qsizetype(0));
        QVERIFY(b.lineEnding() == LE::CRLF);
    }
    const qsizetype range = 1024 * 1024;
    {   // The cut falls between CR and LF.
        const QByteArray data = QByteArray(range - 1, 'a') + "\r\n" + QByteArray(100000, 'b');
        TextBuffer b;
        b.beginLoad();
        b.appendData(data);
        QVERIFY(b.endLoad());
        QCOMPARE(b.tree().lineCount(), qsizetype(2));
        QCOMPARE(b.tree().lineStart(1), range + 1);
        QVERIFY(b.tree().utf8(0, b.tree().byteLength()) == data);
        QVERIFY(b.tree().validate().isEmpty());
    }
    {   // The cut falls inside a 4-byte character.
        QByteArray data("x");
        for (int i = 0; i < 800000; ++i)
            data += smile;
        TextBuffer b;
        b.beginLoad();
        b.appendData(data);
        QVERIFY(b.endLoad());
        QVERIFY(!b.hadInvalidText());
        QCOMPARE(b.tree().length(), qsizetype(1 + 2 * 800000));
        QVERIFY(b.tree().utf8(0, b.tree().byteLength()) == data);
        QVERIFY(b.tree().validate().isEmpty());
    }
    {   // The cut falls inside a run of stray continuation bytes.
        const QByteArray data = QByteArray(range - 6, 'a') + QByteArray(10, '\x80') + QByteArray(5000, 'b');
        TextBuffer b;
        b.beginLoad();
        b.appendData(data);
        QVERIFY(b.endLoad());
        QVERIFY(b.hadInvalidText());
        const QString want = QString(range - 6, u'a') + QString(10, QChar(0xFFFD)) + QString(5000, u'b');
        QVERIFY(b.tree().text(0, b.tree().length()) == want);
        QVERIFY(b.tree().validate().isEmpty());
    }
    {   // Mostly valid text with a few bad bytes: the long runs stay whole pieces.
        QByteArray data = QByteArray(300000, 'a');
        data[100000] = char(0xFF);
        data[200000] = char(0xC3);
        TextBuffer b;
        b.beginLoad();
        b.appendData(data);
        QVERIFY(b.endLoad());
        QVERIFY(b.hadInvalidText());
        QCOMPARE(b.tree().length(), qsizetype(300000));
        QVERIFY(b.tree().pieceCount() <= 12);
        QCOMPARE(b.tree().text(100000, 100001), QString(QChar(0xFFFD)));
        QCOMPARE(b.tree().text(200000, 200001), QString(QChar(0xFFFD)));
        QVERIFY(b.tree().validate().isEmpty());
    }
}

void TestTextBuffer::destroyWithTasks()
{
    // The buffer goes away with tasks outstanding: no callback runs afterwards.
    std::atomic<int> calls{0};
    std::atomic<bool> gone{false};
    std::atomic<int> late{0};
    g_delayMs = 20;
    {
        TextBuffer b;
        b.setLoadNotify([&] {
            ++calls;
            if (gone.load())
                ++late;
        });
        b.beginLoad();
        for (int i = 0; i < 12; ++i)
            b.appendData(QByteArray(100000, char('b' + i)));
    }
    gone = true;
    QThread::msleep(600); // the tasks finish (and are dropped) meanwhile
    QCOMPARE(late.load(), 0);
}

void TestTextBuffer::beginLoadWhileWorkersRun()
{
    // A new load while workers of the old one are busy: the old ones notify
    // nobody and add nothing.
    g_gateClosed = true;
    std::atomic<int> notified{0};
    TextBuffer b;
    b.setLoadNotify([&] { ++notified; });
    b.beginLoad();
    for (int i = 0; i < 3; ++i)
        b.appendData(QByteArray(100000, 'A'));
    b.beginLoad();
    g_gateClosed = false;
    b.appendData(QByteArray(100000, 'B'));
    b.appendData(QByteArray(100000, 'C'));
    QVERIFY(b.endLoad());
    QVERIFY(waitUntil([&] { return notified.load() >= 2; }));
    QThread::msleep(300);
    QCOMPARE(notified.load(), 2);
    QVERIFY(b.tree().utf8(0, b.tree().byteLength()) == QByteArray(100000, 'B') + QByteArray(100000, 'C'));
    QVERIFY(b.tree().validate().isEmpty());
}

void TestTextBuffer::cancelledTasksSilent()
{
    g_gateClosed = true;
    std::atomic<int> notified{0};
    TextBuffer b;
    b.cancelLoad(); // no load: nothing happens
    b.setLoadNotify([&] { ++notified; });
    b.beginLoad();
    for (int i = 0; i < 3; ++i)
        b.appendData(QByteArray(100000, 'A'));
    b.appendData(QByteArray("small"));
    b.cancelLoad();
    QVERIFY(!b.loading());
    QVERIFY(!b.loadFailed());
    QVERIFY(b.tree().isEmpty());
    QVERIFY(b.pollLoad());
    g_gateClosed = false;
    QThread::msleep(300);
    QCOMPARE(notified.load(), 0);
    QVERIFY(b.tree().isEmpty());
    // The buffer is usable again.
    b.setText(QStringLiteral("after"));
    QCOMPARE(b.tree().text(0, b.tree().length()), QStringLiteral("after"));
}

void TestTextBuffer::loadFailure()
{
    // The worker of the middle chunk fails: the text is the chunk before it,
    // whole, and nothing after the hole.
    g_throwOn = 'F';
    TextBuffer b;
    b.beginLoad();
    b.appendData(QByteArray(100000, 'a'));
    b.appendData(QByteArray(100000, 'F'));
    b.appendData(QByteArray(100000, 'c'));
    QVERIFY(b.endLoad());
    QVERIFY(!b.loading());
    QVERIFY(b.loadFailed());
    QVERIFY(b.tree().utf8(0, b.tree().byteLength()) == QByteArray(100000, 'a'));
    QVERIFY2(b.tree().validate().isEmpty(), qPrintable(b.tree().validate()));
    b.appendData(QByteArray("late")); // ignored: no load is running
    QCOMPARE(b.tree().byteLength(), qsizetype(100000));
    // The failure is for this load only.
    b.beginLoad();
    QVERIFY(!b.loadFailed());
    b.appendData(QByteArray("ok"));
    QVERIFY(b.endLoad());
    QVERIFY(!b.loadFailed());
    QCOMPARE(b.tree().text(0, b.tree().length()), QStringLiteral("ok"));
    // A failure seen by pollLoad() without endLoad(wait): later chunks are not
    // appended even if the caller keeps feeding the load.
    TextBuffer c;
    c.beginLoad();
    c.appendData(QByteArray(100000, 'F'));
    c.appendData(QByteArray(100000, 'c'));
    QVERIFY(waitUntil([&] { return c.pollLoad() || c.loadFailed(); }));
    c.appendData(QByteArray(100000, 'd'));
    QVERIFY(c.endLoad());
    QVERIFY(c.loadFailed());
    QVERIFY(c.tree().isEmpty());
}

void TestTextBuffer::abortLoad()
{
    TextBuffer b;
    b.abortLoad(true); // no load: nothing happens
    QVERIFY(!b.loadFailed());
    // Small data only: it is all kept.
    b.beginLoad();
    b.appendData(QByteArray("abc"));
    b.abortLoad(false);
    QVERIFY(!b.loading());
    QVERIFY(!b.loadFailed());
    QCOMPARE(b.tree().text(0, b.tree().length()), QStringLiteral("abc"));
    // The first range is in, the second is stuck, the third is done: the text
    // is the first only.
    g_gateClosed = true;
    b.beginLoad();
    b.appendData(QByteArray(100000, 'c'));
    QVERIFY(waitUntil([&] {
        b.pollLoad();
        return b.tree().byteLength() == 100000;
    }));
    b.appendData(QByteArray(100000, 'A'));
    b.appendData(QByteArray(100000, 'd'));
    b.appendData(QByteArray("tail"));
    QThread::msleep(100);
    b.abortLoad(true);
    QVERIFY(!b.loading());
    QVERIFY(b.loadFailed());
    QVERIFY(b.pollLoad());
    QVERIFY(b.tree().utf8(0, b.tree().byteLength()) == QByteArray(100000, 'c'));
    QVERIFY(b.tree().validate().isEmpty());
    QVERIFY(b.insert(0, QStringLiteral("x")).ok); // editing is allowed again
    g_gateClosed = false;
}

void TestTextBuffer::outOfOrderFinish()
{
    // The second chunk is done while the first is still being checked: nothing
    // is taken until the first is in, and then the order is the input's.
    g_gateClosed = true;
    std::atomic<int> notified{0};
    TextBuffer b;
    b.setLoadNotify([&] { ++notified; });
    b.beginLoad();
    b.appendData(QByteArray(100000, 'A'));
    b.appendData(QByteArray(100000, 'B'));
    QVERIFY(waitUntil([&] { return notified.load() >= 1; }));
    QVERIFY(!b.pollLoad());
    QCOMPARE(b.tree().byteLength(), qsizetype(0));
    g_gateClosed = false;
    QVERIFY(b.endLoad());
    QVERIFY(b.tree().utf8(0, b.tree().byteLength()) == QByteArray(100000, 'A') + QByteArray(100000, 'B'));
    QVERIFY(b.tree().validate().isEmpty());
}

void TestTextBuffer::notifyPerRange()
{
    // One call for every finished range, and none from appendData itself.
    std::atomic<int> n{0};
    TextBuffer b;
    b.setLoadNotify([&] { ++n; });
    b.beginLoad();
    for (int i = 0; i < 50; ++i)
        b.appendData(QByteArray(1000, 's'));
    b.appendData(QByteArray(10, 't'));
    QCOMPARE(n.load(), 0); // small chunks are checked inline
    QVERIFY(b.endLoad());
    QThread::msleep(50);
    QCOMPARE(n.load(), 0);
    QCOMPARE(b.tree().byteLength(), qsizetype(50010));

    b.beginLoad();
    b.appendData(QByteArray(100000, 'a'));
    QVERIFY(b.endLoad());
    QVERIFY(waitUntil([&] { return n.load() >= 1; }));
    QThread::msleep(100);
    QCOMPARE(n.load(), 1);

    b.beginLoad();
    b.appendData(QByteArray(3 * 1024 * 1024 - 10, 'a')); // three ranges
    QVERIFY(b.endLoad());
    QVERIFY(waitUntil([&] { return n.load() >= 4; }));
    QThread::msleep(100);
    QCOMPARE(n.load(), 4);
    QCOMPARE(b.tree().byteLength(), qsizetype(3 * 1024 * 1024 - 10));
}

// ---- Line endings ----

void TestTextBuffer::lineEndingDetection()
{
    struct Row {
        const char *text;
        LE kind;
    };
    const Row rows[] = {
        {"", LE::LF},
        {"no break", LE::LF},
        {"a\nb", LE::LF},
        {"a\r\nb\r\n", LE::CRLF},
        {"a\rb\r", LE::CR},
        {"a\nb\r\n", LE::Mixed},
        {"a\r\nb\rc\nd", LE::Mixed},
        {"a\r\rb", LE::CR},
        {"\r\n\r\n\r\n", LE::CRLF},
        {"a\n\rb", LE::Mixed}, // LF then CR: two breaks of two kinds
    };
    for (const Row &r : rows) {
        TextBuffer b;
        b.setText(QString::fromLatin1(r.text));
        QVERIFY2(b.lineEnding() == r.kind, r.text);
    }
    // CRLF made of two edits.
    TextBuffer b;
    b.insert(0, QStringLiteral("a\r"));
    QVERIFY(b.lineEnding() == LE::CR);
    b.insert(2, QStringLiteral("\nb"));
    QVERIFY(b.lineEnding() == LE::CRLF);
    QCOMPARE(b.tree().lineBreaks().crlf, qsizetype(1));
    // Dominant: the most common kind, LF on a tie.
    b.setText(QStringLiteral("a\r\nb\r\nc\nd"));
    QVERIFY(b.dominantLineEnding() == LE::CRLF);
    b.setText(QStringLiteral("a\r\nb\nc"));
    QVERIFY(b.dominantLineEnding() == LE::LF);
    b.setText(QStringLiteral("a\rb\rc\n"));
    QVERIFY(b.dominantLineEnding() == LE::CR);
    b.setText(QString());
    QVERIFY(b.dominantLineEnding() == LE::LF);
}

static QString convertModel(QString s, LE kind)
{
    s.replace(QStringLiteral("\r\n"), QStringLiteral("\n"));
    s.replace(u'\r', u'\n');
    if (kind == LE::CRLF)
        s.replace(u'\n', QStringLiteral("\r\n"));
    else if (kind == LE::CR)
        s.replace(u'\n', u'\r');
    return s;
}

void TestTextBuffer::lineEndingConversion()
{
    const QString mixed = QStringLiteral("a\r\nb\rc\nd\r\r\n\ne\r");
    for (LE kind : {LE::LF, LE::CRLF, LE::CR}) {
        TextBuffer b;
        b.setText(mixed);
        const qsizetype lines = b.tree().lineCount();
        const quint64 rev = b.revision();
        const auto c = b.convertLineEndings(kind);
        QVERIFY(c.ok && c.changed());
        QVERIFY(b.revision() > rev);
        const QString want = convertModel(mixed, kind);
        QCOMPARE(b.tree().text(0, b.tree().length()), want);
        QCOMPARE(b.tree().lineCount(), lines);
        QVERIFY(b.lineEnding() == kind);
        QVERIFY(b.tree().validate().isEmpty());
        QCOMPARE(c.removedLength, qsizetype(mixed.size()));
        QCOMPARE(c.insertedLength, qsizetype(want.size()));
        // One undo: the pieces of the old text go back.
        b.remove(c.position, c.position + c.insertedLength);
        QVERIFY(b.tree().isEmpty());
        b.insertPieces(0, c.removed);
        QCOMPARE(b.tree().text(0, b.tree().length()), mixed);
        // Converting again to the same kind does nothing.
        b.convertLineEndings(kind);
        const quint64 rev2 = b.revision();
        const auto again = b.convertLineEndings(kind);
        QVERIFY(again.ok && !again.changed());
        QCOMPARE(b.revision(), rev2);
    }
    TextBuffer b;
    b.setText(mixed);
    QVERIFY(!b.convertLineEndings(LE::Mixed).ok);
    QCOMPARE(b.tree().text(0, b.tree().length()), mixed);
    // No breaks: nothing to do. Empty: nothing to do.
    b.setText(QStringLiteral("none"));
    QVERIFY(!b.convertLineEndings(LE::CRLF).changed());
    b.setText(QString());
    QVERIFY(b.convertLineEndings(LE::CRLF).ok);
    // A CR and its LF in two pieces become one break.
    TextBuffer c;
    c.insert(0, QStringLiteral("x\r"));
    c.insert(0, QStringLiteral("QQ")); // so that the next piece does not continue the first
    c.remove(0, 2);
    c.insert(2, QStringLiteral("\ny"));
    QCOMPARE(c.tree().pieceCount(), qsizetype(2));
    c.convertLineEndings(LE::LF);
    QCOMPARE(c.tree().text(0, c.tree().length()), QStringLiteral("x\ny"));
    c.convertLineEndings(LE::CR);
    QCOMPARE(c.tree().text(0, c.tree().length()), QStringLiteral("x\ry"));
}

void TestTextBuffer::convertFlushBetweenCrLf()
{
    // The output is flushed into a new piece near the 64 KB limit; with the CR
    // last in one piece and the LF it swallowed next, the text must still be
    // right for every offset around the limit.
    for (qsizetype pad = MaxPiece - 20; pad <= MaxPiece - 2; ++pad) {
        const QString text = QString(pad, u'a') + QStringLiteral("\r\nb\nc\r\nd");
        for (LE kind : {LE::LF, LE::CRLF, LE::CR}) {
            TextBuffer b;
            b.setText(text);
            const auto c = b.convertLineEndings(kind);
            QVERIFY(c.ok);
            const QString want = convertModel(text, kind);
            QVERIFY2(b.tree().text(0, b.tree().length()) == want, qPrintable(QStringLiteral("pad %1 kind %2").arg(pad).arg(int(kind))));
            QVERIFY2(b.tree().validate().isEmpty(), qPrintable(b.tree().validate()));
            QCOMPARE(b.tree().lineCount(), qsizetype(4));
            QVERIFY(b.lineEnding() == kind);
        }
    }
}

void TestTextBuffer::dominantTies()
{
    struct Row {
        const char *text;
        LE kind;
    };
    const Row rows[] = {
        {"a\nb\r\nc", LE::LF},        // LF = CRLF
        {"a\nb\rc", LE::LF},           // LF = CR
        {"a\r\nb\rc", LE::CRLF},      // CRLF = CR, both above LF
        {"a\r\nb\rc\nd", LE::LF},     // all three equal
        {"a\r\nb\r\nc\rd\ne", LE::CRLF},
        {"a\rb\rc\r\nd\ne", LE::CR},
        {"a\r\nb\nc\nd\r", LE::LF}, // LF leads
        {"plain", LE::LF},
    };
    for (const Row &r : rows) {
        TextBuffer b;
        b.setText(QString::fromLatin1(r.text));
        QVERIFY2(b.dominantLineEnding() == r.kind, r.text);
    }
}

void TestTextBuffer::lineEndingBig()
{
    // All-CRLF text over several pieces, to LF and back: the piece limit holds,
    // and no CRLF is split across a piece in a way that changes the count.
    QString s;
    for (int i = 0; i < 40000; ++i)
        s += QStringLiteral("line \xE9中 %1\r\n").arg(i);
    TextBuffer b;
    b.setText(s);
    QVERIFY(b.lineEnding() == LE::CRLF);
    QCOMPARE(b.tree().lineCount(), qsizetype(40001));
    b.convertLineEndings(LE::LF);
    QVERIFY(b.lineEnding() == LE::LF);
    QVERIFY2(b.tree().validate().isEmpty(), qPrintable(b.tree().validate()));
    QCOMPARE(b.tree().lineCount(), qsizetype(40001));
    QVERIFY(b.tree().text(0, b.tree().length()) == convertModel(s, LE::LF));
    b.convertLineEndings(LE::CR);
    QVERIFY(b.tree().text(0, b.tree().length()) == convertModel(s, LE::CR));
    b.convertLineEndings(LE::CRLF);
    QVERIFY(b.tree().text(0, b.tree().length()) == s);
    QVERIFY2(b.tree().validate().isEmpty(), qPrintable(b.tree().validate()));
}

// ---- Snapshots ----

void TestTextBuffer::snapshotIsFrozen()
{
    TelamonTextSnapshot snap;
    TelamonTextSnapshot snap2;
    QString first;
    quint64 rev1 = 0;
    {
        TextBuffer b;
        b.insert(0, QStringLiteral("one\ntwo\nthree"));
        snap = b.snapshot();
        first = b.tree().text(0, b.tree().length());
        rev1 = b.revision();
        QCOMPARE(snap.revision(), rev1);
        // Edits of every kind, a load, a conversion.
        b.insert(3, QStringLiteral(" and a half"));
        b.remove(0, 2);
        b.convertLineEndings(LE::CRLF);
        snap2 = b.snapshot();
        b.insert(0, QString(100000, u'z'));
        QVERIFY(snap.revision() == rev1);
        QVERIFY(snap2.revision() > rev1);
        QVERIFY(b.revision() > snap2.revision());
        QCOMPARE(snap.text(), first);
        QVERIFY(!snap.isSameVersion(snap2));
        QVERIFY(snap == snap);
        b.beginLoad();
        b.appendData(QByteArray("gone"));
        b.endLoad();
        QCOMPARE(snap.text(), first);
        QCOMPARE(snap.length(), first.size());
        QCOMPARE(snap.lineCount(), qsizetype(3));
    }
    // The buffer is gone; the snapshots are not.
    QCOMPARE(snap.text(), first);
    QCOMPARE(snap.utf8(0, snap.byteLength()), first.toUtf8());
    const TelamonTextSnapshot copy = snap;
    QVERIFY(copy.isSameVersion(snap));
    QCOMPARE(snap2.text(), QStringLiteral("e and a half\r\ntwo\r\nthree"));
}

void TestTextBuffer::snapshotQueries()
{
    TextBuffer b;
    b.setText(QStringLiteral("ab\r\ncd\n\nef"));
    const TelamonTextSnapshot s = b.snapshot();
    QCOMPARE(s.length(), qsizetype(10));
    QCOMPARE(s.lineCount(), qsizetype(4));
    QCOMPARE(s.lineStart(1), qsizetype(4));
    QCOMPARE(s.lineStart(2), qsizetype(7));
    QCOMPARE(s.lineStart(3), qsizetype(8));
    QCOMPARE(s.lineEnd(0), qsizetype(2));
    QCOMPARE(s.lineEnd(1), qsizetype(6));
    QCOMPARE(s.lineEnd(2), qsizetype(7));
    QCOMPARE(s.lineEnd(3), qsizetype(10));
    QCOMPARE(s.lineAt(4), qsizetype(1));
    QCOMPARE(s.lineAt(99), qsizetype(3));
    QCOMPARE(s.text(2, 5), QStringLiteral("\r\nc"));
    QCOMPARE(s.text(-3, 2), QStringLiteral("ab"));
    QCOMPARE(s.text(8, 400), QStringLiteral("ef"));
    QVERIFY(s.text(5, 5).isEmpty());
    QVERIFY(s.text(6, 2).isEmpty());

    // Chunks of a large text, the visitor, offsets in both units.
    QRandomGenerator rng(11);
    QString big;
    while (big.size() < 400000)
        big += randomText(rng, 100);
    b.setText(big);
    const TelamonTextSnapshot sb = b.snapshot();
    QVERIFY(sb.chunkCount() >= 6);
    QByteArray joined;
    qsizetype expectedUnits = 0, count = 0;
    sb.visitChunks([&](const TelamonTextChunk &c) {
        if (c.byteOffset != joined.size() || c.utf16Offset != expectedUnits)
            return false;
        joined.append(c.data, c.byteLength);
        expectedUnits += c.utf16Length;
        ++count;
        return true;
    });
    QCOMPARE(count, sb.chunkCount());
    QVERIFY(joined == big.toUtf8());
    QCOMPARE(expectedUnits, sb.length());
    // Starting from a byte, and stopping early.
    const qsizetype from = sb.byteLength() / 2;
    qsizetype firstOffset = -1, seen = 0;
    sb.visitChunks(
        [&](const TelamonTextChunk &c) {
            if (firstOffset < 0)
                firstOffset = c.byteOffset;
            ++seen;
            return seen < 2;
        },
        from);
    QCOMPARE(seen, qsizetype(2));
    QVERIFY(firstOffset <= from && from < firstOffset + MaxPiece);
    QCOMPARE(sb.chunkIndexAtByte(from), sb.chunkIndexAtByte(firstOffset));
    QCOMPARE(sb.chunkAt(sb.chunkCount()).byteLength, qsizetype(0));
    QCOMPARE(sb.chunkAt(-1).byteLength, qsizetype(0));
    // The maps against the model.
    const Model m = buildModel(big);
    for (int i = 0; i < 300; ++i) {
        const qsizetype p = qsizetype(rng.bounded(quint32(big.size() + 1)));
        QCOMPARE(sb.byteAtUtf16(p), m.byteOfUnit[p]);
        const qsizetype o = qsizetype(rng.bounded(quint32(m.u8.size() + 1)));
        QCOMPARE(sb.utf16AtByte(o), m.unitOfByte[o]);
        QCOMPARE(sb.lineAt(p), modelLineAt(m, p));
    }
    QCOMPARE(sb.byteAtUtf16(-4), qsizetype(0));
    QCOMPARE(sb.byteAtUtf16(sb.length() + 9), sb.byteLength());
}

void TestTextBuffer::snapshotNull()
{
    const TelamonTextSnapshot s;
    QVERIFY(s.isNull());
    QCOMPARE(s.length(), qsizetype(0));
    QCOMPARE(s.lineCount(), qsizetype(0));
    QCOMPARE(s.revision(), quint64(0));
    QVERIFY(s.text().isEmpty());
    QCOMPARE(s.lineEnd(3), qsizetype(0));
    QCOMPARE(s.chunkCount(), qsizetype(0));
    bool called = false;
    s.visitChunks([&](const TelamonTextChunk &) {
        called = true;
        return true;
    });
    QVERIFY(!called);
    // An implementation older than the header gives a null handle.
    struct Old : TelamonTextSnapshotInterface {
        int abiVersion() const override { return 0; }
        void ref() const override { QFAIL("ref on an old implementation"); }
        void deref() const override {}
        qsizetype length() const override { return 0; }
        qsizetype byteLength() const override { return 0; }
        qsizetype lineCount() const override { return 0; }
        quint64 revision() const override { return 0; }
        qsizetype lineStart(qsizetype) const override { return 0; }
        qsizetype lineStartByte(qsizetype) const override { return 0; }
        qsizetype lineAt(qsizetype) const override { return 0; }
        qsizetype lineAtByte(qsizetype) const override { return 0; }
        qsizetype utf16AtByte(qsizetype) const override { return 0; }
        qsizetype byteAtUtf16(qsizetype) const override { return 0; }
        QString text(qsizetype, qsizetype) const override { return QString(); }
        QByteArray utf8(qsizetype, qsizetype) const override { return QByteArray(); }
        qsizetype chunkCount() const override { return 0; }
        TelamonTextChunk chunkAt(qsizetype) const override { return TelamonTextChunk(); }
        qsizetype chunkIndexAtByte(qsizetype) const override { return 0; }
    } old;
    QVERIFY(TelamonTextSnapshot(&old).isNull());
}

void TestTextBuffer::snapshotThreads()
{
    // Readers check every snapshot the main thread publishes while it keeps
    // editing: the text of a revision never changes under them.
    TextBuffer buf;
    QRandomGenerator rng(2024);
    std::mutex mutex;
    TelamonTextSnapshot published;
    QHash<quint64, size_t> expected; // revision -> hash of its text
    std::atomic<bool> stop{false};
    std::atomic<int> checked{0};
    std::atomic<int> failures{0};
    std::mutex failMutex;
    QString failMessage;

    auto fail = [&](const QString &m) {
        ++failures;
        std::lock_guard<std::mutex> g(failMutex);
        if (failMessage.isEmpty())
            failMessage = m;
    };
    auto reader = [&] {
        quint64 lastRev = 0;
        while (!stop.load()) {
            TelamonTextSnapshot s;
            {
                std::lock_guard<std::mutex> g(mutex);
                s = published;
            }
            if (s.isNull() || (s.revision() == lastRev && s.revision() != 0)) {
                std::this_thread::yield();
                continue;
            }
            lastRev = s.revision();
            const QString text = s.text();
            size_t want;
            {
                std::lock_guard<std::mutex> g(mutex);
                if (!expected.contains(s.revision())) {
                    fail(QStringLiteral("revision %1 not published").arg(s.revision()));
                    return;
                }
                want = expected.value(s.revision());
            }
            if (qHash(text, 7) != want)
                fail(QStringLiteral("text of revision %1 changed").arg(s.revision()));
            if (text.size() != s.length())
                fail(QStringLiteral("length %1 vs text %2").arg(s.length()).arg(text.size()));
            QByteArray joined;
            s.visitChunks([&](const TelamonTextChunk &c) {
                joined.append(c.data, c.byteLength);
                return true;
            });
            if (joined != text.toUtf8() || joined.size() != s.byteLength())
                fail(QStringLiteral("chunks of revision %1 differ").arg(s.revision()));
            qsizetype breaks = 0;
            for (qsizetype i = 0; i < text.size(); ++i) {
                if (text[i] == u'\n' || (text[i] == u'\r' && !(i + 1 < text.size() && text[i + 1] == u'\n')))
                    ++breaks;
            }
            if (s.lineCount() != breaks + 1)
                fail(QStringLiteral("lineCount of revision %1").arg(s.revision()));
            if (s.byteAtUtf16(s.length() / 2) < 0 || s.lineStart(s.lineCount() / 2) > s.length())
                fail(QStringLiteral("conversions of revision %1").arg(s.revision()));
            ++checked;
        }
    };
    std::thread t1(reader), t2(reader);

    QString model;
    QElapsedTimer editTimer;
    editTimer.start();
    for (int step = 0; step < 3000 || (checked.load() < 50 && editTimer.elapsed() < 30000); ++step) {
        const qsizetype n = model.size();
        if (n > 20000 || rng.bounded(100) < 35) {
            const qsizetype a = qsizetype(rng.bounded(quint32(n + 1)));
            const qsizetype b = std::min<qsizetype>(n, a + qsizetype(rng.bounded(60u)));
            const auto [ra, rb] = widen(model, a, b);
            buf.remove(a, b);
            model.remove(ra, rb - ra);
        } else {
            const QString t = randomText(rng, int(rng.bounded(8u)) + 1);
            const qsizetype p = qsizetype(rng.bounded(quint32(n + 1)));
            buf.insert(p, t);
            model.insert(widen(model, p, p).first, t);
        }
        {
            std::lock_guard<std::mutex> g(mutex);
            expected.insert(buf.revision(), qHash(model, 7));
            published = buf.snapshot();
        }
        std::this_thread::sleep_for(std::chrono::microseconds(50));
    }
    // Let the readers see the last one, then stop them.
    QElapsedTimer timer;
    timer.start();
    while (checked.load() < 50 && timer.elapsed() < 30000)
        QThread::msleep(5);
    stop = true;
    t1.join();
    t2.join();
    {
        std::lock_guard<std::mutex> g(mutex);
        published = TelamonTextSnapshot();
    }
    QVERIFY2(failures.load() == 0, qPrintable(failMessage));
    QVERIFY2(checked.load() >= 50, qPrintable(QString::number(checked.load())));
    QCOMPARE(buf.tree().text(0, buf.tree().length()), model);
    qInfo() << "snapshots checked by the readers:" << checked.load();
}

QTEST_GUILESS_MAIN(TestTextBuffer)
#include "tst_textbuffer.moc"
