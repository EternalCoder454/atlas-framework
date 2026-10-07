// The framework starts the app (telamon-framework-ui, include/telamon/app.h): Qt,
// the app ID and names, one instance per session, logging and crash hooks.
// Then it loads the QML module's Main with the Rust backend.

#include <telamon/app.h>

// Defined in src/lib.rs.
extern "C" void *telamon_backend_new();

int main(int argc, char *argv[])
{
    return telamon_app_run(argc, argv, "net.eterneon.telamon.apptemplate", "Main", telamon_backend_new);
}
