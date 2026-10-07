# Tests for Telamon.Ui, built with -DTELAMON_UI_TESTS=ON and run with ctest:
#
#   cmake -S . -B build -G Ninja -DTELAMON_UI_TESTS=ON
#   cmake --build build && ctest --test-dir build --output-on-failure
#
#   visual-<variant>   every ui/gallery/demos/*Demo.qml against its golden
#                      (tests/visual/golden/<variant>/<Demo>.png)
#                      variants: light dark accent opaque contrast rtl compact text200
#   TELAMON_UPDATE_GOLDENS=1 ctest ...   rewrites the goldens that fail
#   i18n               a throwaway German catalogue: Telamon.Ui's qsTr() strings
#                      come back translated (tests/i18n)
#   state-<n>          every demo against the state contract of docs/DESIGN.md
#                      (disabled, keyboard focus), in 4 shards (tests/state)
#   a11y               every demo's item tree: what Tab reaches needs an
#                      Accessible.role and name, and Tab goes in reading
#                      order and Shift+Tab back the same way (tests/a11y)
find_package(Qt6 6.11 REQUIRED COMPONENTS QuickTest DBus)

add_executable(telamon-visual-tests visual/main.cpp demolist.h)
target_compile_definitions(telamon-visual-tests PRIVATE
    QUICK_TEST_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}/visual")
# Widgets selects QApplication, which the org.kde.desktop style needs.
target_link_libraries(telamon-visual-tests PRIVATE
    Qt6::QuickTest Qt6::Quick Qt6::QuickControls2 Qt6::Widgets telamon-variant)
# The demos import Telamon.Ui: it must be built first.
add_dependencies(telamon-visual-tests telamonui)

# The contrast variant needs a settings portal to say "high contrast" (see
# visual/fake-portal.cpp).
add_executable(telamon-fake-portal visual/fake-portal.cpp)
target_link_libraries(telamon-fake-portal PRIVATE telamon-variant)

foreach(variant light dark accent opaque contrast rtl compact text200)
    add_test(NAME visual-${variant}
        COMMAND ${CMAKE_CURRENT_SOURCE_DIR}/visual/run-variant.sh ${variant})
    set_tests_properties(visual-${variant} PROPERTIES
        TIMEOUT 600
        ENVIRONMENT "TELAMON_TEST_BIN=$<TARGET_FILE:telamon-visual-tests>;TELAMON_FAKE_PORTAL=$<TARGET_FILE:telamon-fake-portal>;TELAMON_DEMO_DIR=${PROJECT_SOURCE_DIR}/ui/gallery/demos;TELAMON_GOLDEN_DIR=${CMAKE_CURRENT_SOURCE_DIR}/visual/golden;TELAMON_OUT_DIR=${CMAKE_BINARY_DIR}/visual-out;QML_IMPORT_PATH=${CMAKE_BINARY_DIR}")
endforeach()

# The accessibility test: the same demos, the same private environment as the
# visual tests (run-variant.sh light).
add_executable(telamon-a11y-tests a11y/main.cpp demolist.h)
target_compile_definitions(telamon-a11y-tests PRIVATE
    QUICK_TEST_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}/a11y")
target_link_libraries(telamon-a11y-tests PRIVATE
    Qt6::QuickTest Qt6::Quick Qt6::QuickControls2 Qt6::Widgets)
add_dependencies(telamon-a11y-tests telamonui)
add_test(NAME a11y
    COMMAND ${CMAKE_CURRENT_SOURCE_DIR}/visual/run-variant.sh light)
set_tests_properties(a11y PROPERTIES
    TIMEOUT 300
    ENVIRONMENT "TELAMON_TEST_BIN=$<TARGET_FILE:telamon-a11y-tests>;TELAMON_DEMO_DIR=${PROJECT_SOURCE_DIR}/ui/gallery/demos;TELAMON_GOLDEN_DIR=${CMAKE_CURRENT_SOURCE_DIR}/visual/golden;TELAMON_OUT_DIR=${CMAKE_BINARY_DIR}/a11y-out;QML_IMPORT_PATH=${CMAKE_BINARY_DIR}")

# The state-contract test: disabled controls take no focus and look different,
# a control Tab reaches shows keyboard focus. Four shards run in parallel.
add_executable(telamon-state-tests state/main.cpp demolist.h)
target_compile_definitions(telamon-state-tests PRIVATE
    QUICK_TEST_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}/state")
