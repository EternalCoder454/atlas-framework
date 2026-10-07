// TelamonTextView (ui/text): the read-only view over the buffer. Software scene
// graph on the offscreen platform; the item is created in C++, the way Notepad
// uses it.
#include "telamontextview.h"

#include <QAccessible>
#include <QClipboard>
#include <QGuiApplication>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QQuickWindow>
#include <QSignalSpy>
#include <QtTest>

#include <array>
#include <atomic>
#include <new>
#include <thread>

using TelamonTextDetail::setTaskHookForTests;

namespace {

void failOnF(const char *data, qsizetype)
{
    if (data[0] == 'F')
        throw std::bad_alloc();
}

struct Fixture {
    QQuickWindow win;
    TelamonTextView *view = nullptr;

    explicit Fixture(QSize size = QSize(400, 200))
    {
        win.resize(size);
        view = new TelamonTextView(win.contentItem());
        view->setSize(QSizeF(size));
        win.show();
        QTest::qWaitForWindowExposed(&win);
        win.requestActivate();
        QTest::qWaitForWindowActive(&win, 500);
    }
    void settle() { QTest::qWait(30); }
};

QString lines(int n)
{
    QString s;
    for (int i = 0; i < n; ++i)
        s += QStringLiteral("line %1\n").arg(i);
    return s;
}

// A point inside the character at `position`, in window (item) coordinates.
QPointF pointAt(TelamonTextView *v, qsizetype position)
{
    const QRectF r = v->rectangleAt(position);
    return QPointF(r.left() + 1, r.center().y());
}

} // namespace

class TestTextView : public QObject
{
    Q_OBJECT

private slots:
    void cleanup() { setTaskHookForTests(nullptr); }

    void emptyView();
    void layoutOnlyVisible();
    void wrapRows();
    void selectionAndCopy();
    void mouseHitTesting();
    void mouseSelection();
    void followMode();
    void maximumLines();
    void loadChunks();
    void loadFailure();
    void hugeLine();
    void snapshotWhileEditing();
    void decorationsAndPaint();
    void lineNumbersAndHighlighter();
    void keyboardNavigation();
    void accessible();
    void accessibleName();
    void rowIndexDropAndGrow();
    void resizeKeepsAnchor();
    void maximumLinesWrapKeepsPosition();
    void maximumLinesAfterLoad();
    void ungrabStopsAutoscroll();
    void gutterClipsText();
    void hasSelectionAndBounds();
    void surrogateKeys();
    void tabsCountInContentWidth();
    void longLineWindows();
    void maximumLinesShiftsDecorations();
};

void TestTextView::emptyView()
{
    Fixture f;
    TelamonTextView *v = f.view;
    f.settle();
    QCOMPARE(v->length(), qsizetype(0));
    QCOMPARE(v->lineCount(), qsizetype(1));
    QCOMPARE(v->positionAt(QPointF(5, 5)), qsizetype(0));
    QVERIFY(v->rectangleAt(0).width() > 0);
    QVERIFY(v->selectedText().isEmpty());
    v->copy();
    v->selectAll();
    v->select(5, 9);
    QCOMPARE(v->cursorPosition(), qsizetype(0));
    QCOMPARE(v->firstVisibleLine(), qsizetype(0));
    QCOMPARE(v->lastVisibleLine(), qsizetype(0));
    QVERIFY(v->snapshot().length() == 0);
    // Keys and the wheel on nothing.
    QTest::keyClick(&f.win, Qt::Key_Down);
    QTest::keyClick(&f.win, Qt::Key_End, Qt::ControlModifier);
    QWheelEvent we(QPointF(10, 10), QPointF(10, 10), QPoint(), QPoint(0, -120), Qt::NoButton, {}, Qt::NoScrollPhase, false);
    QCoreApplication::sendEvent(v, &we);
    QCOMPARE(v->contentY(), 0.0);
    QVERIFY(!f.win.grabWindow().isNull());
}

void TestTextView::layoutOnlyVisible()
{
    Fixture f;
    TelamonTextView *v = f.view;
    v->setText(lines(5000));
    f.settle();
    const qreal rh = v->rowHeight();
    QCOMPARE(v->lineCount(), qsizetype(5001));
    QCOMPARE(v->contentHeight(), 5001 * rh);
    QCOMPARE(v->firstVisibleLine(), qsizetype(0));
    QCOMPARE(v->lastVisibleLine(), qsizetype(int((200 - 1) / rh)));
    QVERIFY2(v->cachedLayouts() < 200, qPrintable(QString::number(v->cachedLayouts())));
    QSignalSpy spy(v, SIGNAL(visibleRangeChanged()));
    v->setContentY(2500 * rh);
    f.settle();
    QCOMPARE(v->firstVisibleLine(), qsizetype(2500));
    QVERIFY(spy.count() >= 1);
    QCOMPARE(v->lineY(2500), 2500 * rh);
    QVERIFY(v->cachedLayouts() < 200);
    // Positions and lines.
    QCOMPARE(v->positionOfLine(1), qsizetype(QStringLiteral("line 0\n").size()));
    QCOMPARE(v->lineColumn(v->positionOfLine(3) + 2).line, qsizetype(3));
    QCOMPARE(v->lineColumn(v->positionOfLine(3) + 2).column, qsizetype(2));
    // A line far away has no rectangle (not laid out), a visible one has.
    QVERIFY(v->rectangleAt(0).isEmpty());
    QVERIFY(!v->rectangleAt(v->positionOfLine(2501)).isEmpty());
    // The scroll never leaves the text.
    v->setContentY(1e12);
    QVERIFY(v->contentY() <= v->contentHeight() - v->height() + 0.5);
    v->setContentY(-5);
    QCOMPARE(v->contentY(), 0.0);
}

