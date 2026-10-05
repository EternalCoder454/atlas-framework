#include "atlastextview.h"

#include <QAccessible>
#include <QAccessibleEvent>
#include <QAccessibleObject>
#include <QClipboard>
#include <QFontDatabase>
#include <QFontMetricsF>
#include <QGuiApplication>
#include <QKeyEvent>
#include <QMouseEvent>
#include <QPalette>
#include <QQuickWindow>
#include <QSGClipNode>
#include <QSGNode>
#include <QSGRectangleNode>
#include <QSGTextNode>
#include <QStyleHints>
#include <QTextCharFormat>
#include <QTextLayout>
#include <QTextOption>
#include <QWheelEvent>

#include <algorithm>
#include <climits>
#include <cmath>
#include <mutex>
#include <new>

using AtlasTextDetail::TextTree;
using AtlasTextViewDetail::LineBox;
using AtlasTextViewDetail::RowIndex;

namespace AtlasTextViewDetail {

void RowIndex::reset(qsizetype lines)
{
    m_head = 0;
    m_value.assign(size_t(std::max<qsizetype>(0, lines)), 1);
    rebuild();
}

void RowIndex::resize(qsizetype lines)
{
    lines = std::max<qsizetype>(0, lines);
    if (lines < this->lines()) {
        m_value.resize(size_t(m_head + lines));
        rebuild();
        return;
    }
    while (this->lines() < lines)
        pushOne(1);
}

void RowIndex::pushOne(int rows)
{
    if (m_tree.empty())
        m_tree.push_back(0);
    m_value.push_back(rows);
    const size_t i = m_value.size();
    qint64 t = rows;
    for (size_t k = 1; k < (i & (~i + 1)); k <<= 1)
        t += m_tree[i - k];
    m_tree.push_back(t);
}

void RowIndex::dropFront(qsizetype count)
{
    count = std::clamp<qsizetype>(count, 0, lines());
    const size_t n = m_value.size();
    for (qsizetype k = 0; k < count; ++k) {
        const size_t idx = size_t(m_head + k);
        const int v = m_value[idx];
        if (v == 0)
            continue;
        m_value[idx] = 0;
        for (size_t i = idx + 1; i <= n; i += i & (~i + 1))
            m_tree[i] -= v;
    }
    m_head += count;
    if (m_head > 4096 && size_t(m_head) > n / 2) {
        m_value.erase(m_value.begin(), m_value.begin() + m_head);
        m_head = 0;
        rebuild();
    }
}

void RowIndex::rebuild()
{
    const size_t n = m_value.size();
    m_tree.assign(n + 1, 0);
    for (size_t i = 1; i <= n; ++i) {
        m_tree[i] += m_value[i - 1];
        const size_t j = i + (i & (~i + 1));
        if (j <= n)
            m_tree[j] += m_tree[i];
    }
}

void RowIndex::set(qsizetype line, int rows)
{
    rows = std::max(1, rows);
    if (line < 0 || line >= lines())
        return;
    const size_t idx = size_t(m_head + line);
    const int d = rows - m_value[idx];
    if (d == 0)
        return;
    m_value[idx] = rows;
    const size_t n = m_value.size();
    for (size_t i = idx + 1; i <= n; i += i & (~i + 1))
        m_tree[i] += d;
}

qint64 RowIndex::before(qsizetype line) const
{
    line = std::clamp<qsizetype>(line, 0, lines());
    qint64 sum = 0;
    for (size_t i = size_t(m_head + line); i > 0; i -= i & (~i + 1))
        sum += m_tree[i];
    return sum;
}

qsizetype RowIndex::lineAtRow(qint64 row) const
{
    const size_t n = m_value.size();
    if (lines() == 0)
        return 0;
    size_t pos = 0, step = 1;
    while (step * 2 <= n)
        step *= 2;
    qint64 rem = std::max<qint64>(0, row);
    for (; step > 0; step >>= 1) {
        if (pos + step <= n && m_tree[pos + step] <= rem) {
            pos += step;
            rem -= m_tree[pos];
        }
    }
    return std::max<qsizetype>(0, qsizetype(std::min(pos, n - 1)) - m_head);
}

} // namespace AtlasTextViewDetail

namespace {

// A line longer than this is laid out as a window around what is in view.
constexpr qsizetype LongLine = 4096;
constexpr int MaxLayouts = 600;
constexpr int MaxStateGap = 20000;
constexpr qreal Pad = 4;

// The most a screen reader gets in one answer; a 5M-character line is not
// built for every query.
constexpr qsizetype MaxAccessibleText = 1 << 20;
// The most selectedText and copy() build (UTF-16 units).
constexpr qsizetype MaxSelectionText = qsizetype(1) << 27;

bool isWordChar(QChar c)
{
    return c.isLetterOrNumber() || c == u'_';
}

int clampInt(qsizetype v)
{
    return int(std::clamp<qsizetype>(v, 0, INT_MAX));
}

// The unit at `position`, or a null character when there is none to read.
QChar unitAt(const TextTree &t, qsizetype position)
{
    const QString s = t.text(position, position + 1);
    return s.isEmpty() ? QChar() : s.at(0);
}

} // namespace

// ---- Accessibility ----

namespace {

class AtlasTextViewAccessible : public QAccessibleObject, public QAccessibleTextInterface
{
public:
    explicit AtlasTextViewAccessible(AtlasTextView *view) : QAccessibleObject(view) {}

    void *interface_cast(QAccessible::InterfaceType t) override
    {
        if (t == QAccessible::TextInterface)
            return static_cast<QAccessibleTextInterface *>(this);
        return QAccessibleObject::interface_cast(t);
    }
    QAccessibleInterface *parent() const override
    {
        AtlasTextView *v = view();
        if (!v)
            return nullptr;
        for (QQuickItem *p = v->parentItem(); p; p = p->parentItem()) {
            if (QAccessibleInterface *i = QAccessible::queryAccessibleInterface(p))
                return i;
        }
        return v->window() ? QAccessible::queryAccessibleInterface(v->window()) : nullptr;
    }
    QAccessibleInterface *child(int) const override { return nullptr; }
    int childCount() const override { return 0; }
    int indexOfChild(const QAccessibleInterface *) const override { return -1; }
    // The name and the description come from the item's Accessible attached
    // object (Accessible.name, Accessible.description), as Qt Quick's own
    // accessible does. There is no value text: it would be the whole file.
    QString text(QAccessible::Text t) const override
    {
        const char *prop = t == QAccessible::Name ? "name" : t == QAccessible::Description ? "description" : nullptr;
        QObject *o = object();
        if (!prop || !o)
            return QString();
        for (QObject *c : o->children()) {
            if (c->inherits("QQuickAccessibleAttached"))
                return c->property(prop).toString();
        }
        return QString();
    }
    QRect rect() const override
    {
        AtlasTextView *v = view();
        if (!v)
            return QRect();
        return QRectF(v->mapToGlobal(QPointF(0, 0)), QSizeF(v->width(), v->height())).toAlignedRect();
    }
    QAccessible::Role role() const override { return QAccessible::EditableText; }
    QAccessible::State state() const override
    {
        QAccessible::State s;
        AtlasTextView *v = view();
        if (!v) {
            s.invalid = true;
            return s;
        }
        s.focusable = true;
        s.focused = v->hasActiveFocus();
        s.readOnly = v->readOnly();
        s.selectableText = true;
        s.multiLine = true;
        s.invisible = !v->isVisible();
        s.disabled = !v->isEnabled();
        return s;
    }

