# Tests for Atlas.Ui, built with -DATLAS_UI_TESTS=ON and run with ctest:
#
#   cmake -S . -B build -G Ninja -DATLAS_UI_TESTS=ON
#   cmake --build build && ctest --test-dir build --output-on-failure
#
#   visual-<variant>   every ui/gallery/demos/*Demo.qml against its golden
#                      (tests/visual/golden/<variant>/<Demo>.png)
#   ATLAS_UPDATE_GOLDENS=1 ctest ...   rewrites the goldens
#   a11y               every demo's item tree: what Tab reaches needs an
#                      Accessible.role and name (tests/a11y)
find_package(Qt6 6.11 REQUIRED COMPONENTS QuickTest)

add_executable(atlas-visual-tests visual/main.cpp demolist.h)
target_compile_definitions(atlas-visual-tests PRIVATE
    QUICK_TEST_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}/visual")
# Widgets selects QApplication, which the org.kde.desktop style needs.
target_link_libraries(atlas-visual-tests PRIVATE
    Qt6::QuickTest Qt6::Quick Qt6::QuickControls2 Qt6::Widgets)
# The demos import Atlas.Ui: it must be built first.
add_dependencies(atlas-visual-tests atlasui)

foreach(variant light dark accent opaque)
    add_test(NAME visual-${variant}
        COMMAND ${CMAKE_CURRENT_SOURCE_DIR}/visual/run-variant.sh ${variant})
    set_tests_properties(visual-${variant} PROPERTIES
        TIMEOUT 600
        ENVIRONMENT "ATLAS_TEST_BIN=$<TARGET_FILE:atlas-visual-tests>;ATLAS_DEMO_DIR=${PROJECT_SOURCE_DIR}/ui/gallery/demos;ATLAS_GOLDEN_DIR=${CMAKE_CURRENT_SOURCE_DIR}/visual/golden;ATLAS_OUT_DIR=${CMAKE_BINARY_DIR}/visual-out;QML_IMPORT_PATH=${CMAKE_BINARY_DIR}")
endforeach()

# The accessibility test: the same demos, the same private environment as the
# visual tests (run-variant.sh light).
add_executable(atlas-a11y-tests a11y/main.cpp demolist.h)
target_compile_definitions(atlas-a11y-tests PRIVATE
    QUICK_TEST_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}/a11y")
target_link_libraries(atlas-a11y-tests PRIVATE
    Qt6::QuickTest Qt6::Quick Qt6::QuickControls2 Qt6::Widgets)
add_dependencies(atlas-a11y-tests atlasui)
add_test(NAME a11y
    COMMAND ${CMAKE_CURRENT_SOURCE_DIR}/visual/run-variant.sh light)
set_tests_properties(a11y PROPERTIES
    TIMEOUT 300
    ENVIRONMENT "ATLAS_TEST_BIN=$<TARGET_FILE:atlas-a11y-tests>;ATLAS_DEMO_DIR=${PROJECT_SOURCE_DIR}/ui/gallery/demos;ATLAS_GOLDEN_DIR=${CMAKE_CURRENT_SOURCE_DIR}/visual/golden;ATLAS_OUT_DIR=${CMAKE_BINARY_DIR}/a11y-out;QML_IMPORT_PATH=${CMAKE_BINARY_DIR}")
