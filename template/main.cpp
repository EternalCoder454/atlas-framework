// The framework starts the app (atlas-framework-ui, include/atlas/app.h): Qt,
// the app ID and names, one instance per session, logging and crash hooks.
// Then it loads the QML module's Main with the Rust backend.

#include <atlas/app.h>

// Defined in src/lib.rs.
extern "C" void *atlas_backend_new();

int main(int argc, char *argv[])
{
    return atlas_app_run(argc, argv, "net.eterneon.atlas.apptemplate", "Main", atlas_backend_new);
}
