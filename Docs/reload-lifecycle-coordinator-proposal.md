# DwarfUICore Reload Lifecycle Coordinator Proposal

## Status

Proposed on 2026-08-04. This document defines an internal reload-lifecycle
architecture for review. It does not authorize implementation until the
proposal is approved and converted into an implementation checklist.

The current Reload Recovery implementation remains the behavioral baseline:
explicit source reload can recover from split-generation tooltip state,
generation validation remains strict during ordinary service use, retired
public APIs and handles remain stale, and tooltip render trampolines survive
for adoption by the successor generation. This proposal replaces the current
command-level recovery mechanism; it does not weaken those outcomes.

## Summary

DwarfUICore should introduce a private, generation-neutral reload lifecycle
coordinator. Generation-owned modules register retirement and discard actions
with the coordinator when they publish process-owned state. The explicit
`dwarfuicore reload` command asks the coordinator to retire every applicable
owner without loading that owner's script environment, advances the service
runtime generation, discards retired state, and reconstructs modules.

The coordinator survives module reload and accepts records from older runtime
generations. Its purpose is specifically to cross generation boundaries; it
must not apply the exact-generation validation required by ordinary service
APIs. It remains private and provides no consumer-visible lifecycle methods.

This design removes service slot names, service object shapes, and duplicated
generation comparison from `dwarfuicore/command.lua`. It also makes failed
reconstruction attempt cleanup of everything it successfully published,
discard every successfully retired owner, and retain failed cleanup records
before leaving the successor runtime disabled.

## Motivation

The command currently coordinates reload by knowing each subsystem's script,
fallback owner, process slot, and retirement method. Reload Recovery added
more tooltip-specific knowledge so teardown could recover when the process
runtime and surviving tooltip state belonged to different generations.

That behavior is necessary, but the ownership direction is inverted:

- the command knows private service state that service modules should own;
- the command duplicates generation rules already owned by the service
  runtime;
- cleanup depends on whether `reqscript()` can safely return a loaded module;
- partial construction needs a growing set of service-specific fallbacks; and
- every new process-owned subsystem requires another command change.

The command should orchestrate a reload transaction. Individual subsystems
should declare how their own process state is retired and discarded.

## Goals

- Remove service-specific process slots and owner shapes from the reload
  command.
- Retire stale-generation owners without loading generation-sensitive module
  environments.
- Preserve deterministic retirement ordering across UserPrompt, context-menu,
  tooltip, input, and presentation owners.
- Quiesce every externally callable owner before invoking fallible retirement
  cleanup.
- Attempt all eligible retirements even when one action fails.
- Make successful retirement exactly-once while allowing failed, idempotent
  retirement actions to be retried by a later explicit reload.
- Clean up partially published successor-generation state after reconstruction
  failure.
- Preserve reload-safe hook trampolines for successor adoption.
- Preserve strict generation validation for ordinary service acquisition, API
  invocation, handle validation, and module construction.
- Keep the coordinator private and out of the public service-provider
  contract.

## Non-goals

- Changing `reqscript('dwarfuicore/services')` or any public provider API.
- Making ordinary APIs tolerant of stale generations.
- Preserving registrations, open context menus, active prompts, tooltip
  intent, or public API validity across explicit Core reload.
- Automatically reloading DwarfUI or another consumer plugin.
- Adding a general plugin lifecycle framework for non-DwarfUICore code.
- Migrating process state created by a pre-coordinator DwarfUICore runtime.
- Replacing all process-owned slots with one generation container in this
  change.
- Installing packages, automatically restarting Dwarf Fortress, or changing
  production startup behavior. The required first-activation restart remains
  operator-controlled.

## Architectural boundary

### Reload command owns

`dwarfuicore/command.lua` should own only transaction orchestration:

1. load the module registry, service runtime, and reload coordinator;
2. ask the service runtime to enter retiring state;
3. ask the coordinator to recover every structurally valid tracked lifecycle
   owner in an executable status, discard retired future-generation records,
   and report every non-executable restart blocker;
4. if any future-generation record remains, disable the current runtime without
   advancing and stop;
5. otherwise advance to an initializing successor generation;
6. ask the coordinator to discard remaining retired generation-owned state;
7. if recovery or discard reported any failure or restart blocker, publish the
   successor runtime as disabled and stop;
