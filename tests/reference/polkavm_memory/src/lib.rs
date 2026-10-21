// Copyright (c) 2026 Ragnarök contributors
// SPDX-License-Identifier: MIT OR Apache-2.0
//! Explicit backend selection shared by optional public-API reference executables.
use polkavm::{BackendKind, Config, Engine};

/// Construct exactly the requested reference backend; never fall back to the interpreter.
pub fn engine(dynamic_paging: bool) -> Engine {
    let requested = std::env::var("RAGNAROK_PVM_REFERENCE_BACKEND")
        .unwrap_or_else(|_| "interpreter".to_owned());
    let backend = match requested.as_str() {
        "interpreter" => BackendKind::Interpreter,
        "compiler" => BackendKind::Compiler,
        other => panic!("unknown reference backend {other:?}; use interpreter or compiler"),
    };
    let mut config = Config::default();
    config.set_backend(Some(backend));
    config.set_allow_dynamic_paging(dynamic_paging);
    let engine = Engine::new(&config).expect("requested reference backend could not initialize");
    assert_eq!(engine.backend(), backend);
    println!("Reference backend: {backend}; dynamic paging: {dynamic_paging}");
    engine
}

/// Report platform and actual engine setup separately, without enabling kernel facilities.
pub fn backend_info() {
    println!("compiler_platform={}", BackendKind::Compiler.is_supported());
    for dynamic in [false, true] {
        // Engine setup can fail independently of platform support, notably for userfaultfd permissions.
        let mut config = Config::default();
        config.set_backend(Some(BackendKind::Compiler));
        config.set_allow_dynamic_paging(dynamic);
        let result = Engine::new(&config);
        let label = if dynamic {
            "compiler_dynamic_engine"
        } else {
            "compiler_engine"
        };
        println!("{label}={}", result.is_ok());
        if let Err(error) = result {
            eprintln!("{label}: {error}");
        }
    }
}
