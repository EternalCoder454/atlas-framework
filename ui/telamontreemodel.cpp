#include "telamontreemodel.h"

#include <QLoggingCategory>
#include <QVariantMap>

#include <cmath>
#include <limits>

Q_LOGGING_CATEGORY(lcTree, "telamon.ui.tree")

TelamonTreeModel::TelamonTreeModel(QObject *parent)
    : QAbstractItemModel(parent)
{
}

TelamonTreeModel::~TelamonTreeModel() = default;

// Builds the nodes under `into` from the list's objects. Entries that aren't
// objects are skipped; nesting deeper than kMaxDepth is dropped, so a
// self-referencing value can't run away; nodes past kMaxNodes are dropped
// (one warning per setItems()).
void TelamonTreeModel::fill(Node &into, const QVariantList &list, int depth)
{
    if (depth > kMaxDepth) {
        return;
    }
    for (const QVariant &entry : list) {
        if (m_nodes.size() >= kMaxNodes) {
            if (!m_capWarned) {
                m_capWarned = true;
                qCWarning(lcTree) << "TelamonTreeModel: more than" << kMaxNodes << "nodes; the rest are dropped";
            }
            return;
        }
        const QVariantMap map = entry.toMap();
        if (map.isEmpty()) {
            continue;
        }
        auto child = std::make_unique<Node>();
        child->text = map.value(QStringLiteral("text")).toString();
        // A JS number: NaN, infinity and out-of-range values are "no symbol".
        const double sym = map.value(QStringLiteral("symbol")).toDouble();
        child->symbol = (std::isfinite(sym) && sym >= 0 && sym <= double(std::numeric_limits<int>::max())) ? int(sym) : 0;
        child->icon = map.value(QStringLiteral("icon")).toString();
        child->parent = &into;
        child->row = int(into.children.size());
        m_nodes.insert(child.get());
        fill(*child, map.value(QStringLiteral("children")).toList(), depth + 1);
        into.children.push_back(std::move(child));
    }
}

void TelamonTreeModel::setItems(const QVariantList &items)
{
    beginResetModel();
    m_items = items;
    m_root.children.clear();
    m_nodes.clear();
    m_capWarned = false;
    fill(m_root, items, 0);
    endResetModel();
    Q_EMIT itemsChanged();
}

// The node of an index, the root for the invalid index, and nullptr for an
// index that is not a live node of this model (another model's, or one that
// outlived a setItems()): the pointer is never followed before it is checked.
// Best effort: a node of a newer tree at the same address and row as an old
// one is taken for it.
TelamonTreeModel::Node *TelamonTreeModel::node(const QModelIndex &index) const
{
    if (!index.isValid()) {
        return const_cast<Node *>(&m_root);
    }
    if (index.model() != this || index.column() != 0) {
        return nullptr;
    }
    const auto *n = static_cast<const Node *>(index.internalPointer());
    return m_nodes.count(n) && n->row == index.row() ? const_cast<Node *>(n) : nullptr;
}

QModelIndex TelamonTreeModel::index(int row, int column, const QModelIndex &parent) const
{
    if (column != 0 || row < 0 || parent.column() > 0) {
        return {};
    }
    const Node *p = node(parent);
    if (!p || row >= int(p->children.size())) {
        return {};
    }
    return createIndex(row, 0, p->children[size_t(row)].get());
}

QModelIndex TelamonTreeModel::parent(const QModelIndex &child) const
{
    if (!child.isValid()) {
        return {};
    }
    const Node *self = node(child);
    const Node *p = self ? self->parent : nullptr;
    if (!p || p == &m_root) {
        return {};
    }
    return createIndex(p->row, 0, const_cast<Node *>(p));
}

int TelamonTreeModel::rowCount(const QModelIndex &parent) const
{
    const Node *n = parent.column() > 0 ? nullptr : node(parent);
    return n ? int(n->children.size()) : 0;
}

int TelamonTreeModel::columnCount(const QModelIndex &) const
{
    return 1;
}

QVariant TelamonTreeModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid()) {
        return {};
    }
    const Node *n = node(index);
    if (!n) {
        return {};
    }
    switch (role) {
    case Qt::DisplayRole:
        return n->text;
    case SymbolRole:
        return n->symbol;
    case IconRole:
        return n->icon;
    default:
        return {};
    }
}

QHash<int, QByteArray> TelamonTreeModel::roleNames() const
{
    return {{Qt::DisplayRole, "display"}, {SymbolRole, "symbol"}, {IconRole, "icon"}};
}

// Indexes that aren't this model's are skipped. Neighbours in the same parent
// join into one range, so a run of siblings costs one range.
QItemSelection TelamonTreeModel::_selectionOf(const QVariantList &indexes) const
{
    QItemSelection selection;
    QModelIndex runStart;
    QModelIndex runEnd;
    const auto flush = [&] {
        if (runStart.isValid()) {
            selection.append(QItemSelectionRange(runStart, runEnd));
        }
        runStart = runEnd = QModelIndex();
    };
    for (const QVariant &v : indexes) {
        const QModelIndex idx = v.value<QModelIndex>();
        if (!idx.isValid() || idx.model() != this || idx.column() != 0 || !node(idx)) {
            continue;
        }
        if (runStart.isValid() && idx.parent() == runEnd.parent() && idx.row() == runEnd.row() + 1) {
            runEnd = idx;
            continue;
        }
        flush();
        runStart = runEnd = idx;
    }
    flush();
    return selection;
}