8. clear and reconstruct registered module environments;
9. publish the successor runtime as healthy; and
10. on reconstruction failure, retire and discard eligible partial successor
    state before publishing a disabled runtime.

The command must not name tooltip, context-menu, UserPrompt, presenter,
registration-manager, or hook-manager process slots. It must not inspect an
owner object or compare an owner's generation itself.

### Reload coordinator owns

The proposed private module `dwarfuicore/reload_coordinator` owns:

- the process-stable registry of lifecycle owner records;
- owner-record validation and uniqueness;
- deterministic retirement order;
- record state transitions and retry behavior;
- best-effort invocation and aggregate failure reporting;
- discard eligibility;
- private diagnostics for tests and reload failure reports.

The coordinator must start with `--@ module=true`, export through the DFHack
module environment, and be registered in `dwarfuicore/module_registry.lua`
before every module that registers an owner.

### Service subsystems own

Each subsystem owns:

- construction of its process-owned objects;
- an idempotent retirement action;
- a discard action for its process slot or slots;
- registration only after its process state is fully publishable;
- rollback when publication or coordinator registration fails; and
- any adoption logic for process-stable hooks.

No subsystem may ask the coordinator to make a public API current again.

## Coordinator state model

The coordinator uses one process slot, conceptually:

```lua
dfhack.dwarfuicore.reload_coordinator = {
    schema_version=1,
    sequence=0,
    recovery_active=false,
    records={},
}
```

This state is generation-neutral. Loading a new coordinator module adopts the
existing state after validating its schema version. It does not require the
coordinator state's generation to match the service runtime.

Each record contains the equivalent of:

```lua
{
    owner_id='tooltip-presenter',
    runtime_generation=7,
    retirement_order=300,
    sequence=12,
    quiesce=function() end,
    retire=function() end,
    discard=function() end,
    status=ReloadOwnerStatus.ACTIVE,
    failure=nil,
}
```

Closed record status and retirement-order discriminators must use immutable
numeric enum tables. Suggested statuses are `ACTIVE`, `QUIESCING`, `QUIESCED`,
`QUIESCE_FAILED`, `RETIRING`, `RETIRED`, and `RETIRE_FAILED`. The precise
integer values are internal contracts but must remain deterministic within the
package.

`QUIESCING` and `RETIRING` are coordinator-internal transient statuses. The
coordinator sets the applicable transient status immediately before invoking
its callback under `xpcall`, then sets the corresponding success or failure
status before the recovery operation returns. Both
`recover_tracked_owners(runtime_generation)` and `discard_retired_owners()`
independently acquire the same process-wide `recovery_active` guard. Either
operation rejects entry while the guard is set with a deterministic
`RECOVERY_BUSY` failure, so nested reload cannot observe or act on a transient
record. Each operation clears the guard through protected finalization after
every outcome; the command does not hold it across runtime advancement between
the two operations.

Records are keyed by the composite identity of runtime generation and owner
identifier. A partial successor must not overwrite a previous generation's
record for the same logical owner.

The record callbacks are old-generation closures by design. They allow the
old object to retire itself after its script environment is no longer safe to
load. Clearing a script environment does not invalidate an already referenced
Lua function or object, but the command should retire owners before clearing
environments whenever possible.

## Registration contract

The coordinator exposes a private operation equivalent to:

```lua
local token = coordinator.register_owner{
    owner_id='tooltip-presenter',
    runtime_generation=runtime_generation,
    retirement_order=ReloadRetirementOrder.TOOLTIP_PRESENTER,
    quiesce=function()
        presenter:quiesce_for_reload()
    end,
    retire=function()
        return presenter:retire_for_reload()
    end,
    discard=function()
        if dfhack.dwarfuicore.tooltip_runtime == process_state then
            dfhack.dwarfuicore.tooltip_runtime = nil
        end
    end,
}
```

Registration requirements:

- `owner_id` is a non-empty private identifier.
- `runtime_generation` is a positive integer and must match the service
  runtime at registration time.
- `retirement_order` is a recognized immutable enum value.
- `quiesce`, `retire`, and `discard` are functions.
- the composite generation and owner identity is unique;
- callbacks capture the exact state they own;
- discard uses exact identity checks and never clears a replacement state;
  and
- successful registration returns an opaque internal token used only for
  construction rollback or private diagnostics.

Registration validates the current generation because it occurs during
ordinary construction. Cross-generation tolerance belongs only to explicit
coordinator recovery.

