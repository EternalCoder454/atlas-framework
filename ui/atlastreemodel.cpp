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
        fill(*child, map.value(QStringLiteral("children")).toList(), depth + 1);
        into.children.push_back(std::move(child));
    }
}

void AtlasTreeModel::setItems(const QVariantList &items)
{
    beginResetModel();
    m_items = items;
    m_root.children.clear();
    fill(m_root, items, 0);
    endResetModel();
    Q_EMIT itemsChanged();
}

AtlasTreeModel::Node *AtlasTreeModel::node(const QModelIndex &index) const
{
    return index.isValid() ? static_cast<Node *>(index.internalPointer()) : const_cast<Node *>(&m_root);
}

QModelIndex AtlasTreeModel::index(int row, int column, const QModelIndex &parent) const
{
    if (column != 0 || row < 0 || parent.column() > 0) {
        return {};
    }
    const Node *p = node(parent);
    if (row >= int(p->children.size())) {
        return {};
    }
    return createIndex(row, 0, p->children[size_t(row)].get());
}

QModelIndex AtlasTreeModel::parent(const QModelIndex &child) const
{
    if (!child.isValid()) {
        return {};
    }
    const Node *p = node(child)->parent;
    if (!p || p == &m_root) {
        return {};
    }
    return createIndex(p->row, 0, const_cast<Node *>(p));
}

int AtlasTreeModel::rowCount(const QModelIndex &parent) const
{
    return parent.column() > 0 ? 0 : int(node(parent)->children.size());
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
