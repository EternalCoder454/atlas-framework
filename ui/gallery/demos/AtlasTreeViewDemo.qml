import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Atlas.Ui

// Visual-test scene for AtlasTreeView: an AtlasTreeModel (QML can't build a
// tree model itself) with two levels expanded and one row selected, and a
// multi-selection tree beside it. Fixed content, no timers or randomness.
Item {
    id: root

    property bool animate: true

    implicitWidth: 560
    implicitHeight: 500
    width: implicitWidth
    height: implicitHeight

    AtlasTreeModel {
        id: files
        items: [
            {
                text: "Documents",
                symbol: Symbols.Folder,
                children: [
                    {
                        text: "Reports",
                        symbol: Symbols.Folder,
                        children: [
                            { text: "Q1.odt", symbol: Symbols.Description },
                            { text: "Q2.odt", symbol: Symbols.Description }
                        ]
                    },
                    { text: "Notes.md", symbol: Symbols.Description }
                ]
            },
            {
                text: "Music",
                symbol: Symbols.Folder,
                children: [
                    { text: "Album One", symbol: Symbols.Folder },
                    { text: "Album Two", symbol: Symbols.Folder }
                ]
            },
            { text: "Readme", symbol: Symbols.Description }
        ]
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 16

        AtlasTreeView {
            id: single
            Layout.fillWidth: true
            Layout.fillHeight: true
            model: files
            symbolRole: "symbol"
            Accessible.name: "Files"
            Component.onCompleted: {
                expandAll();
                // "Q2.odt": the fifth row.
                selectionModel.setCurrentIndex(selectionModel.model.index(1, 0, selectionModel.model.index(0, 0, selectionModel.model.index(0, 0))), ItemSelectionModel.ClearAndSelect);
            }
        }
        AtlasTreeView {
            id: multi
            Layout.fillWidth: true
            Layout.fillHeight: true
            model: files
            selectionMode: AtlasTreeView.MultiSelection
            Accessible.name: "Files, multiple selection"
            Component.onCompleted: {
                expandAll();
                const m = selectionModel.model;
                selectionModel.select(m.index(0, 0), ItemSelectionModel.Select);
                selectionModel.select(m.index(2, 0), ItemSelectionModel.Select);
            }
        }
    }
}
