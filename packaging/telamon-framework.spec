# The shared base of Telamon apps: Telamon.Ui, its Material Symbols fonts, and
# the Telamon Gallery (telamon-symbols).
#
# 2.0.0 is the framework formerly known as atlas-framework (atlas-ui, atlas-
# symbols-fonts, ...). It installs beside those packages, which apps that have
# not moved to Telamon.Ui still need: no name, file path, font family or QML
# module is shared with them, and there is deliberately no Obsoletes: or
# Conflicts: for them yet (a later release will obsolete them once every app
# has moved). %check fails if a path of this package would ever hold "atlas".

# --define "_telamon_build_cache <dir>" (packaging/build-rpm.sh passes it when
# TELAMON_BUILD_CACHE is set) keeps the CMake build in <dir>, so a rebuild only
# compiles what changed.
%if 0%{?_telamon_build_cache:1}
%global _vpath_builddir %{_telamon_build_cache}/cmake
%endif

Name:           telamon-framework
Version:        2.1.0
Release:        1%{?dist}
Summary:        The shared base of Telamon apps: Telamon.Ui and its icon fonts
# The Material Symbols fonts (ui/symbols) are Apache-2.0.
License:        MIT AND Apache-2.0
URL:            https://github.com/EternalCoder454/atlas-framework
Source0:        telamon-framework-%{version}.tar.gz

BuildRequires:  cmake
BuildRequires:  ninja-build
BuildRequires:  gcc-c++
BuildRequires:  desktop-file-utils
# %check reads the hardening back from the built files (readelf from binutils,
# which gcc-c++ brings in) and has annocheck confirm it.
BuildRequires:  binutils
BuildRequires:  annobin-annocheck
BuildRequires:  cmake(Qt6Core)
BuildRequires:  cmake(Qt6Gui)
BuildRequires:  cmake(Qt6Qml)
BuildRequires:  cmake(Qt6DBus)
BuildRequires:  cmake(Qt6Quick)
BuildRequires:  cmake(Qt6QuickControls2)
BuildRequires:  cmake(Qt6Widgets)
BuildRequires:  cmake(Qt6QmlTools)
# lrelease for the translations; without it the build silently ships none.
BuildRequires:  cmake(Qt6LinguistTools)
BuildRequires:  qt6-qtbase-devel
BuildRequires:  cmake(KF6WindowSystem)
BuildRequires:  cmake(KF6Config)
# TelamonCodeEditor's syntax highlighting
BuildRequires:  cmake(KF6SyntaxHighlighting)
# QML modules qmlcachegen resolves at build time (not linked)
BuildRequires:  kf6-kirigami-devel

%description
Source package for telamon-ui, telamon-symbols-fonts, telamon-symbols-fonts-extra and
telamon-symbols (the Telamon Gallery).

%package -n telamon-ui
Summary:        Telamon.Ui, the QML module every Telamon app shares
License:        MIT
# Symbol draws with these.
Requires:       telamon-symbols-fonts = %{version}-%{release}
# libtelamonui.so needs the Qt minor it was built with (rpm adds
# Qt_6.x_PRIVATE_API, from qmlcachegen's output): rebuild for a Qt minor
# update. See "Compatibility" in docs/DESIGN.md.
# QML modules Telamon.Ui imports (the plugin doesn't link them)
Requires:       kf6-kirigami
Requires:       qt6-qtdeclarative
# TelamonCodeEditor's syntax highlighting (libtelamonui.so links it, and the
# definitions it highlights with are in the same package).
Requires:       kf6-syntax-highlighting
# telamon-preview runs every variant on a private session bus, in the
# org.kde.desktop style.
Requires:       dbus-daemon
Requires:       kf6-qqc2-desktop-style
# The Telamon look: IBM Plex Sans for the UI, JetBrains Mono for code (without
# them Telamon.Ui falls back to the system fonts).
Requires:       ibm-plex-sans-fonts
Requires:       jetbrains-mono-fonts

%description -n telamon-ui
Telamon.Ui gives Telamon apps their shared look: buttons, grouped sections,
the status hero, sidebar items, setup steps, live charts, usage and progress
bars, tables, search, menus, Material Symbols icons, and the window that
follows the shared transparency switch. Apps `import Telamon.Ui`. Also protects
telamon-ui and telamon-symbols-fonts from removal by dnf.