void TestTextView::wrapRows()
{
    Fixture f;
    TelamonTextView *v = f.view;
    QString longLine(1200, u'x');
    for (int i = 6; i < 1200; i += 7)
        longLine[i] = u' ';
    v->setText(QStringLiteral("short\n") + longLine + QStringLiteral("\nend"));
    f.settle();
    const qreal flat = v->contentHeight();
    QCOMPARE(flat, 3 * v->rowHeight());
    v->setWrap(true);
    f.settle();
    QVERIFY(v->wrap());
    QVERIFY2(v->contentHeight() > 10 * v->rowHeight(), qPrintable(QString::number(v->contentHeight())));
    QCOMPARE(v->contentWidth(), v->width());
    // The long line starts on row 1 and `end` is far below it.
    QCOMPARE(v->lineY(1), v->rowHeight());
    QVERIFY(v->lineY(2) > 10 * v->rowHeight());
    // The rectangles of two characters in the same wrapped line are on
    // different rows when far apart.
    v->ensureVisible(v->positionOfLine(1) + 1000);
    f.settle();
    const QRectF a = v->rectangleAt(v->positionOfLine(1) + 1000);
    QVERIFY(!a.isEmpty());
    QVERIFY(a.top() >= 0 && a.bottom() <= v->height() + v->rowHeight());
    QCOMPARE(v->positionAt(pointAt(v, v->positionOfLine(1) + 1000)), v->positionOfLine(1) + 1000);
    v->setWrap(false);
    f.settle();
    QCOMPARE(v->contentHeight(), flat);
}

void TestTextView::selectionAndCopy()
{
    Fixture f;
    TelamonTextView *v = f.view;
    v->setText(QString::fromUtf8("hello world\r\nsecond \xF0\x9F\x98\x80 line"));
    QSignalSpy sel(v, SIGNAL(selectionChanged()));
    v->select(0, 5);
    QCOMPARE(v->selectedText(), QStringLiteral("hello"));
    QCOMPARE(v->selectionStart(), qsizetype(0));
    QCOMPARE(v->selectionEnd(), qsizetype(5));
    QCOMPARE(v->cursorPosition(), qsizetype(5));
    QVERIFY(sel.count() >= 1);
    v->select(5, 0); // backwards
    QCOMPARE(v->selectionStart(), qsizetype(0));
    QCOMPARE(v->cursorPosition(), qsizetype(0));
    v->copy();
    QCOMPARE(QGuiApplication::clipboard()->text(), QStringLiteral("hello"));
    // CRLF counts as two positions and is copied as it is in the file.
    v->select(6, 14);
    QCOMPARE(v->selectedText(), QStringLiteral("world\r\ns"));
    v->selectAll();
    QCOMPARE(v->selectedText(), v->text());
    v->copy();
    QCOMPARE(QGuiApplication::clipboard()->text(), v->text());
    // A selection never splits a surrogate pair.
    const qsizetype smile = v->text().indexOf(QChar(0xD83D));
    v->select(smile + 1, smile + 1);
    QCOMPARE(v->cursorPosition(), smile);
    // Out of range is clamped.
    v->select(-10, 9999);
    QCOMPARE(v->selectionStart(), qsizetype(0));
    QCOMPARE(v->selectionEnd(), v->length());
    // Copy with nothing selected leaves the clipboard alone.
    v->select(3, 3);
    QGuiApplication::clipboard()->setText(QStringLiteral("keep"));
    v->copy();
    QCOMPARE(QGuiApplication::clipboard()->text(), QStringLiteral("keep"));
    // Standard keys.
    v->setCursorPosition(0);
    f.view->forceActiveFocus();
    QTest::keyClick(&f.win, Qt::Key_A, Qt::ControlModifier);
    QCOMPARE(v->selectedText(), v->text());
    QTest::keyClick(&f.win, Qt::Key_C, Qt::ControlModifier);
    QCOMPARE(QGuiApplication::clipboard()->text(), v->text());
}

void TestTextView::mouseHitTesting()
{
    Fixture f;
    TelamonTextView *v = f.view;
    v->setText(QString::fromUtf8("hello world\nsecond \xF0\x9F\x98\x80 line\n\nlast"));
    f.settle();
    // positionAt inverts rectangleAt for every position of every line.
    for (qsizetype p = 0; p <= v->length(); ++p) {
        if (v->text().mid(p, 1).at(0).isLowSurrogate() && p > 0)
            continue;
        const QRectF r = v->rectangleAt(p);
        QVERIFY2(!r.isEmpty(), qPrintable(QString::number(p)));
        QCOMPARE(v->positionAt(pointAt(v, p)), p);
    }
    // Inside a pair: the start of it. Past the end of a line: the end of it.
    const qsizetype smile = v->text().indexOf(QChar(0xD83D));
    const QRectF sr = v->rectangleAt(smile);
    QVERIFY(v->positionAt(QPointF(sr.center().x(), sr.center().y())) != smile + 1);
    QCOMPARE(v->positionAt(QPointF(390, 5)), qsizetype(11));
    // Below the text: the last line. Above: the start.
    QCOMPARE(v->positionAt(QPointF(5, 190)), v->positionOfLine(v->lineCount() - 1));
    QCOMPARE(v->positionAt(QPointF(5, -50)), qsizetype(0));
    QCOMPARE(v->positionAt(QPointF(-50, 5)), qsizetype(0));
    // The rectangle at the end of the text is the caret's, and cursorRectangle follows.
    const QRectF end = v->rectangleAt(v->length());
    QVERIFY(!end.isEmpty() && end.width() <= 2);
    v->setCursorPosition(3);
    QCOMPARE(v->cursorRectangle(), v->rectangleAt(3));
    // The rectangles follow the scroll.
    v->setText(lines(300));
    f.settle();
    const QRectF before = v->rectangleAt(v->positionOfLine(3));
    v->setContentY(v->rowHeight());
    QCOMPARE(v->rectangleAt(v->positionOfLine(3)).top(), before.top() - v->rowHeight());
}

