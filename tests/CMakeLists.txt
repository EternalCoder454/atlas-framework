# Tests for Atlas.Ui, built with -DATLAS_UI_TESTS=ON and run with ctest:
#
#   cmake -S . -B build -G Ninja -DATLAS_UI_TESTS=ON
#   cmake --build build && ctest --test-dir build --output-on-failure
#
#   visual-<variant>   every ui/gallery/demos/*Demo.qml against its golden
#                      (tests/visual/golden/<variant>/<Demo>.png)
#                      variants: light dark accent opaque contrast rtl compact text200
#   ATLAS_UPDATE_GOLDENS=1 ctest ...   rewrites the goldens
#   i18n               a throwaway German catalogue: Atlas.Ui's qsTr() strings
#                      come back translated (tests/i18n)
#   state-<n>          every demo against the state contract of docs/DESIGN.md
#                      (disabled, keyboard focus), in 4 shards (tests/state)
#   a11y               every demo's item tree: what Tab reaches needs an
#                      Accessible.role and name, and Tab goes in reading
#                      order and Shift+Tab back the same way (tests/a11y)
find_package(Qt6 6.11 REQUIRED COMPONENTS QuickTest DBus)

add_executable(atlas-visual-tests visual/main.cpp demolist.h)
target_compile_definitions(atlas-visual-tests PRIVATE
    QUICK_TEST_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}/visual")
# Widgets selects QApplication, which the org.kde.desktop style needs.
target_link_libraries(atlas-visual-tests PRIVATE
    Qt6::QuickTest Qt6::Quick Qt6::QuickControls2 Qt6::Widgets)
# The demos import Atlas.Ui: it must be built first.
add_dependencies(atlas-visual-tests atlasui)

# The contrast variant needs a settings portal to say "high contrast" (see
# visual/fake-portal.cpp).
add_executable(atlas-fake-portal visual/fake-portal.cpp)
set_target_properties(atlas-fake-portal PROPERTIES AUTOMOC ON)
target_link_libraries(atlas-fake-portal PRIVATE Qt6::Core Qt6::DBus)

foreach(variant light dark accent opaque contrast rtl compact text200)
    add_test(NAME visual-${variant}
        COMMAND ${CMAKE_CURRENT_SOURCE_DIR}/visual/run-variant.sh ${variant})
    set_tests_properties(visual-${variant} PROPERTIES
        TIMEOUT 600
        ENVIRONMENT "ATLAS_TEST_BIN=$<TARGET_FILE:atlas-visual-tests>;ATLAS_FAKE_PORTAL=$<TARGET_FILE:atlas-fake-portal>;ATLAS_DEMO_DIR=${PROJECT_SOURCE_DIR}/ui/gallery/demos;ATLAS_GOLDEN_DIR=${CMAKE_CURRENT_SOURCE_DIR}/visual/golden;ATLAS_OUT_DIR=${CMAKE_BINARY_DIR}/visual-out;QML_IMPORT_PATH=${CMAKE_BINARY_DIR}")
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

# The state-contract test: disabled controls take no focus and look different,
# a control Tab reaches shows keyboard focus. Four shards run in parallel.
add_executable(atlas-state-tests state/main.cpp demolist.h)
target_compile_definitions(atlas-state-tests PRIVATE
    QUICK_TEST_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}/state")
target_link_libraries(atlas-state-tests PRIVATE
    Qt6::QuickTest Qt6::Quick Qt6::QuickControls2 Qt6::Widgets)
add_dependencies(atlas-state-tests atlasui)
foreach(shard RANGE 0 3)
    add_test(NAME state-${shard}
        COMMAND ${CMAKE_CURRENT_SOURCE_DIR}/visual/run-variant.sh light)
    set_tests_properties(state-${shard} PROPERTIES
        TIMEOUT 300
        ENVIRONMENT "ATLAS_TEST_BIN=$<TARGET_FILE:atlas-state-tests>;ATLAS_STATE_SHARD=${shard}/4;ATLAS_DEMO_DIR=${PROJECT_SOURCE_DIR}/ui/gallery/demos;ATLAS_GOLDEN_DIR=${CMAKE_CURRENT_SOURCE_DIR}/visual/golden;ATLAS_OUT_DIR=${CMAKE_BINARY_DIR}/state-out-${shard};QML_IMPORT_PATH=${CMAKE_BINARY_DIR}")
endforeach()
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

# Behaviour of AtlasListView (tests/lists): selection, keyboard, signals,
# type-ahead.
add_executable(atlas-lists-tests lists/main.cpp)
target_compile_definitions(atlas-lists-tests PRIVATE
    QUICK_TEST_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}/lists")