If coordinator registration fails, the constructing module must undo its
publication before returning the failure. It must not leave untracked process
state behind.

## Quiescence and retirement contract

The coordinator exposes two private operations:

- `recover_tracked_owners(runtime_generation)` performs quiescence and
  retirement, then attempts pre-advancement discard only for retired records
  whose generation is later than `runtime_generation`; and
- `discard_retired_owners()` performs post-advancement discard for every
  remaining `RETIRED` record.

Recovery selects every `ACTIVE`, `QUIESCED`, or `RETIRE_FAILED` record with a
structurally valid owner identity, positive generation, and trusted captured
callbacks. Quiescence and retirement selection is not capped at the retiring
runtime generation. A later-generation record is anomalous and must be reported
in the recovery result, but it is still advanced through its remaining
quiescence and retirement operations using its exact captured state.

After retirement, recovery selects every `RETIRED` record whose generation is
later than `runtime_generation` for pre-advancement discard. The coordinator,
not the command, owns that generation comparison. Advancement is allowed only
after every future-generation record has been removed. The separate
`discard_retired_owners()` operation selects all `RETIRED` records that remain
after advancement and never invokes quiescence or retirement callbacks.

Structurally valid `QUIESCE_FAILED` records are not executable recovery
targets. They are reported as restart blockers and remain available only for
diagnostics until process restart.

A malformed record whose identity, generation, callbacks, or state-machine
status cannot be validated is not invoked. It is reported as unrecoverable
coordinator corruption because the coordinator cannot safely execute an
untrusted value as cleanup code. This is distinct from a structurally valid
owner carrying an unexpected generation label. Any malformed record is an
unsafe cleanup failure: it blocks reconstruction and requires process restart.

Recovery records are ordered by immutable retirement order, then registration
sequence. The coordinator first runs the complete quiescence pass for `ACTIVE`
records in that order. Records already in `QUIESCED`, `RETIRE_FAILED`, or
`RETIRED` do not repeat quiescence. It then runs retirement for every record in
`QUIESCED` or `RETIRE_FAILED`, even if another owner failed to quiesce, so one
unsafe owner does not prevent safe owners from cleaning up. `RETIRED` records
proceed only through the applicable discard operation, preserving exactly-once
retirement. Reconstruction requires every applicable owner to have quiesced
successfully. The initial order must preserve the established behavior:

1. active UserPrompt interaction;
2. context-menu session and service;
3. tooltip presenter and presentation state;
4. remaining input, registration, and process-owner cleanup; and
5. discard-only records with no active behavior.

A discard-only record still supplies the required `quiesce` and `retire`
callbacks. Both are explicit idempotent no-ops, allowing every record to follow
one state machine without making either operation optional.

Quiescence is a narrow safety operation. It must synchronously revoke external
dispatch before doing anything fallible: clear an active callback, deactivate
an input consumer, detach a presenter function, or flip the exact plain-table
gate checked by an installed trampoline. It must not invoke consumer code,
restore foreign methods, load modules, or perform best-effort external
cleanup. A successful quiescence transitions the record to `QUIESCED` and is
not invoked again.

A quiescence callback that throws transitions the record to
`QUIESCE_FAILED`. Because quiescence contains no permitted fallible work, the
coordinator cannot treat a partial callback as proof that external dispatch is
inactive. Reconstruction is prohibited and the failure requires process
restart instead of claiming that a disabled successor makes stale callbacks
safe. A `QUIESCE_FAILED` record remains available for diagnostics but is never
selected for callback execution or retried in-process. Focused tests must
inject failures immediately around every inactive-gate transition to prove
this boundary.

Every eligible quiescence and retirement callback is attempted under `xpcall`. One
failure does not prevent later eligible owners from becoming inert or
retiring. The result is an aggregate report with owner identity, generation,
operation, and traceback for every failure.

Retirement runs only for `QUIESCED` or `RETIRE_FAILED` records. A successful
retirement transitions the record to `RETIRED` and is not invoked again. A
failed retirement transitions it to `RETIRE_FAILED`, retains the callback and
state, and can be retried during a later explicit reload. Retirement callbacks
perform potentially fallible cleanup but must never reactivate external
dispatch.

The coordinator does not call `reqscript()` for an owner during retirement.

## Discard contract