%package -n telamon-symbols-fonts
Summary:        Material Symbols fonts for Telamon apps
License:        Apache-2.0
URL:            https://fonts.google.com/icons
BuildArch:      noarch
Requires:       fontconfig

%description -n telamon-symbols-fonts
Google's Material Symbols Rounded as a variable font, installed as the family
"Telamon Symbols Rounded" (only its name differs from Google's, so it sits
beside the Material Symbols fonts of atlas-symbols-fonts): about 4,000 icons that
Telamon apps draw through Telamon.Ui's Symbol (Rounded is its default style). The
Outlined and Sharp styles are in telamon-symbols-fonts-extra.

%package -n telamon-symbols-fonts-extra
Summary:        Material Symbols Outlined and Sharp fonts for Telamon apps
License:        Apache-2.0
URL:            https://fonts.google.com/icons
BuildArch:      noarch
# Same release: they are the same icon set, and the files moved here from
# telamon-symbols-fonts, so a 1.2.0 telamon-symbols-fonts must be replaced first.
Requires:       telamon-symbols-fonts = %{version}-%{release}

%description -n telamon-symbols-fonts-extra
The Outlined and Sharp styles of Google's Material Symbols, for apps that ask
Telamon.Ui's Symbol for them (Symbol.Outlined, Symbol.Sharp) and for the Telamon
Gallery. Without this package those symbols are blank and the app logs a
warning once.

%package -n telamon-symbols
Summary:        Telamon Gallery: every Telamon control and Material Symbol
License:        MIT
Requires:       telamon-ui = %{version}-%{release}
Requires:       kf6-qqc2-desktop-style
# Its Symbols page shows the Outlined and Sharp styles.
Recommends:     telamon-symbols-fonts-extra = %{version}-%{release}

%description -n telamon-symbols
The Telamon Gallery shows every Telamon.Ui control live (with a Disabled switch and
the QML to copy) and lists every Material Symbol: search, pick a style, fill and
weight, and copy the QML for one.

%prep
%autosetup -n telamon-framework-%{version}

%build
%cmake -G Ninja -DCMAKE_BUILD_TYPE=Release -DTELAMON_UI_DEV_PATHS=OFF
%cmake_build

%install
%cmake_install
install -Dpm0644 packaging/telamon-framework.conf %{buildroot}%{_sysconfdir}/dnf/protected.d/telamon-framework.conf
# The translations' directory is owned by telamon-ui even while no language has
# been translated yet (then nothing is installed into it).
install -dm0755 %{buildroot}%{_datadir}/telamon-ui/translations
# Where every Telamon app's crash reports go (telamon-framework-system's crash).
install -Dpm0644 crates/telamon-framework-system/data/telamon/crash-reporting.toml %{buildroot}%{_datadir}/telamon/crash-reporting.toml

%check
# Beside atlas-ui 1.x (see the top): not one installed path may be one of
# theirs, and theirs all have "atlas" in them.
if find %{buildroot} -iname '*atlas*' | grep -q .; then
    find %{buildroot} -iname '*atlas*' >&2
    echo "an installed path has atlas in it: it could clash with the atlas-ui 1.x packages" >&2
    exit 1
fi
desktop-file-validate %{buildroot}%{_datadir}/applications/net.eterneon.telamon.symbols.desktop
# A packaged build loads the fonts and translations from the system only: no
# path into the source or build tree, and none of the development-only
# variables ($TELAMON_UI_SYMBOLS_DIR, $TELAMON_UI_TRANSLATIONS_DIR) or test hooks.
# Both as bytes and as UTF-16 (QStringLiteral), which grep alone can't see.
lib=%{buildroot}%{_libdir}/qt6/qml/Telamon/Ui/libtelamonui.so
strings -el "$lib" > utf16-strings.txt
for s in "%{_builddir}" %{?_telamon_build_cache:"%{_telamon_build_cache}"} TELAMON_UI_SYMBOLS_DIR TELAMON_UI_TRANSLATIONS_DIR TELAMON_UI_TEST_FIXED_ENV; do
    if grep -qF "$s" "$lib" || grep -qF "$s" utf16-strings.txt; then
        echo "libtelamonui.so holds $s, which only development builds may" >&2
        exit 1
    fi