    // ---- QAccessibleTextInterface ----
    void addSelection(int startOffset, int endOffset) override { select(startOffset, endOffset); }
    QString attributes(int offset, int *startOffset, int *endOffset) const override
    {
        *startOffset = offset;
        *endOffset = offset;
        return QString();
    }
    int cursorPosition() const override { return view() ? clampInt(view()->cursorPosition()) : 0; }
    QRect characterRect(int offset) const override
    {
        AtlasTextView *v = view();
        if (!v)
            return QRect();
        const QRectF r = v->rectangleAt(offset);
        if (r.isEmpty())
            return QRect();
        return QRectF(v->mapToGlobal(r.topLeft()), r.size()).toAlignedRect();
    }
    int selectionCount() const override { return view() && view()->selectionStart() != view()->selectionEnd() ? 1 : 0; }
    int offsetAtPoint(const QPoint &point) const override
    {
        AtlasTextView *v = view();
        return v ? clampInt(v->positionAt(v->mapFromGlobal(QPointF(point)))) : 0;
    }
    void selection(int selectionIndex, int *startOffset, int *endOffset) const override
    {
        AtlasTextView *v = view();
        if (!v || selectionIndex != 0 || v->selectionStart() == v->selectionEnd()) {
            *startOffset = *endOffset = 0;
            return;
        }
        *startOffset = clampInt(v->selectionStart());
        *endOffset = clampInt(v->selectionEnd());
    }
    QString text(int startOffset, int endOffset) const override
    {
        return view() ? view()->boundedText(startOffset, endOffset, MaxAccessibleText) : QString();
    }
    void removeSelection(int selectionIndex) override
    {
        if (view() && selectionIndex == 0)
            view()->select(view()->cursorPosition(), view()->cursorPosition());
    }
    void setCursorPosition(int position) override
    {
        if (view())
            view()->setCursorPosition(position);
    }
    void setSelection(int selectionIndex, int startOffset, int endOffset) override
    {
        if (selectionIndex == 0)
            select(startOffset, endOffset);
    }
    int characterCount() const override { return view() ? clampInt(view()->length()) : 0; }
    void scrollToSubstring(int startIndex, int) override
    {
        if (view())
            view()->ensureVisible(startIndex);
    }
    QString textBeforeOffset(int offset, QAccessible::TextBoundaryType type, int *startOffset, int *endOffset) const override
    {
        return around(offset, type, -1, startOffset, endOffset);
    }
    QString textAfterOffset(int offset, QAccessible::TextBoundaryType type, int *startOffset, int *endOffset) const override
    {
        return around(offset, type, 1, startOffset, endOffset);
    }
    QString textAtOffset(int offset, QAccessible::TextBoundaryType type, int *startOffset, int *endOffset) const override
    {
        return around(offset, type, 0, startOffset, endOffset);
    }

private:
    AtlasTextView *view() const { return qobject_cast<AtlasTextView *>(object()); }
    void select(int a, int b)
    {
        if (view())
            view()->select(a, b);
    }
    // The character or line (with its break) before, at or after `offset`.
    QString around(int offset, QAccessible::TextBoundaryType type, int which, int *startOffset, int *endOffset) const
    {
        AtlasTextView *v = view();
        *startOffset = *endOffset = 0;
        if (!v)
            return QString();
        const qsizetype len = v->length();
        offset = clampInt(std::clamp<qsizetype>(offset, 0, len));
        qsizetype a = offset, b = offset;
        if (type == QAccessible::CharBoundary) {
            a = std::clamp<qsizetype>(offset + which, 0, len);
            b = std::min<qsizetype>(a + 1, len);
        } else {
            qsizetype line = v->lineColumn(offset).line + which;
            line = std::clamp<qsizetype>(line, 0, v->lineCount() - 1);
            a = v->positionOfLine(line);
            b = line + 1 < v->lineCount() ? v->positionOfLine(line + 1) : len;
        }
        if (b - a > MaxAccessibleText)
            b = std::max(a, v->alignedPosition(a + MaxAccessibleText));
        *startOffset = clampInt(a);
        *endOffset = clampInt(b);
        return v->boundedText(a, b, MaxAccessibleText);
    }
};

QAccessibleInterface *atlasTextViewFactory(const QString &className, QObject *object)
{
    if (className == QLatin1String("AtlasTextView")) {
        if (auto *v = qobject_cast<AtlasTextView *>(object))
            return new AtlasTextViewAccessible(v);
    }
    return nullptr;
}

} // namespace

// ---- The item ----

AtlasTextView::AtlasTextView(QQuickItem *parent) : QQuickItem(parent)
{
    static std::once_flag once;
    std::call_once(once, [] { QAccessible::installFactory(atlasTextViewFactory); });
    setFlag(ItemHasContents);
    setFlag(ItemIsFocusScope, false);
    setClip(true);
    setActiveFocusOnTab(true);
    setAcceptedMouseButtons(Qt::LeftButton | Qt::MiddleButton);
    setCursor(Qt::IBeamCursor);
    m_font = QFontDatabase::systemFont(QFontDatabase::FixedFont);
    const QPalette pal = QGuiApplication::palette();
    m_textColor = pal.color(QPalette::Text);
    m_selectionColor = pal.color(QPalette::Highlight);
    m_selectionColor.setAlpha(120);
    m_numberColor = m_textColor;
    m_numberColor.setAlpha(130);
    updateMetrics();
    m_buf.setLoadNotify([self = QPointer<AtlasTextView>(this)] {
        // On a worker thread, under the buffer's mutex: only post.
        if (self)
            QMetaObject::invokeMethod(self.data(), "onLoadNotify", Qt::QueuedConnection);
    });
}

AtlasTextView::~AtlasTextView()
{
    // Waits for a notification in progress; none starts afterwards.
    m_buf.setLoadNotify(nullptr);
}

void AtlasTextView::updateMetrics()
{
    const QFontMetricsF fm(m_font);
    m_rowH = std::max<qreal>(1, std::ceil(fm.lineSpacing()));
    m_cw = std::max<qreal>(1, fm.horizontalAdvance(QLatin1Char('0')));
}

qreal AtlasTextView::gutterWidth() const
{
    if (!m_lineNumbers)
        return 0;
    int digits = 1;
    for (qsizetype n = lineCount(); n >= 10; n /= 10)
        ++digits;
    return (digits + 2) * m_cw;
}

qreal AtlasTextView::textLeft() const
{
    return gutterWidth() + Pad;
}

qreal AtlasTextView::wrapWidth() const
{
    return std::max(m_cw * 2, viewWidth() - textLeft() - Pad);
}

int AtlasTextView::columnsPerRow() const
{
    return std::max(1, int(wrapWidth() / m_cw));
}

void AtlasTextView::scheduleUpdate()
{
    polish();
    update();
}

// ---- Rows and positions ----

void AtlasTextView::ensureRows() const
{
    if (!m_wrap)
        return;
    const qsizetype n = lineCount();
    if (!m_rowsValid) {
        m_rows.reset(n);
        m_rowsValid = true;
    } else if (m_rows.lines() != n) {
        m_rows.resize(n);
    }
}

qsizetype AtlasTextView::lineRowCount(qsizetype line) const
{
    if (!m_wrap)
        return 1;
    ensureRows();
    return m_rows.rows(std::clamp<qsizetype>(line, 0, lineCount() - 1));
}

qsizetype AtlasTextView::lineAtY(qreal y) const
{
    const qsizetype lines = lineCount();
    if (y <= 0 || lines <= 1)
        return 0;
    if (!m_wrap)
        return std::min<qsizetype>(lines - 1, qsizetype(y / m_rowH));
    ensureRows();
    return m_rows.lineAtRow(qint64(y / m_rowH));
}

qreal AtlasTextView::lineTop(qsizetype line) const
{
    line = std::clamp<qsizetype>(line, 0, lineCount() - 1);
    if (!m_wrap)
        return qreal(line) * m_rowH;
    ensureRows();
    return qreal(m_rows.before(line)) * m_rowH;
}

qreal AtlasTextView::lineY(qsizetype line) const
{
    return lineTop(line);
}

qreal AtlasTextView::contentHeight() const
{
    if (!m_wrap)
        return qreal(lineCount()) * m_rowH;
    ensureRows();
    return qreal(m_rows.total()) * m_rowH;
}

qreal AtlasTextView::contentWidth() const
{
    if (m_wrap)
        return viewWidth();
    return textLeft() + qreal(m_maxCols) * m_cw + Pad * 2;
}

qreal AtlasTextView::maxContentY() const
{
    return std::max<qreal>(0, contentHeight() - viewHeight());
}

qsizetype AtlasTextView::firstVisibleLine() const
{
    return lineAtY(m_contentY);
}

qsizetype AtlasTextView::lastVisibleLine() const
{
    return lineAtY(m_contentY + std::max<qreal>(0, viewHeight() - 1));
}

qsizetype AtlasTextView::positionOfLine(qsizetype line) const
{
    return m_buf.tree().lineStart(line);
}