Only a `RETIRED` record may be discarded. Discard invokes the record's action
under protection and removes the record only after the action succeeds.

Discard actions must use exact captured-state identity. They must not clear a
new owner that has already replaced the retired state. A discard failure is
reported and the record remains available for another explicit recovery
attempt. On that attempt, a future-generation `RETIRED` record is selected by
pre-advancement recovery, while any other `RETIRED` record is selected by the
post-advancement `discard_retired_owners()` operation. Both paths retry discard
only; successful quiescence and retirement are not repeated.

`QUIESCE_FAILED` and `RETIRE_FAILED` state is never discarded merely to make
reconstruction proceed. Failed retirement is safe to retry only because the
owner is already quiesced. `QUIESCE_FAILED` is not retryable in-process: an
owner that cannot be proven quiescent blocks reconstruction and is reported as
requiring process restart.

## Process-stable hook adoption

Render and input trampolines that are explicitly designed for adoption are not
ordinary generation-owned service state. Their exported function identity may
need to remain installed so foreign wrapper chains and exact-identity cleanup
contracts remain valid.

The lifecycle distinction must be explicit:

- generation-owned presenters, sessions, services, registrations, observers,
  and selections are quiesced, retired, and discarded;
- process-stable trampoline records remain installed but are quiesced by the
  retiring owner; and
- the successor hook manager adopts the existing record and advances its
  internal generation before accepting new presentation or input ownership.

The tooltip presenter's quiescence callback must synchronously detach its
intent observer and presenter callback, clear selected transport and owner
dispatch, and make the renderer inactive without destructively removing the
render trampoline. Its retirement callback performs remaining fallible
cleanup. The successor generation must adopt the exact existing trampoline
identity.

The coordinator does not make a stale presenter current. It only ensures that
the stale presenter is retired before successor adoption.

### Reload-relevant owner inventory

The initial implementation must use the following lifecycle classification.
Any change to a listed policy requires an explicit proposal amendment.

| State or owner | Lifecycle policy | Retirement and successor behavior |
| --- | --- | --- |
| `service_provider_runtime` | Transaction authority | `command.lua` advances and disables it through the existing runtime contract; it is not a coordinator owner record. |
| Service-provider identity and weak handle-identity stores | Process-stable identity metadata | Preserve across reload so old API and handle identities can be classified as stale; never make them current. |
| `tooltip_runtime` presenter | Generation-owned | Retire presentation and observer ownership, then discard by exact captured-state identity. |
| `tooltip_service`, map-target registry, namespace registry, and registration runtime | Generation-owned | Retire active semantics where applicable; otherwise use discard-only records; discard by exact identity. |
| `tooltip_render_hook` | Process-stable and adoptable | Quiesce through presenter retirement, preserve installed trampoline records, and let the successor hook manager adopt and advance their internal runtime generation. |
| `context_menu_service` and registration manager | Generation-owned | Close active sessions, release registrations and callbacks, then discard by exact identity. |
| `context_menu_input_hook` | Generation-owned and destructively retired | Release priority consumers, restore/remove owned native and screen hooks through `shutdown()`, and discard its process state. It is not adoptable under this proposal. |
| `user_prompt_service` and its runtime callback ownership | Generation-owned | Remove the state-change callback, cancel active work with the Core-reload cause, release shared input/render ownership, and discard exact service state. |

## Reload transaction

The successful transaction is:

```text
healthy or disabled runtime
    -> runtime begins retiring
    -> coordinator reports generation anomalies
    -> coordinator advances all structurally valid tracked owners through
       remaining quiescence and retirement operations
    -> coordinator discards retired future-generation records
    -> runtime publishes initializing successor
    -> coordinator discards remaining retired generation-owned state
    -> old module environments are cleared
    -> new modules construct and register successor owners
    -> registry contracts are validated
    -> successor runtime becomes healthy
```

If safe retirement or discard of a current- or older-generation record fails,
the command still advances the retiring runtime to a successor so old APIs
become stale. The successor is marked disabled, the aggregate lifecycle
failure is reported, and failed coordinator records remain available for a
later recovery attempt. Module reconstruction does not start after a cleanup
failure. An owner that cannot be proven quiescent is an unsafe failure and
requires process restart; generation advancement is not presented as
sufficient protection from its callbacks.

