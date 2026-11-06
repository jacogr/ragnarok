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

/// Read genuine process CPU; canonical primary windows include every in-process thread.
pub fn process_cpu() -> u128 {
    read(libc::CLOCK_PROCESS_CPUTIME_ID)
}

/// The existing canonical protocol retains code; historical commands keep their original lifecycle.
pub fn retained_protocol() -> bool {
    std::env::var("RAGNAROK_PVM_PERFORMANCE").as_deref() == Ok("1")
}

/// One pending restore is published only after the caller validates the complete execution result.
struct ReferenceRestore {
    sample: usize,
    before: usize,
    after: usize,
    cpu: Option<u128>,
    wall: Option<u128>,
}

/// The one current canonical producer measures complete requests, with process CPU as primary.
pub fn full_invocation() -> bool {
    std::env::var("RAGNAROK_PVM_PERFORMANCE").as_deref() == Ok("1")
}

/// Scope is explicit; historical readers never infer it from a filename or a new schema label.
pub fn invocation_scope_header() {
    if full_invocation() {
        println!("PVM_MEASURE_SCOPE,1,full-invocation-v1,consume-before-reuse-v1,process-cpu");
    }
}

/// One public interpreter instance retains lowered code while each call restores independent input.
pub struct RetainedInterpreter {
    instance: RawInstance,
    label: String,
    samples: usize,
    completed: usize,
    last_after: usize,
    pending: Option<ReferenceRestore>,
    full_invocation: bool,
}

impl RetainedInterpreter {
    /// Construction is measured once outside all calls; the actual interpreter cache must start empty.
    pub fn new(module: &Module, label: &str, samples: usize) -> Self {
        assert!(retained_protocol());
        assert!(samples == 1 || samples == 13);
        let full = full_invocation();
        let wall = (!full).then(std::time::Instant::now);
        let cpu = if full { None } else { Some(process_cpu()) };
        let instance = module.instantiate().unwrap();
        let cpu = cpu.map(|start| process_cpu() - start);
        let wall = wall.map(|start| start.elapsed().as_nanos());
        let cache = instance
            .interpreter_cache_size()
            .expect("retained reference requires the actual interpreter");
        assert_eq!(cache, 0, "new reference instance must have an empty cache");
        // Small lifecycle phases may honestly measure zero at the host clock's resolution.
        if !full {
            println!(
                "REFERENCE_INSTANCE,1,{label},{},{},{cache}",
                cpu.unwrap(),
                wall.unwrap()
            );
        }
        Self {
            instance,
            label: label.to_owned(),
            samples,
            completed: 0,
            last_after: cache,
            pending: None,
            full_invocation: full,
        }
    }

    /// Reset complete invocation memory and ABI through public APIs without discarding lowered code.
    pub fn restore(
        &mut self,
        sample: usize,
        restore: impl FnOnce(&mut RawInstance),
    ) -> &mut RawInstance {
        assert_eq!(
            sample, self.completed,
            "reference samples must be consecutive"
        );
        assert!(sample < self.samples && self.pending.is_none());
        let before = self.instance.interpreter_cache_size().unwrap();
        assert_eq!(before, self.last_after, "reference cache continuity");
        let wall = (!self.full_invocation).then(std::time::Instant::now);
        let cpu = if self.full_invocation {
            None
        } else {
            Some(process_cpu())
        };
        self.instance.reset_memory().unwrap();
        restore(&mut self.instance);
        let cpu = cpu.map(|start| process_cpu() - start);
        let wall = wall.map(|start| start.elapsed().as_nanos());
        // Observe only after memory, permissions, all registers, gas and PC have been restored.
        let after = self.instance.interpreter_cache_size().unwrap();
        assert_eq!(
            before, after,
            "invocation restore must retain interpreter code"
        );
        self.pending = Some(ReferenceRestore {
            sample,
            before,
            after,
            cpu,
            wall,
        });
        &mut self.instance
    }

    /// Emit continuity and restore scopes only after the producer's complete independent oracle passes.
    pub fn complete_sample(&mut self, sample: usize) {
        let restored = self
            .pending
            .take()
            .expect("sample must restore before execution");
        assert_eq!(sample, restored.sample);
        assert_eq!(sample, self.completed);
        let after = self.instance.interpreter_cache_size().unwrap();
        assert!(
            after > 0,
            "reference execution must populate its interpreter cache"
        );
        assert!(
            after >= restored.after,
            "retained interpreter cache must not shrink"
        );
        if self.full_invocation {
            if sample == 0 {
                println!("REFERENCE_INSTANCE,2,{},0", self.label);
            }
            println!(
                "REFERENCE_CACHE,2,{},{sample},{},{},{}",
                self.label, restored.before, restored.after, after
            );
        } else {
            println!(
                "REFERENCE_RESTORE,1,{},{sample},{},{}",
                self.label,
                restored.cpu.unwrap(),
                restored.wall.unwrap()
            );
            println!(
                "REFERENCE_CACHE,1,{},{sample},{},{},{}",
                self.label, restored.before, restored.after, after
            );
        }
        self.last_after = after;
        self.completed += 1;
    }