AtlasText::LineColumn AtlasTextView::lineColumn(qsizetype position) const
{
    const TextTree &t = m_buf.tree();
    position = std::clamp<qsizetype>(position, 0, t.length());
    AtlasText::LineColumn lc;
    lc.line = t.lineAt(position);
    lc.column = position - t.lineStart(lc.line);
    return lc;
}

void AtlasTextView::lineExtent(qsizetype line, qsizetype *start, qsizetype *len, qsizetype *breakLen) const
{
    const TextTree &t = m_buf.tree();
    const qsizetype lines = t.lineCount();
    line = std::clamp<qsizetype>(line, 0, lines - 1);
    *start = t.lineStart(line);
    const qsizetype next = line + 1 < lines ? t.lineStart(line + 1) : t.length();
    const qsizetype full = next - *start;
    qsizetype brk = 0;
    if (line + 1 < lines) {
        brk = 1;
        if (full >= 2 && t.text(next - 2, next) == QLatin1String("\r\n"))
            brk = 2;
    }
    *breakLen = brk;
    *len = full - brk;
}

// ---- Highlighting ----

bool AtlasTextView::lineStatesTo(qsizetype line) const
{
    if (!m_highlighter)
        return false;
    if (qsizetype(m_states.size()) >= line)
        return true;
    if (line - qsizetype(m_states.size()) > MaxStateGap)
        return false;
    while (qsizetype(m_states.size()) < line) {
        const qsizetype l = qsizetype(m_states.size());
        qsizetype start, len, brk;
        lineExtent(l, &start, &len, &brk);
        const int startState = l == 0 ? m_highlighter->initialState() : m_states[size_t(l - 1)];
        int end = startState;
        if (len <= m_highlightLimit) {
            QList<AtlasText::FormatRun> runs;
            end = m_highlighter->highlightLine(startState, m_buf.tree().text(start, start + len), &runs);
        }
        m_states.push_back(end);
    }
    return true;
}

bool AtlasTextView::runsFor(qsizetype line, QList<AtlasText::FormatRun> *runs) const
{
    if (!m_highlighter || !lineStatesTo(line))
        return false;
    qsizetype start, len, brk;
    lineExtent(line, &start, &len, &brk);
    if (len > m_highlightLimit)
        return false;
    const int startState = line == 0 ? m_highlighter->initialState() : m_states[size_t(line - 1)];
    m_highlighter->highlightLine(startState, m_buf.tree().text(start, start + len), runs);
    return true;
}

void AtlasTextView::applyHighlight(LineBox &box, qsizetype line) const
{
    if (box.sliceStart != 0 || box.sliceEnd != box.len)
        return; // a window of a long line is shown in the plain style
    QList<AtlasText::FormatRun> runs;
    if (!runsFor(line, &runs))
        return;
    QList<QTextLayout::FormatRange> formats;
    for (const AtlasText::FormatRun &r : std::as_const(runs)) {
        if (r.length <= 0 || r.start < 0 || r.start >= box.len)
            continue;
        QTextCharFormat f;
        if (r.format.foreground.isValid())
            f.setForeground(r.format.foreground);
        if (r.format.background.isValid())
            f.setBackground(r.format.background);
        if (r.format.bold)
            f.setFontWeight(QFont::Bold);
        f.setFontItalic(r.format.italic);
        f.setFontUnderline(r.format.underline);
        f.setFontStrikeOut(r.format.strikeOut);
        QTextLayout::FormatRange fr;
        fr.start = int(r.start);
        fr.length = int(std::min(r.length, box.len - r.start));
        fr.format = f;
        formats.append(fr);
    }
    box.layout->setFormats(formats);
}

AtlasText::Format AtlasTextView::formatAt(qsizetype position) const
{
    AtlasText::Format none;
    const AtlasText::LineColumn lc = lineColumn(position);
    QList<AtlasText::FormatRun> runs;
    if (!runsFor(lc.line, &runs))
        return none;
    for (const AtlasText::FormatRun &r : std::as_const(runs)) {
        if (lc.column >= r.start && lc.column < r.start + r.length)
            return r.format;
    }
    return none;
}

void AtlasTextView::setHighlighter(std::shared_ptr<const AtlasTextHighlighterInterface> highlighter)
{
    m_highlighter = std::move(highlighter);
    rehighlight();
}

void AtlasTextView::rehighlight()
{
    m_states.clear();
    invalidateLayouts();
    scheduleUpdate();
}

void AtlasTextView::rehighlight(qsizetype firstLine, qsizetype lastLine)
{
    Q_UNUSED(lastLine);
    firstLine = std::clamp<qsizetype>(firstLine, 0, lineCount() - 1);
    if (qsizetype(m_states.size()) > firstLine)
        m_states.resize(size_t(firstLine));
    invalidateLayouts();
    scheduleUpdate();
}

void AtlasTextView::setSyntax(const QString &name)
{
    if (m_syntax == name)
        return;
    m_syntax = name; // the built-in highlighter is step 1c; a name is only kept
    emit syntaxChanged();
}

void AtlasTextView::setSyntaxTheme(const QString &name)
{
    if (m_syntaxTheme == name)
        return;
    m_syntaxTheme = name;
    emit syntaxThemeChanged();
}

void AtlasTextView::setHighlightLimit(qsizetype units)
{
    units = std::max<qsizetype>(0, units);
    if (m_highlightLimit == units)
        return;
    m_highlightLimit = units;
    emit highlightLimitChanged();
    rehighlight();
}

// ---- Layout ----

void AtlasTextView::invalidateLayouts()
{
    ++m_generation;
    m_cache.clear();
}

LineBox &AtlasTextView::layoutLine(qsizetype line) const
{
    const TextTree &t = m_buf.tree();
    line = std::clamp<qsizetype>(line, 0, t.lineCount() - 1);
    auto &slot = m_cache[line];
    if (!slot)
        slot = std::make_unique<LineBox>();
    LineBox &b = *slot;

    qsizetype start, len, brk;
    lineExtent(line, &start, &len, &brk);
    const bool isLong = len > LongLine;
    // What the window of a long line has to cover now, and what it asks for.
    qsizetype needS = 0, needE = len, ss = 0, se = len;
    int rowOff = 0;
    if (isLong) {
        if (!m_wrap) {
            const qsizetype c0 = qsizetype(m_contentX / m_cw);
            const qsizetype cols = qsizetype(viewWidth() / m_cw) + 2;
            needS = std::max<qsizetype>(0, c0 - 2);
            needE = std::min(len, c0 + cols + 2);
            ss = std::max<qsizetype>(0, c0 - 512);
            se = std::min(len, c0 + cols + 512);
        } else {
            const qsizetype cpr = columnsPerRow();
            const qsizetype r0 = std::max<qsizetype>(0, qsizetype((m_contentY - lineTop(line)) / m_rowH));
            const qsizetype rows = qsizetype(viewHeight() / m_rowH) + 2;
            const qsizetype r0m = std::max<qsizetype>(0, r0 - 4);
            needS = std::min(len, r0 * cpr);
            needE = std::min(len, (r0 + rows) * cpr);
            ss = std::min(len, r0m * cpr);
            se = std::min(len, (r0 + rows + 4) * cpr);
            rowOff = int(r0m);
        }
    }
    if (b.layout && b.revision == m_buf.revision() && b.generation == m_generation && b.start == start && b.len == len
        && b.sliceStart <= needS && b.sliceEnd >= needE)
        return b;

    if (isLong) {
        ss = t.alignDown(start + ss) - start;
        se = t.alignUp(start + se) - start;
    }
    b.start = start;
    b.len = len;
    b.breakLen = brk;
    b.sliceStart = ss;
    b.sliceEnd = se;
    b.rowOffset = rowOff;
    b.revision = m_buf.revision();
    b.generation = m_generation;
    b.layout = std::make_unique<QTextLayout>(t.text(start + ss, start + se), m_font);
    QTextOption o;
    o.setTabStopDistance(m_tabWidth * m_cw);
    o.setWrapMode(!m_wrap ? QTextOption::NoWrap : isLong ? QTextOption::WrapAnywhere : QTextOption::WrapAtWordBoundaryOrAnywhere);
    b.layout->setTextOption(o);
    applyHighlight(b, line);
    const qreal w = m_wrap ? wrapWidth() : 1e7;
    b.layout->beginLayout();
    qreal y = 0;
    for (;;) {
        QTextLine tl = b.layout->createLine();
        if (!tl.isValid())
            break;
        tl.setLineWidth(w);
        tl.setPosition(QPointF(0, y));
        y += m_rowH;
    }
    b.layout->endLayout();
    if (m_wrap) {
        ensureRows();
        const qsizetype cpr = columnsPerRow();
        const int rows = isLong ? int(std::min<qsizetype>(1 << 28, (len + cpr - 1) / cpr)) : b.layout->lineCount();
        m_rows.set(line, rows);
    } else {
        // Columns, with the tab stops counted; a long line's window is only part of it.
        const qsizetype cols = isLong ? len : qsizetype(std::ceil(b.layout->maximumWidth() / m_cw));
        m_maxCols = std::max(m_maxCols, std::max(cols, len > 0 ? qsizetype(1) : qsizetype(0)));
    }
    return b;
}

