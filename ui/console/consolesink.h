// TelamonConsoleSinkPrivate: the C++ behind TelamonConsoleView. It owns the
// QTextDocument of the view's TextEdit: it parses what append() gets (ansiparser),
// adds the text at the end of the document in one edit, keeps at most
// `maximumLines` lines, and draws the colours as per-block layout formats (as a
// QSyntaxHighlighter does), never as rich text. Not API (the name ends in
// "Private", which tools/apidump leaves out): apps use TelamonConsoleView
// (docs/reference/telamon-ui/telamon-console-view.md).
#pragma once

#include "ansiparser.h"
#include "consoletheme.h"

#include <QColor>
#include <QHash>
#include <QObject>
#include <QPointer>
#include <QQuickTextDocument>
#include <QTextDocument>
#include <QTextLayout>
#include <QVariantList>
#include <QtQml/qqmlregistration.h>

#include <deque>

class TelamonConsoleSinkPrivate : public QObject
{
    Q_OBJECT
    QML_NAMED_ELEMENT(TelamonConsoleSinkPrivate)

    Q_PROPERTY(QQuickTextDocument *textDocument READ textDocument WRITE setTextDocument NOTIFY textDocumentChanged FINAL)
    Q_PROPERTY(int maximumLines READ maximumLines WRITE setMaximumLines NOTIFY maximumLinesChanged FINAL)
    Q_PROPERTY(int lineCount READ lineCount NOTIFY lineCountChanged FINAL)
    Q_PROPERTY(QVariantList palette READ palette WRITE setPalette NOTIFY paletteChanged FINAL)
    Q_PROPERTY(QColor textColor READ textColor WRITE setTextColor NOTIFY paletteChanged FINAL)
    Q_PROPERTY(QColor surfaceColor READ surfaceColor WRITE setSurfaceColor NOTIFY paletteChanged FINAL)
    Q_PROPERTY(bool highContrast READ highContrast WRITE setHighContrast NOTIFY paletteChanged FINAL)

public:
    explicit TelamonConsoleSinkPrivate(QObject *parent = nullptr);

    QQuickTextDocument *textDocument() const { return m_quickDoc; }
    void setTextDocument(QQuickTextDocument *doc);
    int maximumLines() const { return m_max; }
    void setMaximumLines(int lines);
    // The lines of text; the empty line after a final newline is not one.
    int lineCount() const;
    QVariantList palette() const { return m_paletteVariant; }
    void setPalette(const QVariantList &colors);
    QColor textColor() const { return m_text; }
    void setTextColor(const QColor &c);
    QColor surfaceColor() const { return m_surface; }
    void setSurfaceColor(const QColor &c);
    bool highContrast() const { return m_highContrast; }
    void setHighContrast(bool on);

    // Parses `text` and adds it at the end.
    Q_INVOKABLE void append(const QString &text);
    // Empties the document and the parser.
    Q_INVOKABLE void clear();
    Q_INVOKABLE QString plainText() const;
    // Draws the colours again now, if a colour changed and the queued redraw has not run yet.
    Q_INVOKABLE void applyTheme();

    // For tests: the style runs kept for a line (start, length, fg, bg, flags; -1 is the
    // default colour), the formats the document's layout holds for it, a line's
    // text, a slot's colour on screen, and the contrast of two colours.
    Q_INVOKABLE QVariantList runsAt(int line) const;
    Q_INVOKABLE QVariantList formatsAt(int line) const;
    Q_INVOKABLE QString lineText(int line) const;
    Q_INVOKABLE QColor slotColor(int slot);
    Q_INVOKABLE double contrast(const QColor &a, const QColor &b) const;
    Q_INVOKABLE int blockCount() const;

Q_SIGNALS:
    void textDocumentChanged();
    void maximumLinesChanged();
    void lineCountChanged();
    void paletteChanged();
    // The first lines went and the text above `height` pixels with them: a view that
    // is not following moves up by that much to keep what it shows in place.
    void trimmedAbove(qreal height);

private:
    using Runs = QList<TelamonConsole::Run>;

    bool lastBlockEmpty() const;
    void apply(TelamonConsole::Parsed &parsed);
    void removeFront(int blocks);
    void setBlockFormats(int firstBlock);
    QList<QTextLayout::FormatRange> formatsFor(const Runs &runs);
    void themeChanged();
    void ensureTheme();
    void redraw();
    void resetDocument();

    QPointer<QQuickTextDocument> m_quickDoc;
    QPointer<QTextDocument> m_doc;
    TelamonConsole::AnsiParser m_parser;
    // The style runs of each block, by block number (as palette slots).
    std::deque<Runs> m_lines;
    int m_max = 10000;
    int m_lastCount = 0;
    qreal m_trimmedHeight = 0;

    QVariantList m_paletteVariant;
    QList<QColor> m_palette;
    QColor m_text = Qt::black;
    QColor m_surface = Qt::white;
    bool m_highContrast = false;
    TelamonConsole::ConsoleTheme m_theme;
    bool m_themeDirty = true;
    bool m_redrawQueued = false;
    QHash<quint32, QTextCharFormat> m_formats;
};
