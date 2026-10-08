# Telamon.Ui: the shared look of Telamon apps (buttons, grouped sections,
# status hero, sidebar items, setup steps, live charts, usage and progress
# bars, tables, search, menus, document tabs, find and status bars, banners,
# toasts, toolbar buttons, and Material Symbols icons: see Symbol.qml and
# symbols.h). A QML module installed with Qt's own, like Kirigami: apps
# `import Telamon.Ui` and link nothing. One library, the plugin, holds the C++
# types and the QML compiled ahead of time by qmlcachegen.
#
# Installed in Qt's QML directory (/usr/lib64/qt6/qml/Telamon/Ui), with the
# qmldir, the qmltypes and the .qml files, which qmllint and qmlcachegen read
# when they compile an app against it.
#
# Its API is a contract with every Telamon app: see "Compatibility" in
# docs/DESIGN.md before renaming or removing anything.
# TelamonStyle is a QML singleton: the qmldir needs it marked before the module.
set_source_files_properties(TelamonStyle.qml TelamonStatus.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)
# TelamonStatusView is Telamon.Ui's own: what the views show for a status.
set_source_files_properties(TelamonStatusView.qml PROPERTIES QT_QML_INTERNAL_TYPE TRUE)
qt_add_qml_module(telamonui
    URI Telamon.Ui
    VERSION 1.0
    PLUGIN_TARGET telamonui
    # The plugin is the module: nothing else registers its C++ types.
    NO_PLUGIN_OPTIONAL
    NO_GENERATE_PLUGIN_SOURCE
    CLASS_NAME TelamonUiPlugin
    QML_FILES
        TelamonWindow.qml
        TelamonHeaderBar.qml
        TelamonWindowButtons.qml
        TelamonAppMenu.qml
        TelamonStyle.qml
        TelamonButton.qml
        PrimaryButton.qml
        SecondaryButton.qml
        TextButton.qml
        MenuButton.qml
        Section.qml
        SectionRow.qml
        StatusHero.qml
        SidebarItem.qml
        SidebarGroup.qml
        TelamonSidebar.qml
        StepItem.qml
        TelamonPage.qml
        TelamonSwitch.qml
        TelamonTransparencySwitch.qml
        TelamonProgressBar.qml
        TelamonEdgeGlow.qml
        ConfirmDialog.qml
        NotesText.qml
        LiveChart.qml
        UsageBar.qml
        MiniBars.qml
        DataTable.qml
        SearchField.qml
        ContextMenu.qml
        ContextMenuItem.qml
        ContextMenuSeparator.qml
        Symbol.qml
        TelamonIcon.qml
        TelamonAboutPage.qml
        TabBar.qml
        FindBar.qml
        StatusBar.qml
        StatusBarItem.qml
        InfoBanner.qml
        Toast.qml
        ToolbarButton.qml
        TelamonBreadcrumb.qml
        TelamonIconGrid.qml
        TelamonListView.qml
        TelamonAppCard.qml
        TelamonScreenshotCarousel.qml
        TelamonShelf.qml
        TelamonInstallButton.qml
        TelamonSearchResults.qml
        TelamonTextField.qml
        TelamonPasswordField.qml
        TelamonTextArea.qml
        TelamonComboBox.qml
        TelamonCheckBox.qml
        TelamonRadioButton.qml
        TelamonSlider.qml
        TelamonSpinBox.qml
        TelamonCalendar.qml
        TelamonDatePicker.qml
        TelamonTimePicker.qml
        TelamonToolTip.qml
        TelamonSpinner.qml
        TelamonPlaceholder.qml
        TelamonEmptyState.qml
        TelamonLabel.qml
        TelamonFocusRing.qml
        TelamonAction.qml
        TelamonActionCollection.qml
        TelamonSegmentedControl.qml
        TelamonSplitButton.qml
        TelamonChip.qml
        TelamonChipGroup.qml
        TelamonShortcutLabel.qml
        TelamonShortcutsDialog.qml
        TelamonDoubleSpinBox.qml
        TelamonShortcutField.qml
        TelamonSplitView.qml
        TelamonSpringAnimation.qml
        TelamonNavigationStack.qml
        TelamonViewSwitcher.qml
        TelamonColorField.qml
        TelamonFileField.qml
        TelamonFolderField.qml
        TelamonAutocompleteField.qml
        TelamonFontPicker.qml
        fontfamilies.js
        TelamonDropZone.qml
        TelamonOnboarding.qml
        TelamonPasswordStrength.qml
        TelamonChoiceCard.qml
        TelamonAccentPicker.qml
        TelamonToolbar.qml
        TelamonFloatingToolbar.qml
        TelamonFlowLayout.qml
        TelamonPopover.qml
        TelamonScrollBar.qml
        TelamonDialog.qml
        TelamonForm.qml
        TelamonFormEntry.qml
        TelamonPreferencesPage.qml
        TelamonPreferencesDialog.qml
        TelamonCard.qml
        TelamonExpandableSection.qml
        TelamonTreeView.qml
        TelamonCodeView.qml
        TelamonCopyButton.qml
        TelamonCommandPalette.qml
        TelamonStat.qml
        TelamonDetailGrid.qml
        TelamonSparkline.qml
        TelamonAvatar.qml
        TelamonRating.qml
        TelamonBadge.qml
        TelamonStatus.qml
        TelamonStatusView.qml
    SOURCES
        livechart.h livechart.cpp
        text/telamontextview.h text/telamontextview.cpp
        telamonsparkline.h telamonsparkline.cpp
        repaintarea.h repaintarea.cpp
        accessibilitystate.h accessibilitystate.cpp
        appearance.h appearance.cpp
        portalappearance.h portalappearance.cpp
        telamonshortcuts.h telamonshortcuts.cpp
        telamonvalidators.h telamonvalidators.cpp
        telamontreemodel.h telamontreemodel.cpp
        telamonformat.h telamonformat.cpp
        telamonglobalshortcut.h telamonglobalshortcut.cpp
        telamonapp.h telamonapp.cpp
        telamonclipboard.h telamonclipboard.cpp
        telamonsettings.h telamonsettings.cpp
        telamonportal.h telamonportal.cpp
        telamoncolorsprivate.h telamoncolorsprivate.cpp
        telamonwindowchrome.h telamonwindowchrome.cpp
        symbols.h symbols.cpp symbols/symbolnames.h
        legacyconfig.h legacyconfig.cpp
        translations.cpp telamonuiplugin.cpp
)
# TelamonApp.uiVersion: the project version in the root CMakeLists.txt.
target_compile_definitions(telamonui PRIVATE TELAMON_UI_VERSION="${PROJECT_VERSION}")
# Development builds (TELAMON_UI_DEV_BUILD, see the root CMakeLists.txt) run from
# the source tree: they find the symbol fonts in ui/symbols when the
# telamon-symbols-fonts package isn't installed, and honour the test hook. A
# packaged build has none of it: the path wouldn't exist on the user's
# machine. Decided when configuring.
if(TELAMON_UI_DEV_BUILD)
    target_compile_definitions(telamonui PRIVATE
        TELAMON_UI_DEV_PATHS
        TELAMON_UI_SYMBOLS_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}/symbols")
