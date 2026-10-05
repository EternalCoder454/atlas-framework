// AtlasShortcuts: the registry of the app's actions. Every AtlasAction adds
// itself on completion and removes itself on destruction; the registry
// watches each one's `shortcut`, `text` and `enabled`, keeps the list for
// AtlasShortcutsDialog, and reports conflicts: one shortcut on two actions
// that are both enabled. Two actions conflict when they live in the same
// window (actions outside any Item or window share the app level). An action
// whose Item is not in a window yet takes part in no comparison until it is.
// Each new conflict is logged once with qWarning, naming the shortcut and the
// action texts.
//
// Also the helpers AtlasShortcutLabel uses to turn a shortcut (a string such
// as "Ctrl+S" or a QKeySequence::StandardKey number) into text.
#pragma once

#include <QList>
#include <QKeySequence>
#include <QObject>
#include <QPointer>
#include <QSet>
#include <QStringList>
#include <QTimer>
#include <QVariantList>
#include <QtQml/qqmlregistration.h>

class AtlasShortcuts : public QObject
{
    Q_OBJECT
    QML_NAMED_ELEMENT(AtlasShortcuts)
    QML_SINGLETON

    Q_PROPERTY(QList<QObject *> actions READ actions NOTIFY actionsChanged FINAL)
    Q_PROPERTY(QVariantList conflicts READ conflicts NOTIFY conflictsChanged FINAL)

public:
    explicit AtlasShortcuts(QObject *parent = nullptr);

    // Registered actions, in the order they were added.
    QList<QObject *> actions() const;
    // [{ shortcut: "Ctrl+S", texts: ["Save", "Sort"] }], by shortcut.
    QVariantList conflicts() const;

    Q_INVOKABLE void add(QObject *action);
    Q_INVOKABLE void remove(QObject *action);

    // `sequence` (a string or a StandardKey number) in the platform's own
    // spelling ("Ctrl+Shift+S"); empty when it is no shortcut.
    Q_INVOKABLE QString readable(const QVariant &sequence) const;
    // The same, as keycap labels: one list per chord, one string per key.
    Q_INVOKABLE QVariantList keys(const QVariant &sequence) const;
    // The portable text ("Ctrl+S", English names): what `conflicts` reports.
    Q_INVOKABLE QString portable(const QVariant &sequence) const;

    // An action's text without its "&" mnemonic markers ("&&" is one "&").
    Q_INVOKABLE QString plainText(const QString &text) const;

    static QKeySequence toSequence(const QVariant &sequence);

Q_SIGNALS:
    void actionsChanged();
    void conflictsChanged();

private Q_SLOTS:
    void onActionChanged();
    void onActionDestroyed(QObject *action);
    void recompute();

private:
    void scheduleRecompute();

    QList<QPointer<QObject>> m_actions;
    QVariantList m_conflicts; // as of the last recompute()
    QSet<QString> m_warned;
    QTimer m_timer;
    bool m_dirty = false;
};