target_link_libraries(atlas-lists-tests PRIVATE
    Qt6::QuickTest Qt6::Quick Qt6::QuickControls2 Qt6::Widgets)
add_dependencies(atlas-lists-tests atlasui)
add_test(NAME lists
    COMMAND ${CMAKE_CURRENT_SOURCE_DIR}/visual/run-variant.sh light)
set_tests_properties(lists PROPERTIES
    TIMEOUT 120
    ENVIRONMENT "ATLAS_TEST_BIN=$<TARGET_FILE:atlas-lists-tests>;ATLAS_DEMO_DIR=${PROJECT_SOURCE_DIR}/ui/gallery/demos;ATLAS_GOLDEN_DIR=${CMAKE_CURRENT_SOURCE_DIR}/visual/golden;ATLAS_OUT_DIR=${CMAKE_BINARY_DIR}/lists-out;QML_IMPORT_PATH=${CMAKE_BINARY_DIR}")
# DataTable behaviour: selection, column resize and visibility, the row menu
# (tests/tables).
add_executable(atlas-tables-tests tables/main.cpp)
target_compile_definitions(atlas-tables-tests PRIVATE
    QUICK_TEST_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}/tables")
target_link_libraries(atlas-tables-tests PRIVATE
    Qt6::QuickTest Qt6::Quick Qt6::QuickControls2 Qt6::Widgets)
add_dependencies(atlas-tables-tests atlasui)
add_test(NAME tables
    COMMAND ${CMAKE_CURRENT_SOURCE_DIR}/visual/run-variant.sh light)
set_tests_properties(tables PROPERTIES
    TIMEOUT 120
    ENVIRONMENT "ATLAS_TEST_BIN=$<TARGET_FILE:atlas-tables-tests>;ATLAS_DEMO_DIR=${PROJECT_SOURCE_DIR}/ui/gallery/demos;ATLAS_GOLDEN_DIR=${CMAKE_CURRENT_SOURCE_DIR}/visual/golden;ATLAS_OUT_DIR=${CMAKE_BINARY_DIR}/tables-out;QML_IMPORT_PATH=${CMAKE_BINARY_DIR}")

# The frameless window (tests/chrome): AtlasHeaderBar's drag and double click,
# AtlasWindow's resize handles and cursors, AtlasWindowChrome's button layout.
add_executable(atlas-chrome-tests chrome/main.cpp)
target_compile_definitions(atlas-chrome-tests PRIVATE
    QUICK_TEST_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}/chrome")
target_link_libraries(atlas-chrome-tests PRIVATE
    Qt6::QuickTest Qt6::Quick Qt6::QuickControls2 Qt6::Widgets)
add_dependencies(atlas-chrome-tests atlasui)
add_test(NAME chrome
    COMMAND ${CMAKE_CURRENT_SOURCE_DIR}/visual/run-variant.sh light)
set_tests_properties(chrome PROPERTIES
    TIMEOUT 120
    ENVIRONMENT "ATLAS_TEST_BIN=$<TARGET_FILE:atlas-chrome-tests>;ATLAS_DEMO_DIR=${PROJECT_SOURCE_DIR}/ui/gallery/demos;ATLAS_GOLDEN_DIR=${CMAKE_CURRENT_SOURCE_DIR}/visual/golden;ATLAS_OUT_DIR=${CMAKE_BINARY_DIR}/chrome-out;QML_IMPORT_PATH=${CMAKE_BINARY_DIR}")

# ToolbarButton's keys and AtlasProgressBar's layout (tests/input).
add_executable(atlas-input-tests input/main.cpp)
target_compile_definitions(atlas-input-tests PRIVATE
    QUICK_TEST_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}/input")
target_link_libraries(atlas-input-tests PRIVATE
    Qt6::QuickTest Qt6::Quick Qt6::QuickControls2 Qt6::Widgets)
add_dependencies(atlas-input-tests atlasui)
add_test(NAME input
    COMMAND ${CMAKE_CURRENT_SOURCE_DIR}/visual/run-variant.sh light)
set_tests_properties(input PROPERTIES
    TIMEOUT 120
    ENVIRONMENT "ATLAS_TEST_BIN=$<TARGET_FILE:atlas-input-tests>;ATLAS_DEMO_DIR=${PROJECT_SOURCE_DIR}/ui/gallery/demos;ATLAS_GOLDEN_DIR=${CMAKE_CURRENT_SOURCE_DIR}/visual/golden;ATLAS_OUT_DIR=${CMAKE_BINARY_DIR}/input-out;QML_IMPORT_PATH=${CMAKE_BINARY_DIR}")

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