QRectF AtlasTextView::contentRectOf(qsizetype position) const
{
    const TextTree &t = m_buf.tree();
    position = std::clamp<qsizetype>(position, 0, t.length());
    const qsizetype line = t.lineAt(position);
    const LineBox &b = layoutLine(line);
    const qsizetype local = std::clamp<qsizetype>(position - b.start, 0, b.len);
    const qreal top = lineTop(line);
    if (local >= b.sliceStart && local <= b.sliceEnd && b.layout->lineCount() > 0) {
        const int l = int(local - b.sliceStart);
        const QTextLine tl = b.layout->lineForTextPosition(l);
        if (tl.isValid()) {
            const qreal x = tl.cursorToX(l);
            const qreal ox = m_wrap ? 0 : qreal(b.sliceStart) * m_cw;
            const qreal y = top + qreal(b.rowOffset) * m_rowH + tl.y();
            qreal w = 1;
            if (local < b.len && l < b.layout->text().size()) {
                const QString &s = b.layout->text();
                const int next = (l + 1 < s.size() && s[l].isHighSurrogate() && s[l + 1].isLowSurrogate()) ? l + 2 : l + 1;
                w = std::max<qreal>(1, tl.cursorToX(next) - x);
                if (s[l] == u'\t' && w <= 0)
                    w = m_cw;
            }
            return QRectF(ox + x, y, w, m_rowH);
        }
    }
    // Outside the laid-out window (or an empty layout): the monospace estimate.
    if (m_wrap) {
        const qsizetype cpr = columnsPerRow();
        return QRectF(qreal(local % cpr) * m_cw, top + qreal(local / cpr) * m_rowH, local < b.len ? m_cw : 1, m_rowH);
    }
    return QRectF(qreal(local) * m_cw, top, local < b.len ? m_cw : 1, m_rowH);
}

QRectF AtlasTextView::rectangleAt(qsizetype position) const
{
    const TextTree &t = m_buf.tree();
    position = std::clamp<qsizetype>(position, 0, t.length());
    const qsizetype line = t.lineAt(position);
    const qreal top = lineTop(line);
    if (top > m_contentY + 2 * viewHeight() || top + qreal(lineRowCount(line)) * m_rowH < m_contentY - viewHeight())
        return QRectF(); // not laid out: not near the viewport
    const QRectF r = contentRectOf(position);
    return QRectF(r.x() + textLeft() - m_contentX, r.y() - m_contentY, r.width(), r.height());
}

QRectF AtlasTextView::cursorRectangle() const
{
    return rectangleAt(m_cursor);
}

qsizetype AtlasTextView::positionAt(const QPointF &p) const
{
    const TextTree &t = m_buf.tree();
    const qreal cy = std::max<qreal>(0, p.y() + m_contentY);
    const qsizetype line = lineAtY(cy);
    const LineBox &b = layoutLine(line);
    if (b.layout->lineCount() == 0)
        return b.start;
    const int row = std::clamp(int((cy - lineTop(line)) / m_rowH) - b.rowOffset, 0, b.layout->lineCount() - 1);
    const qreal ox = m_wrap ? 0 : qreal(b.sliceStart) * m_cw;
    const qreal x = p.x() + m_contentX - textLeft() - ox;
    const int cp = b.layout->lineAt(row).xToCursor(x, QTextLine::CursorBetweenCharacters);
    const qsizetype pos = std::clamp<qsizetype>(b.start + b.sliceStart + cp, b.start, b.start + b.len);
    return t.alignDown(pos);
}

void AtlasTextView::geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry)
{
    QQuickItem::geometryChange(newGeometry, oldGeometry);
    if (newGeometry.size() == oldGeometry.size())
        return;
    if (m_wrap && newGeometry.width() != oldGeometry.width()) {
        recordAnchor();
        m_rowsValid = false;
    }
    invalidateLayouts();
    scheduleUpdate();
}

// Remembers the line at the top of the view, from the rows as they are now:
// call it before anything that measures the rows again.
void AtlasTextView::recordAnchor()
{
    if (m_anchorLine >= 0 || (m_wrap && !m_rowsValid))
        return;
    m_anchorLine = lineAtY(m_contentY);
    m_anchorRows = (m_contentY - lineTop(m_anchorLine)) / m_rowH;
}

void AtlasTextView::updatePolish()
{
    if (m_cache.size() > size_t(MaxLayouts))
        m_cache.clear();
    const qreal shownY = m_contentY;
    qsizetype aLine;
    qreal aOff;
    if (m_anchorLine >= 0) {
        // The rows were measured again: put the same line back at the top. The
        // line is kept as it is: the offset can be past the one row it has until
        // it is laid out.
        aLine = std::min(m_anchorLine, lineCount() - 1);
        aOff = m_anchorRows * m_rowH;
        m_contentY = lineTop(aLine) + aOff;
        m_anchorLine = -1;
        m_anchorRows = 0;
    } else {
        aLine = lineAtY(m_contentY);
        aOff = m_contentY - lineTop(aLine);
    }
    const qsizetype lo = lineAtY(std::max<qreal>(0, m_contentY - viewHeight()));
    const qsizetype hi = std::min(lineAtY(m_contentY + 2 * viewHeight()), lo + 300);
    for (qsizetype l = lo; l <= hi; ++l)
        layoutLine(l);
    qreal ny = m_contentY;
    if (m_wrap)
        ny = lineTop(aLine) + aOff;
    if (m_pinned && m_follow)
        ny = maxContentY();
    ny = std::clamp<qreal>(ny, 0, maxContentY());
    m_contentY = ny;
    const qreal maxX = m_wrap ? 0 : std::max<qreal>(0, contentWidth() - viewWidth());
    const qreal nx = std::clamp<qreal>(m_contentX, 0, maxX);
    if (nx != m_contentX) {
        m_contentX = nx;
        emit contentXChanged();
    }
    if (ny != shownY) {
        emit contentYChanged();
        polish(); // lay out around the new position
    }
    const qreal cw = contentWidth(), ch = contentHeight();
    if (cw != m_lastContentW) {
        m_lastContentW = cw;
        emit contentWidthChanged();
    }
    if (ch != m_lastContentH) {
        m_lastContentH = ch;
        emit contentHeightChanged();
    }
    const qsizetype f = firstVisibleLine(), l = lastVisibleLine();
    if (f != m_firstSignalled || l != m_lastSignalled) {
        m_firstSignalled = f;
        m_lastSignalled = l;
        emit visibleRangeChanged();
    }
    update();
}

// ---- Painting ----

