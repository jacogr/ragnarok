// Copyright (c) 2026 Ragnarök contributors
// SPDX-License-Identifier: MIT OR Apache-2.0
//! Explicit reference backend receipts and complete parent/worker CPU accounting.
use polkavm::{BackendKind, Module, RawInstance};

/// Existing reference commands keep their interpreted default unless explicitly selected.
pub fn selected(default: BackendKind) -> BackendKind {
    match std::env::var("RAGNAROK_PVM_REFERENCE_BACKEND").as_deref() {
        Err(std::env::VarError::NotPresent) => default,
        Err(error) => panic!("invalid reference backend: {error}"),
        Ok("interpreter") => BackendKind::Interpreter,
        Ok("compiler") => BackendKind::Compiler,
        _ => panic!("unknown reference backend"),
    }
}

/// Additional evidence belongs only to the explicit backend comparison protocol.
pub fn explicit() -> bool {
    std::env::var_os("RAGNAROK_PVM_REFERENCE_BACKEND").is_some()
}

/// Stable names describe the actual pinned engine, never a substituted backend.
pub fn name(backend: BackendKind) -> &'static str {
    match backend {
        BackendKind::Interpreter => "interpreter",
        BackendKind::Compiler => "compiler",
    }
}

/// Fail closed on an unavailable or malformed OS CPU clock.
fn read(clock: libc::clockid_t) -> u128 {
    let mut value = libc::timespec {
        tv_sec: 0,
        tv_nsec: 0,
    };
    assert_eq!(
        unsafe { libc::clock_gettime(clock, &mut value) },
        0,
        "CPU clock: {}",
        std::io::Error::last_os_error()
    );
    assert!(value.tv_sec >= 0 && (0..1_000_000_000).contains(&value.tv_nsec));
    (value.tv_sec as u128)
        .checked_mul(1_000_000_000)
        .unwrap()
        .checked_add(value.tv_nsec as u128)
        .unwrap()
}

/// Module compilation occurs in the parent; instance/restore work is reported separately.
pub fn process_cpu() -> u128 {
    read(libc::CLOCK_PROCESS_CPUTIME_ID)
}

/// Bind requested/actual selection to positive compiled code or an interpreted module.
pub fn module_receipt(label: &str, actual: BackendKind, module: &Module, preparation: u128) {
    if !explicit() {
        return;
    }
    assert_eq!(selected(actual), actual);
    let bytes = module.machine_code().map_or(0, |code| code.len());
    assert_eq!(bytes > 0, actual == BackendKind::Compiler);
    assert!(preparation > 0);
    println!(
        "REFERENCE_MODULE,{label},{},{},{bytes},{preparation}",
        name(selected(actual)),
        name(actual)
    );
}

/// One invocation retains its sandbox clock; the caller keeps its instance alive through finish().
pub struct CpuTimer {
    worker: Option<libc::clockid_t>,
    worker_start: u128,
    parent_start: u128,
}

/// Parent and sandbox CPU remain visible independently of elapsed wall time.
pub struct CpuSample {
    pub parent: u128,
    pub worker: u128,
    pub total: u128,
    worker_clock: bool,
}

impl CpuTimer {
    /// Resolve a separate process clock before the parent execution interval starts.
    fn for_pid(pid: Option<u32>) -> Self {
        let worker = pid.map(|pid| {
            assert_ne!(
                pid,
                std::process::id(),
                "worker must not double count parent CPU"
            );
            #[cfg(target_os = "linux")]
            {
                let pid = i32::try_from(pid).unwrap();
                let mut clock = 0;
                let error = unsafe { libc::clock_getcpuclockid(pid, &mut clock) };
                assert_eq!(
                    error,
                    0,
                    "sandbox CPU clock: {}",
                    std::io::Error::from_raw_os_error(error)
                );
                clock
            }
            #[cfg(not(target_os = "linux"))]
            {
                panic!("separate-process CPU measurement requires Linux");
            }
        });
        let worker_start = worker.map_or(0, read);
        let parent_start = process_cpu();
        Self {
            worker,
            worker_start,
            parent_start,
        }
    }

