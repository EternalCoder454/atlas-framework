//! One example QObject. Copy it, rename it and add your own properties and
//! invokables. Never block the GUI thread: run slow work on a thread and post
//! the result back with `qt_thread().queue(..)`.

#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }

    extern "RustQt" {
        #[qobject]
        #[qproperty(QString, status)]
        #[qproperty(bool, busy)]
        #[namespace = "telamon_app"]
        type Backend = super::BackendRust;

        /// Example invokable: does some work on a worker thread.
        #[qinvokable]
        fn refresh(self: Pin<&mut Backend>);

        /// Example invokable: sends one desktop notification.
        #[qinvokable]
        #[cxx_name = "sendNotification"]
        fn send_notification(self: Pin<&mut Backend>);
    }

    // Lets worker threads post closures back to the Qt thread.
    impl cxx_qt::Threading for Backend {}

    // Lets Rust create the object (see `telamon_backend_new` in lib.rs).
    #[namespace = "rust::cxxqtlib1"]
    unsafe extern "C++" {
        include!("cxx-qt-lib/common.h");

        #[cxx_name = "make_unique"]
        fn backend_make_unique() -> UniquePtr<Backend>;
    }
}

use core::pin::Pin;
use cxx_qt::Threading;
use cxx_qt_lib::QString;
use telamon_framework_system::notify::{Note, Notifier, escape};

/// Held by a worker thread: when it is dropped, normally or by a panic
/// unwinding, `busy` goes back to false on the Qt thread, so the buttons never
/// stay disabled. A panic is logged.
struct BusyGuard(cxx_qt::CxxQtThread<qobject::Backend>);

impl Drop for BusyGuard {
    fn drop(&mut self) {
        let panicked = std::thread::panicking();
        if panicked {
            log::error!("the worker thread panicked");
        }
        let _ = self.0.queue(move |mut obj| {
            if panicked {
                obj.as_mut().set_status(QString::from("Failed (see the log)"));
            }
            obj.as_mut().set_busy(false);
        });
    }
}

pub struct BackendRust {
    status: QString,
    busy: bool,
}

impl Default for BackendRust {
    fn default() -> Self {
        Self {
            status: QString::from("Ready"),
            busy: false,
        }
    }
}

impl qobject::Backend {
    pub fn refresh(mut self: Pin<&mut Self>) {
        if *self.busy() {
            return;
        }
        self.as_mut().set_busy(true);
        self.as_mut().set_status(QString::from("Working…"));
        let qt = self.qt_thread();
        std::thread::spawn(move || {
            let _guard = BusyGuard(qt.clone());
            // Replace with the app's own work (telamon_framework_* crates, ...).
            let text = format!("Template {}", env!("CARGO_PKG_VERSION"));
            let _ = qt.queue(move |mut obj| {
                obj.as_mut().set_status(QString::from(text.as_str()));
            });
        });
    }
}

impl qobject::Backend {
    /// A notification, the Telamon OS way: only because the user pressed a button
    /// (a real app notifies only when the user can act on it), a popup with no
    /// sound, from the user's session, not persistent. The `demoAction` event
    /// is declared in data/telamon-apptemplate.notifyrc, which Plasma reads for
    /// the app's name, icon and settings. See `telamon_framework_system::notify`.
    pub fn send_notification(mut self: Pin<&mut Self>) {
        if *self.busy() {
            return;
        }
        self.as_mut().set_busy(true);
        let qt = self.qt_thread();
        // D-Bus can take a while (no server, a slow one): never on the GUI thread.
        std::thread::spawn(move || {
            let _guard = BusyGuard(qt.clone());
            let notifier = Notifier::new(telamon_framework_ui::app_info());
            let note = Note::new(
                "demoAction",
                "Hello from Telamon App",
                // Anything that came from outside goes through `escape`.
                escape(&format!("Template {}", env!("CARGO_PKG_VERSION"))),
            );
            let result = notifier.send_blocking(&note);
            if let Err(e) = &result {
                log::warn!("cannot send the notification: {e}");
            }
            let text = match result {
                Ok(()) => "Notification sent".to_string(),
                Err(_) => "Could not send the notification".to_string(),
            };
            let _ = qt.queue(move |mut obj| {
                obj.as_mut().set_status(QString::from(text.as_str()));
            });
        });
    }
}
