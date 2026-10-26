// Copyright (c) 2026 Ragnarök contributors
// SPDX-License-Identifier: MIT OR Apache-2.0
//! Opaque resident guest executor. Nim owns unsigned gas, protocol hosts and publication.
//! Every C entry catches Rust unwinds; no pointer or slice is retained from caller storage.
use polkavm::{
    BackendKind, Config, Engine, InterruptKind, MemoryProtection, Module, ModuleConfig,
    ProgramBlob, ProgramCounter, ProgramParts, RawInstance, Reg, SandboxKind,
};
use polkavm_common::program::InstructionSetKind;
use std::panic::{catch_unwind, AssertUnwindSafe};

/// Exclusive invocation owner; module and engine lifetimes are retained by the public instance.
pub struct Rpvm {
    instance: RawInstance,
    ready: bool,
    host_continuation: bool,
}

/// Fixed-width output copied only after one complete instruction finishes or stops.
#[repr(C)]
pub struct RpvmEvent {
    registers: [u64; 13],
    kind: u32,
    pc: u32,
    detail: u32,
}

/// Translate panic into a local ABI error; do not let an unwind enter Nim.
fn boundary(f: impl FnOnce() -> Result<(), i32>) -> i32 {
    match catch_unwind(AssertUnwindSafe(f)) {
        Ok(Ok(())) => 0,
        Ok(Err(e)) => e,
        Err(_) => 5,
    }
}

/// Create exactly the requested engine without environment defaults or fallback.
#[no_mangle]
pub unsafe extern "C" fn rpvm_create(
    backend: u32,
    code: *const u8,
    length: usize,
    output: *mut *mut Rpvm,
) -> i32 {
    boundary(|| {
        if output.is_null() {
            return Err(1);
        }
        *output = std::ptr::null_mut();
        if code.is_null() || length == 0 || length > 128 * 1024 * 1024 {
            return Err(1);
        }
        let selected = match backend {
            1 => BackendKind::Interpreter,
            2 => BackendKind::Compiler,
            _ => return Err(1),
        };
        if !selected.is_supported() {
            return Err(2);
        }
        let mut config = Config::default();
        config.set_backend(Some(selected));
        config.set_allow_dynamic_paging(true);
        // Pin the supported native sandbox; never use an upstream auto/environment setting.
        if selected == BackendKind::Compiler {
            if !SandboxKind::Linux.is_supported() {
                return Err(2);
            }
            config.set_sandbox(Some(SandboxKind::Linux));
        }
        let engine = Engine::new(&config).map_err(|_| 2)?;
        if engine.backend() != selected {
            return Err(2);
        }
        let mut parts = ProgramParts::empty(InstructionSetKind::JamV1);
        parts.code_and_jump_table = std::slice::from_raw_parts(code, length).to_vec().into();
        let blob = ProgramBlob::from_parts(parts).map_err(|_| 1)?;
        let mut profile = ModuleConfig::new();
        profile.set_page_size(4096);
        profile.set_dynamic_paging(true);
        profile.set_step_tracing(true);
        // Unsigned protocol gas and prepaid reentry are accounted for in Nim, never narrowed.
        profile.set_gas_metering(None);
        let module = Module::from_blob(&engine, &profile, blob).map_err(|_| 3)?;
        if selected == BackendKind::Compiler && module.machine_code().is_none() {
            return Err(2);
        }
        let mut instance = module.instantiate().map_err(|_| 3)?;
        instance.set_gas(0);
        *output = Box::into_raw(Box::new(Rpvm {
            instance,
            ready: false,
            host_continuation: false,
        }));
        Ok(())
    })
}

/// Release the sole owning handle after all calls have returned; null is harmless.
#[no_mangle]
pub unsafe extern "C" fn rpvm_destroy(handle: *mut Rpvm) -> i32 {
    boundary(|| {
        if !handle.is_null() {
            drop(Box::from_raw(handle));
        }
        Ok(())
    })
}