    /// Dispose the single retained instance once, separately from every call and restoration interval.
    pub fn finish(self) {
        assert_eq!(
            self.completed, self.samples,
            "incomplete retained reference case"
        );
        assert!(self.pending.is_none());
        let Self {
            instance,
            label,
            full_invocation,
            ..
        } = self;
        if full_invocation {
            drop(instance);
            println!("REFERENCE_INSTANCE_DROP,2,{label}");
            return;
        }
        let wall = std::time::Instant::now();
        let cpu = process_cpu();
        drop(instance);
        let cpu = process_cpu() - cpu;
        let wall = wall.elapsed().as_nanos();
        println!("REFERENCE_INSTANCE_DROP,1,{label},{cpu},{wall}");
    }
}

/// Bind requested/actual selection to positive compiled code or an interpreted module.
pub fn module_receipt(label: &str, actual: BackendKind, module: &Module, preparation: u128) {
    if !explicit() || full_invocation() {
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

/// Per-task Linux perf clocks update a running remote task; process-group clocks can lag.
enum CpuCounter {
    Process,
    #[cfg(target_os = "linux")]
    Task(std::fs::File),
}

impl CpuCounter {
    #[cfg(target_os = "linux")]
    fn task(pid: u32) -> Self {
        use std::os::fd::FromRawFd;
        // A task clock covers the entire process only while its pinned runtime has one thread.
        assert_eq!(
            std::fs::read_dir(format!("/proc/{pid}/task"))
                .unwrap()
                .count(),
            1,
            "task-clock measurement requires one runtime thread"
        );
        // PERF_ATTR_SIZE_VER0 from Linux's stable perf_event_open ABI; unused fields stay zero.
        #[repr(C)]
        #[derive(Default)]
        struct Attr {
            kind: u32,
            size: u32,
            config: u64,
            period: u64,
            sample: u64,
            format: u64,
            flags: u64,
            wakeup: u32,
            breakpoint: u32,
            address: u64,
        }
        assert_eq!(std::mem::size_of::<Attr>(), 64);
        let attr = Attr {
            kind: 1,
            size: 64,
            config: 1,
            ..Attr::default()
        };
        // PERF_TYPE_SOFTWARE / PERF_COUNT_SW_TASK_CLOCK, enabled immediately, CLOEXEC.
        let fd = unsafe {
            libc::syscall(
                libc::SYS_perf_event_open,
                &attr,
                libc::pid_t::try_from(pid).unwrap(),
                -1_i32,
                -1_i32,
                8_u64,
            )
        };
        assert!(
            fd >= 0,
            "perf task-clock unavailable: {}",
            std::io::Error::last_os_error()
        );
        Self::Task(unsafe { std::fs::File::from_raw_fd(i32::try_from(fd).unwrap()) })
    }

    fn read(&self) -> u128 {
        match self {
            Self::Process => process_cpu(),
            #[cfg(target_os = "linux")]
            Self::Task(file) => {
                use std::io::Read;
                let mut bytes = [0_u8; 8];
                let mut handle = file;
                handle.read_exact(&mut bytes).unwrap();
                u128::from(u64::from_ne_bytes(bytes))
            }
        }
    }
}

/// One invocation retains its sandbox clock; the caller keeps its instance alive through finish().
pub struct CpuTimer {
    worker: Option<CpuCounter>,
    parent: CpuCounter,
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
                CpuCounter::task(pid)
            }
            #[cfg(not(target_os = "linux"))]
            {
                panic!("separate-process CPU measurement requires Linux");
            }
        });
        let parent = {
            #[cfg(target_os = "linux")]
            {
                if explicit() || pid.is_some() {
                    CpuCounter::task(std::process::id())
                } else {
                    CpuCounter::Process
                }
            }
            #[cfg(not(target_os = "linux"))]
            {
                CpuCounter::Process
            }
        };
        let worker_start = worker.as_ref().map_or(0, CpuCounter::read);
        let parent_start = parent.read();
        Self {
            worker,
            parent,
            worker_start,
            parent_start,
        }
    }

    /// Enclose cold construction without creating a dummy instance; include every process thread.
    pub fn start_process() -> Self {
        let parent = CpuCounter::Process;
        let parent_start = parent.read();
        Self {
            parent,
            worker: None,
            parent_start,
            worker_start: 0,
        }
    }

    /// Linux compiled execution must expose its actual worker; interpretation has none.
    pub fn start(instance: &RawInstance) -> Self {
        // Legacy Compiler CLI reports wall time only; CPU calibration is an explicit protocol.
        let calibrated = explicit();
        let pid = if calibrated { instance.pid() } else { None };
        if calibrated {
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
        let parent = self.parent.read().checked_sub(self.parent_start).unwrap();
        let worker = self.worker.as_ref().map_or(0, |clock| {
            clock.read().checked_sub(self.worker_start).unwrap()
        });
        let total = parent.checked_add(worker).unwrap();
        CpuSample {
            parent,
            worker,
            total,
            worker_clock: self.worker.is_some(),
        }
    }
}

