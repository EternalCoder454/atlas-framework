// AccessibilityState.active: whether an assistive technology (a screen
// reader) is listening, so a component can leave out text only one would
// read. Qt keeps the answer and says when it changes.
// See docs/reference/telamon-ui/accessibility-state.md.
#pragma once

#include <QAccessible>
#include <QColor>
#include <QObject>
#include <QQuickItem>
#include <QtQml/qqmlregistration.h>

class AccessibilityState : public QObject, public QAccessible::ActivationObserver
{
    Q_OBJECT
    QML_NAMED_ELEMENT(AccessibilityState)
    QML_SINGLETON

    Q_PROPERTY(bool active READ active NOTIFY activeChanged)
    Q_PROPERTY(bool highContrast READ highContrast NOTIFY highContrastChanged)
    Q_PROPERTY(bool reducedMotion READ reducedMotion NOTIFY reducedMotionChanged)
    Q_PROPERTY(QColor accentColor READ accentColor NOTIFY accentColorChanged)

public:
    explicit AccessibilityState(QObject *parent = nullptr);
    ~AccessibilityState() override;

    bool active() const { return QAccessible::isActive(); }
    void accessibilityActiveChanged(bool) override { Q_EMIT activeChanged(); }

    bool highContrast() const { return m_highContrast; }
    bool reducedMotion() const { return m_reducedMotion; }
    QColor accentColor() const { return m_accentColor; }

    // Not API (the leading _): moves `item` right after `sibling` among
    // their parent's children, the order Qt's Tab chain follows. QML has no
    // stackAfter; TelamonShelf keeps its cards in index order with it.
    Q_INVOKABLE void _stackAfter(QQuickItem *item, QQuickItem *sibling) const;

Q_SIGNALS:
    void activeChanged();
    void highContrastChanged();
    void reducedMotionChanged();
    void accentColorChanged();

private:
    void refresh();

    bool m_highContrast = false;
    bool m_reducedMotion = false;
    QColor m_accentColor;
};
