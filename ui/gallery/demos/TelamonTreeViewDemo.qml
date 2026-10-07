import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Telamon.Ui

// Visual-test scene for TelamonTreeView: a TelamonTreeModel (QML can't build a
// tree model itself) with two levels expanded and one row selected, and a
// multi-selection tree beside it. Fixed content, no timers or randomness.
Item {
    id: root

    property bool animate: true

    implicitWidth: 560
    implicitHeight: 500
    width: implicitWidth
    height: implicitHeight

    TelamonTreeModel {
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

        TelamonTreeView {
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
        TelamonTreeView {
            id: multi
            Layout.fillWidth: true
            Layout.fillHeight: true
            model: files
            selectionMode: TelamonTreeView.MultiSelection
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