QSGNode *AtlasTextView::updatePaintNode(QSGNode *old, UpdatePaintNodeData *)
{
    QSGNode *root = old ? old : new QSGNode;
    while (QSGNode *c = root->firstChild()) {
        root->removeChildNode(c);
        delete c;
    }
    if (!window() || width() <= 0 || height() <= 0)
        return root;

    const TextTree &t = m_buf.tree();
    // The text, the selection and the caret are clipped at the gutter's edge,
    // so a scrolled line does not slide under the numbers. The current-line
    // tint spans the whole width and goes below, the numbers on top.
    QSGNode *under = new QSGNode;
    root->appendChildNode(under);
    QSGNode *body = root;
    if (m_lineNumbers) {
        const qreal gw = std::min(gutterWidth(), width());
        QSGClipNode *clip = new QSGClipNode;
        clip->setIsRectangular(true);
        clip->setClipRect(QRectF(gw, 0, width() - gw, height()));
        root->appendChildNode(clip);
        body = clip;
    }
    QSGNode *numbers = new QSGNode;
    root->appendChildNode(numbers);
    auto addRectTo = [&](QSGNode *parent, const QRectF &r, const QColor &c) {
        if (r.width() <= 0 || r.height() <= 0 || !c.isValid())
            return;
        QSGRectangleNode *n = window()->createRectangleNode();
        n->setRect(r);
        n->setColor(c);
        parent->appendChildNode(n);
    };
    auto addRect = [&](const QRectF &r, const QColor &c) { addRectTo(body, r, c); };
    const qsizetype lo = firstVisibleLine(), hi = lastVisibleLine();
    const qsizetype selA = selectionStart(), selB = selectionEnd();
    const qsizetype cursorLine = t.lineAt(m_cursor);
    const qreal left = textLeft();

    for (qsizetype line = lo; line <= hi; ++line) {
        const LineBox &b = layoutLine(line);
        const qreal top = lineTop(line) - m_contentY;
        const qreal ox = left - m_contentX + (m_wrap ? 0 : qreal(b.sliceStart) * m_cw);
        const qreal oy = top + qreal(b.rowOffset) * m_rowH;
        const int rowsHere = int(lineRowCount(line));

        // The rectangles of [a, b) (positions) in this line.
        auto rangeRects = [&](qsizetype a, qsizetype e, bool withBreak, auto &&out) {
            const qsizetype la = std::max(a, b.start + b.sliceStart), lb = std::min(e, b.start + b.sliceEnd);
            const int n = b.layout->lineCount();
            for (int i = 0; i < n; ++i) {
                const QTextLine tl = b.layout->lineAt(i);
                const qsizetype s = b.start + b.sliceStart + tl.textStart();
                const qsizetype en = s + tl.textLength();
                const qsizetype ra = std::max(la, s), rb = std::min(lb, en);
                if (ra < rb) {
                    const qreal x1 = tl.cursorToX(int(ra - b.start - b.sliceStart));
                    const qreal x2 = tl.cursorToX(int(rb - b.start - b.sliceStart));
                    out(QRectF(ox + std::min(x1, x2), oy + tl.y(), std::abs(x2 - x1), m_rowH));
                }
                if (withBreak && i == n - 1) {
                    const qreal xe = tl.cursorToX(int(tl.textStart() + tl.textLength()));
                    out(QRectF(ox + xe, oy + tl.y(), m_cw, m_rowH));
                }
            }
            if (n == 0 && withBreak)
                out(QRectF(ox, oy, m_cw, m_rowH));
        };

        if (m_currentLine && line == cursorLine && selA == selB) {
            QColor c = m_textColor;
            c.setAlpha(22);
            addRectTo(under, QRectF(0, top, width(), qreal(rowsHere) * m_rowH), c);
        }
        // Decorations of every layer that touch this line.
        const qsizetype lineEnd = b.start + b.len;
        for (const Decorations &d : m_layers) {
            auto it = std::lower_bound(d.ranges.begin(), d.ranges.end(), b.start - d.longest, [](const AtlasText::Range &r, qsizetype v) { return r.start < v; });
            for (; it != d.ranges.end() && it->start <= lineEnd; ++it) {
                if (it->end <= b.start || it->start >= it->end)
                    continue;
                QColor c;
                switch (d.style) {
                case AtlasText::DecorationStyle::Match: c = QColor(255, 213, 79, 100); break;
                case AtlasText::DecorationStyle::CurrentMatch: c = QColor(255, 152, 0, 170); break;
                case AtlasText::DecorationStyle::Bracket: c = QColor(128, 128, 128, 110); break;
                case AtlasText::DecorationStyle::CurrentLine: c = QColor(128, 128, 128, 40); break;
                case AtlasText::DecorationStyle::Error: c = QColor(229, 57, 53, 70); break;
                case AtlasText::DecorationStyle::Warning: c = QColor(255, 179, 0, 70); break;
                case AtlasText::DecorationStyle::Info: c = QColor(30, 136, 229, 70); break;
                case AtlasText::DecorationStyle::Spelling: c = QColor(229, 57, 53); break;
                }
                if (d.style == AtlasText::DecorationStyle::Spelling) {
                    rangeRects(it->start, it->end, false, [&](const QRectF &r) {
                        const qreal step = std::max<qreal>(2, m_cw / 2);
                        int i = 0;
                        for (qreal x = r.left(); x < r.right() && i < 400; x += step, ++i)
                            addRect(QRectF(x, r.bottom() - 3 + (i % 2) * 1.5, std::min(step, r.right() - x), 1.5), c);
                    });
                } else {
                    rangeRects(it->start, it->end, false, [&](const QRectF &r) { addRect(r, c); });
                }
            }
        }
        if (selA < selB && selB > b.start && selA <= lineEnd + b.breakLen) {
            const qsizetype a = std::max(selA, b.start), e = std::min(selB, lineEnd + b.breakLen);
            rangeRects(a, std::min(e, lineEnd), e > lineEnd && b.breakLen > 0, [&](const QRectF &r) { addRect(r, m_selectionColor); });
        }
        QSGTextNode *tn = window()->createTextNode();
        tn->setColor(m_textColor);
        tn->addTextLayout(QPointF(ox, oy), b.layout.get());
        body->appendChildNode(tn);

        if (m_lineNumbers) {
            QTextLayout nl(QString::number(line + 1), m_font);
            nl.beginLayout();
            QTextLine l = nl.createLine();
            l.setLineWidth(1e5);
            l.setPosition(QPointF(0, 0));
            nl.endLayout();
            QSGTextNode *gn = window()->createTextNode();
            gn->setColor(m_numberColor);
            gn->addTextLayout(QPointF(gutterWidth() - m_cw - l.naturalTextWidth(), top), &nl);
            numbers->appendChildNode(gn);
        }
    }
    if (hasActiveFocus() && selA == selB) {
        const QRectF r = cursorRectangle();
        if (!r.isEmpty())
            addRect(QRectF(r.x(), r.y(), 1.5, r.height()), m_textColor);
    }
    return root;
}

// ---- Properties ----

QString AtlasTextView::text() const
{
    const TextTree &t = m_buf.tree();
    try {
        return t.text(0, t.length());
    } catch (const std::bad_alloc &) {
        qWarning("AtlasTextView: not enough memory to build the whole text");
        return QString();
    }
}

QString AtlasTextView::textInRange(qsizetype start, qsizetype end) const
{
    try {
        return m_buf.tree().text(start, end);
    } catch (const std::bad_alloc &) {
        qWarning("AtlasTextView: not enough memory to build the text range");
        return QString();
    }
}

QString AtlasTextView::boundedText(qsizetype start, qsizetype end, qsizetype limit) const
{
    const TextTree &t = m_buf.tree();
    start = std::clamp<qsizetype>(start, 0, t.length());
    end = std::clamp<qsizetype>(end, start, t.length());
    if (end - start > limit)
        end = std::max(start, t.alignDown(start + limit));
    return textInRange(start, end);
}

// Over MaxSelectionText units it is empty: a notifying property must not build
// a whole huge file whenever the selection changes. hasSelection tells whether
// there is one, and copy() has the same limit.
QString AtlasTextView::selectedText() const
{
    if (selectionEnd() - selectionStart() > MaxSelectionText)
        return QString();
    return textInRange(selectionStart(), selectionEnd());
}

void AtlasTextView::setReadOnly(bool readOnly)
{
    // The view is read-only until step 2; the flag is kept for the interface.
    if (m_readOnly == readOnly)
        return;
    m_readOnly = readOnly;
    emit readOnlyChanged();
}

void AtlasTextView::setUndoLimit(int limit)
{
    limit = std::max(0, limit);
    if (m_undoLimit == limit)
        return;
    m_undoLimit = limit;
    emit undoLimitChanged();
}

void AtlasTextView::setWrap(bool wrap)
{
    if (m_wrap == wrap)
        return;
    recordAnchor();
    m_wrap = wrap;
    m_rowsValid = false;
    m_contentX = 0;
    invalidateLayouts();
    emit wrapChanged();
    scheduleUpdate();
}

