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
qt_add_qml_module(atlasui
    URI Atlas.Ui
    VERSION 1.0
    PLUGIN_TARGET atlasui
    # The plugin is the module: nothing else registers its C++ types.
    NO_PLUGIN_OPTIONAL
    QML_FILES
        AtlasWindow.qml
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
        AtlasTextArea.qml
        AtlasComboBox.qml
        AtlasCheckBox.qml
        AtlasRadioButton.qml
        AtlasSlider.qml
        AtlasSpinBox.qml
        AtlasToolTip.qml
        AtlasSpinner.qml
        AtlasPlaceholder.qml
        AtlasEmptyState.qml
        AtlasFocusRing.qml
    SOURCES
        livechart.h livechart.cpp
        repaintarea.h repaintarea.cpp
        accessibilitystate.h accessibilitystate.cpp
        appearance.h appearance.cpp
        atlasapp.h atlasapp.cpp
        symbols.h symbols.cpp symbols/symbolnames.h
)
# Development builds run from the source tree find the symbol fonts here when
# the atlas-symbols-fonts package isn't installed. Not in packaged builds
# (prefix /usr): the path wouldn't exist on the user's machine. Decided when
# configuring: configure with -DCMAKE_INSTALL_PREFIX=/usr to install over the
# system copy (`cmake --install --prefix /usr` alone would keep the path).
if(NOT CMAKE_INSTALL_PREFIX STREQUAL "/usr")
    target_compile_definitions(atlasui PRIVATE
        ATLAS_UI_SYMBOLS_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}/symbols")
endif()
# Appearance: the shared transparency switch (atlasrc) and window blur.
target_link_libraries(atlasui PRIVATE Qt6::Quick Qt6::QuickControls2 Qt6::Qml
    KF6::WindowSystem KF6::ConfigCore)

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