done

# telamon-preview is a tool for apps' CI: it must not hold a path into the source
# or build tree either.
bin=%{buildroot}%{_bindir}/telamon-preview
strings -el "$bin" > utf16-strings-preview.txt
for s in "%{_builddir}" %{?_telamon_build_cache:"%{_telamon_build_cache}"}; do
    if grep -qF "$s" "$bin" || grep -qF "$s" utf16-strings-preview.txt; then
        echo "telamon-preview holds $s, which only development builds may" >&2
        exit 1
    fi
done

# The library and the programs carry the hardening Fedora's build flags give
# them (docs/SECURITY.md, "Build hardening"): the plugin every Telamon app loads
# is a shared object with full RELRO and BIND_NOW, no executable stack, no
# RPATH and stack protectors, the programs are also position independent; readelf
# says so, not the flags we meant. None holds a development-only variable.
packaging/check-hardening.sh --lib --cxx \
    --forbid TELAMON_UI_SYMBOLS_DIR --forbid TELAMON_UI_TRANSLATIONS_DIR --forbid TELAMON_UI_TEST_FIXED_ENV \
    %{buildroot}%{_libdir}/qt6/qml/Telamon/Ui/libtelamonui.so
packaging/check-hardening.sh --cxx %{buildroot}%{_bindir}/telamon-preview %{buildroot}%{_bindir}/telamon-symbols
# annocheck agrees (PIE, BIND_NOW, RELRO, non-executable stack, CET, no writable
# GOT, ...). The tests that need annobin notes or debuginfo, which this build
# has neither of, are skipped: check-hardening.sh covers stack protectors.
annocheck --ignore-unknown --skip-notes --skip-optimization --skip-pic --skip-stack-clash \
    --skip-stack-prot --skip-fortify --skip-gaps \
    %{buildroot}%{_libdir}/qt6/qml/Telamon/Ui/libtelamonui.so %{buildroot}%{_bindir}/telamon-preview %{buildroot}%{_bindir}/telamon-symbols

# Every language catalogue (telamon-ui_<locale>.ts) must have shipped as a .qm:
# a missing LinguistTools would otherwise build without translations, quietly.
shopt -s nullglob
ts=(ui/translations/telamon-ui_*.ts)
qm=(%{buildroot}%{_datadir}/telamon-ui/translations/telamon-ui_*.qm)
if [ "${#ts[@]}" -gt 0 ] && [ "${#qm[@]}" -lt "${#ts[@]}" ]; then
    echo "${#ts[@]} translation(s) in ui/translations but ${#qm[@]} .qm file(s) installed" >&2
    exit 1
fi

%files -n telamon-ui
%license LICENSE
%dir %{_libdir}/qt6/qml/Telamon
%{_libdir}/qt6/qml/Telamon/Ui/
%{_bindir}/telamon-preview
%{_datadir}/telamon-ui/
%dir %{_datadir}/telamon
%{_datadir}/telamon/crash-reporting.toml
%config(noreplace) %{_sysconfdir}/dnf/protected.d/telamon-framework.conf

%files -n telamon-symbols-fonts
%license ui/symbols/LICENSE.txt
%dir %{_datadir}/fonts/telamon-symbols
%{_datadir}/fonts/telamon-symbols/TelamonSymbolsRounded.ttf

%files -n telamon-symbols-fonts-extra
%license ui/symbols/LICENSE.txt
%dir %{_datadir}/fonts/telamon-symbols
%{_datadir}/fonts/telamon-symbols/TelamonSymbolsOutlined.ttf
%{_datadir}/fonts/telamon-symbols/TelamonSymbolsSharp.ttf

%files -n telamon-symbols
%license LICENSE
%{_bindir}/telamon-symbols
%{_datadir}/applications/net.eterneon.telamon.symbols.desktop