Neither advancement nor reconstruction starts while a later-generation record
remains in any lifecycle state. It must be successfully quiesced, retired, and
discarded first. If that cleanup fails, the command marks the current runtime
disabled without advancing and reports the aggregate failure. Once every such
record is removed, the service runtime advances by its normal single generation
step; the anomalous generation label never determines or skips the successor
generation.

This preserves the existing rule that teardown failure cannot leave the old
public generation usable. Ordinary cleanup failure makes it stale by advancing
to a disabled successor; future-generation cleanup failure disables the current
runtime without advancing.

## Reconstruction failure recovery

If reconstruction fails after the successor generation has been published,
the command must:

1. ask the coordinator to quiesce and retire every registered owner from that
   successor generation;
2. attempt every eligible quiescence and retirement despite individual
   failures;
3. discard successfully retired successor records;
4. clear the service runtime's partial service and facade caches;
5. mark the successor generation disabled; and
6. report both the reconstruction failure and any cleanup failures.

This cleanup runs before control returns to the caller. A later explicit
reload may retry `RETIRE_FAILED` records without loading their scripts because
those records are already quiesced. Successfully published state whose
retirement fails remains tracked and is not discarded. `QUIESCE_FAILED` state
cannot be retried in-process and is reported as requiring process restart.

Modules must publish and register transactionally so failure before
registration leaves no process-owned state. Focused tests must inject failure
after each publication boundary to prove that every partial topology is either
cleaned immediately or remains tracked for retry.

## Ordinary generation validation

The coordinator is not an alternative access path to a service. Its
cross-generation selection rules apply only after the explicit reload command
has placed the service runtime in retiring state.

The following behavior remains unchanged:

- service acquisition requires the healthy current generation;
- public API invocation and handle validation require a healthy runtime, so
  same-generation objects reject a disabled runtime as `SERVICE_UNHEALTHY`;
- service records must match their owning runtime generation;
- public API objects reject generation advancement as `STALE_API`;
- old handles reject generation advancement as `STALE_HANDLE`;
- service modules reject conflicting process state during ordinary loading;
  and
- initialization does not repair malformed or split-generation state.

Only explicit reload may invoke coordinator recovery.

## Process restart compatibility boundary

The coordinator does not adopt process state created by a pre-coordinator
DwarfUICore runtime. Such state has no trusted coordinator record, quiescence
callback, or transactional publication proof. Introducing the coordinator
therefore requires the operator to restart Dwarf Fortress before the
coordinator-bearing runtime is initialized.

Activating the coordinator-bearing runtime requires a documented process
restart. Source-reloading coordinator-bearing code into a process that ran the
pre-coordinator implementation is unsupported and must not be attempted. No
runtime detector, adapter, or old-owner inspection is required. After restart,
every process-owned subsystem is constructed by coordinator-aware code and
registered transactionally from its first publication.

Source reload remains supported after that restart. All state created by the
coordinator-bearing runtime is tracked and can use the normal recovery
contract, including disabled, partial, stale-labeled, and future-labeled owner
records.

## Module and package organization

The implementation should add private modules equivalent to:

- `dwarfuicore/reload_contracts` for immutable numeric lifecycle enums;
- `dwarfuicore/reload_coordinator` for process state and operations.

Exact names may be refined during checklist review, but responsibilities must
remain separated. The modules must be added to `module_registry.lua` in
dependency order, included in syntax and package checks, and remain absent from
the public `dwarfuicore/services` exports.

## Implementation sequence

1. Characterize current successful reload, split-generation recovery,
   teardown failure, reconstruction retry, stale API/handle rejection, and
   trampoline identity behavior.
2. Add coordinator contracts, state validation, registration, deterministic
   retirement, discard, aggregation, retry, and diagnostics tests.
3. Document and observe the required process restart before first activation
   or live validation of coordinator-bearing code.
4. Register tooltip generation-owned state and preserve render-hook adoption.
5. Register context-menu owners, including partial construction boundaries.
6. Register UserPrompt owners and preserve cancellation-before-shared-owner
   ordering.
7. Add reconstruction-failure cleanup for freshly registered successor state.
8. Reduce `command.lua` to transaction orchestration and remove its process
   slot list and service-specific teardown logic.
9. Update module-registry and package contracts.
10. Run the complete acceptance evidence without modifying installed
    packages.

Each implementation step must keep focused tests green. The current
command-level recovery implementation is removed only after coordinator-aware
modules cover the same complete and partial process states created after
restart.

