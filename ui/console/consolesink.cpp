#include "consolesink.h"

#include <QAbstractTextDocumentLayout>
#include <QFont>
#include <QTextBlock>
#include <QTextCursor>
#include <QTextLayout>
#include <QVariantMap>

#include <algorithm>
#include <utility>

namespace
{
// Style runs kept for one line (a line is at most 4,096 units): one run is a
// layout format, and a flood of colour changes would cost a view of 10,000
// lines the memory of a million.
constexpr qsizetype MaxRunsPerLine = 256;
} // namespace

using namespace TelamonConsole;

TelamonConsoleSinkPrivate::TelamonConsoleSinkPrivate(QObject *parent)
    : QObject(parent)
{
    m_lines.emplace_back();
}

void TelamonConsoleSinkPrivate::setTextDocument(QQuickTextDocument *doc)
{
    if (doc == m_quickDoc) {
        return;
    }
    m_quickDoc = doc;
    m_doc = doc ? doc->textDocument() : nullptr;
    m_lines.clear();
    if (m_doc) {
        // Only this object edits the document, and it never needs the history.
        m_doc->setUndoRedoEnabled(false);
        m_doc->setMaximumBlockCount(0);
        m_lines.resize(size_t(m_doc->blockCount()));
        redraw();
    } else {
        m_lines.emplace_back();
    }
    m_lastCount = lineCount();
    Q_EMIT textDocumentChanged();
    Q_EMIT lineCountChanged();
}

bool TelamonConsoleSinkPrivate::lastBlockEmpty() const
{
    return !m_doc || m_doc->lastBlock().length() <= 1;
}

int TelamonConsoleSinkPrivate::lineCount() const
{
    if (!m_doc) {
        return 0;
    }
    const int blocks = m_doc->blockCount();
    return lastBlockEmpty() ? blocks - 1 : blocks;
}

int TelamonConsoleSinkPrivate::blockCount() const
{
    return m_doc ? m_doc->blockCount() : 0;
}

void TelamonConsoleSinkPrivate::setMaximumLines(int lines)
{
    // Not more than a bound that keeps the arithmetic of a trim in range.
    lines = std::clamp(lines, 1, 100'000'000);
    if (lines == m_max) {
        return;
    }
    m_max = lines;
    if (m_doc) {
        const int excess = m_doc->blockCount() - (m_max + (lastBlockEmpty() ? 1 : 0)); // m_max <= 100,000,000
        if (excess > 0) {
            removeFront(excess);
            if (m_trimmedHeight > 0) {
                Q_EMIT trimmedAbove(std::exchange(m_trimmedHeight, 0));
            }
        }
        if (lineCount() != m_lastCount) {
            m_lastCount = lineCount();
            Q_EMIT lineCountChanged();
        }
    }
    Q_EMIT maximumLinesChanged();
}

// Takes the first `blocks` blocks away and notes how much height went with
// them. Done in an edit of its own: one edit that also adds text at the end
// has the document's layout lay out every block again (160 ms at 10,000 lines),
// two lay out the blocks that changed and move the others (3 ms).
void TelamonConsoleSinkPrivate::removeFront(int blocks)
{
    const qreal top = m_doc->documentLayout()->blockBoundingRect(m_doc->findBlockByNumber(blocks)).top();
    QTextCursor cursor(m_doc);
    cursor.beginEditBlock();
    cursor.setPosition(0);
    cursor.setPosition(m_doc->findBlockByNumber(blocks).position(), QTextCursor::KeepAnchor);
    cursor.removeSelectedText();
    cursor.endEditBlock();
    m_lines.erase(m_lines.begin(), m_lines.begin() + blocks);
    m_trimmedHeight += std::max<qreal>(0, top - m_doc->documentMargin());
}

void TelamonConsoleSinkPrivate::resetDocument()
{
    QTextCursor cursor(m_doc);
    cursor.select(QTextCursor::Document);
    cursor.removeSelectedText();
    m_lines.clear();
    m_lines.emplace_back();
}

void TelamonConsoleSinkPrivate::clear()
{
    m_parser.reset();
    if (!m_doc) {
        return;
    }
    QTextCursor cursor(m_doc);
    cursor.beginEditBlock();
    resetDocument();
    setBlockFormats(0);
    cursor.endEditBlock();
    if (m_lastCount != 0) {
        m_lastCount = 0;
        Q_EMIT lineCountChanged();
    }
}

void TelamonConsoleSinkPrivate::append(const QString &text)
{
    if (!m_doc || text.isEmpty()) {
        return;
    }
    Parsed parsed;
    m_parser.feed(text, parsed);
    apply(parsed);
}

