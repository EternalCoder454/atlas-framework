# apidump: lists Atlas.Ui's public API for tools/check-api.sh. Built with
# -DATLAS_UI_TESTS=ON; not installed.
add_executable(apidump main.cpp)
set_target_properties(apidump PROPERTIES RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR})
target_link_libraries(apidump PRIVATE Qt6::Core Qt6::Gui Qt6::Qml Qt6::Quick Qt6::Widgets)
# It loads the module from the build tree.
add_dependencies(apidump atlasui)
