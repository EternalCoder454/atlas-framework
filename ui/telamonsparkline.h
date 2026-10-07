// TelamonSparklineItem: a small line chart with no axes or captions, for the
// trend of a figure in a card or a row. Drawn with QPainter so it renders on
// Qt Quick's software backend as well as on the GPU. Use it through
// TelamonSparkline.qml, which gives it the theme's accent colour.
#pragma once

#include <QColor>
#include <QQuickPaintedItem>
#include <QtQml/qqmlregistration.h>

#include <limits>

class TelamonSparklineItem : public QQuickPaintedItem
{
    Q_OBJECT
    QML_NAMED_ELEMENT(TelamonSparklineItem)

    // The samples, oldest first, spread over the full width. A NaN is a gap:
    // the line breaks there.
    Q_PROPERTY(QList<qreal> values READ values WRITE setValues NOTIFY valuesChanged)
    // The values at the bottom and the top of the item. NaN (the default)
    // scales to the samples.
    Q_PROPERTY(qreal minimum READ minimum WRITE setMinimum NOTIFY minimumChanged)
    Q_PROPERTY(qreal maximum READ maximum WRITE setMaximum NOTIFY maximumChanged)
    // The least span an automatic scale shows, so a flat or nearly flat series
    // is not blown up into a mountain range.
    Q_PROPERTY(qreal minimumRange READ minimumRange WRITE setMinimumRange NOTIFY minimumRangeChanged)
    Q_PROPERTY(QColor color READ color WRITE setColor NOTIFY colorChanged)
    // A soft area under the line.
    Q_PROPERTY(bool fill READ fill WRITE setFill NOTIFY fillChanged)
    Q_PROPERTY(qreal lineWidth READ lineWidth WRITE setLineWidth NOTIFY lineWidthChanged)

public:
    explicit TelamonSparklineItem(QQuickItem *parent = nullptr);

    QList<qreal> values() const { return m_values; }
    void setValues(const QList<qreal> &v);
    qreal minimum() const { return m_minimum; }
    void setMinimum(qreal v);
    qreal maximum() const { return m_maximum; }
    void setMaximum(qreal v);
    qreal minimumRange() const { return m_minimumRange; }
    void setMinimumRange(qreal v);
    QColor color() const { return m_color; }
    void setColor(const QColor &c);
    bool fill() const { return m_fill; }
    void setFill(bool f);
    qreal lineWidth() const { return m_lineWidth; }
    void setLineWidth(qreal w);

    // The scale in use: the explicit limits, else the samples' range widened
    // to minimumRange around its middle. Always scaleMaximum > scaleMinimum.
    qreal scaleMinimum() const;
    qreal scaleMaximum() const;

    // How many times the item asked for a repaint (for tests).
    int updateCount() const { return m_updates; }

    void paint(QPainter *p) override;

Q_SIGNALS:
    void valuesChanged();
    void minimumChanged();
    void maximumChanged();
    void minimumRangeChanged();
    void colorChanged();
    void fillChanged();
    void lineWidthChanged();

private:
    void repaint();
    void resolve(qreal &lo, qreal &hi) const;

    QList<qreal> m_values;
    qreal m_minimum = std::numeric_limits<qreal>::quiet_NaN();
    qreal m_maximum = std::numeric_limits<qreal>::quiet_NaN();
    qreal m_minimumRange = 0;
    QColor m_color{0x3d, 0xae, 0xe9};
    bool m_fill = false;
    qreal m_lineWidth = 1.5;
    int m_updates = 0;
};
