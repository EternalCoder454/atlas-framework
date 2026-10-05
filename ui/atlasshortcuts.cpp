#include "atlasshortcuts.h"

#include <QHash>
#include <QLoggingCategory>
#include <QMetaMethod>
#include <QMetaProperty>
#include <QQuickItem>
#include <QQuickWindow>
#include <algorithm>

Q_LOGGING_CATEGORY(lcShortcuts, "atlas.ui.shortcuts")

namespace {
// Reads an action's property; an invalid variant when it has none.
QVariant read(QObject *action, const char *name)
{
    return action ? action->property(name) : QVariant();
}

// "&Save" and "Save && Close" as the reader sees them: "Save", "Save & Close".
QString plain(QString text)
{
    QString out;
    out.reserve(text.size());
    for (qsizetype i = 0; i < text.size(); ++i) {
        if (text[i] == QLatin1Char('&') && i + 1 < text.size()) {
            ++i;
        }
        out += text[i];
    }
    return out;
}

// The window an action works in: the one of the nearest Item above it.
QObject *windowOf(QObject *action)
{
    for (QObject *o = action; o; o = o->parent()) {
        if (auto *item = qobject_cast<QQuickItem *>(o)) {
            return item->window();
        }
    }
    return nullptr;
}

// Native text -> keys. A "+" ends a key, unless it is the key: "Ctrl++".
QStringList splitKeys(const QString &chord)
{
    QStringList keys;
    QString current;
    for (const QChar c : chord) {
        if (c == QLatin1Char('+') && !current.isEmpty()) {
            keys << current;
            current.clear();
        } else {
            current += c;
        }
    }
    if (!current.isEmpty()) {
        keys << current;
    }
    return keys;
}
}

AtlasShortcuts::AtlasShortcuts(QObject *parent)
    : QObject(parent)
{
    // Several changes in one turn of the event loop make one comparison.
    m_timer.setSingleShot(true);
    m_timer.setInterval(0);
    connect(&m_timer, &QTimer::timeout, this, &AtlasShortcuts::recompute);
}

QList<QObject *> AtlasShortcuts::actions() const
{
    QList<QObject *> out;
    out.reserve(m_actions.size());
    for (const auto &a : m_actions) {
        if (a) {
            out << a.data();
        }
    }
    return out;
}

QVariantList AtlasShortcuts::conflicts()
{
    if (m_dirty) {
        recompute();
    }
    return m_conflicts;
}

QKeySequence AtlasShortcuts::toSequence(const QVariant &sequence)
{
    if (sequence.metaType() == QMetaType::fromType<QKeySequence>()) {
        return sequence.value<QKeySequence>();
    }
    switch (sequence.metaType().id()) {
    case QMetaType::QString:
        return QKeySequence::fromString(sequence.toString(), QKeySequence::PortableText);
    case QMetaType::Int:
    case QMetaType::UInt:
    case QMetaType::Long:
    case QMetaType::LongLong:
    case QMetaType::Double: {
        const int n = sequence.toInt();
        // StandardKey numbers are small; anything above is a key code.
        if (n <= 0) {
            return {};
        }
        return n < 0x1000 ? QKeySequence(static_cast<QKeySequence::StandardKey>(n)) : QKeySequence(n);
    }
    default:
        return {};
    }
}

QString AtlasShortcuts::readable(const QVariant &sequence) const
{
    return toSequence(sequence).toString(QKeySequence::NativeText);
}

QString AtlasShortcuts::portable(const QVariant &sequence) const
{
    return toSequence(sequence).toString(QKeySequence::PortableText);
}

QString AtlasShortcuts::plainText(const QString &text) const
{
    return plain(text);
}

QVariantList AtlasShortcuts::keys(const QVariant &sequence) const
{
    const QKeySequence seq = toSequence(sequence);
    QVariantList chords;
    for (int i = 0; i < seq.count(); ++i) {
        const QString chord = QKeySequence(seq[i]).toString(QKeySequence::NativeText);
        if (!chord.isEmpty()) {
            chords << splitKeys(chord);
        }
    }
    return chords;
}