target_link_libraries(telamon-state-tests PRIVATE
    Qt6::QuickTest Qt6::Quick Qt6::QuickControls2 Qt6::Widgets)
add_dependencies(telamon-state-tests telamonui)
foreach(shard RANGE 0 3)
    add_test(NAME state-${shard}
        COMMAND ${CMAKE_CURRENT_SOURCE_DIR}/visual/run-variant.sh light)
    set_tests_properties(state-${shard} PROPERTIES
        TIMEOUT 300
        ENVIRONMENT "TELAMON_TEST_BIN=$<TARGET_FILE:telamon-state-tests>;TELAMON_STATE_SHARD=${shard}/4;TELAMON_DEMO_DIR=${PROJECT_SOURCE_DIR}/ui/gallery/demos;TELAMON_GOLDEN_DIR=${CMAKE_CURRENT_SOURCE_DIR}/visual/golden;TELAMON_OUT_DIR=${CMAKE_BINARY_DIR}/state-out-${shard};QML_IMPORT_PATH=${CMAKE_BINARY_DIR}")
endforeach()
# Behaviour of the field controls (tests/fields): TelamonAutocompleteField's
# keyboard handling, TelamonColorField's hex parsing.
add_executable(telamon-fields-tests fields/main.cpp)
target_compile_definitions(telamon-fields-tests PRIVATE
    QUICK_TEST_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}/fields")
target_link_libraries(telamon-fields-tests PRIVATE
    Qt6::QuickTest Qt6::Quick Qt6::QuickControls2 Qt6::Widgets)
add_dependencies(telamon-fields-tests telamonui)
add_test(NAME fields
    COMMAND ${CMAKE_CURRENT_SOURCE_DIR}/visual/run-variant.sh light)
set_tests_properties(fields PROPERTIES
    TIMEOUT 120
    ENVIRONMENT "TELAMON_TEST_BIN=$<TARGET_FILE:telamon-fields-tests>;TELAMON_DEMO_DIR=${PROJECT_SOURCE_DIR}/ui/gallery/demos;TELAMON_GOLDEN_DIR=${CMAKE_CURRENT_SOURCE_DIR}/visual/golden;TELAMON_OUT_DIR=${CMAKE_BINARY_DIR}/fields-out;QML_IMPORT_PATH=${CMAKE_BINARY_DIR}")

# Behaviour of TelamonListView (tests/lists): selection, keyboard, signals,
# type-ahead.
add_executable(telamon-lists-tests lists/main.cpp)
target_compile_definitions(telamon-lists-tests PRIVATE
    QUICK_TEST_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}/lists")
target_link_libraries(telamon-lists-tests PRIVATE
    Qt6::QuickTest Qt6::Quick Qt6::QuickControls2 Qt6::Widgets)
add_dependencies(telamon-lists-tests telamonui)
add_test(NAME lists
    COMMAND ${CMAKE_CURRENT_SOURCE_DIR}/visual/run-variant.sh light)
set_tests_properties(lists PROPERTIES
    TIMEOUT 120
    ENVIRONMENT "TELAMON_TEST_BIN=$<TARGET_FILE:telamon-lists-tests>;TELAMON_DEMO_DIR=${PROJECT_SOURCE_DIR}/ui/gallery/demos;TELAMON_GOLDEN_DIR=${CMAKE_CURRENT_SOURCE_DIR}/visual/golden;TELAMON_OUT_DIR=${CMAKE_BINARY_DIR}/lists-out;QML_IMPORT_PATH=${CMAKE_BINARY_DIR}")
# Store controls (tests/store): TelamonScreenshotCarousel's viewer, TelamonShelf,
# TelamonInstallButton's remove, removing and queued states, TelamonAppCard's
# verified and compact.
add_executable(telamon-store-tests store/main.cpp)
target_compile_definitions(telamon-store-tests PRIVATE
    QUICK_TEST_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}/store")
target_link_libraries(telamon-store-tests PRIVATE
    Qt6::QuickTest Qt6::Quick Qt6::QuickControls2 Qt6::Widgets)
add_dependencies(telamon-store-tests telamonui)
add_test(NAME store
    COMMAND ${CMAKE_CURRENT_SOURCE_DIR}/visual/run-variant.sh light)