    /// Linux compiled execution must expose its actual worker; interpretation has none.
    pub fn start(instance: &RawInstance) -> Self {
        let pid = instance.pid();
        if explicit() {
            match selected(BackendKind::Interpreter) {
                BackendKind::Interpreter => assert!(pid.is_none()),
                BackendKind::Compiler => {
                    if cfg!(target_os = "linux") {
                        assert!(pid.is_some(), "missing Linux compiler worker");
                    }
                }
            }
        }
        Self::for_pid(pid)
    }

    /// Read parent first and worker last so worker-clock queries stay outside parent timing.
    pub fn finish(self) -> CpuSample {
        let parent = process_cpu().checked_sub(self.parent_start).unwrap();
        let worker = self.worker.map_or(0, |clock| {
            read(clock).checked_sub(self.worker_start).unwrap()
        });
        let total = parent.checked_add(worker).unwrap();
        assert!(total > 0);
        if self.worker.is_some() {
            assert!(worker > 0, "sandbox execution CPU omitted");
        }
        CpuSample {
            parent,
            worker,
            total,
            worker_clock: self.worker.is_some(),
        }
    }
}

impl CpuSample {
    /// Emit only after the caller's complete CPU/memory/event checks succeed.
    pub fn receipt(&self, label: &str, sample: usize) {
        if explicit() {
            println!(
                "REFERENCE_CPU,{label},{sample},{},{},{},{}",
                self.parent,
                self.worker,
                self.total,
                u8::from(self.worker_clock)
            );
        }
    }
}

/// A real child CPU test catches the parent-only measurement mistake before benchmarks.
pub fn clock_control() -> bool {
    use std::io::{BufRead, Write};
    let mode = match std::env::var("RAGNAROK_PVM_CLOCK_CONTROL") {
        Err(_) => return false,
        Ok(mode) => mode,
    };
    if mode == "child" {
        println!("READY");
        std::io::stdout().flush().unwrap();
        let mut command = String::new();
        std::io::stdin().read_line(&mut command).unwrap();
        assert_eq!(command.trim(), "RUN");
        let start = process_cpu();
        let mut work = 1_u64;
        while process_cpu() - start < 20_000_000 {
            for _ in 0..10000 {
                work = std::hint::black_box(work.wrapping_mul(3).wrapping_add(1));
            }
        }
        std::hint::black_box(work);
        println!("DONE");
        std::io::stdout().flush().unwrap();
        command.clear();
        std::io::stdin().read_line(&mut command).unwrap();
        assert_eq!(command.trim(), "EXIT");
        return true;
    }
    assert_eq!(mode, "parent");
    assert!(cfg!(target_os = "linux"));
    let mut child = std::process::Command::new(std::env::current_exe().unwrap())
        .env("RAGNAROK_PVM_CLOCK_CONTROL", "child")
        .stdin(std::process::Stdio::piped())
        .stdout(std::process::Stdio::piped())
        .spawn()
        .unwrap();
    let mut input = child.stdin.take().unwrap();
    let mut output = std::io::BufReader::new(child.stdout.take().unwrap());
    let mut line = String::new();
    output.read_line(&mut line).unwrap();
    assert_eq!(line.trim(), "READY");
    let timer = CpuTimer::for_pid(Some(child.id()));
    writeln!(input, "RUN").unwrap();
    input.flush().unwrap();
    line.clear();
    output.read_line(&mut line).unwrap();
    assert_eq!(line.trim(), "DONE");
    let measured = timer.finish();
    writeln!(input, "EXIT").unwrap();
    input.flush().unwrap();
    assert!(child.wait().unwrap().success());
    assert!(
        measured.worker >= 20_000_000 && measured.worker > measured.parent * 2,
        "child CPU control parent={} worker={}",
        measured.parent,
        measured.worker
    );
    println!(
        "REFERENCE_CLOCK_CONTROL,{},{},{}",
        measured.parent, measured.worker, measured.total
    );
    true
}