endif()
# Translations: ui/translations/telamon-ui.ts is the source catalogue (every
# qsTr() string of the module, no language); a translator copies it to
# telamon-ui_<locale>.ts. translations.cpp loads telamon-ui_<locale>.qm from the
# data directory when the plugin loads. Development builds also look in the
# build tree, for the same reason as the symbol fonts above.
target_compile_definitions(telamonui PRIVATE
    TELAMON_UI_TRANSLATIONS_DIR="${CMAKE_INSTALL_FULL_DATADIR}/telamon-ui/translations")
if(TELAMON_UI_DEV_BUILD)
    target_compile_definitions(telamonui PRIVATE
        TELAMON_UI_TRANSLATIONS_BUILD_DIR="${CMAKE_CURRENT_BINARY_DIR}/translations")
endif()
# Appearance: the shared transparency switch (telamonrc) and window blur.
# The text buffer behind TelamonTextView (ui/text): pure QtCore, so a static
# library the plugin links and its tests link alone. Not installed, and telamonui
# is installed without an export set; if one is ever added, the include paths
# below are BUILD_INTERFACE-only so no source-tree path can leak into it.
add_library(telamontext STATIC
    text/texttree.h text/texttree.cpp
    text/textbuffer.h text/textbuffer.cpp)
set_target_properties(telamontext PROPERTIES POSITION_INDEPENDENT_CODE ON)
target_include_directories(telamontext PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/text>
    $<BUILD_INTERFACE:${PROJECT_SOURCE_DIR}/crates/telamon-framework-ui/include>)
