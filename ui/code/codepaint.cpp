// See codepaint.h.
#include "codepaint.h"

#include <QAbstractTextDocumentLayout>
#include <QFontMetricsF>
#include <QPainter>
#include <QTextBlock>
#include <QTextDocument>
#include <QTextLayout>

#include <algorithm>
#include <cmath>

namespace
{
constexpr qreal LeftPad = 6;
constexpr qreal RightPad = 6;
constexpr qreal BarWidth = 3;
constexpr qreal BarGap = 3;
}

TelamonCodePaintPrivate::TelamonCodePaintPrivate(QQuickItem *parent)
    : QQuickPaintedItem(parent)
{
    setAntialiasing(true);
}

void TelamonCodePaintPrivate::setCore(TelamonCodeCorePrivate *core)
{
    if (m_core == core) {
        return;
    }
    if (m_core) {
        disconnect(m_core, nullptr, this, nullptr);
    }
    m_core = core;
    if (core) {
        connect(core, &TelamonCodeCorePrivate::marksChanged, this, [this] { update(); });
        connect(core, &TelamonCodeCorePrivate::layoutChanged, this, [this] { update(); });
    }
    Q_EMIT coreChanged();
    update();
}

#define TELAMON_PAINT_SETTER(Name, member, signal)  \
    if (member == value) {                           \
        return;                                      \
    }                                                \
    member = value;                                  \
    Q_EMIT signal();                                 \
    update();

void TelamonCodePaintPrivate::setMode(int value)
{
    TELAMON_PAINT_SETTER(Mode, m_mode, modeChanged)
}

void TelamonCodePaintPrivate::setContentY(qreal value)
{
    TELAMON_PAINT_SETTER(ContentY, m_contentY, contentYChanged)
}

void TelamonCodePaintPrivate::setTopPadding(qreal value)
{
    TELAMON_PAINT_SETTER(TopPadding, m_topPadding, topPaddingChanged)
}

void TelamonCodePaintPrivate::setFont(const QFont &value)
{
    if (m_font == value) {
        return;
    }
    m_font = value;
    measure();
    Q_EMIT fontChanged();
    update();
}

void TelamonCodePaintPrivate::setNumberColor(const QColor &value)
{
    TELAMON_PAINT_SETTER(NumberColor, m_number, colorsChanged)
}

void TelamonCodePaintPrivate::setCurrentNumberColor(const QColor &value)
{
    TELAMON_PAINT_SETTER(CurrentNumberColor, m_currentNumber, colorsChanged)
}

void TelamonCodePaintPrivate::setAddedColor(const QColor &value)
{
    TELAMON_PAINT_SETTER(AddedColor, m_added, colorsChanged)
}

void TelamonCodePaintPrivate::setChangedColor(const QColor &value)
{
    TELAMON_PAINT_SETTER(ChangedColor, m_changed, colorsChanged)
}

void TelamonCodePaintPrivate::setAddedBand(const QColor &value)
{
    TELAMON_PAINT_SETTER(AddedBand, m_addedBand, colorsChanged)
}

void TelamonCodePaintPrivate::setChangedBand(const QColor &value)
{
    TELAMON_PAINT_SETTER(ChangedBand, m_changedBand, colorsChanged)
}

void TelamonCodePaintPrivate::setCurrentLineColor(const QColor &value)
{
    TELAMON_PAINT_SETTER(CurrentLineColor, m_currentLine, colorsChanged)
}

void TelamonCodePaintPrivate::setCursorRect(const QRectF &value)
{
    TELAMON_PAINT_SETTER(CursorRect, m_cursorRect, cursorRectChanged)
}

void TelamonCodePaintPrivate::setShowCurrentLine(bool value)
{
    TELAMON_PAINT_SETTER(ShowCurrentLine, m_showCurrent, showCurrentLineChanged)
}

void TelamonCodePaintPrivate::setCurrentLine(int value)
{
    TELAMON_PAINT_SETTER(CurrentLine, m_cursorLine, currentLineChanged)
}

void TelamonCodePaintPrivate::setLineCount(int value)
{
    value = std::max(1, value);
    if (m_lineCount == value) {
        return;
    }
    m_lineCount = value;
    measure();
    Q_EMIT lineCountChanged();
    update();
}

