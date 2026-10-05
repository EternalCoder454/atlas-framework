// A stand-in for xdg-desktop-portal that says "the user wants high contrast".
// Qt reads that from the settings portal (org.freedesktop.appearance, key
// "contrast"); there is no other switch. Used by the visual-contrast test
// (tests/visual/fake-portal.cpp) and by atlas-preview.
#pragma once

#include <QString>

namespace AtlasVariant {

// Serves the answer on the session bus, creates `readyFile` once it does, and
// runs the event loop (a QCoreApplication must exist). Returns an exit code.
// It also ends when its bus connection closes, and after `timeoutSeconds`
// when that is above 0, so it never outlives the run that started it.
int runFakePortal(const QString &readyFile, int timeoutSeconds = 0);

} // namespace AtlasVariant