target_link_libraries(telamontext PUBLIC Qt6::Core Qt6::Gui)

target_link_libraries(telamonui PRIVATE telamontext Qt6::Quick Qt6::QuickControls2 Qt6::Qml Qt6::DBus
    KF6::WindowSystem KF6::ConfigCore)

# Every Telamon app loads the plugin, and nothing links it: the QML engine only
# looks up the two symbols Q_PLUGIN_METADATA marks for export
# (qt_plugin_instance, qt_plugin_query_metadata_v2), plus the type
# registration Qt's generated code exports itself. Everything else stays
# hidden, so the dynamic linker has a few dozen symbols to bind at load
# instead of 31,000, and unused code and data are dropped at link time.
set_target_properties(telamonui telamontext PROPERTIES
    CXX_VISIBILITY_PRESET hidden
    VISIBILITY_INLINES_HIDDEN ON)
if(CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
    target_compile_options(telamonui PRIVATE -ffunction-sections -fdata-sections)
    target_compile_options(telamontext PRIVATE -ffunction-sections -fdata-sections)
    target_link_options(telamonui PRIVATE LINKER:--gc-sections)
endif()

# lupdate and lrelease come with qt6-linguist. Without them the module still
# builds, without translations (the strings show in English).
find_package(Qt6 6.11 QUIET COMPONENTS LinguistTools)
if(Qt6LinguistTools_FOUND)
    file(GLOB telamonui_language_ts CONFIGURE_DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/translations/telamon-ui_*.ts)
    # `cmake --build <dir> --target telamon-ui_update_translations` rewrites the
    # .ts files from the sources; commit the result.
    qt_add_lupdate(SOURCE_TARGETS telamonui
        TS_FILES translations/telamon-ui.ts ${telamonui_language_ts}
        LUPDATE_TARGET telamon-ui_update_translations
        NO_GLOBAL_TARGET)
    if(telamonui_language_ts)
        qt_add_lrelease(TS_FILES ${telamonui_language_ts}
            QM_OUTPUT_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/translations
            QM_FILES_OUTPUT_VARIABLE telamonui_qm_files
            LRELEASE_TARGET telamon-ui_release_translations
            NO_GLOBAL_TARGET)
        add_dependencies(telamonui telamon-ui_release_translations)
        install(FILES ${telamonui_qm_files}
            DESTINATION ${CMAKE_INSTALL_DATADIR}/telamon-ui/translations)
    endif()
else()
    message(STATUS "Qt6 LinguistTools not found (qt6-linguist): building Telamon.Ui without translations")
endif()

qt_query_qml_module(telamonui
    TARGET_PATH target_path
    QMLDIR qmldir
    TYPEINFO typeinfo
    QML_FILES qml_files
    QML_FILES_DEPLOY_PATHS qml_deploy_paths
)
set(module_dir ${QT6_INSTALL_QML}/${target_path})
install(TARGETS telamonui LIBRARY DESTINATION ${module_dir})
install(FILES ${qmldir} ${typeinfo} DESTINATION ${module_dir})
foreach(file deploy_path IN ZIP_LISTS qml_files qml_deploy_paths)
    cmake_path(GET deploy_path PARENT_PATH dir)
    install(FILES ${file} DESTINATION ${module_dir}/${dir})
endforeach()

# The fonts Symbol draws with (the telamon-symbols-fonts package).
install(FILES
        symbols/TelamonSymbolsOutlined.ttf
        symbols/TelamonSymbolsRounded.ttf
        symbols/TelamonSymbolsSharp.ttf
        DESTINATION ${CMAKE_INSTALL_DATADIR}/fonts/telamon-symbols)
