pragma Singleton
import QtQml

// What a view shows instead of its rows: the values of `status` on
// TelamonListView, DataTable, TelamonTreeView and TelamonPage. A singleton that
// only holds the enum, so `TelamonStatus.Loading` reads the same in every app;
// nothing to create. See docs/reference/telamon-ui/telamon-status.md.
//
//   TelamonListView {
//       status: files.loading ? TelamonStatus.Loading : TelamonStatus.Ready
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