void TestTextView::mouseSelection()
{
    Fixture f;
    TelamonTextView *v = f.view;
    v->setText(QStringLiteral("hello world and more\nsecond line"));
    f.settle();
    QTest::mouseClick(&f.win, Qt::LeftButton, {}, pointAt(v, 3).toPoint());
    QCOMPARE(v->cursorPosition(), qsizetype(3));
    QVERIFY(v->hasActiveFocus());
    QVERIFY(v->selectedText().isEmpty());
    // Drag.
    QTest::mousePress(&f.win, Qt::LeftButton, {}, pointAt(v, 2).toPoint());
    QTest::mouseMove(&f.win, pointAt(v, 8).toPoint());
    QTest::mouseMove(&f.win, pointAt(v, 12).toPoint());
    QTest::mouseRelease(&f.win, Qt::LeftButton, {}, pointAt(v, 12).toPoint());
    QCOMPARE(v->selectionStart(), qsizetype(2));
    QCOMPARE(v->selectionEnd(), qsizetype(12));
    // Shift+click extends.
    QTest::mouseClick(&f.win, Qt::LeftButton, {}, pointAt(v, 1).toPoint());
    QTest::mouseClick(&f.win, Qt::LeftButton, Qt::ShiftModifier, pointAt(v, 7).toPoint());
    QCOMPARE(v->selectionStart(), qsizetype(1));
    QCOMPARE(v->selectionEnd(), qsizetype(7));
    // Double click: the word.
    QTest::mouseDClick(&f.win, Qt::LeftButton, {}, pointAt(v, 7).toPoint());
    QCOMPARE(v->selectedText(), QStringLiteral("world"));
    // A drag below the view scrolls and keeps the selection inside the text.
    v->setText(lines(400));
    f.settle();
    QTest::mousePress(&f.win, Qt::LeftButton, {}, pointAt(v, 1).toPoint());
    QTest::mouseMove(&f.win, QPoint(20, 195));
    QTest::mouseMove(&f.win, QPoint(20, 260));
    QTest::qWait(250);
    QVERIFY(v->contentY() > 0);
    QTest::mouseRelease(&f.win, Qt::LeftButton, {}, QPoint(20, 260));
    QVERIFY(v->selectionEnd() <= v->length());
    QVERIFY(v->selectionEnd() > v->positionOfLine(5));
    // The timer stops with the drag.
    const qreal y = v->contentY();
    QTest::qWait(150);
    QCOMPARE(v->contentY(), y);
    // The wheel scrolls.
    QWheelEvent we(QPointF(10, 10), QPointF(10, 10), QPoint(), QPoint(0, -120), Qt::NoButton, {}, Qt::NoScrollPhase, false);
    QCoreApplication::sendEvent(v, &we);
    QVERIFY(v->contentY() > y);
}

void TestTextView::followMode()
{
    Fixture f;
    TelamonTextView *v = f.view;
    v->setFollow(true);
    v->setText(lines(100));
    f.settle();
    v->setContentY(1e9);
    f.settle();
    const qsizetype before = v->lineCount();
    v->appendText(lines(50));
    f.settle();
    QCOMPARE(v->lineCount(), before + 50);
    QVERIFY2(qAbs(v->contentY() - (v->contentHeight() - v->height())) < 1.0, qPrintable(QString::number(v->contentY())));
    QCOMPARE(v->lastVisibleLine(), v->lineCount() - 1);
    // Scrolled away: the view stays where it is.
    v->setContentY(0);
    v->appendText(lines(10));
    f.settle();
    QCOMPARE(v->contentY(), 0.0);
    // Follow off: a view at the bottom does not move.
    v->setFollow(false);
    v->setContentY(1e9);
    const qreal y = v->contentY();
    v->appendText(lines(10));
    f.settle();
    QCOMPARE(v->contentY(), y);
    // appendText signals the change and is refused while loading.
    QList<std::array<qsizetype, 3>> spy;
    connect(v, &TelamonTextView::contentsChange, this, [&](qsizetype p, qsizetype r, qsizetype a) { spy.append({p, r, a}); });
    const qsizetype len = v->length();
    v->appendText(QStringLiteral("tail"));
    QCOMPARE(spy.size(), qsizetype(1));
    QCOMPARE(spy.at(0)[0], len);
    QCOMPARE(spy.at(0)[1], qsizetype(0));
    QCOMPARE(spy.at(0)[2], qsizetype(4));
    v->beginLoad();
    v->appendText(QStringLiteral("ignored"));
    QVERIFY(v->text().isEmpty());
    v->endLoad();
}

void TestTextView::maximumLines()
{
    Fixture f;
    TelamonTextView *v = f.view;
    v->setMaximumLines(20);
    v->setFollow(true);
    for (int i = 0; i < 100; ++i)
        v->appendText(QStringLiteral("row %1\n").arg(i));
    f.settle();
    QVERIFY(v->lineCount() <= 20);
    QVERIFY(v->text().contains(QStringLiteral("row 99")));
    QVERIFY(!v->text().contains(QStringLiteral("row 10\n")));
    QCOMPARE(v->maximumLines(), qsizetype(20));
    v->setCursorPosition(v->length());
    v->setMaximumLines(5);
    QVERIFY(v->lineCount() <= 5);
    QCOMPARE(v->cursorPosition(), v->length());
}

