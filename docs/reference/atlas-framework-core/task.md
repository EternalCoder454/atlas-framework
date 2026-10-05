---
title: task
summary: One tokio runtime thread for the app, and spawn_ui, which runs a future with a timeout and cancellation and posts the result back to the UI thread.
order: 25
---

The `task` module is behind the cargo feature `task` (off by default: a light app pays for no async runtime). Enable it with `atlas-framework-core = { ..., features = ["task"] }`. It pulls in `tokio` (features `rt`, `time`, `sync`, `macros`), which zbus already brings for apps that use polkit.

The module is Qt-free: the crate has no Qt dependency. `spawn_ui` takes a closure that posts a job to the UI thread; with cxx-qt that is `CxxQtThread::queue`.

## Example

```rust,ignore
use atlas_framework_core::task::{Outcome, spawn_ui};
use std::{pin::Pin, time::Duration};

// inside a cxx-qt QObject's method; `qt = self.qt_thread()`
let handle = spawn_ui(
    move |job| qt.queue(job),
    Duration::from_secs(10),
    async { fetch_something().await },
    |obj: Pin<&mut MyObject>, outcome| match outcome {
        Outcome::Done(v) => obj.show(v),
        Outcome::TimedOut => obj.show_error("took too long"),
        Outcome::Cancelled | Outcome::Panicked => obj.show_error("stopped"),
    },
)?;
// later: handle.cancel();
```

## Behaviour

- One runtime for the app: a thread named `atlas-tasks` running a current-thread tokio runtime with timers on (no I/O driver: tokio's sockets do not work on it, so use your own runtime for those). It starts on the first call.
- The runtime has one thread: **never block in a future** (no `std::thread::sleep`, blocking file or network calls, or long loops without an await), or every other task waits. Use `runtime()?.spawn_blocking(...)` (the blocking pool is on, threads start on demand) or a thread of your own.
- `spawn_ui` runs the future for at most `timeout`. On timeout the future is dropped.
- `on_done` runs once on the UI thread, for every outcome including `Cancelled`, so a busy indicator can always be reset.
- If `post` fails (for `queue`: the QObject is gone) the result is dropped quietly.
- Dropping a `TaskHandle` does not cancel the task.
- A panic in the future is logged and reported as `Outcome::Panicked`; the runtime goes on. A panic in `post` or `on_done` is caught and logged too. All of this needs `panic = "unwind"` (the default); with `"abort"` the process ends.
- Errors: `spawn_ui` and `runtime` fail only if the runtime thread cannot start (they try again on the next call). If the runtime thread has ended (it should not), the next call logs it and starts a new one; tasks of the old one are lost.
- `TaskHandle::is_cancelled()` is true once `cancel` has been called, even if the task had already finished or timed out first: the outcome tells how it ended.

## Items

| Name | Signature | Description |
|---|---|---|
| `spawn_ui` | `pub fn spawn_ui<O, T, E, P, F, D>(post: P, timeout: Duration, future: F, on_done: D) -> io::Result<TaskHandle>` | `P: FnOnce(UiJob<O>) -> Result<(), E> + Send`, `F: Future<Output = T> + Send`, `D: FnOnce(Pin<&mut O>, Outcome<T>) + Send`; `T: Send`, all `'static` |
| `runtime` | `pub fn runtime() -> io::Result<tokio::runtime::Handle>` | The app's runtime handle, starting it if needed |
| `Outcome<T>` | `pub enum` | `Done(T)`, `TimedOut`, `Cancelled`, `Panicked` (`Debug, Clone, PartialEq, Eq`) |
| `UiJob<O>` | `pub type` | `Box<dyn for<'a> FnOnce(Pin<&'a mut O>) + Send + 'static>` |
| `TaskHandle` | `pub struct` | `Debug, Clone`. `cancel(&self)` stops the task (callable more than once, from any thread); `is_cancelled(&self) -> bool` |
