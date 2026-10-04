# Atlas Gallery: every Atlas.Ui control, live, and every Material Symbol with
# the QML to copy. Built by the top-level CMakeLists.txt; run
# build/atlas-symbols (the binary and app ID keep the name they shipped as).
# Installed, it uses the installed Atlas.Ui like any app.
qt_add_executable(atlas-symbols main.cpp)
# Beside build/Atlas/Ui, so the QML engine finds the module from the build tree.
set_target_properties(atlas-symbols PROPERTIES RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR})
qt_add_qml_module(atlas-symbols
    URI net.eterneon.atlas.symbols
    VERSION 1.0
    QML_FILES Main.qml SymbolsPage.qml ControlsPage.qml
)

# The demos (also the visual tests' scenes) and their images, compiled in as
# plain files: the Controls page loads them by URL, and they import Atlas.Ui
# like any app. They are not part of the module, so qmllint leaves them to
# the tests.
file(GLOB demo_files CONFIGURE_DEPENDS
    ${CMAKE_CURRENT_SOURCE_DIR}/demos/*Demo.qml)
file(GLOB demo_images CONFIGURE_DEPENDS
    ${CMAKE_CURRENT_SOURCE_DIR}/demos/images/*)
qt_add_resources(atlas-symbols atlas-gallery-demos
    PREFIX /net/eterneon/atlas/symbols/demos
    BASE ${CMAKE_CURRENT_SOURCE_DIR}/demos
    FILES ${demo_files} ${demo_images}
)

# snippets.json: the demo list and, for each control, the example from the
# header comment of ui/<Type>.qml (see snippets.cmake). Regenerated when a
# control's file, a demo or the script changes.
file(GLOB control_files CONFIGURE_DEPENDS ${CMAKE_SOURCE_DIR}/ui/*.qml)
set(snippets_json ${CMAKE_CURRENT_BINARY_DIR}/snippets.json)
add_custom_command(
    OUTPUT ${snippets_json}
    COMMAND ${CMAKE_COMMAND} -DUI_DIR=${CMAKE_SOURCE_DIR}/ui
            -DDEMOS_DIR=${CMAKE_CURRENT_SOURCE_DIR}/demos -DOUT=${snippets_json}
            -P ${CMAKE_CURRENT_SOURCE_DIR}/snippets.cmake
    DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/snippets.cmake ${control_files}
            ${demo_files}
    COMMENT "Generating the gallery's snippets.json"
    VERBATIM
)
set_source_files_properties(${snippets_json} PROPERTIES GENERATED TRUE)
qt_add_resources(atlas-symbols atlas-gallery-snippets
    PREFIX /net/eterneon/atlas/symbols
    BASE ${CMAKE_CURRENT_BINARY_DIR}
    FILES ${snippets_json}
)

target_link_libraries(atlas-symbols PRIVATE
    Qt6::Core Qt6::Gui Qt6::Qml Qt6::Quick Qt6::QuickControls2 Qt6::Widgets)
# qmlcachegen and qmllint check the pages against Atlas.Ui.
add_dependencies(atlas-symbols atlasui)

install(TARGETS atlas-symbols RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
install(FILES net.eterneon.atlas.symbols.desktop
        DESTINATION ${CMAKE_INSTALL_DATADIR}/applications)