void TestTextView::loadChunks()
{
    Fixture f;
    TelamonTextView *v = f.view;
    QSignalSpy loaded(v, SIGNAL(loaded()));
    QList<std::array<qsizetype, 3>> contents;
    connect(v, &TelamonTextView::contentsChange, this, [&](qsizetype p, qsizetype r, qsizetype a) { contents.append({p, r, a}); });
    v->setText(QStringLiteral("old text"));
    v->beginLoad();
    QVERIFY(v->loading());
    QVERIFY(v->text().isEmpty());
    QByteArray all;
    for (int i = 0; i < 6; ++i) {
        QByteArray chunk;
        for (int k = 0; k < 20000; ++k)
            chunk += "line " + QByteArray::number(i * 20000 + k) + "\n";
        all += chunk;
        v->appendBytes(chunk);
    }
    all += "tail\xFF";
    v->appendBytes(QByteArray("tail\xFF"));
    v->endLoad();
    QTRY_VERIFY_WITH_TIMEOUT(!v->loading(), 20000);
    QCOMPARE(v->loadProgress(), 1.0);
    QVERIFY(v->hadInvalidText());
    QVERIFY(!v->loadFailed());
    QCOMPARE(v->lineCount(), qsizetype(120001));
    QCOMPARE(v->snapshot().utf8(0, all.size() + 2), all.left(all.size() - 1) + "\xEF\xBF\xBD");
    QVERIFY(loaded.count() >= 2); // setText and the load
    QVERIFY(contents.size() >= 2);
    // The first lines show while the rest is still being counted: here only
    // that the view is consistent when scrolled to the end.
    v->setContentY(1e12);
    f.settle();
    QCOMPARE(v->lastVisibleLine(), v->lineCount() - 1);
    // Restart: a second beginLoad() before endLoad() starts over.
    v->beginLoad();
    v->appendBytes(QByteArray("first"));
    v->beginLoad();
    v->appendBytes(QByteArray("second"));
    v->endLoad();
    QTRY_VERIFY(!v->loading());
    QCOMPARE(v->text(), QStringLiteral("second"));
    // appendData outside a load is ignored.
    v->appendBytes(QByteArray("late"));
    QCOMPARE(v->text(), QStringLiteral("second"));
}

void TestTextView::loadFailure()
{
    Fixture f;
    TelamonTextView *v = f.view;
    setTaskHookForTests(failOnF);
    v->beginLoad();
    v->appendBytes(QByteArray(100000, 'a'));
    v->appendBytes(QByteArray(100000, 'F'));
    v->appendBytes(QByteArray(100000, 'c'));
    v->endLoad();
    QTRY_VERIFY_WITH_TIMEOUT(!v->loading(), 20000);
    QVERIFY(v->loadFailed());
    QCOMPARE(v->length(), qsizetype(100000)); // the chunk before the failure, whole
    f.settle();
    QCOMPARE(v->lastVisibleLine(), qsizetype(0));
    QVERIFY(!f.win.grabWindow().isNull());
    // The view is usable afterwards.
    v->setText(QStringLiteral("fine"));
    QVERIFY(!v->loadFailed());
    QCOMPARE(v->text(), QStringLiteral("fine"));
}

void TestTextView::hugeLine()
{
    Fixture f;
    TelamonTextView *v = f.view;
    const qsizetype n = 5000000;
    v->setText(QString(n, u'0') + QStringLiteral("\nnext"));
    f.settle();
    const qreal cw = v->characterWidth();
    QVERIFY(v->cachedLayouts() <= 3);
    QVERIFY(v->contentWidth() > n * cw * 0.99);
    // Scroll far right: positions follow the monospace estimate.
    v->setContentX(1000000 * cw);
    f.settle();
    const qsizetype p = v->positionAt(QPointF(100, 5));
    QVERIFY2(qAbs(p - 1000000 - qsizetype(100 / cw)) < 20, qPrintable(QString::number(p)));
    QVERIFY(!v->rectangleAt(p).isEmpty());
    QVERIFY(!f.win.grabWindow().isNull());
    // The end of the line.
    v->ensureVisible(n);
    f.settle();
    QVERIFY(v->contentX() > (n - 1000) * cw);
    QCOMPARE(v->positionAt(QPointF(v->width() - 2, 5)), n);
    // Wrapped: rows from the length, only the rows in view laid out.
    v->setContentX(0);
    v->setWrap(true);
    f.settle();
    const int cpr = int((v->width() - 8) / cw);
    QVERIFY(v->contentHeight() > qreal(n / cpr) * v->rowHeight() * 0.95);
    v->setContentY(v->contentHeight() / 2);
    f.settle();
    QVERIFY(v->cachedLayouts() <= 3);
    const qsizetype mid = v->positionAt(QPointF(10, 5));
    QVERIFY(mid > n / 3 && mid < 2 * n / 3);
    QVERIFY(!f.win.grabWindow().isNull());
    // Selecting all of it and copying works and is the whole text.
    v->selectAll();
    QCOMPARE(v->selectedText().size(), v->length());
}

void TestTextView::snapshotWhileEditing()
{
    Fixture f;
    TelamonTextView *v = f.view;
    v->setText(lines(2000));
    const TelamonTextSnapshot snap = v->snapshot();
    const QString frozen = snap.text();
    std::atomic<bool> stop{false};
    std::atomic<int> bad{0};
    std::thread reader([&] {
        while (!stop.load()) {
            if (snap.length() != frozen.size() || snap.text(0, 20) != frozen.left(20) || snap.lineCount() != 2001)
                ++bad;
        }
    });
    for (int i = 0; i < 300; ++i) {
        v->appendText(QStringLiteral("more %1\n").arg(i));
        if (i % 50 == 0)
            f.settle();
    }
    v->setText(QStringLiteral("replaced"));
    stop = true;
    reader.join();
    QCOMPARE(bad.load(), 0);
    QCOMPARE(snap.text(), frozen);
    QVERIFY(v->snapshot().revision() > snap.revision());
}

