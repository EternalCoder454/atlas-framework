//! Background work for a UI app: one tokio runtime thread for the whole app,
//! and [`spawn_ui`], which runs a future there with a timeout and a way to
//! cancel it, then hands the result back on the UI thread.
//!
//! This module is Qt-free on purpose (the crate has no Qt dependency). The
//! hand-over is a closure that posts a job to the UI thread; with cxx-qt that
//! is `CxxQtThread::queue`:
//!
//! ```ignore
//! let qt = self.qt_thread();
//! let handle = spawn_ui(
//!     move |job| qt.queue(job),
//!     Duration::from_secs(10),
//!     async { fetch().await },
//!     |obj: Pin<&mut MyObject>, outcome| obj.show(outcome),
//! )?;
//! ```

use std::future::Future;
use std::io;
use std::panic::{AssertUnwindSafe, catch_unwind};
use std::pin::Pin;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex, mpsc};
use std::thread::JoinHandle;
use std::time::Duration;

use tokio::runtime::Handle;
use tokio::sync::Notify;

// Panics in `post` and `on_done` are caught and logged, like those in the
// future, only with `panic = "unwind"` (the default); with "abort" the
// process ends.

/// How a task ended.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Outcome<T> {
    /// The future finished with this value.
    Done(T),
    /// The future did not finish within the timeout; it was dropped.
    TimedOut,
    /// [`TaskHandle::cancel`] was called first; the future was dropped.
    Cancelled,
    /// The future panicked (the panic is logged, the runtime keeps going).
    Panicked,
}

/// A job for the UI thread: it gets the object `on_done` was written for.
pub type UiJob<O> = Box<dyn for<'a> FnOnce(Pin<&'a mut O>) + Send + 'static>;

/// Cancels a task started by [`spawn_ui`]. Cloning shares the task. Dropping
/// the handle does not cancel: the task runs on and delivers its result.
#[derive(Debug, Clone)]
pub struct TaskHandle {
    inner: Arc<Shared>,
}

#[derive(Debug, Default)]
struct Shared {
    cancelled: AtomicBool,
    wake: Notify,
}

impl TaskHandle {
    /// Stops the task (its future is dropped at the next await) and delivers
    /// `Outcome::Cancelled`, unless the task had already finished. Safe to
    /// call more than once, from any thread.
    pub fn cancel(&self) {
        self.inner.cancelled.store(true, Ordering::SeqCst);
        // notify_one keeps a permit, so a cancel before the task first runs
        // is not lost.
        self.inner.wake.notify_one();
    }

    /// Whether [`cancel`](Self::cancel) has been called. It does not mean the
    /// task ended as `Cancelled`: a task that finished first (or timed out)
    /// keeps its own outcome.
    pub fn is_cancelled(&self) -> bool {
        self.inner.cancelled.load(Ordering::SeqCst)
    }
}

struct Running {
    handle: Handle,
    thread: JoinHandle<()>,
}

static RUNTIME: Mutex<Option<Running>> = Mutex::new(None);

fn start() -> io::Result<Running> {
    let (tx, rx) = mpsc::channel();
    let thread = std::thread::Builder::new()
        .name("atlas-tasks".into())
        .spawn(move || {
            match tokio::runtime::Builder::new_current_thread()
                .enable_time()
                .build()
            {
                Ok(rt) => {
                    let _ = tx.send(Ok(rt.handle().clone()));
                    // Runs every spawned task; the app never stops it.
                    rt.block_on(std::future::pending::<()>());
                }
                Err(e) => {
                    let _ = tx.send(Err(e));
                }
            }
        })?;
    let handle = rx
        .recv()
        .map_err(|_| io::Error::other("the task thread ended at start"))??;
    Ok(Running { handle, thread })
}

/// The handle in `slot` if its thread still runs; otherwise starts the
/// runtime again (once per call) and stores that.
fn live(
    slot: &mut Option<Running>,
    start: impl FnOnce() -> io::Result<Running>,
) -> io::Result<Handle> {
    if let Some(r) = slot.as_ref()
        && !r.thread.is_finished()
    {
        return Ok(r.handle.clone());
    }
    if slot.take().is_some() {
        log::error!("the atlas-tasks thread ended; starting it again");
    }
    let r = start()?;
    let h = r.handle.clone();
    *slot = Some(r);
    Ok(h)
}