set_tests_properties(store PROPERTIES
    TIMEOUT 120
    ENVIRONMENT "TELAMON_TEST_BIN=$<TARGET_FILE:telamon-store-tests>;TELAMON_DEMO_DIR=${PROJECT_SOURCE_DIR}/ui/gallery/demos;TELAMON_GOLDEN_DIR=${CMAKE_CURRENT_SOURCE_DIR}/visual/golden;TELAMON_OUT_DIR=${CMAKE_BINARY_DIR}/store-out;QML_IMPORT_PATH=${CMAKE_BINARY_DIR}")
# DataTable behaviour: selection, column resize and visibility, the row menu
# (tests/tables).
add_executable(telamon-tables-tests tables/main.cpp)
target_compile_definitions(telamon-tables-tests PRIVATE
    QUICK_TEST_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}/tables")
target_link_libraries(telamon-tables-tests PRIVATE
    Qt6::QuickTest Qt6::Quick Qt6::QuickControls2 Qt6::Widgets)
add_dependencies(telamon-tables-tests telamonui)
add_test(NAME tables
    COMMAND ${CMAKE_CURRENT_SOURCE_DIR}/visual/run-variant.sh light)
set_tests_properties(tables PROPERTIES
    TIMEOUT 120
    ENVIRONMENT "TELAMON_TEST_BIN=$<TARGET_FILE:telamon-tables-tests>;TELAMON_DEMO_DIR=${PROJECT_SOURCE_DIR}/ui/gallery/demos;TELAMON_GOLDEN_DIR=${CMAKE_CURRENT_SOURCE_DIR}/visual/golden;TELAMON_OUT_DIR=${CMAKE_BINARY_DIR}/tables-out;QML_IMPORT_PATH=${CMAKE_BINARY_DIR}")

# TelamonStatus on TelamonListView, DataTable, TelamonTreeView and TelamonPage, and
# TelamonSplitView's collapse and Back (tests/status).
add_executable(telamon-status-tests status/main.cpp)
target_compile_definitions(telamon-status-tests PRIVATE
    QUICK_TEST_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}/status")
target_link_libraries(telamon-status-tests PRIVATE
    Qt6::QuickTest Qt6::Quick Qt6::QuickControls2 Qt6::Widgets)
add_dependencies(telamon-status-tests telamonui)
add_test(NAME status
    COMMAND ${CMAKE_CURRENT_SOURCE_DIR}/visual/run-variant.sh light)
set_tests_properties(status PROPERTIES
    TIMEOUT 120
    ENVIRONMENT "TELAMON_TEST_BIN=$<TARGET_FILE:telamon-status-tests>;TELAMON_DEMO_DIR=${PROJECT_SOURCE_DIR}/ui/gallery/demos;TELAMON_GOLDEN_DIR=${CMAKE_CURRENT_SOURCE_DIR}/visual/golden;TELAMON_OUT_DIR=${CMAKE_BINARY_DIR}/status-out;QML_IMPORT_PATH=${CMAKE_BINARY_DIR}")

# The frameless window (tests/chrome): TelamonHeaderBar's drag and double click,
# TelamonWindow's resize handles and cursors, TelamonWindowChrome's button layout.
add_executable(telamon-chrome-tests chrome/main.cpp)
target_compile_definitions(telamon-chrome-tests PRIVATE
    QUICK_TEST_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}/chrome")
target_link_libraries(telamon-chrome-tests PRIVATE
    Qt6::QuickTest Qt6::Quick Qt6::QuickControls2 Qt6::Widgets)
add_dependencies(telamon-chrome-tests telamonui)
add_test(NAME chrome
    COMMAND ${CMAKE_CURRENT_SOURCE_DIR}/visual/run-variant.sh light)
set_tests_properties(chrome PROPERTIES
    TIMEOUT 120
    ENVIRONMENT "TELAMON_TEST_BIN=$<TARGET_FILE:telamon-chrome-tests>;TELAMON_DEMO_DIR=${PROJECT_SOURCE_DIR}/ui/gallery/demos;TELAMON_GOLDEN_DIR=${CMAKE_CURRENT_SOURCE_DIR}/visual/golden;TELAMON_OUT_DIR=${CMAKE_BINARY_DIR}/chrome-out;QML_IMPORT_PATH=${CMAKE_BINARY_DIR}")

# ToolbarButton's keys and TelamonProgressBar's layout (tests/input).
add_executable(telamon-input-tests input/main.cpp)
target_compile_definitions(telamon-input-tests PRIVATE
    QUICK_TEST_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}/input")