void TestTextView::decorationsAndPaint()
{
    Fixture f;
    TelamonTextView *v = f.view;
    v->setTextColor(Qt::black);
    f.win.setColor(Qt::white);
    v->setText(QStringLiteral("find the needle in the needle stack\nsecond line here"));
    f.settle();
    const QImage plain = f.win.grabWindow();
    QVERIFY(!plain.isNull());
    auto dark = [](const QImage &img) {
        int n = 0;
        for (int y = 0; y < img.height(); ++y)
            for (int x = 0; x < img.width(); ++x)
                n += qGray(img.pixel(x, y)) < 100;
        return n;
    };
    QVERIFY2(dark(plain) > 20, "the text is painted");
    // A decoration layer changes the picture; clearing it restores it.
    v->setDecorations(QStringLiteral("find"), {{9, 15}, {23, 29}}, TelamonText::DecorationStyle::CurrentMatch);
    f.settle();
    QVERIFY(f.win.grabWindow() != plain);
    v->setDecorations(QStringLiteral("spell"), {{0, 4}}, TelamonText::DecorationStyle::Spelling);
    f.settle();
    QVERIFY(!f.win.grabWindow().isNull());
    v->clearDecorations(QStringLiteral("find"));
    v->clearDecorations(QStringLiteral("spell"));
    v->clearDecorations(QStringLiteral("none"));
    f.settle();
    QCOMPARE(f.win.grabWindow(), plain);
    // A selection is painted too, and decorations beyond the text are clamped.
    v->select(0, 20);
    f.settle();
    QVERIFY(f.win.grabWindow() != plain);
    v->setDecorations(QStringLiteral("far"), {{-5, 99999}, {7, 7}}, TelamonText::DecorationStyle::Error);
    f.settle();
    QVERIFY(!f.win.grabWindow().isNull());
    // Decorations survive a load into a shorter text without crashing.
    v->setText(QStringLiteral("x"));
    f.settle();
    QVERIFY(!f.win.grabWindow().isNull());
}

namespace {
class WordHighlighter : public TelamonTextHighlighterInterface
{
public:
    int initialState() const override { return 0; }
    int highlightLine(int startState, const QString &line, QList<TelamonText::FormatRun> *runs) const override
    {
        // State 1 = inside a /* */ comment.
        int state = startState;
        if (line.contains(QStringLiteral("/*")))
            state = 1;
        if (line.contains(QStringLiteral("*/")))
            state = 0;
        TelamonText::FormatRun r;
        r.start = 0;
        r.length = line.size();
        r.format.foreground = (startState == 1 || state == 1) ? QColor(Qt::darkGreen) : QColor(Qt::blue);
        r.format.name = (startState == 1 || state == 1) ? QStringLiteral("Comment") : QStringLiteral("Code");
        if (line.size() > 0)
            runs->append(r);
        return state;
    }
};
} // namespace

void TestTextView::lineNumbersAndHighlighter()
{
    Fixture f;
    TelamonTextView *v = f.view;
    v->setText(QStringLiteral("a /* open\nstill comment\nclose */ b\ncode"));
    f.settle();
    const QRectF noGutter = v->rectangleAt(0);
    v->setShowLineNumbers(true);
    f.settle();
    QVERIFY(v->showLineNumbers());
    QVERIFY(v->rectangleAt(0).left() > noGutter.left() + 10);
    QVERIFY(!f.win.grabWindow().isNull());
    // The highlighter's state flows from line to line, and formatAt reports it.
    QVERIFY(v->formatAt(0).name.isEmpty()); // no highlighter yet
    v->setHighlighter(std::make_shared<WordHighlighter>());
    f.settle();
    QCOMPARE(v->formatAt(0).name, QStringLiteral("Comment"));
    QCOMPARE(v->formatAt(v->positionOfLine(1) + 2).name, QStringLiteral("Comment"));
    QCOMPARE(v->formatAt(v->positionOfLine(2) + 2).name, QStringLiteral("Comment"));
    QCOMPARE(v->formatAt(v->positionOfLine(3)).name, QStringLiteral("Code"));
    QVERIFY(!f.win.grabWindow().isNull());
    // Limit: a line longer than the limit is left plain.
    v->setHighlightLimit(5);
    QVERIFY(v->formatAt(0).name.isEmpty());
    v->setHighlighter(nullptr);
    QVERIFY(v->formatAt(0).name.isEmpty());
    // highlightCurrentLine and the setters.
    v->setHighlightCurrentLine(true);
    QVERIFY(v->highlightCurrentLine());
    v->setTabWidth(8);
    QCOMPARE(v->tabWidth(), 8);
    v->setSyntax(QStringLiteral("C++"));
    QCOMPARE(v->syntax(), QStringLiteral("C++"));
    QVERIFY(v->syntaxForFile(QStringLiteral("a.cpp"), QString()).isEmpty());
    f.settle();
    QVERIFY(!f.win.grabWindow().isNull());
}

void TestTextView::keyboardNavigation()
{
    Fixture f;
    TelamonTextView *v = f.view;
    v->setText(QStringLiteral("one two\r\nthree\n\nfour five"));
    v->forceActiveFocus();
    f.settle();
    v->setCursorPosition(0);
    QTest::keyClick(&f.win, Qt::Key_Right);
    QCOMPARE(v->cursorPosition(), qsizetype(1));
    QTest::keyClick(&f.win, Qt::Key_End);
    QCOMPARE(v->cursorPosition(), qsizetype(7));
    QTest::keyClick(&f.win, Qt::Key_Right); // over the CRLF in one step
    QCOMPARE(v->cursorPosition(), qsizetype(9));
    QTest::keyClick(&f.win, Qt::Key_Left);
    QCOMPARE(v->cursorPosition(), qsizetype(7));
    QTest::keyClick(&f.win, Qt::Key_Down);
    QCOMPARE(v->lineColumn(v->cursorPosition()).line, qsizetype(1));
    QTest::keyClick(&f.win, Qt::Key_Down);
    QTest::keyClick(&f.win, Qt::Key_Down);
    QCOMPARE(v->lineColumn(v->cursorPosition()).line, qsizetype(3));
    QTest::keyClick(&f.win, Qt::Key_Down); // past the last line: the end
    QCOMPARE(v->cursorPosition(), v->length());
    QTest::keyClick(&f.win, Qt::Key_Home, Qt::ControlModifier);
    QCOMPARE(v->cursorPosition(), qsizetype(0));
    QTest::keyClick(&f.win, Qt::Key_Right, Qt::ShiftModifier);
    QTest::keyClick(&f.win, Qt::Key_Right, Qt::ShiftModifier);
    QCOMPARE(v->selectedText(), QStringLiteral("on"));
    QTest::keyClick(&f.win, Qt::Key_Left); // collapses to the start
    QCOMPARE(v->cursorPosition(), qsizetype(0));
    QVERIFY(v->selectedText().isEmpty());
    QTest::keyClick(&f.win, Qt::Key_End, Qt::ControlModifier | Qt::ShiftModifier);
    QCOMPARE(v->selectionEnd(), v->length());
    // The editing keys do nothing in the read-only view.
    const QString text = v->text();
    for (const QChar c : QStringLiteral("typed")) QTest::keyClick(&f.win, c.toLatin1());
    QTest::keyClick(&f.win, Qt::Key_Delete);
    QTest::keyClick(&f.win, Qt::Key_Backspace);
    QCOMPARE(v->text(), text);
    v->insert(0, QStringLiteral("x"));
    v->remove(0, 3);
    v->replace(0, 1, QStringLiteral("y"));
    v->cut();
    v->paste();
    v->undo();
    QCOMPARE(v->text(), text);
    QVERIFY(!v->canUndo() && !v->canRedo() && !v->modified());
}