/// Prime tracing at the exact instruction before executing it; reject unrepresentable reentry.
#[no_mangle]
pub unsafe extern "C" fn rpvm_prepare(
    handle: *mut Rpvm,
    pc: u32,
    registers: *const u64,
    count: usize,
) -> i32 {
    boundary(|| {
        if handle.is_null() || registers.is_null() || count != 13 {
            return Err(1);
        }
        let owner = &mut *handle;
        let resident_continuation = owner.host_continuation
            && owner.instance.next_program_counter() == Some(ProgramCounter(pc));
        owner.ready = false;
        owner.host_continuation = false;
        for (index, value) in std::slice::from_raw_parts(registers, count)
            .iter()
            .enumerate()
        {
            owner
                .instance
                .set_reg(Reg::from_raw(index as u32).ok_or(1)?, *value);
        }
        if !resident_continuation {
            // A checked ordinary host reply uses the instance's existing exact continuation.
            // Fresh/arbitrary entries still require the public explicit-PC capability.
            owner.instance.set_next_program_counter(ProgramCounter(pc));
        }
        match owner.instance.run().map_err(|_| 3)? {
            InterruptKind::Step if owner.instance.program_counter() == Some(ProgramCounter(pc)) => {
                owner.ready = true;
                Ok(())
            }
            _ => Err(4), // No guest instruction ran; arbitrary entry is a capability requirement.
        }
    })
}

/// Execute from one traced instruction to the next trace or a genuine guest suspension.
#[no_mangle]
pub unsafe extern "C" fn rpvm_step(handle: *mut Rpvm, output: *mut RpvmEvent) -> i32 {
    boundary(|| {
        if handle.is_null() || output.is_null() {
            return Err(1);
        }
        let owner = &mut *handle;
        if !owner.ready {
            return Err(1);
        }
        let causing = owner.instance.program_counter().ok_or(3)?.0;
        let event = owner.instance.run().map_err(|_| 3)?;
        let (kind, pc, detail) = match event {
            InterruptKind::Step => (0, owner.instance.program_counter().ok_or(3)?.0, 0),
            InterruptKind::Trap => (1, causing, 0),
            InterruptKind::Finished => (2, causing, 0),
            InterruptKind::Segfault(fault) if fault.page_size == 4096 => {
                (3, causing, fault.page_address)
            }
            InterruptKind::Ecalli(number) => (4, causing, number),
            _ => return Err(3), // Upstream gas is disabled; unexpected events are local failures.
        };
        owner.ready = kind == 0;
        owner.host_continuation = kind == 4;
        let mut registers = [0; 13];
        for (index, value) in registers.iter_mut().enumerate() {
            *value = owner.instance.reg(Reg::from_raw(index as u32).ok_or(3)?);
        }
        *output = RpvmEvent {
            registers,
            kind,
            pc,
            detail,
        };
        Ok(())
    })
}

/// Replace or remove one page after checked Nim snapshot comparison; read-only data is staged writable.
#[no_mangle]
pub unsafe extern "C" fn rpvm_page(
    handle: *mut Rpvm,
    address: u32,
    access: u32,
    data: *const u8,
    length: usize,
) -> i32 {
    boundary(|| {
        if handle.is_null() || address % 4096 != 0 || access > 2 {
            return Err(1);
        }
        let instance = &mut (*handle).instance;
        if access == 0 {
            if length != 0 {
                return Err(1);
            }
            instance.free_pages(address, 4096).map_err(|_| 3)?;
        } else {
            if data.is_null() || length != 4096 {
                return Err(1);
            }
            instance
                .zero_memory_with_memory_protection(address, 4096, MemoryProtection::ReadWrite)
                .map_err(|_| 3)?;
            instance
                .write_memory(address, std::slice::from_raw_parts(data, length))
                .map_err(|_| 3)?;
            if access == 1 {
                instance.protect_memory(address, 4096).map_err(|_| 3)?;
            }
        }
        Ok(())
    })
}

