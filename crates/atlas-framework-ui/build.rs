use cxx_qt_build::CxxQtBuilder;

fn main() {
    // KF6 ships no pkg-config files; Fedora puts its headers here.
    println!("cargo::rerun-if-env-changed=ATLAS_KF6_INCLUDEDIR");
    let kf6 = std::env::var("ATLAS_KF6_INCLUDEDIR").unwrap_or_else(|_| "/usr/include/KF6".into());
    for lib in ["KF6DBusAddons", "KF6WindowSystem"] {
        println!("cargo::rustc-link-lib=dylib={lib}");
    }
    let builder = CxxQtBuilder::new()
        .crate_include_root(Some("include".into()))
        .qt_module("Gui")
        .qt_module("Widgets")
        .qt_module("Qml")
        .qt_module("Quick")
        .qt_module("QuickControls2")
        .qt_module("DBus")
        .cpp_file("cpp/atlasapp.cpp");
    // SAFETY: only adds include directories.
    let builder = unsafe {
        builder.cc_builder(|cc| {
            cc.include(concat!(env!("CARGO_MANIFEST_DIR"), "/include"));
            cc.include(format!("{kf6}/KDBusAddons"));
            cc.include(format!("{kf6}/KWindowSystem"));
        })
    };
    builder.build();
}
