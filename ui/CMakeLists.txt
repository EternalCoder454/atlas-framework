# Atlas.Ui: the shared look of Atlas apps (pill buttons, grouped sections,
# status hero, sidebar items, setup steps, live charts, usage and progress
# bars, tables, search, menus, document tabs, find and status bars, banners,
# toasts, toolbar buttons, and Material Symbols icons: see Symbol.qml and
# symbols.h). A QML module installed with Qt's own, like Kirigami: apps
# `import Atlas.Ui` and link nothing. One library, the plugin, holds the C++
# types and the QML compiled ahead of time by qmlcachegen.
#
# Installed in Qt's QML directory (/usr/lib64/qt6/qml/Atlas/Ui), with the
# qmldir, the qmltypes and the .qml files, which qmllint and qmlcachegen read
# when they compile an app against it.
#
# Its API is a contract with every Atlas app: see "Compatibility" in
# docs/DESIGN.md before renaming or removing anything.
# AtlasStyle is a QML singleton: the qmldir needs it marked before the module.
set_source_files_properties(AtlasStyle.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)
qt_add_qml_module(atlasui
    URI Atlas.Ui
    VERSION 1.0
    PLUGIN_TARGET atlasui
    # The plugin is the module: nothing else registers its C++ types.
    NO_PLUGIN_OPTIONAL
    NO_GENERATE_PLUGIN_SOURCE
    CLASS_NAME AtlasUiPlugin
    QML_FILES
        AtlasWindow.qml
        AtlasStyle.qml
        AtlasButton.qml
        PrimaryButton.qml
        SecondaryButton.qml
        TextButton.qml
        MenuButton.qml
        Section.qml
        SectionRow.qml
        StatusHero.qml
        SidebarItem.qml
        SidebarGroup.qml
        AtlasSidebar.qml
        StepItem.qml
        AtlasPage.qml
        AtlasSwitch.qml
        AtlasProgressBar.qml
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
        AtlasAboutPage.qml
        TabBar.qml
        FindBar.qml
        StatusBar.qml
        StatusBarItem.qml
        InfoBanner.qml
        Toast.qml
        ToolbarButton.qml
        AtlasBreadcrumb.qml
        AtlasIconGrid.qml
        AtlasAppCard.qml
        AtlasScreenshotCarousel.qml
        AtlasInstallButton.qml
        AtlasSearchResults.qml
        AtlasTextField.qml
        AtlasPasswordField.qml
        AtlasTextArea.qml
        AtlasComboBox.qml
        AtlasCheckBox.qml
        AtlasRadioButton.qml
        AtlasSlider.qml
        AtlasSpinBox.qml
        AtlasCalendar.qml
        AtlasDatePicker.qml
        AtlasTimePicker.qml
        AtlasToolTip.qml
        AtlasSpinner.qml
        AtlasPlaceholder.qml
        AtlasEmptyState.qml
        AtlasLabel.qml
        AtlasFocusRing.qml
        AtlasAction.qml
        AtlasSegmentedControl.qml
        AtlasSplitButton.qml
        AtlasChip.qml
        AtlasChipGroup.qml
        AtlasShortcutLabel.qml
        AtlasShortcutsDialog.qml
        AtlasDoubleSpinBox.qml
        AtlasShortcutField.qml
        AtlasSplitView.qml
        AtlasNavigationStack.qml
        AtlasViewSwitcher.qml
        AtlasColorField.qml
        AtlasFileField.qml
        AtlasFolderField.qml
        AtlasAutocompleteField.qml
        AtlasFontPicker.qml
        AtlasDropZone.qml
        AtlasOnboarding.qml
    SOURCES
        livechart.h livechart.cpp
        repaintarea.h repaintarea.cpp
        accessibilitystate.h accessibilitystate.cpp
        appearance.h appearance.cpp
        atlasshortcuts.h atlasshortcuts.cpp
        atlasvalidators.h atlasvalidators.cpp
        atlasapp.h atlasapp.cpp
        symbols.h symbols.cpp symbols/symbolnames.h
        translations.cpp atlasuiplugin.cpp
)
# AtlasApp.uiVersion: the project version in the root CMakeLists.txt.
target_compile_definitions(atlasui PRIVATE ATLAS_UI_VERSION="${PROJECT_VERSION}")
# Development builds (ATLAS_UI_DEV_BUILD, see the root CMakeLists.txt) run from
# the source tree: they find the symbol fonts in ui/symbols when the
# atlas-symbols-fonts package isn't installed, and honour the test hook. A
# packaged build has none of it: the path wouldn't exist on the user's
# machine. Decided when configuring.
if(ATLAS_UI_DEV_BUILD)
    target_compile_definitions(atlasui PRIVATE
        ATLAS_UI_DEV_PATHS
        ATLAS_UI_SYMBOLS_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}/symbols")