# The date and time controls: keyboard navigation, minimum and maximum, minute
# snapping (tests/dates). Same private environment as the visual tests.
add_executable(atlas-dates-tests dates/main.cpp)
target_compile_definitions(atlas-dates-tests PRIVATE
    QUICK_TEST_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}/dates")
target_link_libraries(atlas-dates-tests PRIVATE
    Qt6::QuickTest Qt6::Quick Qt6::QuickControls2 Qt6::Widgets)
add_dependencies(atlas-dates-tests atlasui)
add_test(NAME dates
    COMMAND ${CMAKE_CURRENT_SOURCE_DIR}/visual/run-variant.sh light)
set_tests_properties(dates PROPERTIES
    TIMEOUT 120
    ENVIRONMENT "ATLAS_TEST_BIN=$<TARGET_FILE:atlas-dates-tests>;ATLAS_DEMO_DIR=${PROJECT_SOURCE_DIR}/ui/gallery/demos;ATLAS_GOLDEN_DIR=${CMAKE_CURRENT_SOURCE_DIR}/visual/golden;ATLAS_OUT_DIR=${CMAKE_BINARY_DIR}/dates-out;QML_IMPORT_PATH=${CMAKE_BINARY_DIR}")

# AtlasTreeView and AtlasTreeModel: keyboard navigation, expand and collapse,
# selection modes, type-ahead, signals (tests/tree).
add_executable(atlas-tree-tests tree/main.cpp)
target_compile_definitions(atlas-tree-tests PRIVATE
    QUICK_TEST_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}/tree")
target_link_libraries(atlas-tree-tests PRIVATE
    Qt6::QuickTest Qt6::Quick Qt6::QuickControls2 Qt6::Widgets)
add_dependencies(atlas-tree-tests atlasui)
add_test(NAME tree
    COMMAND ${CMAKE_CURRENT_SOURCE_DIR}/visual/run-variant.sh light)
set_tests_properties(tree PROPERTIES
    TIMEOUT 120
    ENVIRONMENT "ATLAS_TEST_BIN=$<TARGET_FILE:atlas-tree-tests>;ATLAS_DEMO_DIR=${PROJECT_SOURCE_DIR}/ui/gallery/demos;ATLAS_GOLDEN_DIR=${CMAKE_CURRENT_SOURCE_DIR}/visual/golden;ATLAS_OUT_DIR=${CMAKE_BINARY_DIR}/tree-out;QML_IMPORT_PATH=${CMAKE_BINARY_DIR}")

# The shortcut registry (ui/atlasshortcuts.cpp, compiled into the test):
# add, remove, conflicts, destroyed actions.
find_package(Qt6 6.11 REQUIRED COMPONENTS Test)
add_executable(atlas-shortcuts-tests shortcuts/tst_shortcuts.cpp
    ${PROJECT_SOURCE_DIR}/ui/atlasshortcuts.h ${PROJECT_SOURCE_DIR}/ui/atlasshortcuts.cpp)
target_include_directories(atlas-shortcuts-tests PRIVATE ${PROJECT_SOURCE_DIR}/ui)
target_link_libraries(atlas-shortcuts-tests PRIVATE Qt6::Test Qt6::Quick Qt6::Qml)
add_test(NAME shortcuts COMMAND atlas-shortcuts-tests)
set_tests_properties(shortcuts PROPERTIES TIMEOUT 60 ENVIRONMENT "QT_QPA_PLATFORM=offscreen")

# The Atlas validators (ui/atlasvalidators.cpp, compiled into the test):
# acceptable, intermediate and invalid input of each, hostile input included.
add_executable(atlas-validators-tests validators/tst_validators.cpp
    ${PROJECT_SOURCE_DIR}/ui/atlasvalidators.h ${PROJECT_SOURCE_DIR}/ui/atlasvalidators.cpp)
target_include_directories(atlas-validators-tests PRIVATE ${PROJECT_SOURCE_DIR}/ui)
target_link_libraries(atlas-validators-tests PRIVATE Qt6::Test Qt6::Quick Qt6::Qml)
add_test(NAME validators COMMAND atlas-validators-tests)
set_tests_properties(validators PROPERTIES TIMEOUT 60 ENVIRONMENT "QT_QPA_PLATFORM=offscreen")

# The clipboard singleton (ui/atlasclipboard.cpp, compiled into the test):
# text, rich text and image round trips, and what setImage() refuses.
add_executable(atlas-clipboard-tests clipboard/tst_clipboard.cpp
    ${PROJECT_SOURCE_DIR}/ui/atlasclipboard.h ${PROJECT_SOURCE_DIR}/ui/atlasclipboard.cpp)