## Alternatives rejected

### Keep service-specific recovery in the command

This preserves the current behavior with the smallest diff, but every new
owner expands the command's knowledge of private state and repeats generation
logic. It does not establish a reusable failure-cleanup contract.

### Clear stale slots before retirement

Clearing references does not release observers, callbacks, selected owners,
active input, native indicators, or presenter state. It can also strand an
installed trampoline pointing at stale behavior. Retirement must precede
discard whenever active behavior was published.

### Load stale modules to ask them to shut down

Generation-sensitive module initialization is the operation that fails for
split-generation state. Cleanup must use already captured owner callbacks and
must not depend on reconstructing the stale module environment.

### Put every process owner into the service runtime immediately

A single generation-owned state container would make split generations
structurally harder to create and remains a viable longer-term architecture.
Migrating all services and process-stable hooks at once is substantially larger
than the reload coordinator and is not required to establish correct ownership
direction now.

### Clean only after reconstruction failure

Immediate rollback prevents newly failed generations from leaking state, but
it cannot finish interrupted cleanup or recover an already disabled split
generation. The coordinator must support both immediate rollback and later
explicit recovery for coordinator-tracked state.

## Acceptance criteria

The proposal is satisfied only when all of the following are proven:

- `command.lua` contains no service-specific process slot, owner shape, or
  generation comparison.
- Every generation-owned process state published by tooltip, context-menu, and
  UserPrompt is covered by a coordinator record or an explicitly documented
  process-stable adoption contract.
- Retirement runs in deterministic order and attempts all eligible records
  after an individual failure.
- Every externally callable owner is demonstrably quiescent before fallible
  retirement begins; a disabled runtime is never treated as a substitute for
  revoking stale callback dispatch.
- Successful records retire exactly once; failed idempotent records can be
  retried only when they are `RETIRE_FAILED`, while `RETIRED` records whose
  discard failed retry discard without repeating retirement.
- Discard cannot clear replacement state.
- First activation and live validation occur only after the required process
  restart; no in-process pre-coordinator migration is attempted.
- Every structurally valid future-labeled owner in an executable status is
  reported as anomalous and advanced through its remaining quiescence,
  retirement, and exact discard operations before normal single-step runtime
  advancement and reconstruction. A future-labeled `QUIESCE_FAILED` record is
  instead reported as a restart blocker.
- Both coordinator recovery operations reject nested entry as `RECOVERY_BUSY`,
  clear their shared guard after every outcome, and leave no record in
  `QUIESCING` or `RETIRING` when they return.
- Malformed coordinator records are never invoked as cleanup callbacks.
- Any malformed coordinator record blocks reconstruction and requires process
  restart.
- Failed retirement or discard of a current- or older-generation record
  advances the runtime generation, leaves the successor disabled, preserves
  retry records, and rejects old APIs and handles as stale.
- Failed cleanup of a future-generation record leaves the current generation
  disabled without advancement, preserves the record for retry when safe, and
  blocks reconstruction. Existing same-generation APIs and handles reject that
  disabled runtime as `SERVICE_UNHEALTHY`.
- A failed reconstruction attempts quiescence and retirement of every
  successfully published successor owner, discards every successfully retired
  owner, and retains each safely inactive failed record before returning.
- A corrected retry reaches a healthy later generation.
- Tooltip presenter retirement preserves the exact render trampoline, and the
  successor generation adopts it without double presentation.
- Ordinary module loading and service use still reject split-generation state.
- The coordinator is absent from public service exports.
- Registry order and package contents include every new private module.
- Focused coordinator, command reload, service-runtime, tooltip presenter,
  render-hook, context-menu, UserPrompt, API, and failure-recovery suites pass.
- The full unit suite and Lua syntax checks pass.
- Expanded and ZIP package verification pass exactly.
- A terminal live source reload adopts the current source registry without
  restarting Dwarf Fortress or modifying installed package files.

## Recommendation

Adopt the reload lifecycle coordinator plus immediate failed-reconstruction
cleanup. Keep generation validation strict everywhere outside explicit reload,
preserve stable hook identities through explicit adoption, and require a
process restart before first activating the coordinator-bearing runtime.

This is the smallest architecture that corrects ownership direction, handles
both current and future split-generation failures, and allows the reload
command to remain generic as DwarfUICore gains additional process-owned
services.
