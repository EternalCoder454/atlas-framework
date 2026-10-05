// AtlasTreeModel: a read-only tree model for AtlasTreeView (and any Qt Quick
// TreeView) built from nested JS objects, for apps whose tree is small and
// static or rebuilt as a whole; an app with a large or live tree writes its
// own QAbstractItemModel. One column; the roles are `display` (the text),
// `symbol` (a Symbols.<Name> value, 0 if none) and `icon` (an icon name or
// image url, empty if none):
//
//   AtlasTreeModel {
//       id: tree
//       items: [
//           { text: "Documents", symbol: Symbols.Folder, children: [
//               { text: "Report.odt" }, { text: "Notes.md" } ] },
//           { text: "Music" }
//       ]
//   }
//   AtlasTreeView { model: tree; symbolRole: "symbol" }
//
// Setting `items` again replaces the whole tree (the view collapses).
#pragma once

#include <QAbstractItemModel>
#include <QItemSelection>
#include <QVariantList>
#include <QtQml/qqmlregistration.h>

#include <memory>
#include <vector>

class AtlasTreeModel : public QAbstractItemModel
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(QVariantList items READ items WRITE setItems NOTIFY itemsChanged FINAL)

public:
    explicit AtlasTreeModel(QObject *parent = nullptr);
    ~AtlasTreeModel() override;

    QVariantList items() const { return m_items; }
    void setItems(const QVariantList &items);

    QModelIndex index(int row, int column, const QModelIndex &parent = {}) const override;
    QModelIndex parent(const QModelIndex &child) const override;
    int rowCount(const QModelIndex &parent = {}) const override;
    int columnCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    // One selection for the given indexes (the view's rows in view order),
    // so a range of n rows is selected in a single call, not n.
    Q_INVOKABLE QItemSelection selectionOf(const QVariantList &indexes) const;

Q_SIGNALS:
    void itemsChanged();

private:
    struct Node {
        QString text;
        int symbol = 0;
        QString icon;
        Node *parent = nullptr;
        int row = 0;
        std::vector<std::unique_ptr<Node>> children;
    };
    enum Role { SymbolRole = Qt::UserRole + 1, IconRole };

    static constexpr int kMaxDepth = 64;
    void fill(Node &into, const QVariantList &list, int depth);
    Node *node(const QModelIndex &index) const;

    QVariantList m_items;
    Node m_root;
};