void TelamonConsoleSinkPrivate::apply(Parsed &parsed)
{
    if (parsed.text.isEmpty() && !parsed.clearsLastLine) {
        return;
    }
    QString &text = parsed.text;
    QList<Run> &runs = parsed.runs;

    // The plan, before the document changes: how many lines the text ends, and
    // so how many have to go.
    const int blocks = m_doc->blockCount();
    qsizetype newlines = 0;
    for (qsizetype from = 0; (from = text.indexOf(QLatin1Char('\n'), from)) >= 0; ++from) {
        ++newlines;
    }
    const bool endsEmpty = text.isEmpty() ? (parsed.clearsLastLine || lastBlockEmpty()) : text.endsWith(QLatin1Char('\n'));
    const qint64 excess = qint64(blocks) + newlines - (qint64(m_max) + (endsEmpty ? 1 : 0));

    // Everything that is there goes, and the first lines of the new text with it.
    qsizetype dropChars = 0;
    bool dropAll = false;
    if (excess > blocks - 1) {
        dropAll = true;
        qint64 lines = excess - blocks + 1; // lines of the new text that are dropped
        for (qsizetype from = 0; lines > 0; --lines) {
            from = text.indexOf(QLatin1Char('\n'), from) + 1;
            dropChars = from;
        }
    }

    // Two edits: taking lines off the top, then adding at the bottom. In one edit the
    // document's layout would lay out every block again (see removeFront()).
    if (dropAll) {
        QTextCursor reset(m_doc);
        reset.beginEditBlock();
        resetDocument();
        reset.endEditBlock();
    } else if (excess > 0) {
        removeFront(int(excess));
    }

    QTextCursor cursor(m_doc);
    cursor.beginEditBlock();
    if (parsed.clearsLastLine && !dropAll) {
        cursor.movePosition(QTextCursor::End);
        cursor.movePosition(QTextCursor::StartOfBlock, QTextCursor::KeepAnchor);
        cursor.removeSelectedText();
        m_lines.back().clear();
    }

    const int firstBlock = m_doc->blockCount() - 1;
    const int base = m_doc->lastBlock().length() - 1;
    if (dropChars > 0) {
        text.remove(0, dropChars);
    }
    if (!text.isEmpty()) {
        cursor.movePosition(QTextCursor::End);
        cursor.insertText(text);
    }
    const int blocksNow = m_doc->blockCount();
    m_lines.resize(size_t(blocksNow));

    // The runs go to the lines they are on.
    int line = firstBlock;
    qsizetype lineStart = 0;
    qsizetype nextNewline = text.indexOf(QLatin1Char('\n'));
    for (const Run &r : std::as_const(runs)) {
        if (r.start + r.length <= dropChars) {
            continue;
        }
        const qsizetype start = r.start - dropChars;
        while (nextNewline >= 0 && nextNewline < start) {
            ++line;
            lineStart = nextNewline + 1;
            nextNewline = text.indexOf(QLatin1Char('\n'), lineStart);
        }
        Run placed = r;
        placed.start = int(start - lineStart) + (line == firstBlock ? base : 0);
        Runs &target = m_lines[size_t(line)];
        if (!target.isEmpty() && target.last().start + target.last().length == placed.start && target.last().style == placed.style) {
            target.last().length += placed.length;
        } else if (target.size() < MaxRunsPerLine) {
            target.append(placed);
        } // else: the rest of the line stays in the plain style
    }

    setBlockFormats(firstBlock);
    cursor.endEditBlock();

    const int count = lineCount();
    if (count != m_lastCount) {
        m_lastCount = count;
        Q_EMIT lineCountChanged();
    }
    if (m_trimmedHeight > 0) {
        Q_EMIT trimmedAbove(std::exchange(m_trimmedHeight, 0));
    }
}

// Gives each block from `firstBlock` on the formats of its runs. All of them,
// also the ones with none: a block that is split gives its layout to either half.
void TelamonConsoleSinkPrivate::setBlockFormats(int firstBlock)
{
    ensureTheme();
    QTextBlock block = m_doc->findBlockByNumber(firstBlock);
    for (size_t i = size_t(firstBlock); block.isValid() && i < m_lines.size(); block = block.next(), ++i) {
        block.layout()->setFormats(formatsFor(m_lines[i]));
    }
}

QList<QTextLayout::FormatRange> TelamonConsoleSinkPrivate::formatsFor(const Runs &runs)
{
    QList<QTextLayout::FormatRange> out;
    out.reserve(runs.size());
    for (const Run &r : runs) {
        const quint32 key = quint32(r.style.fg) | (quint32(r.style.bg) << 8) | (quint32(r.style.flags) << 16);
        auto it = m_formats.find(key);
        if (it == m_formats.end()) {
            it = m_formats.insert(key, m_theme.format(r.style));
        }
        QTextLayout::FormatRange range;
        range.start = r.start;
        range.length = r.length;
        range.format = it.value();
        out.append(range);
    }
    return out;
}

