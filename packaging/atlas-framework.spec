# The shared base of Atlas apps: Atlas.Ui, its Material Symbols fonts, and
# the Atlas Gallery (atlas-symbols).

# --define "_atlas_build_cache <dir>" (packaging/build-rpm.sh passes it when
# ATLAS_BUILD_CACHE is set) keeps the CMake build in <dir>, so a rebuild only
# compiles what changed.
%if 0%{?_atlas_build_cache:1}
%global _vpath_builddir %{_atlas_build_cache}/cmake
%endif

Name:           atlas-framework
Version:        1.3.0
Release:        1%{?dist}
Summary:        The shared base of Atlas apps: Atlas.Ui and its icon fonts
# The Material Symbols fonts (ui/symbols) are Apache-2.0.
License:        MIT AND Apache-2.0
URL:            https://github.com/EternalCoder454/atlas-framework
Source0:        atlas-framework-%{version}.tar.gz

BuildRequires:  cmake
BuildRequires:  ninja-build
BuildRequires:  gcc-c++
BuildRequires:  desktop-file-utils
BuildRequires:  cmake(Qt6Core)
BuildRequires:  cmake(Qt6Gui)
BuildRequires:  cmake(Qt6Qml)
BuildRequires:  cmake(Qt6Quick)
BuildRequires:  cmake(Qt6QuickControls2)
BuildRequires:  cmake(Qt6Widgets)
BuildRequires:  cmake(Qt6QmlTools)
BuildRequires:  qt6-qtbase-devel
BuildRequires:  cmake(KF6WindowSystem)
BuildRequires:  cmake(KF6Config)
# QML modules qmlcachegen resolves at build time (not linked)
BuildRequires:  kf6-kirigami-devel

%description
Source package for atlas-ui, atlas-symbols-fonts, atlas-symbols-fonts-extra and
atlas-symbols (the Atlas Gallery).

%package -n atlas-ui
Summary:        Atlas.Ui, the QML module every Atlas app shares
License:        MIT
# Symbol draws with these.
Requires:       atlas-symbols-fonts = %{version}-%{release}
# libatlasui.so needs the Qt minor it was built with (rpm adds
# Qt_6.x_PRIVATE_API, from qmlcachegen's output): rebuild for a Qt minor
# update. See "Compatibility" in docs/DESIGN.md.
# QML modules Atlas.Ui imports (the plugin doesn't link them)
Requires:       kf6-kirigami
Requires:       qt6-qtdeclarative

%description -n atlas-ui
Atlas.Ui gives Atlas apps their shared look: pill buttons, grouped sections,
the status hero, sidebar items, setup steps, live charts, usage and progress
bars, tables, search, menus, Material Symbols icons, and the window that
follows the shared transparency switch. Apps `import Atlas.Ui`. Also protects
atlas-ui and atlas-symbols-fonts from removal by dnf.

%package -n atlas-symbols-fonts
Summary:        Material Symbols fonts for Atlas apps
License:        Apache-2.0
URL:            https://fonts.google.com/icons
BuildArch:      noarch
Requires:       fontconfig

%description -n atlas-symbols-fonts
Google's Material Symbols Rounded as a variable font: about 4,000 icons that
Atlas apps draw through Atlas.Ui's Symbol (Rounded is its default style). The
Outlined and Sharp styles are in atlas-symbols-fonts-extra.

%package -n atlas-symbols-fonts-extra
Summary:        Material Symbols Outlined and Sharp fonts for Atlas apps
License:        Apache-2.0
URL:            https://fonts.google.com/icons
BuildArch:      noarch
# Same release: they are the same icon set, and the files moved here from
# atlas-symbols-fonts, so a 1.2.0 atlas-symbols-fonts must be replaced first.
Requires:       atlas-symbols-fonts = %{version}-%{release}

%description -n atlas-symbols-fonts-extra
The Outlined and Sharp styles of Google's Material Symbols, for apps that ask
Atlas.Ui's Symbol for them (Symbol.Outlined, Symbol.Sharp) and for the Atlas
Gallery. Without this package those symbols are blank and the app logs a
warning once.

%package -n atlas-symbols
Summary:        Atlas Gallery: every Atlas control and Material Symbol
License:        MIT
Requires:       atlas-ui = %{version}-%{release}
Requires:       kf6-qqc2-desktop-style
# Its Symbols page shows the Outlined and Sharp styles.
Recommends:     atlas-symbols-fonts-extra = %{version}-%{release}