void AtlasTextView::setTabWidth(int columns)
{
    columns = std::clamp(columns, 1, 32);
    if (m_tabWidth == columns)
        return;
    m_tabWidth = columns;
    invalidateLayouts();
    emit tabWidthChanged();
    scheduleUpdate();
}

void AtlasTextView::setShowLineNumbers(bool show)
{
    if (m_lineNumbers == show)
        return;
    recordAnchor();
    m_lineNumbers = show;
    invalidateLayouts();
    m_rowsValid = false;
    emit showLineNumbersChanged();
    scheduleUpdate();
}

void AtlasTextView::setHighlightCurrentLine(bool highlight)
{
    if (m_currentLine == highlight)
        return;
    m_currentLine = highlight;
    emit highlightCurrentLineChanged();
    update();
}

void AtlasTextView::setFont(const QFont &font)
{
    if (m_font == font)
        return;
    recordAnchor();
    m_font = font;
    updateMetrics();
    m_rowsValid = false;
    m_maxCols = 0;
    invalidateLayouts();
    emit fontChanged();
    scheduleUpdate();
}

void AtlasTextView::setTextColor(const QColor &c)
{
    m_textColor = c;
    emit colorsChanged();
    update();
}

void AtlasTextView::setSelectionColor(const QColor &c)
{
    m_selectionColor = c;
    emit colorsChanged();
    update();
}

void AtlasTextView::setLineNumberColor(const QColor &c)
{
    m_numberColor = c;
    emit colorsChanged();
    update();
}

void AtlasTextView::setFollow(bool follow)
{
    if (m_follow == follow)
        return;
    m_follow = follow;
    m_pinned = follow && atBottom();
    emit followChanged();
}

void AtlasTextView::setMaximumLines(qsizetype lines)
{
    lines = std::max<qsizetype>(0, lines);
    if (m_maxLines == lines)
        return;
    m_maxLines = lines;
    emit maximumLinesChanged();
    applyMaximumLines();
}

void AtlasTextView::setContentX(qreal x)
{
    const qreal nx = m_wrap ? 0 : std::clamp<qreal>(x, 0, std::max<qreal>(0, contentWidth() - viewWidth()));
    if (nx == m_contentX)
        return;
    m_contentX = nx;
    emit contentXChanged();
    scheduleUpdate();
}

void AtlasTextView::setContentY(qreal y)
{
    const qreal ny = std::clamp<qreal>(y, 0, maxContentY());
    if (ny == m_contentY)
        return;
    m_contentY = ny;
    m_pinned = m_follow && atBottom();
    emit contentYChanged();
    scheduleUpdate();
}

bool AtlasTextView::atBottom() const
{
    return m_contentY >= maxContentY() - 1;
}

// ---- Decorations ----

void AtlasTextView::setDecorations(const QString &layer, const QList<AtlasText::Range> &ranges, AtlasText::DecorationStyle style)
{
    clearDecorations(layer);
    if (ranges.isEmpty())
        return;
    Decorations d;
    d.layer = layer;
    d.style = style;
    const qsizetype n = length();
    for (const AtlasText::Range &r : ranges) {
        AtlasText::Range c{std::clamp<qsizetype>(std::min(r.start, r.end), 0, n), std::clamp<qsizetype>(std::max(r.start, r.end), 0, n)};
        if (c.start < c.end) {
            d.ranges.push_back(c);
            d.longest = std::max(d.longest, c.end - c.start);
        }
    }
    std::sort(d.ranges.begin(), d.ranges.end(), [](const AtlasText::Range &a, const AtlasText::Range &b) { return a.start < b.start; });
    if (!d.ranges.empty())
        m_layers.push_back(std::move(d));
    update();
}

void AtlasTextView::setDecorationPairs(const QString &layer, const QVariantList &pairs, int style)
{
    QList<AtlasText::Range> ranges;
    for (qsizetype i = 0; i + 1 < pairs.size(); i += 2)
        ranges.append({pairs[i].toLongLong(), pairs[i + 1].toLongLong()});
    setDecorations(layer, ranges, AtlasText::DecorationStyle(std::clamp(style, 0, 7)));
}

void AtlasTextView::clearDecorations(const QString &layer)
{
    const auto it = std::remove_if(m_layers.begin(), m_layers.end(), [&](const Decorations &d) { return d.layer == layer; });
    if (it != m_layers.end()) {
        m_layers.erase(it, m_layers.end());
        update();
    }
}

// ---- Loading ----

void AtlasTextView::documentChanged(bool appended, qsizetype oldLength, qsizetype oldLines, qsizetype droppedLines)
{
    m_cache.clear();
    ++m_generation;
    if (droppedLines > 0) {
        // Lines went from the front: keep the rows of the rest and the widest line.
        if (m_wrap && m_rowsValid)
            m_rows.dropFront(droppedLines);
        m_states.clear();
    } else if (!appended) {
        m_rowsValid = false;
        m_states.clear();
        m_maxCols = 0;
    } else if (qsizetype(m_states.size()) > oldLines - 1) {
        m_states.resize(size_t(std::max<qsizetype>(0, oldLines - 1)));
    }
    const qsizetype n = length();
    m_cursor = std::min(m_cursor, n);
    m_anchor = std::min(m_anchor, n);
    if (n != oldLength)
        emit lengthChanged();
    if (lineCount() != oldLines)
        emit lineCountChanged();
    emit textChanged();
    emit lineEndingChanged();
    scheduleUpdate();
}

// The text was replaced or cleared: tell the screen readers. The texts are the
// first part only, as appendText does.
void AtlasTextView::notifyReplaced(const QString &oldHead)
{
    if (!QAccessible::isActive())
        return;
    if (!oldHead.isEmpty()) {
        QAccessibleTextRemoveEvent ev(this, 0, oldHead);
        QAccessible::updateAccessibility(&ev);
    }
    if (length() > 0) {
        QAccessibleTextInsertEvent ev(this, 0, textInRange(0, 4096));
        QAccessible::updateAccessibility(&ev);
    }
}

void AtlasTextView::beginLoad()
{
    const qsizetype oldLen = length(), oldLines = lineCount();
    const bool wasLoading = m_loading;
    const QString oldHead = QAccessible::isActive() ? textInRange(0, 4096) : QString();
    if (!wasLoading)
        m_loadOldLength = oldLen;
    m_buf.beginLoad();
    m_loading = true;
    m_inputEnded = false;
    m_pinned = false;
    m_anchorLine = -1;
    m_layers.clear();
    m_contentX = m_contentY = 0;
    setCursorAndAnchor(0, 0);
    documentChanged(false, oldLen, oldLines);
    notifyReplaced(oldHead);
    emit contentXChanged();
    emit contentYChanged();
    if (!wasLoading)
        emit loadingChanged();
    emit loadProgressChanged();
    emit hadInvalidTextChanged();
    emit loadFailedChanged();
}

void AtlasTextView::appendData(const char *utf8, qsizetype size)
{
    if (!m_loading || m_inputEnded || !utf8 || size <= 0)
        return;
    m_buf.appendData(utf8, size);
    emit loadProgressChanged();
}

void AtlasTextView::appendBytes(const QByteArray &utf8)
{
    if (!m_loading || m_inputEnded || utf8.isEmpty())
        return;
    m_buf.appendData(utf8); // shares the bytes: a big chunk is not copied
    emit loadProgressChanged();
}

void AtlasTextView::onLoadNotify()
{
    if (!m_loading)
        return;
    const qsizetype oldLen = length(), oldLines = lineCount();
    const quint64 oldRevision = m_buf.revision();
    const bool done = m_buf.pollLoad();
    if (m_buf.revision() != oldRevision)
        documentChanged(true, oldLen, oldLines);
    emit loadProgressChanged();
    if (done)
        finishLoad(m_loadOldLength);
}

void AtlasTextView::endLoad()
{
    if (!m_loading || m_inputEnded)
        return;
    m_inputEnded = true;
    const qsizetype oldLen = length(), oldLines = lineCount();
    const quint64 oldRevision = m_buf.revision();
    const bool done = m_buf.endLoad(false);
    if (m_buf.revision() != oldRevision)
        documentChanged(true, oldLen, oldLines);
    if (done)
        finishLoad(m_loadOldLength);
}

