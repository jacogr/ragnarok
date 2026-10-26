#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Measure optional ABI lifecycle phases without folding construction or page copies into execution.

This synthetic host-call probe includes Python/ctypes overhead. It does not measure application
throughput, protocol gas pricing or DOOM, and makes no performance-equivalence claim.
"""
import ctypes as c
import json
import platform
from statistics import median
from time import perf_counter_ns
from build_polkavm import build_native
from native_dependencies import ROOT


class Event(c.Structure):
    """Match the maintained fixed-width C output, including its natural trailing alignment."""
    _fields_ = [('registers', c.c_uint64*13), ('kind', c.c_uint32),
                ('pc', c.c_uint32), ('detail', c.c_uint32)]


def run():
    """Validate every sample, retaining construction, cold, resident, reset and publication separately."""
    library = c.CDLL(str(build_native()))
    library.rpvm_create.argtypes = [c.c_uint32, c.c_void_p, c.c_size_t, c.POINTER(c.c_void_p)]
    library.rpvm_destroy.argtypes = [c.c_void_p]
    library.rpvm_prepare.argtypes = [c.c_void_p, c.c_uint32, c.c_void_p, c.c_size_t]
    library.rpvm_step.argtypes = [c.c_void_p, c.POINTER(Event)]
    library.rpvm_page.argtypes = [c.c_void_p, c.c_uint32, c.c_uint32, c.c_void_p, c.c_size_t]
    library.rpvm_read.argtypes = [c.c_void_p, c.c_uint32, c.c_void_p, c.c_size_t]
    library.rpvm_reset.argtypes = [c.c_void_p]
    wire = (c.c_uint8*8)(0, 0, 4, 10, 2, 50, 0, 5)
    registers = (c.c_uint64*13)()
    registers[0] = 0xffff0000
    page = (c.c_uint8*4096)(*([173]*4096))
    observed = (c.c_uint8*4096)()
    report = dict(scope=__doc__.strip(), platform=platform.platform(), engines={})

    def checked(function, *arguments):
        """Every ABI status is checked outside any implicit fallback path."""
        status = function(*arguments)
        if status != 0:
            raise RuntimeError('ABI operation refused: '+str(status))

    def call(handle):
        """Execute a genuine host suspension and halt using one resident instance."""
        event = Event()
        checked(library.rpvm_step, handle, c.byref(event))
        assert (event.kind, event.pc, event.detail) == (4, 0, 2)
        checked(library.rpvm_prepare, handle, 2, registers, 13)
        checked(library.rpvm_step, handle, c.byref(event))
        assert event.kind == 2 and list(event.registers) == list(registers)

    for backend, name in ((1, 'polkavm-interpreted'), (2, 'polkavm-native')):
        rows = []
        for sample in range(7):
            handle = c.c_void_p()
            started = perf_counter_ns()
            status = library.rpvm_create(backend, wire, len(wire), c.byref(handle))
            construction = perf_counter_ns()-started
            if status == 2:
                assert handle.value is None
                report['engines'][name] = dict(status='unavailable')
                break
            if status != 0:
                raise RuntimeError('Explicit engine construction refused: '+str(status))
            try:
                row = dict(construction_ns=construction)
                started = perf_counter_ns()
                for index in range(32):
                    checked(library.rpvm_page, handle, 65536+index*4096, 2, page, 4096)
                row['initial_mapping_ns'] = perf_counter_ns()-started
                started = perf_counter_ns()
                checked(library.rpvm_prepare, handle, 0, registers, 13)
                row['cold_prepare_ns'] = perf_counter_ns()-started
                started = perf_counter_ns()
                call(handle)
                row['cold_execution_ns'] = perf_counter_ns()-started
                started = perf_counter_ns()
                checked(library.rpvm_prepare, handle, 0, registers, 13)
                call(handle)
                row['resident_reentry_execution_ns'] = perf_counter_ns()-started
                started = perf_counter_ns()
                for index in range(32):
                    checked(library.rpvm_read, handle, 65536+index*4096, observed, 4096)
                    assert bytes(observed) == bytes(page)
                row['complete_memory_publication_ns'] = perf_counter_ns()-started
                started = perf_counter_ns()
                checked(library.rpvm_reset, handle)
                row['reset_ns'] = perf_counter_ns()-started
                assert library.rpvm_read(handle, 65536, observed, 4096) == 3
                checked(library.rpvm_prepare, handle, 0, registers, 13)
                call(handle) # The reset instance must execute independently after losing its entire prior RAM.
                rows.append(row)
            finally:
                checked(library.rpvm_destroy, handle)
        else:
            report['engines'][name] = dict(status='measured', samples=rows,
                medians={key: median(row[key] for row in rows) for key in rows[0]},
                publication_bytes=32*4096, guest_host_calls=2)
    folder = ROOT/'build/tests/pvm-runtime-measure'
    folder.mkdir(parents=True, exist_ok=True)
    (folder/'results.json').write_text(json.dumps(report, indent=2)+'\n')
    print('Runtime ABI phase measurements: '+str(folder/'results.json'))


if __name__ == '__main__':
    run()
