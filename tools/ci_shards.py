# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Expose shuffled() and stratified() for reproducible plans without maintained timing weights."""
import random


# A fresh private generator gives every runner the same plan, independent of other random users.
def shuffled(items, seed, group):
    values = list(items)
    if seed is not None:
        # Reject malformed report seeds instead of silently validating another partition's scope.
        if not isinstance(seed, str) or not seed.strip():
            raise ValueError('Shard seed must be a nonempty string')
        random.Random(group+':'+seed).shuffle(values)
    return values


# Give every shard one random member of each similarly weighted block; randomize ties, tails and run order.
def stratified(items, count, seed, group, weight):
    values = shuffled(items, seed, group+':ties')
    if seed is None or type(count) is not int or count < 1:
        # This planner requires an explicit reproducible seed and at least one destination.
        raise ValueError('Stratified shards require a seed and positive count')
    values.sort(key=weight)
    generator = random.Random(group+':'+seed)
    partitions = [[] for _ in range(count)]
    for offset in range(0, len(values), count):
        # Full blocks give one member to every shard; a partial block chooses distinct random owners.
        block = values[offset:offset+count]
        generator.shuffle(block)
        owners = list(range(count))
        generator.shuffle(owners)
        for owner, item in zip(owners, block):
            partitions[owner].append(item)
    for partition in partitions:
        # Sorting is only for assignment; execution order remains randomized within each runner.
        generator.shuffle(partition)
    return partitions