void AtlasTextView::finishLoad(qsizetype oldLength)
{
    m_loading = false;
    emit loadingChanged();
    emit loadProgressChanged();
    emit hadInvalidTextChanged();
    emit loadFailedChanged();
    // The text arrived in pieces that were not reported one by one.
    if (QAccessible::isActive() && length() > 0) {
        QAccessibleTextInsertEvent ev(this, 0, textInRange(0, 4096));
        QAccessible::updateAccessibility(&ev);
    }
    emit contentsChange(0, oldLength, length());
    applyMaximumLines();
    emit loaded();
}

void AtlasTextView::setText(const QString &text)
{
    const qsizetype oldLen = loading() ? m_loadOldLength : length(), oldLines = lineCount();
    const bool wasLoading = m_loading;
    const QString oldHead = QAccessible::isActive() ? textInRange(0, 4096) : QString();
    m_buf.setText(text);
    m_loading = false;
    m_inputEnded = true;
    m_contentX = m_contentY = 0;
    m_pinned = false;
    m_anchorLine = -1;
    m_layers.clear();
    setCursorAndAnchor(0, 0);
    documentChanged(false, oldLen, oldLines);
    notifyReplaced(oldHead);
    if (wasLoading)
        emit loadingChanged();
    emit contentXChanged();
    emit contentYChanged();
    emit hadInvalidTextChanged();
    emit loadFailedChanged();
    emit contentsChange(0, oldLen, length());
    applyMaximumLines();
    emit loaded();
}

void AtlasTextView::markSaved(quint64)
{
    // Nothing to clear: the read-only view is never modified.
}

void AtlasTextView::appendText(const QString &text)
{
    if (m_loading || text.isEmpty())
        return;
    const bool wasBottom = atBottom();
    const qsizetype oldLen = length(), oldLines = lineCount();
    m_buf.insert(oldLen, text);
    documentChanged(true, oldLen, oldLines);
    if (QAccessible::isActive()) {
        QAccessibleTextInsertEvent ev(this, int(oldLen), text.left(4096));
        QAccessible::updateAccessibility(&ev);
    }
    emit contentsChange(oldLen, 0, length() - oldLen);
    applyMaximumLines();
    if (m_follow && wasBottom) {
        m_pinned = true;
        setContentY(maxContentY());
    }
}

void AtlasTextView::applyMaximumLines()
{
    if (m_maxLines <= 0 || m_loading || lineCount() <= m_maxLines)
        return;
    const qsizetype drop = lineCount() - m_maxLines;
    const qsizetype cut = positionOfLine(drop);
    const qsizetype oldLen = length(), oldLines = lineCount();
    // The height of what goes: its real rows when they are measured.
    qint64 droppedRows = drop;
    if (m_wrap && m_rowsValid) {
        ensureRows();
        droppedRows = m_rows.before(drop);
    }
    const QString head = QAccessible::isActive() ? textInRange(0, std::min<qsizetype>(cut, 4096)) : QString();
    m_buf.remove(0, cut);
    m_cursor = std::max<qsizetype>(0, m_cursor - cut);
    m_anchor = std::max<qsizetype>(0, m_anchor - cut);
    if (!m_pinned)
        m_contentY = std::max<qreal>(0, m_contentY - qreal(droppedRows) * m_rowH);
    documentChanged(false, oldLen, oldLines, drop);
    if (QAccessible::isActive() && !head.isEmpty()) {
        QAccessibleTextRemoveEvent ev(this, 0, head);
        QAccessible::updateAccessibility(&ev);
    }
    emit contentsChange(0, cut, 0);
    emit selectionChanged();
    emit cursorPositionChanged();
}

// ---- Selection, caret and keys ----

void AtlasTextView::setCursorAndAnchor(qsizetype cursor, qsizetype anchor, bool keepGoal)
{
    const qsizetype n = length();
    cursor = m_buf.tree().alignDown(std::clamp<qsizetype>(cursor, 0, n));
    anchor = m_buf.tree().alignDown(std::clamp<qsizetype>(anchor, 0, n));
    const bool cursorMoved = cursor != m_cursor;
    const bool selChanged = anchor != m_anchor || cursorMoved;
    m_cursor = cursor;
    m_anchor = anchor;
    if (!keepGoal)
        m_goalX = -1;
    if (cursorMoved) {
        emit cursorPositionChanged();
        if (QAccessible::isActive()) {
            QAccessibleTextCursorEvent ev(this, clampInt(cursor));
            QAccessible::updateAccessibility(&ev);
        }
    }
    if (selChanged) {
        emit selectionChanged();
        update();
    }
}

void AtlasTextView::setCursorPosition(qsizetype position)
{
    moveCursor(position, false);
}

void AtlasTextView::select(qsizetype start, qsizetype end)
{
    const qsizetype n = length();
    start = std::clamp<qsizetype>(start, 0, n);
    end = std::clamp<qsizetype>(end, 0, n);
    setCursorAndAnchor(end, start);
}

void AtlasTextView::selectAll()
{
    select(0, length());
}

void AtlasTextView::copy()
{
    if (selectionStart() == selectionEnd())
        return;
    if (selectionEnd() - selectionStart() > MaxSelectionText) {
        qWarning("AtlasTextView: the selection is too large to copy");
        return;
    }
    if (QClipboard *cb = QGuiApplication::clipboard()) {
        const QString text = textInRange(selectionStart(), selectionEnd());
        if (!text.isEmpty())
            cb->setText(text);
    }
}

void AtlasTextView::moveCursor(qsizetype position, bool extend, bool keepGoal)
{
    position = std::clamp<qsizetype>(position, 0, length());
    setCursorAndAnchor(position, extend ? m_anchor : position, keepGoal);
    ensureVisible(m_cursor);
}

void AtlasTextView::scrollTo(qreal x, qreal y)
{
    setContentX(x);
    setContentY(y);
}

void AtlasTextView::ensureVisible(qsizetype position)
{
    const QRectF r = contentRectOf(position);
    qreal y = m_contentY;
    if (r.top() < y)
        y = r.top();
    else if (r.bottom() > y + viewHeight())
        y = r.bottom() - viewHeight();
    qreal x = m_contentX;
    if (!m_wrap) {
        const qreal avail = std::max(m_cw, viewWidth() - textLeft() - Pad);
        if (r.left() < x)
            x = r.left();
        else if (r.right() > x + avail)
            x = r.right() - avail;
        m_maxCols = std::max(m_maxCols, qsizetype(r.right() / m_cw) + 1);
    }
    scrollTo(x, y);
}

qsizetype AtlasTextView::wordStart(qsizetype position) const
{
    qsizetype start, len, brk;
    lineExtent(lineColumn(position).line, &start, &len, &brk);
    const qsizetype col = std::clamp<qsizetype>(position - start, 0, len);
    const QString s = m_buf.tree().text(start, start + std::min<qsizetype>(len, start + len));
    qsizetype i = col;
    if (i < s.size() && isWordChar(s[i])) {
        while (i > 0 && isWordChar(s[i - 1]))
            --i;
    } else if (i < s.size()) {
        const bool ws = s[i].isSpace();
        while (i > 0 && !isWordChar(s[i - 1]) && s[i - 1].isSpace() == ws)
            --i;
    }
    return start + i;
}

qsizetype AtlasTextView::wordEnd(qsizetype position) const
{
    qsizetype start, len, brk;
    lineExtent(lineColumn(position).line, &start, &len, &brk);
    const qsizetype col = std::clamp<qsizetype>(position - start, 0, len);
    const QString s = m_buf.tree().text(start, start + len);
    qsizetype i = col;
    if (i < s.size() && isWordChar(s[i])) {
        while (i < s.size() && isWordChar(s[i]))
            ++i;
    } else if (i < s.size()) {
        const bool ws = s[i].isSpace();
        while (i < s.size() && !isWordChar(s[i]) && s[i].isSpace() == ws)
            ++i;
    }
    return start + i;
}

void AtlasTextView::moveVertically(int rows, bool extend)
{
    const QRectF r = contentRectOf(m_cursor);
    const qreal goal = m_goalX >= 0 ? m_goalX : r.x();
    const qreal y = r.y() + rows * m_rowH + m_rowH / 2;
    qsizetype target;
    if (y < 0)
        target = 0;
    else if (y >= contentHeight())
        target = length();
    else
        target = positionAt(QPointF(goal + textLeft() - m_contentX, y - m_contentY));
    moveCursor(target, extend, true);
    m_goalX = goal;
}

