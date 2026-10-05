#include "atlasshortcuts.h"
#include "atlaslogsafe.h"

#include <QHash>
#include <QLoggingCategory>
#include <QMetaMethod>
#include <QMetaProperty>
#include <QQuickItem>
#include <QQuickWindow>
#include <algorithm>
#include <cmath>
#include <limits>

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

// Where an action works: the window of the nearest Item or window above it.
// `pending` is an Item that is not in a window yet: the answer comes later
// (windowChanged), and until then the action takes part in no conflict. No
// Item or window above at all is the app level: `window` stays null.
struct Place {
    QObject *window = nullptr;
    bool pending = false;
};

Place placeOf(QObject *action)
{
    for (QObject *o = action; o; o = o->parent()) {
        if (auto *item = qobject_cast<QQuickItem *>(o)) {
            QQuickWindow *w = item->window();
            return {w, w == nullptr};
        }
        if (auto *w = qobject_cast<QQuickWindow *>(o)) {
            return {w, false};
        }
    }
    return {};
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

// The last result of recompute(), which runs once per turn of the event loop
// after a change: reading it from a binding never emits a signal.
QVariantList AtlasShortcuts::conflicts() const
{
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
    case QMetaType::ULong:
    case QMetaType::LongLong:
    case QMetaType::ULongLong:
    case QMetaType::Double:
    case QMetaType::Float: {
        // Checked before it is converted: NaN, infinity and values outside
        // int are not keys (a plain cast of them is undefined).
        int n = 0;
        if (sequence.metaType().id() == QMetaType::Double || sequence.metaType().id() == QMetaType::Float) {
            const double d = sequence.toDouble();
            if (!std::isfinite(d) || d < 1 || d > double(std::numeric_limits<int>::max())) {
                return {};
            }
            n = int(d);
        } else {
            bool ok = false;
            const qlonglong ll = sequence.toLongLong(&ok);
            if (!ok || ll < 1 || ll > std::numeric_limits<int>::max()) {
                return {};
            }
            n = int(ll);
        }
        // The StandardKey numbers end at the last enum value; anything above is a key code.
        return n <= static_cast<int>(QKeySequence::Cancel) ? QKeySequence(static_cast<QKeySequence::StandardKey>(n)) : QKeySequence(n);
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
    // An action whose Item is not in a window yet joins the comparison when it is.
    for (QObject *o = action; o; o = o->parent()) {
        if (auto *item = qobject_cast<QQuickItem *>(o)) {
            if (!item->window()) {
                connect(item, &QQuickItem::windowChanged, this, &AtlasShortcuts::onActionChanged, Qt::UniqueConnection);
            }
            break;
        }
    }
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
    // One list per shortcut and window: only actions in the same place conflict.
    QHash<QString, QHash<QObject *, QList<Entry>>> byShortcut;
    QStringList order;
    for (const auto &a : std::as_const(m_actions)) {
        if (!a || !read(a, "enabled").toBool()) {
            continue;
        }
        const Place place = placeOf(a);
        if (place.pending) {
            continue;
        }
        const QString key = portable(read(a, "shortcut"));
        if (key.isEmpty()) {
            continue;
        }
        if (!byShortcut.contains(key)) {
            order << key;
        }
        byShortcut[key][place.window].append({place.window, plain(read(a, "text").toString())});
    }
    std::sort(order.begin(), order.end());

    QVariantList result;
    QSet<QString> now;
    for (const QString &key : std::as_const(order)) {
        QStringList texts;
        const auto &windows = byShortcut[key];
        for (auto it = windows.cbegin(); it != windows.cend(); ++it) {
            if (it.value().size() >= 2) {
                for (const Entry &e : it.value()) {
                    texts << e.text;
                }
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
            qCWarning(lcShortcuts).noquote() << "Shortcut conflict:" << logSafe(key) << "is used by" << logSafe(texts.join(QStringLiteral(", ")));
        }
    }
    // A conflict that went away and comes back is a new one.
    m_warned = now;
    if (result != m_conflicts) {
        m_conflicts = result;
        Q_EMIT conflictsChanged();
    }
}