%changelog
* Fri Oct 09 2026 Telamon <atlas@eterneon.net> - 2.1.0-1
- New: TelamonCodeEditor (an editable code editor with syntax highlighting, a
  line-number gutter and live edits from outside) and TelamonConsoleView (a
  bounded, colour-aware view of a command's streaming output). telamon-ui now
  needs kf6-syntax-highlighting.

* Fri Oct 09 2026 Telamon <atlas@eterneon.net> - 2.0.10-1
- Tooling only, no API change: the native-bundle workflow signs telamon-bundle.json
  with minisign (the new sign job and tools/sign-bundle.sh; a release without a
  signature, or with publish: false, stays a draft for offline signing), the
  bundle tools refuse a PAX sparse member and resolve links with a budget, and
  make-bundle.sh --exclude no longer removes through a symlink or a newline in a name.

* Fri Oct 09 2026 Telamon <atlas@eterneon.net> - 2.0.9-1
- Secure phase: every text control in Telamon.Ui is plain text (a string that
  starts with "<" was read as HTML), links open through TelamonPortal.openUrl,
  QML engines refuse cleartext http: and ftp:, TelamonAvatar and
  TelamonChoiceCard take https pictures only with allowRemote, NotesText keeps
  only a release note's tags. New: crash: false in app! (and
  telamon_app_set_crash_reporting) keeps an app out of Telamon crash reporting.
  The crash sender needs a 2xx answer and TLS 1.2; the crates read state files
  with caps and never block on a FIFO, settings values cannot forge keys,
  notifications and polkit checks validate their input. The package build now
  checks the hardening of the plugin and programs (readelf and annocheck).
  See docs/SECURITY.md.

* Thu Oct 08 2026 Telamon <atlas@eterneon.net> - 2.0.8-1
- Fix: the crash report scrubber hides more. Secrets such as PGPASSWORD=,
  dbPassword=, pass=, an OAuth ?code=, Authorization: Bearer with several
  spaces, a standalone Basic credential, long hex digests, base64 secrets that
  contain a slash or end in =, webhook paths and serial or IMEI values. Every
  absolute path outside the system's directories is hidden, and each word of
  the full name. Uptime is rounded to the hour and RAM to the GB. Messages and
  frames lose bidi and invisible characters. An event with a very long time no
  longer stops event collection. Report files are read safely, scrubbed again
  and the payload is at most 64 KiB.

* Thu Oct 08 2026 Telamon <atlas@eterneon.net> - 2.0.7-1
- Fix: an InfoBanner's close button (and FindBar's, TabBar's, and the shortcut
  field's clear button) draws a Material Symbol, not a chevron where the icon
  theme lacks "window-close". A TelamonCodeView with
  wrap: false no longer starts scrolled by 2 pixels (its first character was
  clipped when the line was wider than the view).

* Thu Oct 08 2026 Telamon <atlas@eterneon.net> - 2.0.6-1
- Fix: ten things the Telamon Gates screenshots showed at 150%. A code view's
  horizontal bar no longer covers its last line (it is a TelamonScrollBar and
  has room of its own). The focus ring is the accent, not magenta. The sidebar
  filter's magnifier and clear symbol share an inset and the text clears the
  magnifier. The transparency row without blur dims only its switch (shown
  off), not its text. The error colour passes 4.5:1 as text in Light and Dark.
  About-page dividers are one device pixel and as padded on the right as on the
  left, and a value ends where a chevron does. An info banner's icon is in the
  accent. A sidebar title that elides keeps its right padding. A context menu
  is as wide as its content (7 to 24 grid units) and has an outline and a
  shadow in Dark. The spinner's arc is longer and no longer cut off at 16 px.
  API: TelamonStyle.outline and SectionRow.switchEnabled are new.

* Thu Oct 08 2026 Telamon <atlas@eterneon.net> - 2.0.5-1
- Added TelamonIcon (a Kirigami.Icon that is a layer on the software renderer).
- Fix: icons drawn over dialogs, popups and menus with the software renderer;
  Telamon.Ui's controls use TelamonIcon for all their icons.

* Thu Oct 08 2026 Telamon <atlas@eterneon.net> - 2.0.4-1
- Native app bundles: tools/make-bundle.sh and tools/bundle.py pack a built
  app as a per-user bundle (<id>-<version>-x86_64.tar.zst and
  telamon-bundle.json) for Telamon Store; a reusable GitHub workflow
  (bundle.yml) builds and attaches it to a release; the app template ships
  with the caller workflow, metainfo and an icon. Nothing in the packages
  changes.