void AtlasTextView::keyPressEvent(QKeyEvent *e)
{
    struct Move {
        QKeySequence::StandardKey move, select;
        int kind;
    };
    static const Move moves[] = {
        {QKeySequence::MoveToPreviousChar, QKeySequence::SelectPreviousChar, 0},
        {QKeySequence::MoveToNextChar, QKeySequence::SelectNextChar, 1},
        {QKeySequence::MoveToPreviousLine, QKeySequence::SelectPreviousLine, 2},
        {QKeySequence::MoveToNextLine, QKeySequence::SelectNextLine, 3},
        {QKeySequence::MoveToStartOfLine, QKeySequence::SelectStartOfLine, 4},
        {QKeySequence::MoveToEndOfLine, QKeySequence::SelectEndOfLine, 5},
        {QKeySequence::MoveToPreviousPage, QKeySequence::SelectPreviousPage, 6},
        {QKeySequence::MoveToNextPage, QKeySequence::SelectNextPage, 7},
        {QKeySequence::MoveToStartOfDocument, QKeySequence::SelectStartOfDocument, 8},
        {QKeySequence::MoveToEndOfDocument, QKeySequence::SelectEndOfDocument, 9},
        {QKeySequence::MoveToPreviousWord, QKeySequence::SelectPreviousWord, 10},
        {QKeySequence::MoveToNextWord, QKeySequence::SelectNextWord, 11},
    };
    if (e->matches(QKeySequence::Copy)) {
        copy();
        e->accept();
        return;
    }
    if (e->matches(QKeySequence::SelectAll)) {
        selectAll();
        e->accept();
        return;
    }
    const TextTree &t = m_buf.tree();
    for (const Move &m : moves) {
        const bool plain = e->matches(m.move), extend = e->matches(m.select);
        if (!plain && !extend)
            continue;
        const qsizetype n = length();
        const bool hasSel = m_anchor != m_cursor;
        qsizetype pos = m_cursor;
        switch (m.kind) {
        case 0:
            if (hasSel && !extend) {
                pos = selectionStart();
            } else if (pos > 0) {
                pos = (pos >= 2 && t.text(pos - 2, pos) == QLatin1String("\r\n")) ? pos - 2 : t.alignDown(pos - 1);
            }
            break;
        case 1:
            if (hasSel && !extend) {
                pos = selectionEnd();
            } else if (pos < n) {
                pos = (t.text(pos, pos + 2) == QLatin1String("\r\n")) ? pos + 2 : t.alignUp(pos + 1);
            }
            break;
        case 2:
            moveVertically(-1, extend);
            e->accept();
            return;
        case 3:
            moveVertically(1, extend);
            e->accept();
            return;
        case 4: {
            qsizetype s, l, b;
            lineExtent(lineColumn(pos).line, &s, &l, &b);
            pos = s;
            break;
        }
        case 5: {
            qsizetype s, l, b;
            lineExtent(lineColumn(pos).line, &s, &l, &b);
            pos = s + l;
            break;
        }
        case 6:
        case 7:
            moveVertically((m.kind == 6 ? -1 : 1) * std::max(1, int(viewHeight() / m_rowH) - 1), extend);
            e->accept();
            return;
        case 8: pos = 0; break;
        case 9: pos = n; break;
        case 10: {
            qsizetype p = pos;
            while (p > 0 && !isWordChar(unitAt(t, p - 1)))
                --p;
            pos = p > 0 ? wordStart(p - 1) : 0;
            break;
        }
        case 11: {
            qsizetype p = pos;
            while (p < n && !isWordChar(unitAt(t, p)))
                ++p;
            pos = p < n ? wordEnd(p) : n;
            break;
        }
        }
        moveCursor(pos, extend);
        e->accept();
        return;
    }
    QQuickItem::keyPressEvent(e);
}

// ---- Mouse and wheel ----

void AtlasTextView::mousePressEvent(QMouseEvent *e)
{
    if (e->button() != Qt::LeftButton) {
        e->ignore();
        return;
    }
    forceActiveFocus(Qt::MouseFocusReason);
    const qsizetype pos = positionAt(e->position());
    const qint64 now = qint64(e->timestamp());
    if (m_clicks == 2 && now - m_lastDoubleClick <= QGuiApplication::styleHints()->mouseDoubleClickInterval())
        m_clicks = 3;
    else
        m_clicks = 1;
    m_dragging = true;
    m_lastMouse = e->position();
    if (m_clicks == 3) {
        qsizetype s, l, b;
        lineExtent(lineColumn(pos).line, &s, &l, &b);
        select(s, s + l + b);
        m_clicks = 0;
    } else if (e->modifiers() & Qt::ShiftModifier) {
        moveCursor(pos, true);
    } else {
        moveCursor(pos, false);
    }
    e->accept();
}

void AtlasTextView::mouseDoubleClickEvent(QMouseEvent *e)
{
    if (e->button() != Qt::LeftButton) {
        e->ignore();
        return;
    }
    const qsizetype pos = positionAt(e->position());
    m_clicks = 2;
    m_lastDoubleClick = qint64(e->timestamp());
    m_dragging = true;
    select(wordStart(pos), wordEnd(pos));
    e->accept();
}

void AtlasTextView::mouseMoveEvent(QMouseEvent *e)
{
    if (!m_dragging) {
        e->ignore();
        return;
    }
    m_lastMouse = e->position();
    moveCursor(positionAt(m_lastMouse), true);
    const bool outside = m_lastMouse.y() < 0 || m_lastMouse.y() > viewHeight();
    if (outside && !m_scrollTimer.isActive())
        m_scrollTimer.start(40, this);
    else if (!outside)
        m_scrollTimer.stop();
    e->accept();
}

void AtlasTextView::stopDrag()
{
    m_dragging = false;
    m_scrollTimer.stop();
}

void AtlasTextView::mouseReleaseEvent(QMouseEvent *e)
{
    stopDrag();
    e->accept();
}

// The grab was taken away mid-drag (a popup, a touch, a window switch): no
// release comes, so the drag and its autoscroll end here.
void AtlasTextView::mouseUngrabEvent()
{
    stopDrag();
}

void AtlasTextView::itemChange(ItemChange change, const ItemChangeData &value)
{
    if (change == ItemVisibleHasChanged && !value.boolValue)
        stopDrag();
    QQuickItem::itemChange(change, value);
}

void AtlasTextView::timerEvent(QTimerEvent *e)
{
    if (e->timerId() == m_scrollTimer.timerId())
        autoScroll();
    else
        QQuickItem::timerEvent(e);
}

void AtlasTextView::autoScroll()
{
    if (!m_dragging || !isVisible()) {
        stopDrag();
        return;
    }
    qreal d = 0;
    if (m_lastMouse.y() < 0)
        d = m_lastMouse.y();
    else if (m_lastMouse.y() > viewHeight())
        d = m_lastMouse.y() - viewHeight();
    else {
        m_scrollTimer.stop();
        return;
    }
    setContentY(m_contentY + std::clamp<qreal>(d, -m_rowH * 4, m_rowH * 4) + (d < 0 ? -m_rowH : m_rowH));
    // Extend to the line the pointer now stands over (clamped to the text).
    const qreal y = std::clamp<qreal>(m_lastMouse.y(), 0, std::max<qreal>(0, viewHeight() - 1));
    setCursorAndAnchor(positionAt(QPointF(m_lastMouse.x(), y)), m_anchor);
}

void AtlasTextView::wheelEvent(QWheelEvent *e)
{
    qreal dy = e->pixelDelta().y(), dx = e->pixelDelta().x();
    if (e->pixelDelta().isNull()) {
        dy = e->angleDelta().y() / 120.0 * 3 * m_rowH;
        dx = e->angleDelta().x() / 120.0 * 3 * m_cw;
    }
    if (e->modifiers() & Qt::ShiftModifier && dx == 0)
        std::swap(dx, dy);
    setContentY(m_contentY - dy);
    setContentX(m_contentX - dx);
    e->accept();
}

void AtlasTextView::focusInEvent(QFocusEvent *e)
{
    QQuickItem::focusInEvent(e);
    update();
}

void AtlasTextView::focusOutEvent(QFocusEvent *e)
{
    QQuickItem::focusOutEvent(e);
    stopDrag();
    update();
}