endif()
# Translations: ui/translations/atlas-ui.ts is the source catalogue (every
# qsTr() string of the module, no language); a translator copies it to
# atlas-ui_<locale>.ts. translations.cpp loads atlas-ui_<locale>.qm from the
# data directory when the plugin loads. Development builds also look in the
# build tree, for the same reason as the symbol fonts above.
target_compile_definitions(atlasui PRIVATE
    ATLAS_UI_TRANSLATIONS_DIR="${CMAKE_INSTALL_FULL_DATADIR}/atlas-ui/translations")
if(ATLAS_UI_DEV_BUILD)
    target_compile_definitions(atlasui PRIVATE
        ATLAS_UI_TRANSLATIONS_BUILD_DIR="${CMAKE_CURRENT_BINARY_DIR}/translations")
endif()
# Appearance: the shared transparency switch (atlasrc) and window blur.
target_link_libraries(atlasui PRIVATE Qt6::Quick Qt6::QuickControls2 Qt6::Qml
    KF6::WindowSystem KF6::ConfigCore)

# lupdate and lrelease come with qt6-linguist. Without them the module still
# builds, without translations (the strings show in English).
find_package(Qt6 6.11 QUIET COMPONENTS LinguistTools)
if(Qt6LinguistTools_FOUND)
    file(GLOB atlasui_language_ts CONFIGURE_DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/translations/atlas-ui_*.ts)
    # `cmake --build <dir> --target atlas-ui_update_translations` rewrites the
    # .ts files from the sources; commit the result.
    qt_add_lupdate(SOURCE_TARGETS atlasui
        TS_FILES translations/atlas-ui.ts ${atlasui_language_ts}
        LUPDATE_TARGET atlas-ui_update_translations
        NO_GLOBAL_TARGET)
    if(atlasui_language_ts)
        qt_add_lrelease(TS_FILES ${atlasui_language_ts}
            QM_OUTPUT_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/translations
            QM_FILES_OUTPUT_VARIABLE atlasui_qm_files
            LRELEASE_TARGET atlas-ui_release_translations
            NO_GLOBAL_TARGET)
        add_dependencies(atlasui atlas-ui_release_translations)
        install(FILES ${atlasui_qm_files}
            DESTINATION ${CMAKE_INSTALL_DATADIR}/atlas-ui/translations)
    endif()
else()
    message(STATUS "Qt6 LinguistTools not found (qt6-linguist): building Atlas.Ui without translations")
endif()

qt_query_qml_module(atlasui
    TARGET_PATH target_path
    QMLDIR qmldir
    TYPEINFO typeinfo
    QML_FILES qml_files
    QML_FILES_DEPLOY_PATHS qml_deploy_paths
)
set(module_dir ${QT6_INSTALL_QML}/${target_path})
install(TARGETS atlasui LIBRARY DESTINATION ${module_dir})
install(FILES ${qmldir} ${typeinfo} DESTINATION ${module_dir})
foreach(file deploy_path IN ZIP_LISTS qml_files qml_deploy_paths)
    cmake_path(GET deploy_path PARENT_PATH dir)
    install(FILES ${file} DESTINATION ${module_dir}/${dir})
endforeach()

# The fonts Symbol draws with (the atlas-symbols-fonts package).
install(FILES
        symbols/MaterialSymbolsOutlined.ttf
        symbols/MaterialSymbolsRounded.ttf
        symbols/MaterialSymbolsSharp.ttf
        DESTINATION ${CMAKE_INSTALL_DATADIR}/fonts/atlas-symbols)