void AtlasShortcuts::add(QObject *action)
{
    if (!action) {
        return;
    }
    for (const auto &a : std::as_const(m_actions)) {
        if (a == action) {
            return;
        }
    }
    m_actions.append(action);

    // Each property the registry watches announces its change to one slot.
    const QMetaObject *mo = action->metaObject();
    const int slot = metaObject()->indexOfSlot("onActionChanged()");
    for (const char *name : {"shortcut", "text", "enabled"}) {
        const QMetaProperty p = mo->property(mo->indexOfProperty(name));
        if (p.isValid() && p.hasNotifySignal()) {
            connect(action, p.notifySignal(), this, metaObject()->method(slot));
        } else {
            qCWarning(lcShortcuts) << "action" << action << "has no notifiable" << name;
        }
    }
    connect(action, &QObject::destroyed, this, &AtlasShortcuts::onActionDestroyed);
    Q_EMIT actionsChanged();
    scheduleRecompute();
}

void AtlasShortcuts::remove(QObject *action)
{
    if (!action) {
        return;
    }
    disconnect(action, nullptr, this, nullptr);
    const qsizetype before = m_actions.size();
    m_actions.removeIf([action](const QPointer<QObject> &a) { return a.isNull() || a == action; });
    if (m_actions.size() != before) {
        Q_EMIT actionsChanged();
        scheduleRecompute();
    }
}

void AtlasShortcuts::onActionDestroyed(QObject *action)
{
    // Only the pointer value is used: the object is already gone.
    m_actions.removeIf([action](const QPointer<QObject> &a) { return a.isNull() || a.data() == action; });
    Q_EMIT actionsChanged();
    scheduleRecompute();
}

void AtlasShortcuts::onActionChanged()
{
    scheduleRecompute();
}

void AtlasShortcuts::scheduleRecompute()
{
    m_dirty = true;
    m_timer.start();
}

void AtlasShortcuts::recompute()
{
    m_timer.stop();
    m_dirty = false;

    struct Entry {
        QObject *window;
        QString text;
    };
    QHash<QString, QList<Entry>> byShortcut;
    QStringList order;
    for (const auto &a : std::as_const(m_actions)) {
        if (!a || !read(a, "enabled").toBool()) {
            continue;
        }
        const QString key = portable(read(a, "shortcut"));
        if (key.isEmpty()) {
            continue;
        }
        if (!byShortcut.contains(key)) {
            order << key;
        }
        byShortcut[key].append({windowOf(a), plain(read(a, "text").toString())});
    }
    std::sort(order.begin(), order.end());

    QVariantList result;
    QSet<QString> now;
    for (const QString &key : std::as_const(order)) {
        const QList<Entry> &entries = byShortcut[key];
        if (entries.size() < 2) {
            continue;
        }
        const qsizetype unknown = std::count_if(entries.begin(), entries.end(), [](const Entry &e) { return !e.window; });
        QHash<QObject *, qsizetype> perWindow;
        for (const Entry &e : entries) {
            if (e.window) {
                ++perWindow[e.window];
            }
        }
        QStringList texts;
        for (const Entry &e : entries) {
            // Alone in a known window, and nothing of unknown window to meet.
            const bool involved = e.window ? (perWindow[e.window] + unknown >= 2) : entries.size() >= 2;
            if (involved) {
                texts << e.text;
            }
        }
        if (texts.size() < 2) {
            continue;
        }
        result.append(QVariantMap{{QStringLiteral("shortcut"), key}, {QStringLiteral("texts"), texts}});
        QStringList sorted = texts;
        sorted.sort();
        const QString id = key + QLatin1Char('\n') + sorted.join(QLatin1Char('\n'));
        now.insert(id);
        if (!m_warned.contains(id)) {
            qCWarning(lcShortcuts).noquote() << "Shortcut conflict:" << key << "is used by" << texts.join(QStringLiteral(", "));
        }
    }
    // A conflict that went away and comes back is a new one.
    m_warned = now;
    if (result != m_conflicts) {
        m_conflicts = result;
        Q_EMIT conflictsChanged();
    }
}
