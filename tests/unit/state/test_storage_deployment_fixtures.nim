# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Larger distinct-payload fixtures preserve seed/current complete maps and exact publication generations.
import std/assertions
import std/syncio
import ../../support/storage_deployment_samples
import ../../../src/storage/node_repository as storage_node_repository

for count in [1024, 32768]:
  # Small and larger authored fixtures use the same full distinct-value contract.
  for steps in [16, 64]:
    let fixture = prepareDeployment(count, steps)
    assert fixture.changes.len == steps and fixture.roots.len == steps+1
    var owner = newNodeRepository(deploymentLimits())
    discard owner.publish(owner.snapshot.value, fixture.seed).value
    let seed = owner.snapshot.value
    for change in fixture.changes:
      discard owner.publish(owner.snapshot.value, change).value
    let held = owner.snapshot.value
    checkDeploymentHead(held, fixture.roots[steps], count, steps)
    checkDeployment(held, fixture.roots[0], count, 0)
    assert owner.close == RepositoryError.None
    checkDeploymentHead(held, fixture.roots[steps], count, steps)
    checkDeployment(seed, fixture.roots[0], count, 0)
echo "PASS storage deployment fixtures"