* Thu Oct 08 2026 Telamon <atlas@eterneon.net> - 2.0.3-1
- Fix: the keyboard in ContextMenu. Up and Down skip separators, disabled and
  hidden rows and wrap at the ends, Home and End jump, Right opens a submenu
  and Left closes it (the other way round in a right-to-left layout), and a
  row that holds the keyboard (an icon row, a custom delegate) no longer keeps
  the arrow keys from the menu. No API change.

* Wed Oct 07 2026 Telamon <atlas@eterneon.net> - 2.0.2-1
- Fix: crash reports left out crashes that are not the host's. Core dumps of
  programs in containers (podman, toolbox, distrobox, docker, nspawn) and of
  programs outside the OS (/tmp, /work, a build tree) are no longer queued or
  notified; pending ones of that kind are dropped once. Flatpak crashes are
  labelled with their app ID. No API change.

* Wed Oct 07 2026 Telamon <atlas@eterneon.net> - 2.0.1-1
- Fix: filled symbols (a selected SidebarItem's icon) were drawn broken on a
  GPU; Symbol now uses native text rendering. No API change.

* Wed Oct 07 2026 Telamon <atlas@eterneon.net> - 2.0.0-1
- Renamed: atlas-framework is the Telamon framework. Packages telamon-ui,
  telamon-symbols-fonts, telamon-symbols-fonts-extra and telamon-symbols;
  the QML module is Telamon.Ui, every Atlas<Name> type is Telamon<Name>, and
  the Material Symbols fonts are the "Telamon Symbols" families. Installs
  beside atlas-ui 1.x (no Obsoletes: yet): apps move one by one with
  tools/migrate-app-to-telamon.sh.
- Reads what 1.x wrote: the settings file atlas-<app>rc, atlasrc, the
  crash-reporting switch, reports and state under .../atlas, notification
  choices, and ATLAS_SOFTWARE_RENDERING, ATLAS_REDUCED_MOTION and ATLAS_LOG.
- Telamon.Ui is lighter (a plugin that exports 52 symbols, DataTable cells and
  MenuButton menus made when used).

* Tue Oct 06 2026 Atlas <atlas@eterneon.net> - 1.6.1-1
- Atlas.Ui: the GPU switch on HiDPI screens works (it read the RHI API, not
  the software scene graph backend, and ran only at the start-up check).

* Tue Oct 06 2026 Atlas <atlas@eterneon.net> - 1.6.0-1
- Atlas.Ui: every AtlasWindow has an alpha surface from the start (no black
  corners or grey content on Wayland's CPU path); apps that ask for the
  software renderer draw on the GPU on HiDPI screens.
- crash: SendFailure says why a send failed; reports and markers are written
  atomically, limits hold across processes, messages are capped, journalctl
  and rpm have deadlines, one sender per report, private paths redacted.

* Tue Oct 06 2026 Atlas <atlas@eterneon.net> - 1.5.1-1
- Atlas.Ui: a frameless AtlasWindow rounds its top corners; a second click
  on a MenuButton closes its menu; see CHANGELOG.md
* Mon Oct 05 2026 Atlas <atlas@eterneon.net> - 1.5.0-1
- Atlas.Ui: AtlasForm, AtlasFormEntry, AtlasPreferencesDialog and
  AtlasPreferencesPage; AtlasShelf and the store card states; AtlasTextView;
  InfoBanner.animated; AtlasStyle.alpha, mix and softwareRendering
- Robustness fixes across Atlas.Ui and the crates; see CHANGELOG.md

* Sun Oct 04 2026 Atlas <atlas@eterneon.net> - 1.4.0-1
- Atlas.Ui: AtlasPasswordField, a password field with a show/hide eye
- Atlas.Ui: the Atlas look (violet accent, pink focus ring, IBM Plex Sans and
  JetBrains Mono, small rounding, tonal neutrals, blur with solid fallback)
- Atlas.Ui: springs, sliding selection, window-edge glow, reduced motion
- Atlas.Ui: new controls from docs/ROADMAP.md (tables, lists, settings, code
  view, command palette, onboarding and more); see CHANGELOG.md

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