/// The app's one runtime: a thread named `atlas-tasks` running a
/// current-thread tokio runtime (timers on, no I/O driver), started on the
/// first call. A failed start (no threads left) is an error here and is
/// tried again on the next call; if the thread has ended (it should not),
/// the next call logs it and starts a new one. Tasks of the old one are lost.
pub fn runtime() -> io::Result<Handle> {
    live(
        &mut RUNTIME.lock().unwrap_or_else(|e| e.into_inner()),
        start,
    )
}

/// Runs `future` on the app's runtime for at most `timeout`, then posts
/// `on_done` to the UI thread with the [`Outcome`].
///
/// - `post` hands a job to the UI thread (`move |job| qt.queue(job)` for a
///   cxx-qt `CxxQtThread`). Its error, normally "the QObject is gone", is
///   ignored: nothing is left to show the result to.
/// - `on_done` runs on the UI thread, once, for every outcome including
///   `Cancelled`, so a busy indicator can always be reset.
/// - Fails only if the runtime thread cannot start.
pub fn spawn_ui<O, T, E, P, F, D>(
    post: P,
    timeout: Duration,
    future: F,
    on_done: D,
) -> io::Result<TaskHandle>
where
    O: 'static,
    T: Send + 'static,
    P: FnOnce(UiJob<O>) -> Result<(), E> + Send + 'static,
    F: Future<Output = T> + Send + 'static,
    D: for<'a> FnOnce(Pin<&'a mut O>, Outcome<T>) + Send + 'static,
{
    let rt = runtime()?;
    let shared = Arc::new(Shared::default());
    let handle = TaskHandle {
        inner: shared.clone(),
    };
    let work = rt.spawn(future);
    let abort = work.abort_handle();
    rt.spawn(async move {
        let outcome = tokio::select! {
            biased;
            _ = shared.wake.notified() => {
                abort.abort();
                Outcome::Cancelled
            }
            r = tokio::time::timeout(timeout, work) => match r {
                Ok(Ok(v)) => Outcome::Done(v),
                Ok(Err(e)) if e.is_cancelled() => Outcome::Cancelled,
                Ok(Err(_)) => {
                    log::error!("a background task panicked");
                    Outcome::Panicked
                }
                Err(_) => {
                    abort.abort();
                    Outcome::TimedOut
                }
            },
        };
        let job: UiJob<O> = Box::new(move |obj| {
            if catch_unwind(AssertUnwindSafe(|| on_done(obj, outcome))).is_err() {
                log::error!("a background task's on_done panicked");
            }
        });
        // Gone QObject: nothing to tell.
        match catch_unwind(AssertUnwindSafe(|| post(job))) {
            Ok(_) => {}
            Err(_) => log::error!("a background task's post closure panicked"),
        }
    });
    Ok(handle)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::AtomicBool;
    use std::sync::mpsc::{Receiver, Sender, channel};

    struct Ui(u32);
    type FakeUi = (Sender<Option<UiJob<Ui>>>, Receiver<(u32, String)>);

    /// A fake UI thread: jobs run on one thread that owns the `Ui`.
    fn fake_ui() -> FakeUi {
        let (jtx, jrx) = channel::<Option<UiJob<Ui>>>();
        let (otx, orx) = channel();
        std::thread::spawn(move || {
            let mut ui = Ui(0);
            while let Ok(Some(job)) = jrx.recv() {
                ui.0 += 1;
                job(Pin::new(&mut ui));
                let _ = otx.send((ui.0, std::thread::current().name().unwrap_or("").into()));
            }
        });
        (jtx, orx)
    }

    fn run(
        timeout: Duration,
        fut: impl Future<Output = u32> + Send + 'static,
    ) -> (TaskHandle, Receiver<Outcome<u32>>) {
        let (jtx, _o) = fake_ui();
        let (rtx, rrx) = channel();
        let h = spawn_ui(
            move |job| jtx.send(Some(job)),
            timeout,
            fut,
            move |_ui: Pin<&mut Ui>, o| {
                let _ = rtx.send(o);
            },
        )
        .unwrap();
        (h, rrx)
    }

    const WAIT: Duration = Duration::from_secs(5);

    #[test]
    fn result_is_delivered_on_the_ui_thread() {
        let (jtx, orx) = fake_ui();
        let (rtx, rrx) = channel();
        spawn_ui(
            move |job| jtx.send(Some(job)),
            Duration::from_secs(5),
            async { 7u32 },
            move |ui: Pin<&mut Ui>, o| {
                let _ = rtx.send((ui.0, o));
            },
        )
        .unwrap();
        assert_eq!(rrx.recv_timeout(WAIT).unwrap(), (1, Outcome::Done(7)));
        orx.recv_timeout(WAIT).unwrap();
    }

    #[test]
    fn times_out() {
        let (_h, r) = run(Duration::from_millis(50), async {
            tokio::time::sleep(Duration::from_secs(60)).await;
            1
        });
        assert_eq!(r.recv_timeout(WAIT).unwrap(), Outcome::TimedOut);
    }

    #[test]
    fn cancels_and_drops_the_future() {
        struct Flag(Sender<()>);
        impl Drop for Flag {
            fn drop(&mut self) {
                let _ = self.0.send(());
            }
        }
        let (dtx, drx) = channel();
        let flag = Flag(dtx);
        let (h, r) = run(Duration::from_secs(60), async move {
            let _flag = flag;
            tokio::time::sleep(Duration::from_secs(60)).await;
            1
        });
        h.cancel();
        h.cancel();
        assert!(h.is_cancelled());
        assert_eq!(r.recv_timeout(WAIT).unwrap(), Outcome::Cancelled);
        drx.recv_timeout(WAIT).unwrap(); // the future was dropped
    }

    #[test]
    fn a_gone_ui_is_ignored_and_a_panic_is_reported() {
        // post fails: on_done never runs, and the runtime still works after.
        let ran = Arc::new(AtomicBool::new(false));
        let ran2 = ran.clone();
        spawn_ui(
            |_job: UiJob<Ui>| Err::<(), _>("gone"),
            Duration::from_secs(5),
            async { 1 },
            move |_: Pin<&mut Ui>, _| ran2.store(true, Ordering::SeqCst),
        )
        .unwrap();
        let (_h, r) = run(Duration::from_secs(5), async { panic!("boom") });
        assert_eq!(r.recv_timeout(WAIT).unwrap(), Outcome::Panicked);
        let (_h, r) = run(Duration::from_secs(5), async { 2 });
        assert_eq!(r.recv_timeout(WAIT).unwrap(), Outcome::Done(2));
        assert!(!ran.load(Ordering::SeqCst));
    }

    #[test]
    fn a_dead_runtime_thread_is_replaced() {
        let dead = std::thread::spawn(|| {});
        let (tx, rx) = mpsc::channel();
        let keep = std::thread::spawn(move || {
            let rt = tokio::runtime::Builder::new_current_thread()
                .build()
                .unwrap();
            tx.send(rt.handle().clone()).unwrap();
            std::thread::sleep(Duration::from_millis(300));
        });
        let old = rx.recv().unwrap();
        while !dead.is_finished() {
            std::thread::yield_now();
        }
        let mut slot = Some(Running {
            handle: old,
            thread: dead,
        });
        let mut started = 0;
        live(&mut slot, || {
            started += 1;
            start()
        })
        .unwrap();
        assert_eq!(started, 1);
        // a live one is kept
        live(&mut slot, || panic!("must not start")).unwrap();
        let _ = keep.join();
    }

    #[test]
    fn a_panicking_on_done_or_post_is_contained() {
        let (jtx, orx) = fake_ui();
        spawn_ui(
            move |job| jtx.send(Some(job)),
            Duration::from_secs(5),
            async { 1 },
            |_: Pin<&mut Ui>, _| panic!("on_done"),
        )
        .unwrap();
        // the fake UI thread survives and reports it ran the job
        orx.recv_timeout(WAIT).unwrap();
        spawn_ui(
            |_job: UiJob<Ui>| -> Result<(), ()> { panic!("post") },
            Duration::from_secs(5),
            async { 1 },
            |_: Pin<&mut Ui>, _| {},
        )
        .unwrap();
        let (_h, r) = run(Duration::from_secs(5), async { 3 });
        assert_eq!(r.recv_timeout(WAIT).unwrap(), Outcome::Done(3));
    }

    #[test]
    fn one_named_runtime_thread() {
        let (jtx, _o) = fake_ui();
        let (rtx, rrx) = channel();
        for _ in 0..2 {
            let rtx = rtx.clone();
            spawn_ui(
                {
                    let jtx = jtx.clone();
                    move |job| jtx.send(Some(job))
                },
                Duration::from_secs(5),
                async { std::thread::current().name().map(String::from) },
                move |_: Pin<&mut Ui>, o| {
                    let _ = rtx.send(o);
                },
            )
            .unwrap();
        }
        for _ in 0..2 {
            assert_eq!(
                rrx.recv_timeout(WAIT).unwrap(),
                Outcome::Done(Some("atlas-tasks".to_string()))
            );
        }
    }
}