void TestTextView::accessible()
{
    Fixture f;
    TelamonTextView *v = f.view;
    v->setText(QString::fromUtf8("hello world\nsecond \xF0\x9F\x98\x80 line"));
    f.settle();
    QAccessibleInterface *iface = QAccessible::queryAccessibleInterface(v);
    QVERIFY(iface);
    QVERIFY(iface->isValid());
    QCOMPARE(iface->role(), QAccessible::EditableText);
    QVERIFY(iface->state().focusable);
    QVERIFY(iface->state().readOnly);
    QVERIFY(iface->state().selectableText);
    QVERIFY(iface->state().multiLine);
    QCOMPARE(iface->childCount(), 0);
    QAccessibleTextInterface *text = iface->textInterface();
    QVERIFY(text);
    QCOMPARE(text->characterCount(), int(v->length()));
    QCOMPARE(text->text(0, 5), QStringLiteral("hello"));
    QCOMPARE(text->text(0, text->characterCount()), v->text());
    QCOMPARE(text->selectionCount(), 0);
    v->select(6, 11);
    QCOMPARE(text->selectionCount(), 1);
    int a = -1, b = -1;
    text->selection(0, &a, &b);
    QCOMPARE(a, 6);
    QCOMPARE(b, 11);
    QCOMPARE(text->cursorPosition(), 11);
    text->setSelection(0, 0, 5);
    QCOMPARE(v->selectedText(), QStringLiteral("hello"));
    text->removeSelection(0);
    QCOMPARE(text->selectionCount(), 0);
    text->setCursorPosition(4);
    QCOMPARE(v->cursorPosition(), qsizetype(4));
    // Geometry: the rectangle of a character maps back to its offset.
    const QRect r = text->characterRect(7);
    QVERIFY(!r.isEmpty());
    QCOMPARE(text->offsetAtPoint(QPoint(r.left() + 1, r.center().y())), 7);
    QVERIFY(iface->rect().contains(r));
    // Lines.
    QString line = text->textAtOffset(14, QAccessible::LineBoundary, &a, &b);
    QCOMPARE(line, QString::fromUtf8("second \xF0\x9F\x98\x80 line"));
    QCOMPARE(a, 12);
    line = text->textBeforeOffset(14, QAccessible::LineBoundary, &a, &b);
    QCOMPARE(line, QStringLiteral("hello world\n"));
    line = text->textAfterOffset(3, QAccessible::LineBoundary, &a, &b);
    QCOMPARE(line, QString::fromUtf8("second \xF0\x9F\x98\x80 line"));
    QCOMPARE(text->textAtOffset(1, QAccessible::CharBoundary, &a, &b), QStringLiteral("e"));
    // Events on a change do not crash with the accessibility active.
    QAccessible::setActive(true);
    v->appendText(QStringLiteral("\nappended"));
    v->select(0, 3);
    QAccessible::setActive(false);
    QCOMPARE(text->characterCount(), int(v->length()));
    // An item with its text empty.
    v->setText(QString());
    QCOMPARE(text->characterCount(), 0);
    QCOMPARE(text->text(0, 10), QString());
}

void TestTextView::accessibleName()
{
    qmlRegisterType<TelamonTextView>("TestTv", 1, 0, "TelamonTextView");
    Fixture f;
    QQmlEngine engine;
    QQmlComponent comp(&engine);
    comp.setData("import QtQuick\nimport TestTv\nTelamonTextView { Accessible.name: \"Build log\"; Accessible.description: \"Output of the build\" }\n", QUrl());
    QObject *o = comp.create();
    QVERIFY2(o, qPrintable(comp.errorString()));
    auto *v = qobject_cast<TelamonTextView *>(o);
    QVERIFY(v);
    v->setParentItem(f.win.contentItem());
    QAccessibleInterface *iface = QAccessible::queryAccessibleInterface(v);
    QVERIFY(iface);
    QCOMPARE(iface->text(QAccessible::Name), QStringLiteral("Build log"));
    QCOMPARE(iface->text(QAccessible::Description), QStringLiteral("Output of the build"));
    QVERIFY(iface->text(QAccessible::Value).isEmpty());
    // Without the attached object the name is empty and nothing breaks.
    QAccessibleInterface *plain = QAccessible::queryAccessibleInterface(f.view);
    QVERIFY(plain);
    QVERIFY(plain->text(QAccessible::Name).isEmpty());
    // Answers are bounded: a very long line is not built whole.
    f.view->setText(QString(3 * 1024 * 1024, QLatin1Char('x')));
    QAccessibleTextInterface *ti = plain->textInterface();
    QVERIFY(ti);
    QVERIFY(ti->text(0, 3 * 1024 * 1024).size() <= (1 << 20));
    int a = 0, b = 0;
    QVERIFY(ti->textAtOffset(5, QAccessible::LineBoundary, &a, &b).size() <= (1 << 20));
    QCOMPARE(b - a, 1 << 20);
    delete v;
}

