# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Index independently derived scenario snapshots without changing maps or protocol expectations."""
from current_stf_oracle import decode_checkpoint
from state_layout_oracle import chapter_key


def case_states(cases):
    """Retain each named case's original map at slot one and successors at their authored slots."""
    result = {}
    for case in cases:
        # Snapshots remain the same caller-owned objects; this helper neither copies nor derives state.
        states = {1: case['initial']}
        for _, state, _ in case['steps']:
            # Index actual slots, preserving skipped slots and the existing last-snapshot-wins behavior.
            states[int.from_bytes(state[chapter_key(11)], 'little')] = state
        result[case['name']] = states
    return result


def checkpoint_states(lines, *, initial_slot=1):
    """Decode P/O rows into per-chain slot indexes; None indexes the initial map by its actual slot."""
    result = []
    for line in lines:
        # Block echoes, refusal controls and other observations are not checkpoint rows.
        if line.startswith('P ') or line.startswith('O '):
            state = decode_checkpoint(bytes.fromhex(line[2:]))
            initial = line.startswith('P ')
            slot = initial_slot if initial else None
            if slot is None:
                # Successors and actual-slot initial maps retain their independently authored slot.
                slot = int.from_bytes(state[chapter_key(11)], 'little')
            if initial:
                # Most historical fixtures deliberately label their initial checkpoint as slot one.
                result.append({})
            result[-1][slot] = state
    return result
