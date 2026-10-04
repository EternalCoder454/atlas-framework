# atlas-framework: Atlas.Ui, the QML module every Atlas app imports, the
# Material Symbols fonts it draws icons with, and Atlas Symbols, the gallery.
#
#   cmake -S . -B build -G Ninja && cmake --build build
#   build/atlas-symbols                  the gallery, run from the build tree
#
# Apps don't build this: they `import Atlas.Ui` from the installed copy
# (the atlas-ui package). To try a change in an app before it is packaged,
# install it where Qt looks, inside the build container:
#
#   cmake -S . -B build -G Ninja -DCMAKE_INSTALL_PREFIX=/usr
#   cmake --build build && cmake --install build
cmake_minimum_required(VERSION 3.24)
project(atlas-framework VERSION 1.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

include(GNUInstallDirs)
find_package(Qt6 6.11 REQUIRED COMPONENTS Core Gui Qml Quick QuickControls2 Widgets)
qt_policy(SET QTP0001 NEW)
qt_policy(SET QTP0004 NEW)
find_package(KF6WindowSystem REQUIRED)
find_package(KF6Config REQUIRED)

# QML modules land under the build root (build/Atlas/Ui), where qmllint and
# qmlcachegen look, and beside the gallery's executable, where the QML
# engine looks at run time.
set(QT_QML_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR})

add_subdirectory(ui)

option(ATLAS_BUILD_GALLERY "Build Atlas Symbols, the icon gallery" ON)
if(ATLAS_BUILD_GALLERY)
    add_subdirectory(ui/gallery)
endif()
