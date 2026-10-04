// The framework starts the app (atlas-framework-ui, include/atlas/app.h): Qt,
// the app ID and names, one instance per session, logging and crash hooks.
// Then it loads the QML module's Main with the Rust backend.

// Defined by atlas-framework-ui.
extern "C" int atlas_app_run(int argc, char *argv[], const char *qmlModule, const char *qmlType, void *(*makeBackend)());
// Defined in src/lib.rs.
extern "C" void *atlas_backend_new();

int main(int argc, char *argv[])
{
    return atlas_app_run(argc, argv, "net.eterneon.atlas.apptemplate", "Main", atlas_backend_new);
}