QString TelamonConsoleSinkPrivate::plainText() const
{
    return m_doc ? m_doc->toPlainText() : QString();
}

// ---- the colours

void TelamonConsoleSinkPrivate::ensureTheme()
{
    if (!m_themeDirty) {
        return;
    }
    m_theme.build(m_palette, m_text, m_surface, m_highContrast);
    m_formats.clear();
    m_themeDirty = false;
}

void TelamonConsoleSinkPrivate::themeChanged()
{
    m_themeDirty = true;
    Q_EMIT paletteChanged();
    if (!m_redrawQueued && m_doc) {
        m_redrawQueued = true;
        QMetaObject::invokeMethod(this, &TelamonConsoleSinkPrivate::applyTheme, Qt::QueuedConnection);
    }
}

void TelamonConsoleSinkPrivate::applyTheme()
{
    if (m_redrawQueued) {
        m_redrawQueued = false;
        redraw();
    }
}

// Every block again from its runs (the text did not change, the colours did).
void TelamonConsoleSinkPrivate::redraw()
{
    if (!m_doc) {
        return;
    }
    m_themeDirty = true;
    setBlockFormats(0);
    m_doc->markContentsDirty(0, m_doc->characterCount());
}

void TelamonConsoleSinkPrivate::setPalette(const QVariantList &colors)
{
    QList<QColor> list;
    list.reserve(colors.size());
    for (const QVariant &v : colors) {
        list.append(v.value<QColor>());
    }
    if (list == m_palette) {
        return;
    }
    m_palette = list;
    m_paletteVariant = colors;
    themeChanged();
}

void TelamonConsoleSinkPrivate::setTextColor(const QColor &c)
{
    if (c == m_text) {
        return;
    }
    m_text = c;
    themeChanged();
}

void TelamonConsoleSinkPrivate::setSurfaceColor(const QColor &c)
{
    if (c == m_surface) {
        return;
    }
    m_surface = c;
    themeChanged();
}

void TelamonConsoleSinkPrivate::setHighContrast(bool on)
{
    if (on == m_highContrast) {
        return;
    }
    m_highContrast = on;
    themeChanged();
}

// ---- for the tests

QVariantList TelamonConsoleSinkPrivate::runsAt(int line) const
{
    QVariantList out;
    if (line < 0 || size_t(line) >= m_lines.size()) {
        return out;
    }
    for (const Run &r : m_lines[size_t(line)]) {
        out.append(QVariantMap{
            {QStringLiteral("start"), r.start},
            {QStringLiteral("length"), r.length},
            {QStringLiteral("fg"), r.style.fg == NoColor ? -1 : int(r.style.fg)},
            {QStringLiteral("bg"), r.style.bg == NoColor ? -1 : int(r.style.bg)},
            {QStringLiteral("flags"), int(r.style.flags)},
        });
    }
    return out;
}

QVariantList TelamonConsoleSinkPrivate::formatsAt(int line) const
{
    QVariantList out;
    const QTextBlock block = m_doc ? m_doc->findBlockByNumber(line) : QTextBlock();
    if (!block.isValid()) {
        return out;
    }
    for (const QTextLayout::FormatRange &r : block.layout()->formats()) {
        out.append(QVariantMap{
            {QStringLiteral("start"), r.start},
            {QStringLiteral("length"), r.length},
            {QStringLiteral("foreground"), r.format.foreground().style() == Qt::NoBrush ? QColor() : r.format.foreground().color()},
            {QStringLiteral("background"), r.format.background().style() == Qt::NoBrush ? QColor() : r.format.background().color()},
            {QStringLiteral("bold"), r.format.fontWeight() >= QFont::Bold},
            {QStringLiteral("italic"), r.format.fontItalic()},
            {QStringLiteral("underline"), r.format.fontUnderline()},
            {QStringLiteral("strike"), r.format.fontStrikeOut()},
        });
    }
    return out;
}

QString TelamonConsoleSinkPrivate::lineText(int line) const
{
    const QTextBlock block = m_doc ? m_doc->findBlockByNumber(line) : QTextBlock();
    return block.isValid() ? block.text() : QString();
}

QColor TelamonConsoleSinkPrivate::slotColor(int slot)
{
    ensureTheme();
    return m_theme.slot(slot);
}

double TelamonConsoleSinkPrivate::contrast(const QColor &a, const QColor &b) const
{
    return contrastRatio(a, b);
}
