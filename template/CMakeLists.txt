cmake_minimum_required(VERSION 3.24)
project(telamon-app-template VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

include(GNUInstallDirs)

find_package(Qt6 6.11 REQUIRED COMPONENTS Core Gui Qml Quick QuickControls2 Widgets)
qt_policy(SET QTP0001 NEW)
find_package(Corrosion REQUIRED)
# telamon-framework-ui's startup code (single instance, window activation)
find_package(KF6DBusAddons REQUIRED)
find_package(KF6WindowSystem REQUIRED)

# Rust crate (static library). cxx-qt-build finds Qt through $QMAKE.
find_program(QMAKE6 NAMES qmake6 qmake REQUIRED)
corrosion_import_crate(MANIFEST_PATH ${CMAKE_CURRENT_SOURCE_DIR}/Cargo.toml CRATES telamon-app-template)
corrosion_set_env_vars(telamon_app_template QMAKE=${QMAKE6})

# The framework's C header (telamon/app.h) comes with the crate's sources, wherever
# cargo put them (this checkout, or a git checkout in ~/.cargo).
find_program(CARGO NAMES cargo REQUIRED)
execute_process(
    COMMAND ${CARGO} metadata --format-version 1 --locked --manifest-path ${CMAKE_CURRENT_SOURCE_DIR}/Cargo.toml
    OUTPUT_VARIABLE CARGO_METADATA
    RESULT_VARIABLE CARGO_METADATA_RESULT
    ERROR_VARIABLE CARGO_METADATA_ERROR
    TIMEOUT 300)
if(NOT CARGO_METADATA_RESULT EQUAL 0)
    message(FATAL_ERROR "cargo metadata failed (${CARGO_METADATA_RESULT}): ${CARGO_METADATA_ERROR}\n"
        "Run `cargo fetch --locked` first, or check the network/vendoring.")
endif()
string(JSON NPACKAGES LENGTH "${CARGO_METADATA}" packages)
math(EXPR LAST_PACKAGE "${NPACKAGES} - 1")
set(TELAMON_UI_CRATE_DIR "")
foreach(i RANGE ${LAST_PACKAGE})
    string(JSON PKG_NAME GET "${CARGO_METADATA}" packages ${i} name)
    if(PKG_NAME STREQUAL "telamon-framework-ui")
        string(JSON PKG_MANIFEST GET "${CARGO_METADATA}" packages ${i} manifest_path)
        get_filename_component(TELAMON_UI_CRATE_DIR "${PKG_MANIFEST}" DIRECTORY)
    endif()
endforeach()
if(NOT EXISTS "${TELAMON_UI_CRATE_DIR}/include/telamon/app.h")
    message(FATAL_ERROR "telamon-framework-ui's include/telamon/app.h not found (looked in '${TELAMON_UI_CRATE_DIR}')")
endif()

qt_add_executable(template-app main.cpp)
target_include_directories(template-app PRIVATE "${TELAMON_UI_CRATE_DIR}/include")
set_target_properties(template-app PROPERTIES OUTPUT_NAME telamon-app-template)

# The shared Telamon look, Telamon.Ui, is installed like Kirigami (the telamon-ui
# package): QML imports it, and nothing links it. qmlcachegen and qmllint read
# its types from the installed copy.
if(NOT EXISTS "${QT6_INSTALL_PREFIX}/${QT6_INSTALL_QML}/Telamon/Ui/qmldir")
    message(FATAL_ERROR "Telamon.Ui is not installed: dnf install telamon-ui (see README.md)")
endif()

# qt_add_qml_module compiles the QML to C++ with qmlcachegen at build time and
# embeds it in the executable: no .qml files are read at run time.

qt_add_qml_module(template-app
    URI net.eterneon.telamon.apptemplate
    VERSION 1.0
    QML_FILES
        qml/Main.qml
        qml/MainPage.qml
)

target_link_libraries(template-app PRIVATE
    telamon_app_template
    Qt6::Core Qt6::Gui Qt6::Qml Qt6::Quick Qt6::QuickControls2 Qt6::Widgets
    KF6::DBusAddons KF6::WindowSystem)

install(TARGETS template-app RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
install(FILES data/net.eterneon.telamon.apptemplate.desktop
        DESTINATION ${CMAKE_INSTALL_DATADIR}/applications)
# The notification events (see src/backend.rs): Plasma reads this for the
# app's name, icon and notification settings. Named <short name>.notifyrc,
# where the short name is "telamon-" and the last part of the app ID.
install(FILES data/telamon-apptemplate.notifyrc
        DESTINATION ${CMAKE_INSTALL_DATADIR}/knotifications6)
# What Telamon Store shows (the name, summary and licence come from the
# metainfo) and the icon the desktop file names; a native bundle
# (tools/make-bundle.sh) carries both.
install(FILES data/net.eterneon.telamon.apptemplate.metainfo.xml
        DESTINATION ${CMAKE_INSTALL_DATADIR}/metainfo)
install(FILES data/net.eterneon.telamon.apptemplate.svg
        DESTINATION ${CMAKE_INSTALL_DATADIR}/icons/hicolor/scalable/apps)
