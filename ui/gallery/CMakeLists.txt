# Atlas Symbols: browse every Material Symbol and copy the QML for one.
# Built by the top-level CMakeLists.txt; run build/atlas-symbols. Installed,
# it uses the installed Atlas.Ui like any app.
qt_add_executable(atlas-symbols main.cpp)
# Beside build/Atlas/Ui, so the QML engine finds the module from the build tree.
set_target_properties(atlas-symbols PROPERTIES RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR})
qt_add_qml_module(atlas-symbols
    URI net.eterneon.atlas.symbols
    VERSION 1.0
    QML_FILES Main.qml
)
target_link_libraries(atlas-symbols PRIVATE
    Qt6::Core Qt6::Gui Qt6::Qml Qt6::Quick Qt6::QuickControls2 Qt6::Widgets)
# qmlcachegen and qmllint check Main.qml against Atlas.Ui.
add_dependencies(atlas-symbols atlasui)

install(TARGETS atlas-symbols RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
install(FILES net.eterneon.atlas.symbols.desktop
        DESTINATION ${CMAKE_INSTALL_DATADIR}/applications)
