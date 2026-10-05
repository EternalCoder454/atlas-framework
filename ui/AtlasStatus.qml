pragma Singleton
import QtQml

// What a view shows instead of its rows: the values of `status` on
// AtlasListView, DataTable, AtlasTreeView and AtlasPage. A singleton that
// only holds the enum, so `AtlasStatus.Loading` reads the same in every app;
// nothing to create. See docs/reference/atlas-ui/atlas-status.md.
//
//   AtlasListView {
//       status: files.loading ? AtlasStatus.Loading : AtlasStatus.Ready
//   }
QtObject {
    enum Status {
        Ready,
        Loading,
        Empty,
        NoResults,
        Error
    }
}