target_link_libraries(telamon-input-tests PRIVATE
    Qt6::QuickTest Qt6::Quick Qt6::QuickControls2 Qt6::Widgets)
add_dependencies(telamon-input-tests telamonui)
add_test(NAME input
    COMMAND ${CMAKE_CURRENT_SOURCE_DIR}/visual/run-variant.sh light)
set_tests_properties(input PROPERTIES
    TIMEOUT 120
    ENVIRONMENT "TELAMON_TEST_BIN=$<TARGET_FILE:telamon-input-tests>;TELAMON_DEMO_DIR=${PROJECT_SOURCE_DIR}/ui/gallery/demos;TELAMON_GOLDEN_DIR=${CMAKE_CURRENT_SOURCE_DIR}/visual/golden;TELAMON_OUT_DIR=${CMAKE_BINARY_DIR}/input-out;QML_IMPORT_PATH=${CMAKE_BINARY_DIR}")

# The translation test: a throwaway telamon-ui_de.qm (tests/i18n) in a directory
# of its own, found through TELAMON_UI_TRANSLATIONS_DIR (development builds only).
find_package(Qt6 6.11 QUIET COMPONENTS LinguistTools)
if(Qt6LinguistTools_FOUND AND TELAMON_UI_DEV_BUILD)
    qt_add_lrelease(TS_FILES i18n/telamon-ui_de.ts
        QM_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/i18n-qm
        LRELEASE_TARGET telamon-ui_test_translations
        NO_GLOBAL_TARGET)
    add_executable(telamon-i18n-tests i18n/main.cpp)
    target_compile_definitions(telamon-i18n-tests PRIVATE
        QUICK_TEST_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}/i18n")
    target_link_libraries(telamon-i18n-tests PRIVATE
        Qt6::QuickTest Qt6::Quick Qt6::QuickControls2 Qt6::Widgets)
    add_dependencies(telamon-i18n-tests telamonui telamon-ui_test_translations)
    add_test(NAME i18n
        COMMAND ${CMAKE_CURRENT_SOURCE_DIR}/visual/run-variant.sh light)
    set_tests_properties(i18n PROPERTIES
        TIMEOUT 120
        ENVIRONMENT "TELAMON_TEST_BIN=$<TARGET_FILE:telamon-i18n-tests>;TELAMON_DEMO_DIR=${PROJECT_SOURCE_DIR}/ui/gallery/demos;TELAMON_GOLDEN_DIR=${CMAKE_CURRENT_SOURCE_DIR}/visual/golden;TELAMON_OUT_DIR=${CMAKE_BINARY_DIR}/i18n-out;QML_IMPORT_PATH=${CMAKE_BINARY_DIR};LANGUAGE=de;LANG=de_DE.UTF-8;LC_ALL=de_DE.UTF-8;TELAMON_UI_TRANSLATIONS_DIR=${CMAKE_BINARY_DIR}/i18n-qm")
endif()

# The date and time controls: keyboard navigation, minimum and maximum, minute
# snapping (tests/dates). Same private environment as the visual tests.
add_executable(telamon-dates-tests dates/main.cpp)
target_compile_definitions(telamon-dates-tests PRIVATE
    QUICK_TEST_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}/dates")
target_link_libraries(telamon-dates-tests PRIVATE
    Qt6::QuickTest Qt6::Quick Qt6::QuickControls2 Qt6::Widgets)
add_dependencies(telamon-dates-tests telamonui)
add_test(NAME dates
    COMMAND ${CMAKE_CURRENT_SOURCE_DIR}/visual/run-variant.sh light)
set_tests_properties(dates PROPERTIES
    TIMEOUT 120
    ENVIRONMENT "TELAMON_TEST_BIN=$<TARGET_FILE:telamon-dates-tests>;TELAMON_DEMO_DIR=${PROJECT_SOURCE_DIR}/ui/gallery/demos;TELAMON_GOLDEN_DIR=${CMAKE_CURRENT_SOURCE_DIR}/visual/golden;TELAMON_OUT_DIR=${CMAKE_BINARY_DIR}/dates-out;QML_IMPORT_PATH=${CMAKE_BINARY_DIR}")

# TelamonTreeView and TelamonTreeModel: keyboard navigation, expand and collapse,
# selection modes, type-ahead, signals (tests/tree).
add_executable(telamon-tree-tests tree/main.cpp)
target_compile_definitions(telamon-tree-tests PRIVATE
    QUICK_TEST_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}/tree")
