// Copyright (c) 2026 Ragnarök contributors
// SPDX-License-Identifier: MIT OR Apache-2.0

//! Give the maintained shared library a relocatable identity for its C and Nim consumers.
fn main() {
    // Platform-specific identities permit colocated loading without a build-machine path.
    match std::env::var("CARGO_CFG_TARGET_OS").as_deref() {
        Ok("macos") => println!(
            "cargo:rustc-cdylib-link-arg=-Wl,-install_name,@rpath/libragnarok_bandersnatch.dylib"
        ),
        Ok("linux") => {
            println!("cargo:rustc-cdylib-link-arg=-Wl,-soname,libragnarok_bandersnatch.so")
        }
        _ => {} // Supported build tooling rejects platforms outside Darwin/Linux.
    }
}
