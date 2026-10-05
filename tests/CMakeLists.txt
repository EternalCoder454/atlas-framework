# Tests for Atlas.Ui, built with -DATLAS_UI_TESTS=ON and run with ctest:
#
#   cmake -S . -B build -G Ninja -DATLAS_UI_TESTS=ON
#   cmake --build build && ctest --test-dir build --output-on-failure
#
#   visual-<variant>   every ui/gallery/demos/*Demo.qml against its golden
#                      (tests/visual/golden/<variant>/<Demo>.png)
#   ATLAS_UPDATE_GOLDENS=1 ctest ...   rewrites the goldens
#   i18n               a throwaway German catalogue: Atlas.Ui's qsTr() strings
#                      come back translated (tests/i18n)
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

# Behaviour of the field controls (tests/fields): AtlasAutocompleteField's
# keyboard handling, AtlasColorField's hex parsing.
add_executable(atlas-fields-tests fields/main.cpp)
target_compile_definitions(atlas-fields-tests PRIVATE
    QUICK_TEST_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}/fields")
target_link_libraries(atlas-fields-tests PRIVATE
    Qt6::QuickTest Qt6::Quick Qt6::QuickControls2 Qt6::Widgets)
add_dependencies(atlas-fields-tests atlasui)
add_test(NAME fields
    COMMAND ${CMAKE_CURRENT_SOURCE_DIR}/visual/run-variant.sh light)
set_tests_properties(fields PROPERTIES
    TIMEOUT 120
    ENVIRONMENT "ATLAS_TEST_BIN=$<TARGET_FILE:atlas-fields-tests>;ATLAS_DEMO_DIR=${PROJECT_SOURCE_DIR}/ui/gallery/demos;ATLAS_GOLDEN_DIR=${CMAKE_CURRENT_SOURCE_DIR}/visual/golden;ATLAS_OUT_DIR=${CMAKE_BINARY_DIR}/fields-out;QML_IMPORT_PATH=${CMAKE_BINARY_DIR}")

# The translation test: a throwaway atlas-ui_de.qm (tests/i18n) in a directory
# of its own, found through ATLAS_UI_TRANSLATIONS_DIR (development builds only).
find_package(Qt6 6.11 QUIET COMPONENTS LinguistTools)
if(Qt6LinguistTools_FOUND AND ATLAS_UI_DEV_BUILD)
    qt_add_lrelease(TS_FILES i18n/atlas-ui_de.ts
        QM_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/i18n-qm
        LRELEASE_TARGET atlas-ui_test_translations
        NO_GLOBAL_TARGET)
    add_executable(atlas-i18n-tests i18n/main.cpp)
    target_compile_definitions(atlas-i18n-tests PRIVATE
        QUICK_TEST_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}/i18n")
    target_link_libraries(atlas-i18n-tests PRIVATE
        Qt6::QuickTest Qt6::Quick Qt6::QuickControls2 Qt6::Widgets)
    add_dependencies(atlas-i18n-tests atlasui atlas-ui_test_translations)
    add_test(NAME i18n
        COMMAND ${CMAKE_CURRENT_SOURCE_DIR}/visual/run-variant.sh light)
    set_tests_properties(i18n PROPERTIES
        TIMEOUT 120
        ENVIRONMENT "ATLAS_TEST_BIN=$<TARGET_FILE:atlas-i18n-tests>;ATLAS_DEMO_DIR=${PROJECT_SOURCE_DIR}/ui/gallery/demos;ATLAS_GOLDEN_DIR=${CMAKE_CURRENT_SOURCE_DIR}/visual/golden;ATLAS_OUT_DIR=${CMAKE_BINARY_DIR}/i18n-out;QML_IMPORT_PATH=${CMAKE_BINARY_DIR};LANGUAGE=de;LANG=de_DE.UTF-8;LC_ALL=de_DE.UTF-8;ATLAS_UI_TRANSLATIONS_DIR=${CMAKE_BINARY_DIR}/i18n-qm")
endif()

# The shortcut registry (ui/atlasshortcuts.cpp, compiled into the test):
# add, remove, conflicts, destroyed actions.
find_package(Qt6 6.11 REQUIRED COMPONENTS Test)
add_executable(atlas-shortcuts-tests shortcuts/tst_shortcuts.cpp
    ${PROJECT_SOURCE_DIR}/ui/atlasshortcuts.h ${PROJECT_SOURCE_DIR}/ui/atlasshortcuts.cpp)
target_include_directories(atlas-shortcuts-tests PRIVATE ${PROJECT_SOURCE_DIR}/ui)
target_link_libraries(atlas-shortcuts-tests PRIVATE Qt6::Test Qt6::Quick Qt6::Qml)
add_test(NAME shortcuts COMMAND atlas-shortcuts-tests)
set_tests_properties(shortcuts PROPERTIES TIMEOUT 60 ENVIRONMENT "QT_QPA_PLATFORM=offscreen")