target_link_libraries(telamon-tree-tests PRIVATE
    Qt6::QuickTest Qt6::Quick Qt6::QuickControls2 Qt6::Widgets)
add_dependencies(telamon-tree-tests telamonui)
add_test(NAME tree
    COMMAND ${CMAKE_CURRENT_SOURCE_DIR}/visual/run-variant.sh light)
set_tests_properties(tree PROPERTIES
    TIMEOUT 120
    ENVIRONMENT "TELAMON_TEST_BIN=$<TARGET_FILE:telamon-tree-tests>;TELAMON_DEMO_DIR=${PROJECT_SOURCE_DIR}/ui/gallery/demos;TELAMON_GOLDEN_DIR=${CMAKE_CURRENT_SOURCE_DIR}/visual/golden;TELAMON_OUT_DIR=${CMAKE_BINARY_DIR}/tree-out;QML_IMPORT_PATH=${CMAKE_BINARY_DIR}")

# The shortcut registry (ui/telamonshortcuts.cpp, compiled into the test):
# add, remove, conflicts, destroyed actions.
find_package(Qt6 6.11 REQUIRED COMPONENTS Test)
add_executable(telamon-shortcuts-tests shortcuts/tst_shortcuts.cpp
    ${PROJECT_SOURCE_DIR}/ui/telamonshortcuts.h ${PROJECT_SOURCE_DIR}/ui/telamonshortcuts.cpp)
target_include_directories(telamon-shortcuts-tests PRIVATE ${PROJECT_SOURCE_DIR}/ui)
target_link_libraries(telamon-shortcuts-tests PRIVATE Qt6::Test Qt6::Quick Qt6::Qml)
add_test(NAME shortcuts COMMAND telamon-shortcuts-tests)
set_tests_properties(shortcuts PROPERTIES TIMEOUT 60 ENVIRONMENT "QT_QPA_PLATFORM=offscreen")

# Hostile input to the C++ types (tests/hardening): TelamonTreeModel with
# foreign and stale indexes, the text scale bounds.
add_executable(telamon-hardening-tests hardening/tst_hardening.cpp
    ${PROJECT_SOURCE_DIR}/ui/telamontreemodel.h ${PROJECT_SOURCE_DIR}/ui/telamontreemodel.cpp
    ${PROJECT_SOURCE_DIR}/ui/textscale.h)
target_include_directories(telamon-hardening-tests PRIVATE ${PROJECT_SOURCE_DIR}/ui)
target_link_libraries(telamon-hardening-tests PRIVATE Qt6::Test Qt6::Qml)
add_test(NAME hardening COMMAND telamon-hardening-tests)
set_tests_properties(hardening PROPERTIES TIMEOUT 60 ENVIRONMENT "QT_QPA_PLATFORM=offscreen")

# Appearance.textScale through the clamp (ui/appearance.cpp, compiled in).
add_executable(telamon-appearance-tests hardening/tst_appearance.cpp
    ${PROJECT_SOURCE_DIR}/ui/appearance.h ${PROJECT_SOURCE_DIR}/ui/appearance.cpp
    ${PROJECT_SOURCE_DIR}/ui/legacyconfig.h ${PROJECT_SOURCE_DIR}/ui/legacyconfig.cpp
    ${PROJECT_SOURCE_DIR}/ui/portalappearance.h ${PROJECT_SOURCE_DIR}/ui/portalappearance.cpp
    ${PROJECT_SOURCE_DIR}/ui/textscale.h)
target_include_directories(telamon-appearance-tests PRIVATE ${PROJECT_SOURCE_DIR}/ui)
target_link_libraries(telamon-appearance-tests PRIVATE Qt6::Test Qt6::Quick Qt6::Qml Qt6::DBus
    KF6::WindowSystem KF6::ConfigCore)
add_test(NAME appearance COMMAND telamon-appearance-tests)
# Its own config dir and no session bus: the user's kdeglobals and portal
# settings must not reach the test (or be written by it).
set_tests_properties(appearance PROPERTIES TIMEOUT 60 ENVIRONMENT
    "QT_QPA_PLATFORM=offscreen;XDG_CONFIG_HOME=${CMAKE_CURRENT_BINARY_DIR}/appearance-config;DBUS_SESSION_BUS_ADDRESS=disabled:")