target_include_directories(atlas-clipboard-tests PRIVATE ${PROJECT_SOURCE_DIR}/ui)
target_link_libraries(atlas-clipboard-tests PRIVATE Qt6::Test Qt6::Quick Qt6::Qml)
add_test(NAME clipboard COMMAND atlas-clipboard-tests)
set_tests_properties(clipboard PROPERTIES TIMEOUT 60 ENVIRONMENT "QT_QPA_PLATFORM=offscreen")
# AtlasFormat (ui/atlasformat.cpp, compiled into the test): every function in
# en_US and de_DE, edge cases included (tests/format).
add_executable(atlas-format-tests format/tst_format.cpp
    ${PROJECT_SOURCE_DIR}/ui/atlasformat.h ${PROJECT_SOURCE_DIR}/ui/atlasformat.cpp)
target_include_directories(atlas-format-tests PRIVATE ${PROJECT_SOURCE_DIR}/ui)
target_link_libraries(atlas-format-tests PRIVATE Qt6::Test Qt6::Quick Qt6::Qml)
add_test(NAME format COMMAND atlas-format-tests)
set_tests_properties(format PROPERTIES TIMEOUT 60 ENVIRONMENT "QT_QPA_PLATFORM=offscreen")
# AtlasSparklineItem (ui/atlassparkline.cpp, compiled into the test): the
# automatic scale and its limits, and no repaint for equal values.
add_executable(atlas-sparkline-tests sparkline/tst_sparkline.cpp
    ${PROJECT_SOURCE_DIR}/ui/atlassparkline.h ${PROJECT_SOURCE_DIR}/ui/atlassparkline.cpp)
target_include_directories(atlas-sparkline-tests PRIVATE ${PROJECT_SOURCE_DIR}/ui)
target_link_libraries(atlas-sparkline-tests PRIVATE Qt6::Test Qt6::Quick Qt6::Qml)
add_test(NAME sparkline COMMAND atlas-sparkline-tests)
set_tests_properties(sparkline PROPERTIES TIMEOUT 60 ENVIRONMENT "QT_QPA_PLATFORM=offscreen")
# lint-app.sh's replacement and deprecation rules (tests/lint/run.sh).
add_test(NAME lint COMMAND bash ${CMAKE_CURRENT_SOURCE_DIR}/lint/run.sh)
set_tests_properties(lint PROPERTIES TIMEOUT 60)
# AtlasSettings and AtlasPortal's rules (ui/atlassettings.cpp and
# ui/atlasportal.cpp, compiled into the test): typed values, the shared file
# and lock, immutable keys, symlink escapes, bad names, the URL scheme filter.
# Runs in a temporary XDG_CONFIG_HOME and never opens a URL or sends a
# notification.
add_executable(atlas-settings-tests settings/tst_settings.cpp
    ${PROJECT_SOURCE_DIR}/ui/atlassettings.h ${PROJECT_SOURCE_DIR}/ui/atlassettings.cpp
    ${PROJECT_SOURCE_DIR}/ui/atlasportal.h ${PROJECT_SOURCE_DIR}/ui/atlasportal.cpp)
target_include_directories(atlas-settings-tests PRIVATE ${PROJECT_SOURCE_DIR}/ui)
target_link_libraries(atlas-settings-tests PRIVATE Qt6::Test Qt6::Gui Qt6::Qml Qt6::DBus KF6::ConfigCore)
add_test(NAME settings COMMAND atlas-settings-tests)
set_tests_properties(settings PROPERTIES TIMEOUT 120 ENVIRONMENT "QT_QPA_PLATFORM=offscreen")

# AtlasWindow.stateKey: saved on change, restored clamped to the screen
# (tests/window). Same private environment as the visual tests.
add_executable(atlas-window-tests window/main.cpp)
target_compile_definitions(atlas-window-tests PRIVATE
    QUICK_TEST_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}/window")
target_link_libraries(atlas-window-tests PRIVATE
    Qt6::QuickTest Qt6::Quick Qt6::QuickControls2 Qt6::Widgets)
add_dependencies(atlas-window-tests atlasui)
add_test(NAME window
    COMMAND ${CMAKE_CURRENT_SOURCE_DIR}/visual/run-variant.sh light)
set_tests_properties(window PROPERTIES
    TIMEOUT 120
    ENVIRONMENT "ATLAS_TEST_BIN=$<TARGET_FILE:atlas-window-tests>;ATLAS_DEMO_DIR=${PROJECT_SOURCE_DIR}/ui/gallery/demos;ATLAS_GOLDEN_DIR=${CMAKE_CURRENT_SOURCE_DIR}/visual/golden;ATLAS_OUT_DIR=${CMAKE_BINARY_DIR}/window-out;QML_IMPORT_PATH=${CMAKE_BINARY_DIR}")
