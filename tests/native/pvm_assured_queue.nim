# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Strict successor admission/queue result and retained-view contracts with genuine assurance-fed priority as a positive control.

import std/[assertions, cmdline]
import ../../src/state/assured/queue as assured_queue
import ../../src/state/computed/assurances as computed_assurances
import ../../src/state/accumulation/queue as accumulation_queue
import ../../src/state/report/admission as report_admission
import ../../src/codec/[bounded, assurances]
import ../support/pvm_assured_queue

proc expect[T](outcome: AssuredQueueResult[T], reason: AssuredQueueError) =
  ## Check exact selected alternatives without converting deliberate runtime misuse into static contradictions.
  assert outcome.error == reason, "assured queue runtime control"
let source = assuredQueueFixture()
let config = assuredQueueConfig(source)
let done = prepareAssuredQueue(source, config)
expect(done, AssuredQueueError.None)
assert done.value.assuredQueuePlan.value.accumulationProjection.value.accumulationImmediateCount.value == 2
let invalid = prepareAssuredQueue(default(AssuredComputedReports), config)
expect(invalid, AssuredQueueError.InvalidSource)
var changed = config
changed.queue.queues.cores = CoreCount(2)
let profile = prepareAssuredQueue(source, changed)
expect(profile, AssuredQueueError.ProfileMismatch)
changed = config
changed.admission.ancestors.headers = ElementLimit(2)
let ancestors = prepareAssuredQueue(source, changed)
expect(ancestors, AssuredQueueError.LimitExceeded)
changed = config
changed.admission.credentials.assignments.roster.maxBytes = ByteLimit(0)
let admission = prepareAssuredQueue(source, changed)
expect(admission, AssuredQueueError.AdmissionFailure)
assert admission.admissionFailure.error == ReportAdmissionError.LimitExceeded
changed = config
changed.queue.items = ElementLimit(1)
let queue = prepareAssuredQueue(source, changed)
expect(queue, AssuredQueueError.QueueFailure)
assert queue.queueFailure.error == AccumulationQueueError.LimitExceeded
let missing = default(AssuredQueueResult[AssuredAccumulationQueue])
case paramStr(1)
of "default": discard missing.value # Default/refused alternatives contain no usable queue or earlier accepted prefix.
of "source": discard invalid.value # Default/refused alternatives contain no usable queue or earlier accepted prefix.
of "profile": discard profile.value # Default/refused alternatives contain no usable queue or earlier accepted prefix.
of "ancestors": discard ancestors.value # Default/refused alternatives contain no usable queue or earlier accepted prefix.
of "admission": discard admission.value # Default/refused alternatives contain no usable queue or earlier accepted prefix.
of "queue": discard queue.value # Default/refused alternatives contain no usable queue or earlier accepted prefix.
of "owner": discard default(AssuredAccumulationQueue).assuredQueueSource.value # An empty owner cannot supply retained source, plan, admission or original parameters.
of "plan": discard default(AssuredAccumulationQueue).assuredQueuePlan.value # An empty owner cannot supply retained source, plan, admission or original parameters.
of "reports": discard default(AssuredAccumulationQueue).assuredQueueAdmission.value # An empty owner cannot supply retained source, plan, admission or original parameters.
of "parameters": discard default(AssuredAccumulationQueue).assuredQueueParameters.value # An empty owner cannot supply retained source, plan, admission or original parameters.
of "admissionFailure-default": discard missing.admissionFailure # Only the selected precise maintained refusal can be extracted.
of "admissionFailure-success": discard done.admissionFailure # Only the selected precise maintained refusal can be extracted.
of "admissionFailure-source": discard invalid.admissionFailure # Only the selected precise maintained refusal can be extracted.
of "admissionFailure-other": discard queue.admissionFailure # Only the selected precise maintained refusal can be extracted.
of "queueFailure-default": discard missing.queueFailure # Only the selected precise maintained refusal can be extracted.
of "queueFailure-success": discard done.queueFailure # Only the selected precise maintained refusal can be extracted.
of "queueFailure-source": discard invalid.queueFailure # Only the selected precise maintained refusal can be extracted.
of "queueFailure-other": discard admission.queueFailure # Only the selected precise maintained refusal can be extracted.
else: discard invalid.value # Unknown modes never become passing controls.