# The Telamon validators (ui/telamonvalidators.cpp, compiled into the test):
# acceptable, intermediate and invalid input of each, hostile input included.
add_executable(telamon-validators-tests validators/tst_validators.cpp
    ${PROJECT_SOURCE_DIR}/ui/telamonvalidators.h ${PROJECT_SOURCE_DIR}/ui/telamonvalidators.cpp)
target_include_directories(telamon-validators-tests PRIVATE ${PROJECT_SOURCE_DIR}/ui)
target_link_libraries(telamon-validators-tests PRIVATE Qt6::Test Qt6::Quick Qt6::Qml)
add_test(NAME validators COMMAND telamon-validators-tests)
set_tests_properties(validators PROPERTIES TIMEOUT 60 ENVIRONMENT "QT_QPA_PLATFORM=offscreen")

# The colour helpers behind TelamonStyle.alpha() and mix() (ui/telamoncolorsprivate.cpp,
# compiled into the test): clamping, NaN, alpha, invalid colours (tests/colors).
add_executable(telamon-colors-tests colors/tst_colors.cpp
    ${PROJECT_SOURCE_DIR}/ui/telamoncolorsprivate.h ${PROJECT_SOURCE_DIR}/ui/telamoncolorsprivate.cpp)
target_include_directories(telamon-colors-tests PRIVATE ${PROJECT_SOURCE_DIR}/ui)
target_link_libraries(telamon-colors-tests PRIVATE Qt6::Test Qt6::Quick Qt6::Qml)
add_test(NAME colors COMMAND telamon-colors-tests)
set_tests_properties(colors PROPERTIES TIMEOUT 60 ENVIRONMENT "QT_QPA_PLATFORM=offscreen")

# The text buffer behind TelamonTextView (ui/text, the telamontext library): a fuzz
# test of the piece tree against a QString model, loads, line endings and
# snapshots, threads included. No display needed.
add_executable(telamon-textbuffer-tests textbuffer/tst_textbuffer.cpp)
target_link_libraries(telamon-textbuffer-tests PRIVATE Qt6::Test telamontext)
add_test(NAME textbuffer COMMAND telamon-textbuffer-tests)
set_tests_properties(textbuffer PROPERTIES TIMEOUT 600 ENVIRONMENT "QT_QPA_PLATFORM=offscreen")

# TelamonTextView (ui/text/telamontextview.cpp, compiled into the test): layout of
# the visible lines, wrap, selection and copy, the mouse, follow mode, loading,
# the accessible. Software scene graph on the offscreen platform.
add_executable(telamon-textview-tests textview/tst_textview.cpp
    ${PROJECT_SOURCE_DIR}/ui/text/telamontextview.h ${PROJECT_SOURCE_DIR}/ui/text/telamontextview.cpp)