// The number column is as wide as the widest number may be: at least three
// digits, so the text does not jump at line 100.
void TelamonCodePaintPrivate::measure()
{
    const QFontMetricsF fm(m_font);
    int digits = 3;
    for (int n = m_lineCount; n >= 1000; n /= 10) {
        ++digits;
    }
    const qreal width = std::ceil(LeftPad + fm.horizontalAdvance(QLatin1Char('0')) * digits + RightPad + BarGap + BarWidth);
    if (!qFuzzyCompare(width, m_gutterWidth)) {
        m_gutterWidth = width;
        setImplicitWidth(width);
        Q_EMIT gutterWidthChanged();
    }
}

void TelamonCodePaintPrivate::paint(QPainter *painter)
{
    QTextDocument *doc = m_core ? m_core->document() : nullptr;
    if (!doc || width() <= 0 || height() <= 0) {
        return;
    }
    if (m_mode == Gutter) {
        paintGutter(painter, doc);
    } else {
        paintBands(painter, doc);
    }
}

void TelamonCodePaintPrivate::paintGutter(QPainter *painter, QTextDocument *doc)
{
    QAbstractTextDocumentLayout *layout = doc->documentLayout();
    const qreal top = m_contentY - m_topPadding;
    const int first = m_core->lineAtY(top);
    const int last = m_core->lineAtY(top + height());
    const QFontMetricsF fm(m_font);
    painter->setFont(m_font);
    const qreal numberRight = width() - RightPad - BarGap - BarWidth;

    for (QTextBlock b = doc->findBlockByNumber(first); b.isValid() && b.blockNumber() <= last; b = b.next()) {
        const QRectF rect = layout->blockBoundingRect(b);
        qreal y = rect.top();
        qreal h = fm.height();
        if (const QTextLayout *tl = b.layout(); tl && tl->lineCount() > 0) {
            // A wrapped line is numbered on its first row.
            y += tl->lineAt(0).y();
            h = tl->lineAt(0).height();
        }
        const qreal itemY = y + m_topPadding - m_contentY;
        painter->setPen(b.blockNumber() == m_cursorLine ? m_currentNumber : m_number);
        painter->drawText(QRectF(LeftPad, itemY, numberRight - LeftPad, h), Qt::AlignRight | Qt::AlignVCenter, QString::number(b.blockNumber() + 1));
    }

    // The bars of the marked lines, at the edge beside the text.
    const auto spans = m_core->marksIn(first, last);
    for (const auto &span : spans) {
        const QRectF fr = layout->blockBoundingRect(doc->findBlockByNumber(span.firstBlock));
        const QRectF lr = layout->blockBoundingRect(doc->findBlockByNumber(span.lastBlock));
        const qreal y0 = fr.top() + m_topPadding - m_contentY;
        const qreal y1 = lr.bottom() + m_topPadding - m_contentY;
        QColor color = span.kind == TelamonCodeCorePrivate::Added ? m_added : m_changed;
        color.setAlphaF(color.alphaF() * span.alpha);
        const qreal x = width() - BarWidth;
        if (span.kind == TelamonCodeCorePrivate::Added) {
            painter->fillRect(QRectF(x, y0, BarWidth, y1 - y0), color);
        } else {
            // Changed is dashed, so the two kinds differ by more than colour.
            constexpr qreal on = 4;
            constexpr qreal off = 2;
            for (qreal y = y0; y < y1; y += on + off) {
                painter->fillRect(QRectF(x, y, BarWidth, std::min(on, y1 - y)), color);
            }
        }
    }
}

void TelamonCodePaintPrivate::paintBands(QPainter *painter, QTextDocument *doc)
{
    QAbstractTextDocumentLayout *layout = doc->documentLayout();
    if (m_showCurrent && m_currentLine.alpha() > 0 && m_cursorRect.height() > 0) {
        painter->fillRect(QRectF(0, m_cursorRect.y() - m_contentY, width(), m_cursorRect.height()), m_currentLine);
    }
    const qreal top = m_contentY - m_topPadding;
    const int first = m_core->lineAtY(top);
    const int last = m_core->lineAtY(top + height());
    const auto spans = m_core->marksIn(first, last);
    for (const auto &span : spans) {
        const QRectF fr = layout->blockBoundingRect(doc->findBlockByNumber(span.firstBlock));
        const QRectF lr = layout->blockBoundingRect(doc->findBlockByNumber(span.lastBlock));
        const qreal y0 = fr.top() + m_topPadding - m_contentY;
        const qreal y1 = lr.bottom() + m_topPadding - m_contentY;
        QColor color = span.kind == TelamonCodeCorePrivate::Added ? m_addedBand : m_changedBand;
        color.setAlphaF(color.alphaF() * span.alpha);
        painter->fillRect(QRectF(0, y0, width(), y1 - y0), color);
    }
}
