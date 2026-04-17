---
description: SolidQueue job conventions for app/jobs/.
paths:
  - app/jobs/**/*.rb
  - spec/jobs/**/*.rb
---

# SolidQueue Job Rules

## Concurrency

- `ProvisioningExecuteJob` runs with `limits_concurrency to: 1, key: project_id` — one provisioning job per Project at a time.
- Cross-project concurrency is allowed.
- Use named queues: `:provisioning`, `:webhooks`, `:health_checks`. Do not use the default queue for long-running work.

## Idempotency (crash recovery)

- Every job must tolerate being re-invoked with the same arguments.
- Every `Provisioning::Steps::*` must implement `already_completed?` so the orchestrator can skip completed steps on resume.
- Stash external resource identifiers in `provisioning_steps.result_snapshot` the moment they are created, before moving to the next step.

## Retries

- SolidQueue-level `retry_on StandardError, attempts: 2` handles worker crashes.
- In-step retries (exponential backoff) are implemented inside the orchestrator's `StepRunner` — not by `retry_on`.
- `discard_on ActiveRecord::RecordNotFound` for deleted targets.

## Do not

- Do not perform HTTP calls directly in a job. Delegate to services/clients.
- Do not silently swallow exceptions. Let the orchestrator mark the step `failed` and decide.
- Do not mix business logic with queueing concerns — jobs are thin entry points.

## Testing

- Use `SolidQueue::Job.perform_now` in unit specs to assert behavior synchronously.
- Assert on the resulting DB state (step status, result_snapshot) rather than stubbing the orchestrator.
- For crash-recovery tests: call `perform_now` twice with the same job id and assert no duplicate external resources were created.
