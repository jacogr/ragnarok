// Copyright (c) 2026 Ragnarök contributors
// SPDX-License-Identifier: MIT OR Apache-2.0

//! Independent layout bounds and rounding from pinned MemoryMapBuilder.
use polkavm_common::abi::MemoryMapBuilder;

pub fn generate(path: &str) {
    let sizes = [
        0,
        1,
        4095,
        4096,
        65535,
        65536,
        0x7fff_ffff,
        0xffff_0000,
        u32::MAX,
    ];
    let pages = [0, 4095, 4096, 8192, 16384, 32768, 65536, 65537, 4097];
    let count = (sizes.len().pow(4) * pages.len()) as u32;
    let mut output = b"PVFLAY01".to_vec();
    output.extend_from_slice(&count.to_le_bytes());
    let mut accepted = 0;
    for page in pages {
        for ro in sizes {
            for rw in sizes {
                for stack in sizes {
                    for aux in sizes {
                        for value in [page, ro, rw, stack, aux] {
                            output.extend_from_slice(&value.to_le_bytes());
                        }
                        let map = MemoryMapBuilder::new(page)
                            .ro_data_size(ro)
                            .rw_data_size(rw)
                            .stack_size(stack)
                            .aux_data_size(aux)
                            .build();
                        let Ok(map) = map else {
                            output.push(0);
                            continue;
                        };
                        output.push(1);
                        accepted += 1;
                        for value in [
                            map.page_size(),
                            map.ro_data_address(),
                            map.rw_data_address(),
                            map.stack_address_low(),
                            map.stack_address_high(),
                            map.aux_data_address(),
                            map.ro_data_size(),
                            map.rw_data_size(),
                            map.stack_size(),
                            map.aux_data_size(),
                            map.heap_base(),
                            map.max_heap_size(),
                        ] {
                            output.extend_from_slice(&value.to_le_bytes());
                        }
                    }
                }
            }
        }
    }
    std::fs::write(path, output).unwrap();
    println!("faithful upstream layout witnesses: {count}, accepted: {accepted}");
}
