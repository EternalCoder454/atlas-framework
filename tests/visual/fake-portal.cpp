// A stand-in for xdg-desktop-portal, for the visual-contrast variant only (the
// code is in tools/preview/fakeportal.cpp). run-variant.sh starts it, waits
// for the file named by argv[1], and the app then runs with
// QT_QPA_PLATFORMTHEME=xdgdesktopportal.
//
//   fake-portal <ready-file>
#include "../../tools/preview/fakeportal.h"

#include <QCoreApplication>

#include <cstdio>

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    if (argc != 2) {
        std::fprintf(stderr, "usage: fake-portal <ready-file>\n");
        return 2;
    }
    return AtlasVariant::runFakePortal(QString::fromLocal8Bit(argv[1]));
}