void TestTextView::rowIndexDropAndGrow()
{
    using TelamonTextViewDetail::RowIndex;
    RowIndex r;
    std::vector<int> ref;
    auto check = [&] {
        QCOMPARE(r.lines(), qsizetype(ref.size()));
        qint64 sum = 0;
        for (qsizetype i = 0; i < r.lines(); i += 37) {
            sum = 0;
            for (qsizetype k = 0; k < i; ++k)
                sum += ref[size_t(k)];
            QCOMPARE(r.before(i), sum);
            QCOMPARE(r.lineAtRow(sum), i);
        }
    };
    r.reset(0);
    r.resize(10000);
    ref.assign(10000, 1);
    for (int i = 0; i < 10000; i += 7) {
        r.set(i, 1 + i % 5);
        ref[size_t(i)] = 1 + i % 5;
    }
    check();
    r.dropFront(100);
    ref.erase(ref.begin(), ref.begin() + 100);
    check();
    r.resize(r.lines() + 500); // grows without a rebuild
    ref.resize(ref.size() + 500, 1);
    check();
    r.dropFront(6000); // compacts
    ref.erase(ref.begin(), ref.begin() + 6000);
    check();
    r.set(3, 9);
    ref[3] = 9;
    r.resize(100);
    ref.resize(100);
    check();
    r.dropFront(1000); // more than there is
    QCOMPARE(r.lines(), qsizetype(0));
    QCOMPARE(r.total(), qint64(0));
}

void TestTextView::resizeKeepsAnchor()
{
    Fixture f;
    TelamonTextView *v = f.view;
    v->setWrap(true);
    QString text;
    for (int i = 0; i < 100; ++i)
        text += QStringLiteral("word word word word word word word word word word word word word word word %1\n").arg(i);
    v->setText(text);
    f.settle();
    // Walk down so that the lines above get their rows measured.
    for (int y = 0; y < 3000; y += 150) {
        v->setContentY(y);
        f.settle();
    }
    v->setContentY(v->lineY(30) + v->rowHeight());
    f.settle();
    QCOMPARE(v->firstVisibleLine(), qsizetype(30));
    v->setWidth(220);
    f.settle();
    QCOMPARE(v->firstVisibleLine(), qsizetype(30));
    QVERIFY2(qAbs(v->contentY() - v->lineY(30) - v->rowHeight()) < 1.0, qPrintable(QString::number(v->contentY() - v->lineY(30))));
    v->setWidth(400);
    f.settle();
    QCOMPARE(v->firstVisibleLine(), qsizetype(30));
    // A font change keeps the line too.
    QFont big = v->font();
    big.setPointSize(big.pointSize() + 6);
    v->setFont(big);
    f.settle();
    QCOMPARE(v->firstVisibleLine(), qsizetype(30));
    // And line numbers.
    v->setShowLineNumbers(true);
    f.settle();
    QCOMPARE(v->firstVisibleLine(), qsizetype(30));
}

void TestTextView::maximumLinesWrapKeepsPosition()
{
    Fixture f;
    TelamonTextView *v = f.view;
    v->setWrap(true);
    QString text;
    for (int i = 0; i < 100; ++i)
        text += QStringLiteral("word word word word word word word word word word word word word word word %1\n").arg(i);
    v->setText(text);
    f.settle();
    QVERIFY(v->lineY(11) > 11 * v->rowHeight() + 1); // the first lines wrap and are measured
    v->setContentY(v->lineY(50));
    f.settle();
    QCOMPARE(v->firstVisibleLine(), qsizetype(50));
    v->setMaximumLines(89); // drops 12 lines (101 lines with the last, empty one)
    f.settle();
    QCOMPARE(v->lineCount(), qsizetype(89));
    QCOMPARE(v->firstVisibleLine(), qsizetype(50 - 12));
    // Appending at the limit keeps the position as well.
    v->appendText(QStringLiteral("more\nmore\n"));
    f.settle();
    QCOMPARE(v->lineCount(), qsizetype(89));
    QCOMPARE(v->firstVisibleLine(), qsizetype(50 - 14));
}

void TestTextView::maximumLinesAfterLoad()
{
    Fixture f;
    TelamonTextView *v = f.view;
    v->setMaximumLines(10);
    v->beginLoad();
    v->appendBytes(lines(100).toUtf8());
    v->endLoad();
    QTRY_VERIFY_WITH_TIMEOUT(!v->loading(), 5000);
    QCOMPARE(v->lineCount(), qsizetype(10));
    QVERIFY(v->text().contains(QStringLiteral("line 99")));
    v->setText(lines(100));
    QCOMPARE(v->lineCount(), qsizetype(10));
    QVERIFY(v->text().contains(QStringLiteral("line 99")));
}

void TestTextView::ungrabStopsAutoscroll()
{
    Fixture f;
    TelamonTextView *v = f.view;
    v->setText(lines(400));
    f.settle();
    QTest::mousePress(&f.win, Qt::LeftButton, {}, pointAt(v, 1).toPoint());
    QTest::mouseMove(&f.win, QPoint(20, 195));
    QTest::mouseMove(&f.win, QPoint(20, 260));
    QVERIFY(v->dragging());
    QVERIFY(v->autoScrolling());
    v->ungrabMouse();
    QVERIFY(!v->dragging());
    QVERIFY(!v->autoScrolling());
    QTest::mouseRelease(&f.win, Qt::LeftButton, {}, QPoint(20, 100));
    // Hidden mid-drag.
    v->setContentY(0);
    QTest::mousePress(&f.win, Qt::LeftButton, {}, pointAt(v, 1).toPoint());
    QTest::mouseMove(&f.win, QPoint(20, 195));
    QTest::mouseMove(&f.win, QPoint(20, 260));
    QVERIFY2(v->dragging(), "dragging");
    QVERIFY(v->autoScrolling());
    v->setVisible(false);
    QVERIFY(!v->dragging());
    QVERIFY(!v->autoScrolling());
    v->setVisible(true);
    QTest::mouseRelease(&f.win, Qt::LeftButton, {}, QPoint(20, 100));
    // Focus lost mid-drag.
    v->setContentY(0);
    QTest::mousePress(&f.win, Qt::LeftButton, {}, pointAt(v, 1).toPoint());
    QTest::mouseMove(&f.win, QPoint(20, 195));
    QTest::mouseMove(&f.win, QPoint(20, 260));
    QVERIFY(v->autoScrolling());
    v->setFocus(false);
    v->window()->contentItem()->forceActiveFocus();
    QVERIFY(!v->hasActiveFocus());
    QVERIFY(!v->dragging());
    QVERIFY(!v->autoScrolling());
    QTest::mouseRelease(&f.win, Qt::LeftButton, {}, QPoint(20, 100));
}

