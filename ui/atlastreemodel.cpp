#include "atlastreemodel.h"

#include <QVariantMap>

AtlasTreeModel::AtlasTreeModel(QObject *parent)
    : QAbstractItemModel(parent)
{
}

AtlasTreeModel::~AtlasTreeModel() = default;

// Builds the nodes under `into` from the list's objects. Entries that aren't
// objects are skipped; nesting deeper than kMaxDepth is dropped, so a
// self-referencing value can't run away.
void AtlasTreeModel::fill(Node &into, const QVariantList &list, int depth)
{
    if (depth > kMaxDepth) {
        return;
    }
    for (const QVariant &entry : list) {
        const QVariantMap map = entry.toMap();
        if (map.isEmpty()) {
            continue;
        }
        auto child = std::make_unique<Node>();
        child->text = map.value(QStringLiteral("text")).toString();
        child->symbol = map.value(QStringLiteral("symbol")).toInt();
        child->icon = map.value(QStringLiteral("icon")).toString();
        child->parent = &into;
        child->row = int(into.children.size());
        m_nodes.insert(child.get());
        fill(*child, map.value(QStringLiteral("children")).toList(), depth + 1);
        into.children.push_back(std::move(child));
    }
}

void AtlasTreeModel::setItems(const QVariantList &items)
{
    beginResetModel();
    m_items = items;
    m_root.children.clear();
    m_nodes.clear();
    fill(m_root, items, 0);
    endResetModel();
    Q_EMIT itemsChanged();
}

// The node of an index, the root for the invalid index, and nullptr for an
// index that is not a live node of this model (another model's, or one that
// outlived a setItems()): the pointer is never followed before it is checked.
AtlasTreeModel::Node *AtlasTreeModel::node(const QModelIndex &index) const
{
    if (!index.isValid()) {
        return const_cast<Node *>(&m_root);
    }
    if (index.model() != this || index.column() != 0) {
        return nullptr;
    }
    const auto *n = static_cast<const Node *>(index.internalPointer());
    return m_nodes.count(n) ? const_cast<Node *>(n) : nullptr;
}

QModelIndex AtlasTreeModel::index(int row, int column, const QModelIndex &parent) const
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

QModelIndex AtlasTreeModel::parent(const QModelIndex &child) const
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

int AtlasTreeModel::rowCount(const QModelIndex &parent) const
{
    const Node *n = parent.column() > 0 ? nullptr : node(parent);
    return n ? int(n->children.size()) : 0;
}

int AtlasTreeModel::columnCount(const QModelIndex &) const
{
    return 1;
}

QVariant AtlasTreeModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.column() != 0) {
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

QHash<int, QByteArray> AtlasTreeModel::roleNames() const
{
    return {{Qt::DisplayRole, "display"}, {SymbolRole, "symbol"}, {IconRole, "icon"}};
}

// Indexes that aren't this model's are skipped. Neighbours in the same parent
// join into one range, so a run of siblings costs one range.
QItemSelection AtlasTreeModel::_selectionOf(const QVariantList &indexes) const
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
        if (!idx.isValid() || idx.model() != this) {
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
