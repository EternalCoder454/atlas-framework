// TelamonCodePaintPrivate: what TelamonCodeEditor.qml draws beside and behind
// its TextEdit, with QPainter so it renders on Qt Quick's software backend as
// well as on the GPU. Not API (the name ends in "Private").
//
//   Gutter: the line numbers of the lines in view (one per line, at the first
//           row of a wrapped line) and the bars of the marked lines.
//   Bands:  behind the text, the tint of the marked lines and of the caret's row.
//
// Only the lines in view are visited, so a long file costs the same as a short
// one. The item has the size of the view, not of the text.
#pragma once

#include "codecore.h"

#include <QColor>
#include <QFont>
#include <QPointer>
#include <QQuickPaintedItem>
#include <QRectF>
#include <QtQml/qqmlregistration.h>

class TelamonCodePaintPrivate : public QQuickPaintedItem
{
    Q_OBJECT
    QML_NAMED_ELEMENT(TelamonCodePaintPrivate)

    Q_PROPERTY(TelamonCodeCorePrivate *core READ core WRITE setCore NOTIFY coreChanged)
    Q_PROPERTY(int mode READ mode WRITE setMode NOTIFY modeChanged)
    // The Flickable's contentY and the TextEdit's top padding: a line at y in
    // the document is at y + topPadding - contentY in this item.
    Q_PROPERTY(qreal contentY READ contentY WRITE setContentY NOTIFY contentYChanged)
    Q_PROPERTY(qreal topPadding READ topPadding WRITE setTopPadding NOTIFY topPaddingChanged)
    Q_PROPERTY(QFont font READ font WRITE setFont NOTIFY fontChanged)
    Q_PROPERTY(QColor numberColor READ numberColor WRITE setNumberColor NOTIFY colorsChanged)
    Q_PROPERTY(QColor currentNumberColor READ currentNumberColor WRITE setCurrentNumberColor NOTIFY colorsChanged)
    // Gutter bars (opaque) and the tint of the bands behind the text.
    Q_PROPERTY(QColor addedColor READ addedColor WRITE setAddedColor NOTIFY colorsChanged)
    Q_PROPERTY(QColor changedColor READ changedColor WRITE setChangedColor NOTIFY colorsChanged)
    Q_PROPERTY(QColor addedBand READ addedBand WRITE setAddedBand NOTIFY colorsChanged)
    Q_PROPERTY(QColor changedBand READ changedBand WRITE setChangedBand NOTIFY colorsChanged)
    Q_PROPERTY(QColor currentLineColor READ currentLineColor WRITE setCurrentLineColor NOTIFY colorsChanged)
    // The caret's rectangle in the TextEdit (its own coordinates), and whether to tint its row.
    Q_PROPERTY(QRectF cursorRect READ cursorRect WRITE setCursorRect NOTIFY cursorRectChanged)
    Q_PROPERTY(bool showCurrentLine READ showCurrentLine WRITE setShowCurrentLine NOTIFY showCurrentLineChanged)
    Q_PROPERTY(int currentLine READ currentLine WRITE setCurrentLine NOTIFY currentLineChanged)
    // How many lines there are, for the width of the number column.
    Q_PROPERTY(int lineCount READ lineCount WRITE setLineCount NOTIFY lineCountChanged)
    Q_PROPERTY(qreal gutterWidth READ gutterWidth NOTIFY gutterWidthChanged)

public:
    enum Mode { Gutter = 0, Bands = 1 };
    Q_ENUM(Mode)

    explicit TelamonCodePaintPrivate(QQuickItem *parent = nullptr);

    void paint(QPainter *painter) override;

    TelamonCodeCorePrivate *core() const { return m_core; }
    void setCore(TelamonCodeCorePrivate *core);
    int mode() const { return m_mode; }
    void setMode(int mode);
    qreal contentY() const { return m_contentY; }
    void setContentY(qreal y);
    qreal topPadding() const { return m_topPadding; }
    void setTopPadding(qreal p);
    QFont font() const { return m_font; }
    void setFont(const QFont &font);
    QColor numberColor() const { return m_number; }
    void setNumberColor(const QColor &c);
    QColor currentNumberColor() const { return m_currentNumber; }
    void setCurrentNumberColor(const QColor &c);
    QColor addedColor() const { return m_added; }
    void setAddedColor(const QColor &c);
    QColor changedColor() const { return m_changed; }
    void setChangedColor(const QColor &c);
    QColor addedBand() const { return m_addedBand; }
    void setAddedBand(const QColor &c);
    QColor changedBand() const { return m_changedBand; }
    void setChangedBand(const QColor &c);
    QColor currentLineColor() const { return m_currentLine; }
    void setCurrentLineColor(const QColor &c);
    QRectF cursorRect() const { return m_cursorRect; }
    void setCursorRect(const QRectF &r);
    bool showCurrentLine() const { return m_showCurrent; }
    void setShowCurrentLine(bool show);
    int currentLine() const { return m_cursorLine; }
    void setCurrentLine(int line);
    int lineCount() const { return m_lineCount; }
    void setLineCount(int count);
    qreal gutterWidth() const { return m_gutterWidth; }

Q_SIGNALS:
    void coreChanged();
    void modeChanged();
    void contentYChanged();
    void topPaddingChanged();
    void fontChanged();
    void colorsChanged();
    void cursorRectChanged();
    void showCurrentLineChanged();
    void currentLineChanged();
    void lineCountChanged();
    void gutterWidthChanged();

private:
    void measure();
    void paintGutter(QPainter *painter, QTextDocument *doc);
    void paintBands(QPainter *painter, QTextDocument *doc);

    QPointer<TelamonCodeCorePrivate> m_core;
    int m_mode = Gutter;
    qreal m_contentY = 0;
    qreal m_topPadding = 0;
    QFont m_font;
    QColor m_number, m_currentNumber, m_added, m_changed, m_addedBand, m_changedBand, m_currentLine;
    QRectF m_cursorRect;
    bool m_showCurrent = true;
    int m_cursorLine = 0;
    int m_lineCount = 1;
    qreal m_gutterWidth = 0;
};
