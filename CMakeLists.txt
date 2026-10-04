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
# The version is the Atlas.Ui version: AtlasApp.uiVersion reports it, and apps
# name the oldest one they work with (`ui:` in atlas_framework_ui::app!).
project(atlas-framework VERSION 1.3.0 LANGUAGES CXX)

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

# Development paths: Atlas.Ui reads the symbol fonts from ui/symbols (or
# $ATLAS_UI_SYMBOLS_DIR), translations from the build tree (or
# $ATLAS_UI_TRANSLATIONS_DIR) and honours $ATLAS_UI_TEST_FIXED_ENV. A packaged
# build must have none of them: it is loaded into every Atlas app, so it holds
# no path into the source tree and reads nothing its environment names. On by
# default for any install prefix but /usr; off for /usr unless asked.
if(CMAKE_INSTALL_PREFIX STREQUAL "/usr")
    set(_atlas_dev_default OFF)
else()
    set(_atlas_dev_default ON)
endif()
option(ATLAS_UI_DEV_PATHS "Atlas.Ui: look in the source and build trees, honour development environment variables" ${_atlas_dev_default})
if(ATLAS_UI_TESTS AND NOT ATLAS_UI_DEV_PATHS)
    message(STATUS "ATLAS_UI_TESTS=ON: forcing ATLAS_UI_DEV_PATHS=ON (the tests need the build-tree paths and test hooks)")
    set(ATLAS_UI_DEV_PATHS ON CACHE BOOL "" FORCE)
endif()
if(ATLAS_UI_DEV_PATHS)
    message(STATUS "ATLAS_UI_DEV_PATHS=ON: Atlas.Ui reads source- and build-tree paths (not for packages)")
endif()

add_subdirectory(ui)

option(ATLAS_BUILD_GALLERY "Build Atlas Symbols, the icon gallery" ON)
if(ATLAS_BUILD_GALLERY)
    add_subdirectory(ui/gallery)
endif()

# The visual tests and the API dump behind tools/check-api.sh: for CI and
# reviewers, not packaged (the RPM build leaves this off).
option(ATLAS_UI_TESTS "Build the Atlas.Ui visual tests and the API dump tool" OFF)
if(ATLAS_UI_TESTS)
    enable_testing()
    add_subdirectory(tests)
    add_subdirectory(tools/apidump)
endif()