/// Copy exactly one mapped page; no borrowed memory escapes the call.
#[no_mangle]
pub unsafe extern "C" fn rpvm_read(
    handle: *mut Rpvm,
    address: u32,
    data: *mut u8,
    length: usize,
) -> i32 {
    boundary(|| {
        if handle.is_null() || data.is_null() || length != 4096 || address % 4096 != 0 {
            return Err(1);
        }
        (*handle)
            .instance
            .read_memory_into(address, std::slice::from_raw_parts_mut(data, length))
            .map_err(|_| 3)?;
        Ok(())
    })
}

/// Reset the reusable instance to its module's empty memory and clear traced continuation state.
#[no_mangle]
pub unsafe extern "C" fn rpvm_reset(handle: *mut Rpvm) -> i32 {
    boundary(|| {
        if handle.is_null() {
            return Err(1);
        }
        let owner = &mut *handle;
        owner.ready = false;
        owner.host_continuation = false;
        owner.instance.reset_memory().map_err(|_| 3)?;
        owner.instance.clear_regs();
        owner.instance.set_gas(0);
        Ok(())
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Test-only RAII ensures assertion failures also release the one opaque lifetime.
    struct Owner(*mut Rpvm);
    impl Drop for Owner {
        fn drop(&mut self) {
            unsafe {
                assert_eq!(rpvm_destroy(self.0), 0);
            }
        }
    }

    #[test]
    fn abi_rejects_bad_buffers_and_contains_unwind() {
        // No invalid length or null buffer can cause a Rust slice to be constructed.
        unsafe {
            let mut handle = std::ptr::null_mut();
            assert_eq!(rpvm_create(1, std::ptr::null(), 8, &mut handle), 1);
            assert!(handle.is_null());
            assert_eq!(rpvm_prepare(handle, 0, std::ptr::null(), 13), 1);
            assert_eq!(rpvm_step(handle, std::ptr::null_mut()), 1);
            assert_eq!(rpvm_reset(handle), 1);
            assert_eq!(rpvm_destroy(handle), 0);
        }
        assert_eq!(std::mem::size_of::<RpvmEvent>(), 120);
        assert_eq!(boundary(|| panic!("ABI unwind witness")), 5);
    }

    #[test]
    fn resident_reset_does_not_retain_memory_registers_or_continuation() {
        // The same handle performs a real host call, resets, then executes an independent clean run.
        unsafe {
            let wire = [0_u8, 0, 4, 10, 2, 50, 0, 5];
            let mut handle = std::ptr::null_mut();
            assert_eq!(rpvm_create(1, wire.as_ptr(), wire.len(), &mut handle), 0);
            let owner = Owner(handle);
            let mut registers = [u64::MAX; 13];
            let canary = [173_u8; 4096];
            assert_eq!(rpvm_page(owner.0, 65536, 2, canary.as_ptr(), 4096), 0);
            assert_eq!(rpvm_prepare(owner.0, 0, registers.as_ptr(), 13), 0);
            let mut event = RpvmEvent {
                registers: [0; 13],
                kind: 99,
                pc: 99,
                detail: 99,
            };
            assert_eq!(rpvm_step(owner.0, &mut event), 0);
            assert_eq!((event.kind, event.pc, event.detail), (4, 0, 2));
            assert_eq!(event.registers, registers);
            assert_eq!(rpvm_reset(owner.0), 0);
            let mut observed = [0_u8; 4096];
            assert_eq!(rpvm_read(owner.0, 65536, observed.as_mut_ptr(), 4096), 3);
            assert_eq!(rpvm_step(owner.0, &mut event), 1);
            registers.fill(0);
            assert_eq!(rpvm_prepare(owner.0, 0, registers.as_ptr(), 13), 0);
            assert_eq!(rpvm_step(owner.0, &mut event), 0);
            assert_eq!(event.registers, registers);
        }
    }
}

/// Report the pristine upstream revision used by this maintained ABI; storage lives for the process.
#[no_mangle]
pub extern "C" fn rpvm_revision() -> *const std::ffi::c_char {
    c"69e5b87c9888bc4f94cabdadc9661cf68a1bfbfa".as_ptr()
}
