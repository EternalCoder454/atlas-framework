---
title: Build and run
summary: The Fedora 44 packages, the CMake commands and how to run the template without showing a window.
order: 20
---

## Packages

On Fedora 44:

```sh
sudo dnf install cmake ninja-build gcc-c++ cargo corrosion qt6-qtbase-devel \
  qt6-qtdeclarative-devel kf6-kirigami-devel kf6-qqc2-desktop-style \
  kf6-kdbusaddons-devel kf6-kwindowsystem-devel atlas-ui
```

`atlas-ui` is the runtime [Atlas.Ui](../atlas-ui/index.md) module; the configure step stops with a plain message when `Atlas/Ui/qmldir` is missing from Qt's QML directory.

## Build

```sh
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build build
```

CMake builds the Rust crate as a static library through Corrosion (`cxx-qt-build` finds Qt through `$QMAKE`, which CMake sets) and links it into the executable `atlas-app-template`. `qt_add_qml_module` compiles the QML to C++ at build time, so no `.qml` file is read at run time.

## Run

```sh
QT_QPA_PLATFORM=offscreen ./build/atlas-app-template
```

`offscreen` draws no window, which suits a check on a build server. To see the window, run the binary without it in a desktop session.

## Install

`cmake --install` puts the binary in `bin`, the desktop file in `share/applications` and the notification events in `share/knotifications6`.