target_link_libraries(telamon-textview-tests PRIVATE Qt6::Test Qt6::Quick Qt6::Qml Qt6::Gui telamontext)
add_test(NAME textview COMMAND telamon-textview-tests)
set_tests_properties(textview PROPERTIES TIMEOUT 300 ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QUICK_BACKEND=software")

# The clipboard singleton (ui/telamonclipboard.cpp, compiled into the test):
# text, rich text and image round trips, and what setImage() refuses.
add_executable(telamon-clipboard-tests clipboard/tst_clipboard.cpp
    ${PROJECT_SOURCE_DIR}/ui/telamonclipboard.h ${PROJECT_SOURCE_DIR}/ui/telamonclipboard.cpp)
target_include_directories(telamon-clipboard-tests PRIVATE ${PROJECT_SOURCE_DIR}/ui)
target_link_libraries(telamon-clipboard-tests PRIVATE Qt6::Test Qt6::Quick Qt6::Qml)
add_test(NAME clipboard COMMAND telamon-clipboard-tests)
set_tests_properties(clipboard PROPERTIES TIMEOUT 60 ENVIRONMENT "QT_QPA_PLATFORM=offscreen")
# TelamonFormat (ui/telamonformat.cpp, compiled into the test): every function in
# en_US and de_DE, edge cases included (tests/format).
add_executable(telamon-format-tests format/tst_format.cpp
    ${PROJECT_SOURCE_DIR}/ui/telamonformat.h ${PROJECT_SOURCE_DIR}/ui/telamonformat.cpp)
target_include_directories(telamon-format-tests PRIVATE ${PROJECT_SOURCE_DIR}/ui)
target_link_libraries(telamon-format-tests PRIVATE Qt6::Test Qt6::Quick Qt6::Qml)
add_test(NAME format COMMAND telamon-format-tests)
set_tests_properties(format PROPERTIES TIMEOUT 60 ENVIRONMENT "QT_QPA_PLATFORM=offscreen")
# TelamonSparklineItem (ui/telamonsparkline.cpp, compiled into the test): the
# automatic scale and its limits, and no repaint for equal values.
add_executable(telamon-sparkline-tests sparkline/tst_sparkline.cpp
    ${PROJECT_SOURCE_DIR}/ui/telamonsparkline.h ${PROJECT_SOURCE_DIR}/ui/telamonsparkline.cpp)
target_include_directories(telamon-sparkline-tests PRIVATE ${PROJECT_SOURCE_DIR}/ui)
target_link_libraries(telamon-sparkline-tests PRIVATE Qt6::Test Qt6::Quick Qt6::Qml)
add_test(NAME sparkline COMMAND telamon-sparkline-tests)
set_tests_properties(sparkline PROPERTIES TIMEOUT 60 ENVIRONMENT "QT_QPA_PLATFORM=offscreen")
# TelamonGlobalShortcut, the portal's appearance settings and their users
# (ui/telamonglobalshortcut.cpp, portalappearance.cpp, appearance.cpp and
# accessibilitystate.cpp, compiled into the test) against a fake portal on a
# private bus the test starts itself (tests/platform).
add_executable(telamon-platform-tests platform/tst_platform.cpp
    ${PROJECT_SOURCE_DIR}/ui/accessibilitystate.h ${PROJECT_SOURCE_DIR}/ui/accessibilitystate.cpp
    ${PROJECT_SOURCE_DIR}/ui/appearance.h ${PROJECT_SOURCE_DIR}/ui/appearance.cpp
    ${PROJECT_SOURCE_DIR}/ui/legacyconfig.h ${PROJECT_SOURCE_DIR}/ui/legacyconfig.cpp
    ${PROJECT_SOURCE_DIR}/ui/telamonglobalshortcut.h ${PROJECT_SOURCE_DIR}/ui/telamonglobalshortcut.cpp
    ${PROJECT_SOURCE_DIR}/ui/portalappearance.h ${PROJECT_SOURCE_DIR}/ui/portalappearance.cpp
    ${PROJECT_SOURCE_DIR}/ui/textscale.h)
target_include_directories(telamon-platform-tests PRIVATE ${PROJECT_SOURCE_DIR}/ui)
target_link_libraries(telamon-platform-tests PRIVATE Qt6::Test Qt6::Quick Qt6::Qml Qt6::DBus
    KF6::WindowSystem KF6::ConfigCore)
add_test(NAME platform COMMAND telamon-platform-tests)
# A skip (no private bus, or not the private one) is a failure here: the test
# must really run. The container has dbus-daemon.
set_tests_properties(platform PROPERTIES FAIL_REGULAR_EXPRESSION "SKIP   :")
# Its own config dir; the bus is the test's private one (see the file).
set_tests_properties(platform PROPERTIES TIMEOUT 120 ENVIRONMENT
    "QT_QPA_PLATFORM=offscreen;DBUS_SESSION_BUS_ADDRESS=disabled:;XDG_CONFIG_HOME=${CMAKE_CURRENT_BINARY_DIR}/platform-config")
# lint-app.sh's replacement and deprecation rules (tests/lint/run.sh).
add_test(NAME lint COMMAND bash ${CMAKE_CURRENT_SOURCE_DIR}/lint/run.sh)
set_tests_properties(lint PROPERTIES TIMEOUT 60)
# TelamonSettings and TelamonPortal's rules (ui/telamonsettings.cpp and
# ui/telamonportal.cpp, compiled into the test): typed values, the shared file
# and lock, immutable keys, symlink escapes, bad names, the URL scheme filter.
# Runs in a temporary XDG_CONFIG_HOME and never opens a URL or sends a
# notification.
add_executable(telamon-settings-tests settings/tst_settings.cpp
    ${PROJECT_SOURCE_DIR}/ui/telamonsettings.h ${PROJECT_SOURCE_DIR}/ui/telamonsettings.cpp
    ${PROJECT_SOURCE_DIR}/ui/legacyconfig.h ${PROJECT_SOURCE_DIR}/ui/legacyconfig.cpp
    ${PROJECT_SOURCE_DIR}/ui/telamonportal.h ${PROJECT_SOURCE_DIR}/ui/telamonportal.cpp)
target_include_directories(telamon-settings-tests PRIVATE ${PROJECT_SOURCE_DIR}/ui)
target_link_libraries(telamon-settings-tests PRIVATE Qt6::Test Qt6::Gui Qt6::Qml Qt6::DBus KF6::ConfigCore)
add_test(NAME settings COMMAND telamon-settings-tests)
set_tests_properties(settings PROPERTIES TIMEOUT 120 ENVIRONMENT "QT_QPA_PLATFORM=offscreen")

# TelamonWindow.stateKey: saved on change, restored clamped to the screen
# (tests/window). Same private environment as the visual tests.
add_executable(telamon-window-tests window/main.cpp)
target_compile_definitions(telamon-window-tests PRIVATE
    QUICK_TEST_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}/window")
target_link_libraries(telamon-window-tests PRIVATE
    Qt6::QuickTest Qt6::Quick Qt6::QuickControls2 Qt6::Widgets)
add_dependencies(telamon-window-tests telamonui)
add_test(NAME window
    COMMAND ${CMAKE_CURRENT_SOURCE_DIR}/visual/run-variant.sh light)
set_tests_properties(window PROPERTIES
    TIMEOUT 120
    ENVIRONMENT "TELAMON_SOFTWARE_RENDERING=;TELAMON_TEST_BIN=$<TARGET_FILE:telamon-window-tests>;TELAMON_DEMO_DIR=${PROJECT_SOURCE_DIR}/ui/gallery/demos;TELAMON_GOLDEN_DIR=${CMAKE_CURRENT_SOURCE_DIR}/visual/golden;TELAMON_OUT_DIR=${CMAKE_BINARY_DIR}/window-out;QML_IMPORT_PATH=${CMAKE_BINARY_DIR}")

# telamon-preview on small pages (tests/preview/run.sh): 8 pictures, warnings
# exit 1, a broken file exit 2. Runs offscreen in the tool's own environment.
add_test(NAME preview COMMAND bash ${CMAKE_CURRENT_SOURCE_DIR}/preview/run.sh $<TARGET_FILE:telamon-preview>)
set_tests_properties(preview PROPERTIES
    TIMEOUT 180
    ENVIRONMENT "QML_IMPORT_PATH=${CMAKE_BINARY_DIR}")

# The first-run setup controls of 1.5.0 item 42 (tests/wizard): TelamonOnboarding's
# labels, busy state, advanceRequested, canGoBack and dots; TelamonPasswordStrength;
# TelamonChoiceCard; TelamonAccentPicker; TelamonWindow.kiosk.
add_executable(telamon-wizard-tests wizard/main.cpp)
target_compile_definitions(telamon-wizard-tests PRIVATE
    QUICK_TEST_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}/wizard")
target_link_libraries(telamon-wizard-tests PRIVATE
    Qt6::QuickTest Qt6::Quick Qt6::QuickControls2 Qt6::Widgets)
add_dependencies(telamon-wizard-tests telamonui)
add_test(NAME wizard
    COMMAND ${CMAKE_CURRENT_SOURCE_DIR}/visual/run-variant.sh light)
set_tests_properties(wizard PROPERTIES
    TIMEOUT 120
    ENVIRONMENT "TELAMON_TEST_BIN=$<TARGET_FILE:telamon-wizard-tests>;TELAMON_DEMO_DIR=${PROJECT_SOURCE_DIR}/ui/gallery/demos;TELAMON_GOLDEN_DIR=${CMAKE_CURRENT_SOURCE_DIR}/visual/golden;TELAMON_OUT_DIR=${CMAKE_BINARY_DIR}/wizard-out;QML_IMPORT_PATH=${CMAKE_BINARY_DIR}")

# No test may reach a real desktop portal: Appearance and AccessibilityState
# read the portal's settings from the session bus, so every test runs with the
# bus disabled (the platform test starts a private one of its own and says so).
get_property(_telamon_all_tests DIRECTORY PROPERTY TESTS)
foreach(_t IN LISTS _telamon_all_tests)
    set_property(TEST ${_t} APPEND PROPERTY ENVIRONMENT_MODIFICATION "DBUS_SESSION_BUS_ADDRESS=set:disabled:")
endforeach()
