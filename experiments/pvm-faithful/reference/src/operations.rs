// Copyright (c) 2026 Ragnarök contributors
// SPDX-License-Identifier: MIT OR Apache-2.0

//! Arithmetic witness values from all public pinned operation.rs helpers.
use polkavm_common::operation as op;

pub fn generate(path: &str) {
    // Cross every boundary pair, then include deterministic full-width random operands.
    let edges = [
        0,
        1,
        2,
        0x7fff_ffff,
        0x8000_0000,
        0xffff_ffff,
        0x1_0000_0000,
        i64::MAX as u64,
        i64::MIN as u64,
        u64::MAX - 1,
        u64::MAX,
    ];
    let mut pairs: Vec<_> = edges
        .iter()
        .flat_map(|a| edges.iter().map(move |b| (*a, *b)))
        .collect();
    let mut random = 0x0123456789abcdef_u64;
    for _ in 0..4096 {
        random ^= random << 13;
        random ^= random >> 7;
        random ^= random << 17;
        let a = random;
        random ^= random << 13;
        random ^= random >> 7;
        random ^= random << 17;
        pairs.push((a, random));
    }
    let mut output = b"PVFOPS01".to_vec();
    output.extend_from_slice(&(pairs.len() as u32).to_le_bytes());
    for &(a, b) in &pairs {
        let values = [
            a,
            b,
            op::divu(a as u32, b as u32) as u64,
            op::divu64(a, b),
            op::remu(a as u32, b as u32) as u64,
            op::remu64(a, b),
            op::div(a as i32, b as i32) as u32 as u64,
            op::div64(a as i64, b as i64) as u64,
            op::rem(a as i32, b as i32) as u32 as u64,
            op::rem64(a as i64, b as i64) as u64,
            op::mulh(a as i32, b as i32) as u32 as u64,
            op::mulh64(a as i64, b as i64) as u64,
            op::mulhsu(a as i32, b as u32) as u32 as u64,
            op::mulhsu64(a as i64, b) as u64,
            op::mulhu(a as u32, b as u32) as u64,
            op::mulhu64(a, b),
        ];
        for value in values {
            output.extend_from_slice(&value.to_le_bytes());
        }
    }
    std::fs::write(path, output).unwrap();
    println!("faithful upstream arithmetic witnesses: {}", pairs.len());
}