impl CpuSample {
    /// Preserve failed full primary observations after the caller's complete state/output checks.
    pub fn report_full_timing_failure(&self, label: &str, sample: usize, wall: u128) {
        if (self.total == 0 || wall == 0) && full_invocation() {
            eprintln!(
                "PVM_TIMING_FAILURE,1,full-invocation-v1,reference,{label},{sample},{},{wall}",
                self.total
            );
        }
    }
    fn validate(&self) {
        assert!(self.total > 0);
        assert!(
            !self.worker_clock || self.worker > 0,
            "validated sandbox execution CPU omitted: parent={} worker={}",
            self.parent,
            self.worker
        );
    }
    /// Emit only after the caller's complete CPU/memory/event checks succeed.
    pub fn receipt(&self, label: &str, sample: usize) {
        // Guest verification precedes this verdict, including on a zero observed delta.
        self.validate();
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
    if mode == "process-threaded" {
        // Exercise the canonical process clock with real work on a different thread and no VM.
        let cpu = CpuTimer::start_process();
        let wall = std::time::Instant::now();
        std::thread::spawn(|| {
            let start = process_cpu();
            let mut work = 1_u64;
            while process_cpu() - start < 20_000_000 {
                for _ in 0..10000 {
                    work = std::hint::black_box(work.wrapping_mul(3).wrapping_add(1));
                }
            }
            std::hint::black_box(work);
        })
        .join()
        .unwrap();
        let wall = wall.elapsed().as_nanos();
        let cpu = cpu.finish();
        assert!(cpu.total >= 20_000_000 && !cpu.worker_clock);
        println!("PROCESS_CLOCK_CONTROL,1,process-cpu,{},{}", cpu.total, wall);
        return true;
    }
    if mode == "threaded" {
        #[cfg(target_os = "linux")]
        {
            let (ready, received) = std::sync::mpsc::channel();
            let (stop, stopped) = std::sync::mpsc::channel();
            let thread = std::thread::spawn(move || {
                ready.send(()).unwrap();
                stopped.recv().unwrap();
            });
            received.recv().unwrap();
            let _counter = CpuCounter::task(std::process::id());
            stop.send(()).unwrap();
            thread.join().unwrap();
            panic!("multithreaded runtime was accepted");
        }
        #[cfg(not(target_os = "linux"))]
        panic!("task clock control requires Linux");
    }
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
        println!("DONE,{}", process_cpu() - start);
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
    let own_cpu: u128 = line.trim().strip_prefix("DONE,").unwrap().parse().unwrap();
    let measured = timer.finish();
    writeln!(input, "EXIT").unwrap();
    input.flush().unwrap();
    assert!(child.wait().unwrap().success());
    measured.validate();
    assert!(own_cpu >= 20_000_000);
    assert!(
        measured.worker.abs_diff(own_cpu) <= std::cmp::max(1_000_000, own_cpu / 20),
        "task clock differs from child's own CPU: measured={} own={}",
        measured.worker,
        own_cpu
    );
    assert!(
        measured.worker >= 20_000_000 && measured.worker > measured.parent * 2,
        "child CPU control parent={} worker={}",
        measured.parent,
        measured.worker
    );
    println!(
        "REFERENCE_CLOCK_CONTROL,{},{},{},{}",
        measured.parent, measured.worker, measured.total, own_cpu
    );
    true
}

/// A real outer owner window includes oracle/driver time and is never substituted for a call.
pub struct OwnerWindow {
    cpu: u128,
    wall: std::time::Instant,
}
impl OwnerWindow {
    pub fn start() -> Self {
        Self {
            cpu: process_cpu(),
            wall: std::time::Instant::now(),
        }
    }
    pub fn finish(self, label: &str) {
        let cpu = process_cpu() - self.cpu;
        let wall = self.wall.elapsed().as_nanos();
        println!("PVM_OWNER_WINDOW,1,{label},{cpu},{wall},includes-driver-oracles");
    }
}