%description -n atlas-symbols
The Atlas Gallery shows every Atlas.Ui control live (with a Disabled switch and
the QML to copy) and lists every Material Symbol: search, pick a style, fill and
weight, and copy the QML for one.

%prep
%autosetup -n atlas-framework-%{version}

%build
%cmake -G Ninja -DCMAKE_BUILD_TYPE=Release
%cmake_build

%install
%cmake_install
install -Dpm0644 packaging/atlas-framework.conf %{buildroot}%{_sysconfdir}/dnf/protected.d/atlas-framework.conf
# Where every Atlas app's crash reports go (atlas-framework-system's crash).
install -Dpm0644 crates/atlas-framework-system/data/atlas/crash-reporting.toml %{buildroot}%{_datadir}/atlas/crash-reporting.toml

%check
desktop-file-validate %{buildroot}%{_datadir}/applications/net.eterneon.atlas.symbols.desktop
# A packaged build loads the fonts and translations from the system only: no
# path into the source or build tree, and none of the development-only
# variables ($ATLAS_UI_SYMBOLS_DIR, $ATLAS_UI_TRANSLATIONS_DIR) or test hooks.
for s in "%{_builddir}" %{?_atlas_build_cache:"%{_atlas_build_cache}"} ATLAS_UI_SYMBOLS_DIR ATLAS_UI_TRANSLATIONS_DIR ATLAS_UI_TEST_FIXED_ENV; do
    if grep -qF "$s" %{buildroot}%{_libdir}/qt6/qml/Atlas/Ui/libatlasui.so; then
        echo "libatlasui.so holds $s, which only development builds may" >&2
        exit 1
    fi
done

%files -n atlas-ui
%license LICENSE
%dir %{_libdir}/qt6/qml/Atlas
%{_libdir}/qt6/qml/Atlas/Ui/
%dir %{_datadir}/atlas
%{_datadir}/atlas/crash-reporting.toml
%config(noreplace) %{_sysconfdir}/dnf/protected.d/atlas-framework.conf

%files -n atlas-symbols-fonts
%license ui/symbols/LICENSE.txt
%dir %{_datadir}/fonts/atlas-symbols
%{_datadir}/fonts/atlas-symbols/MaterialSymbolsRounded.ttf

%files -n atlas-symbols-fonts-extra
%license ui/symbols/LICENSE.txt
%dir %{_datadir}/fonts/atlas-symbols
%{_datadir}/fonts/atlas-symbols/MaterialSymbolsOutlined.ttf
%{_datadir}/fonts/atlas-symbols/MaterialSymbolsSharp.ttf

%files -n atlas-symbols
%license LICENSE
%{_bindir}/atlas-symbols
%{_datadir}/applications/net.eterneon.atlas.symbols.desktop

%changelog
* Sun Oct 04 2026 Atlas <atlas@eterneon.net> - 1.3.0-1
- Atlas.Ui: form controls (AtlasTextField, AtlasTextArea, AtlasComboBox,
  AtlasCheckBox, AtlasRadioButton, AtlasSlider, AtlasSpinBox), feedback
  (AtlasToolTip, AtlasSpinner, AtlasPlaceholder, AtlasEmptyState,
  AtlasFocusRing) and AtlasBreadcrumb, AtlasIconGrid, AtlasAppCard,
  AtlasScreenshotCarousel, AtlasInstallButton, AtlasSearchResults
- Atlas.Ui reports its version (AtlasApp.uiVersion) for the apps' startup check
- atlas-symbols-fonts ships Rounded only; Outlined and Sharp move to the new
  atlas-symbols-fonts-extra
- atlas-symbols is the Atlas Gallery: every control live, and the symbols

* Sun Oct 04 2026 Atlas <atlas@eterneon.net> - 1.2.0-1
- Atlas.Ui: TabBar, FindBar, StatusBar, StatusBarItem, InfoBanner, Toast and
  ToolbarButton (from Atlas Notepad)
- ContextMenuItem: a check mark for checked checkable rows, icon.source, a
  submenu arrow; hidden rows and separators take no room

* Sun Oct 04 2026 Atlas <atlas@eterneon.net> - 1.1.0-1
- Atlas.Ui: AtlasApp and AtlasAboutPage
- atlas-ui ships /usr/share/atlas/crash-reporting.toml (from atlasos-updater):
  crash reports go to the AtlasOS relay, which posts them as GitHub issues

* Sat Oct 03 2026 Atlas <atlas@eterneon.net> - 1.0.0-1
- First package: Atlas.Ui, atlas-symbols-fonts and Atlas Symbols, moved out
  of atlasos-updater