void TestTextView::gutterClipsText()
{
    Fixture f;
    TelamonTextView *v = f.view;
    v->setShowLineNumbers(true);
    QString text;
    for (int i = 0; i < 5; ++i)
        text += QString(400, QLatin1Char('X')) + QLatin1Char('\n');
    v->setText(text);
    v->setContentX(0);
    f.settle();
    const int gw = int(3 * v->characterWidth());
    const QImage a = f.win.grabWindow().copy(0, 0, gw, 100);
    v->setContentX(120);
    f.settle();
    QCOMPARE(v->contentX(), 120.0);
    const QImage b = f.win.grabWindow().copy(0, 0, gw, 100);
    QVERIFY(a == b);
}

void TestTextView::hasSelectionAndBounds()
{
    Fixture f;
    TelamonTextView *v = f.view;
    v->setText(lines(10));
    QVERIFY(!v->property("hasSelection").toBool());
    QSignalSpy spy(v, SIGNAL(selectionChanged()));
    v->selectAll();
    QVERIFY(v->property("hasSelection").toBool());
    QVERIFY(spy.count() >= 1);
    QCOMPARE(v->selectedText(), v->text());
    v->copy();
    QCOMPARE(QGuiApplication::clipboard()->text(), v->text());
    QCOMPARE(v->boundedText(0, 1000, 5), QStringLiteral("line "));
    // A bound that falls inside a surrogate pair is moved back.
    v->setText(QString::fromUtf8("a\xF0\x9F\x98\x80z"));
    QCOMPARE(v->boundedText(0, 4, 2), QStringLiteral("a"));
    QCOMPARE(v->boundedText(-5, 100, 100), v->text());
}

void TestTextView::surrogateKeys()
{
    Fixture f;
    TelamonTextView *v = f.view;
    v->setText(QString::fromUtf8("\xF0\x9F\x98\x80\xF0\x9F\x98\x80 \xF0\x9F\x98\x80"));
    v->forceActiveFocus();
    v->setCursorPosition(v->length());
    for (int i = 0; i < 6; ++i)
        QTest::keyClick(&f.win, Qt::Key_Left, Qt::ControlModifier);
    QCOMPARE(v->cursorPosition(), qsizetype(0));
    for (int i = 0; i < 6; ++i)
        QTest::keyClick(&f.win, Qt::Key_Right, Qt::ControlModifier);
    QCOMPARE(v->cursorPosition(), v->length());
    // A position inside a pair is aligned and does not crash.
    v->setCursorPosition(1);
    QTest::keyClick(&f.win, Qt::Key_Right, Qt::ControlModifier);
    QVERIFY(v->cursorPosition() >= 0);
}

void TestTextView::tabsCountInContentWidth()
{
    Fixture f;
    TelamonTextView *v = f.view;
    v->setTabWidth(8);
    v->setText(QStringLiteral("\t\t\tx"));
    f.settle();
    QVERIFY(v->contentWidth() >= 25 * v->characterWidth());
}

void TestTextView::longLineWindows()
{
    Fixture f;
    TelamonTextView *v = f.view;
    const qsizetype n = 3 * 1024 * 1024;
    QString text(n, QLatin1Char('x'));
    text.replace(2 * 1024 * 1024, 5, QStringLiteral("hello"));
    v->setText(text);
    QAccessibleInterface *iface = QAccessible::queryAccessibleInterface(v);
    QAccessibleTextInterface *ti = iface->textInterface();
    int a = 0, b = 0;
    const int off = 2 * 1024 * 1024 + 2;
    const QString w = ti->textAtOffset(off, QAccessible::LineBoundary, &a, &b);
    QVERIFY(w.size() <= (1 << 20));
    QVERIFY(a <= off && off < b);
    QCOMPARE(b - a, int(w.size()));
    QVERIFY(w.contains(QStringLiteral("hello")));
    // A double click inside a huge line selects a word within the window.
    v->setText(QString(300000, QLatin1Char('a')));
    QTest::mouseDClick(&f.win, Qt::LeftButton, {}, QPoint(30, 8));
    QVERIFY(v->selectionEnd() - v->selectionStart() <= 2 * 65536);
}

void TestTextView::maximumLinesShiftsDecorations()
{
    Fixture f;
    TelamonTextView *v = f.view;
    v->setText(lines(30));
    v->setDecorationPairs(QStringLiteral("a"), {0, 3}, 0);
    v->setDecorationPairs(QStringLiteral("b"), {v->positionOfLine(25), v->positionOfLine(25) + 4}, 0);
    v->setMaximumLines(10);
    f.settle();
    QCOMPARE(v->lineCount(), qsizetype(10));
    QVERIFY(!f.win.grabWindow().isNull());
    // Setting text clears the layers, so a later change finds none.
    v->setText(lines(5));
    v->setMaximumLines(3);
    QCOMPARE(v->lineCount(), qsizetype(3));
}

int main(int argc, char **argv)
{
    qputenv("QT_QUICK_BACKEND", "software");
    QQuickWindow::setGraphicsApi(QSGRendererInterface::Software);
    QGuiApplication app(argc, argv);
    TestTextView tc;
    return QTest::qExec(&tc, argc, argv);
}

#include "tst_textview.moc"
