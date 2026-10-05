# atlas-preview: loads an app's QML page offscreen in the visual-test matrix and
# writes one PNG per variant (tools/README.md). Installed with Atlas.Ui.
#
# atlas-variant is the part tests/visual shares with it: the variants' fonts,
# palette and colour schemes, and the settings-portal stand-in the contrast
# variant needs. The schemes are compiled in, so the installed tool holds no
# path into the source tree.
qt_add_library(atlas-variant STATIC variant.cpp fakeportal.cpp)
target_link_libraries(atlas-variant PUBLIC Qt6::Core Qt6::Gui Qt6::DBus)
target_include_directories(atlas-variant PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
set_target_properties(atlas-variant PROPERTIES AUTOMOC ON POSITION_INDEPENDENT_CODE ON)
qt_add_resources(atlas-variant atlas-variant-schemes
    PREFIX /atlas-preview/schemes
    BASE ${PROJECT_SOURCE_DIR}/tests/visual/schemes
    FILES
        ${PROJECT_SOURCE_DIR}/tests/visual/schemes/BreezeLight.colors
        ${PROJECT_SOURCE_DIR}/tests/visual/schemes/BreezeDark.colors
        ${PROJECT_SOURCE_DIR}/tests/visual/schemes/BreezeHighContrast.colors)

qt_add_executable(atlas-preview main.cpp)
target_link_libraries(atlas-preview PRIVATE atlas-variant
    Qt6::Core Qt6::Gui Qt6::Qml Qt6::Quick Qt6::QuickControls2 Qt6::Widgets)
# Beside build/Atlas/Ui, like the gallery, so the tests find the module.
set_target_properties(atlas-preview PROPERTIES RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR})
add_dependencies(atlas-preview atlasui)

install(TARGETS atlas-preview RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
