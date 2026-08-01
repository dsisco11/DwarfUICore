# Service Provider API Phase 0 Baseline and Inventory

Status: baseline and current-flow inventory complete on 2026-08-01

Source contract: `Docs/service-provider-api-proposal.md`

Execution contract: `Docs/service-provider-api.todo`

## Repository and package baseline

| Item | Captured value |
| --- | --- |
| Branch | `repo-split` |
| Revision | `331285c2720afb911b57d7303e078604736adfea` |
| Worktree at capture | Clean; branch was 11 commits ahead of `origin/repo-split` |
| Rockspec | `dwarfuicore 0.1.0-1` |
| DFHack package metadata | displayed `0.1.0`; numeric `1` |
| Lua compiler | Lua `5.4.6` |
| Unit baseline | 274 successes, 0 failures, 0 errors, 0 pending |
| Syntax baseline | 34 production and 52 test/support files passed |
| Offline build baseline | Passed with live reload disabled |
| Package baseline | Expanded and zip verification passed |
| Package artifacts | 35 expanded files; 35 zip files; 68,591-byte zip |

The package result is offline evidence only. It is not installed-runtime or
live acceptance evidence.

## Reload-managed module order

The captured registry contains 32 modules in this dependency order:

1. `dwarfuicore/utils/immutable_enum`
2. `dwarfuicore/utils/function_chain`
3. `dwarfuicore/utils/numbers`
4. `dwarfuicore/class`
5. `dwarfuicore/map_projection`
6. `dwarfuicore/pointer_poller`
7. `dwarfuicore/pointer`
8. `dwarfuicore/text`
9. `dwarfuicore/view_root_resolver`
10. `dwarfuicore/widget_extensions`
11. `dwarfuicore/tooltip/target`
12. `dwarfuicore/tooltip/map_target`
13. `dwarfuicore/tooltip/service`
14. `dwarfuicore/tooltip/target_detector`
15. `dwarfuicore/tooltip/registration`
16. `dwarfuicore/tooltip/renderer`
17. `dwarfuicore/tooltip/render_hook`
18. `dwarfuicore/tooltip/presenter`
19. `dwarfuicore/tooltip/runtime`
20. `dwarfuicore/tooltip/api`
21. `dwarfuicore/context_menu/definition`
22. `dwarfuicore/context_menu/target`
23. `dwarfuicore/context_menu/input_sample`
24. `dwarfuicore/context_menu/root_discovery`
25. `dwarfuicore/context_menu/map_target`
26. `dwarfuicore/context_menu/registration`
27. `dwarfuicore/context_menu/target_detector`
28. `dwarfuicore/context_menu/input_hook`
29. `dwarfuicore/context_menu/renderer`
30. `dwarfuicore/context_menu/service`
31. `dwarfuicore/context_menu/screen`
32. `dwarfuicore/context_menu/api`

Registered module environments are cleared in reverse dependency order. The
registry is then cleared and reloaded, after which fresh module environments
are cleared and reconstructed in forward dependency order.

## Current process-owned state

| Process slot or callback | Current owner and load behavior |
| --- | --- |
| `pointer_poller_module_generation` | Incremented whenever `pointer_poller` loads; queued callbacks compare both module and instance generations. |
| `widget_extensions` | Reuses its prior record and increments its generation while retaining replacement diagnostics. |
| `tooltip_map_target_registry` | Reuses same-version weak registration state, increments its generation, and replaces incompatible state. |
| `tooltip_service` | Reuses same-version weak widget registrations but shuts down target/intent state and increments generation during module load. |
| `tooltip_render_hook` | Reuses same-version hook state; manager ownership and hook reconciliation are recreated around that process record. |
| `context_menu_root_discovery_generation` | Incremented at module load so stale scheduled discovery callbacks self-retire. |
| `context_menu_registration_generation` | Incremented at module load; stale managers clear themselves when observed. |
| `context_menu_registration_manager` | The registration module shuts down the previous manager, clearing registrations and discovery, before publishing a new eager manager. |
| `context_menu_input_hook` | Module load shuts down the previous manager, creates a new generation record, and preserves only unavoidable foreign-wrapper retirement records. |
| `context_menu_service` | Module load shuts down the prior service, allocates a fresh generation/state record, and eagerly builds a new service over current collaborators. |
| `dfhack.onStateChange.dwarfuicore_context_menu` | Owned by the current context-menu service; world unload closes the menu and destructively clears all current registrations. |

There is no single authoritative DwarfUICore runtime-generation record today.
Generation and health are distributed across module-specific slots. Several
module loads mutate process state or retire predecessors before any future
provider arguments could be validated.

## Explicit reload and teardown

The root `dwarfuicore reload` command currently:

1. retires the context-menu service or partial registration owner;
2. retires the tooltip presenter or partial render-hook owner;
3. clears loaded registered environments in the old registry's safe order;
4. clears and reloads the registry;
5. clears fresh registered module environments;
6. runs every registered module in dependency order; and
7. loads and validates the reconstructed registry contract.

This is destructive development reload, but it does not yet publish one atomic
runtime status/generation around the entire transition. A failed reconstruction
can therefore leave partially rebuilt module side effects even though retired
service owners are not intentionally reused.

## Tooltip registration and presentation flow

Current widget flow:

```text
tooltip/api.register(widget)
  -> tooltip/registration.register(widget)
  -> tooltip/service.register(widget)
  -> weak widget-key registration with original sequence
  -> PointerPoller demand starts
  -> target detector resolves eligible roots and reverse-render hit
  -> greatest root/registration sequence wins
  -> widget is adapted to a normalized target
  -> service mediates pointer transitions and publishes immutable intent
  -> presenter selects overlay or screen transport
  -> render-hook trampoline renders the tooltip
```

Current map flow:

```text
tooltip/api.register_map_tile(options)
  -> weak opaque handle and signed-16 exact-coordinate record
  -> weak coordinate bucket and registration sequence
  -> pointer poller enables map sampling
  -> widget/blocker detection runs first
  -> exact map fallback chooses greatest live registration sequence
  -> map candidate is adapted and enters the same service/presenter path
```

Widget registrations live in `tooltip_service.registrations`, a weak-key table.
Map handles are weak keys in the primary registry and coordinate buckets; the
coordinate index uses weak values. Update validates a complete replacement
position/text before changing a record and preserves its handle and sequence.

The current tooltip backend has no namespace component. Widget identity is the
widget itself, map identity is the handle itself, and cross-root ordering uses
registration sequence directly. Same-version service reload preserves weak
widget registrations but retires the active target, intent, observer closure,
and sample sequence.

## Context-menu registration, opening, and callback flow

Current widget registration flow:

```text
context_menu/api.register(widget, definition)
  -> strict definition validation and copied snapshot
  -> weak widget-key record with numeric identity and sequence
  -> root discovery demand starts
  -> discovered roots drive native/screen input-hook reconciliation
```

Current map registration flow:

```text
context_menu/api.register_map_tile(options)
  -> strict options/definition validation
  -> weak opaque handle plus weak owner reference
  -> copied signed-16 coordinate and definition slot
  -> weak coordinate bucket with numeric identity and sequence
  -> root discovery and exact map sampling demand start
```

Opening and selection currently flow as follows:

```text
right-click input trampoline
  -> synchronous pointer/map sample
  -> target detector chooses one widget, blocker, exact map target, or miss
  -> service copies one candidate into one open session
  -> screen presentation renders the copied definition
  -> selection copies a public callback context
  -> service closes the session before protected callback invocation
```

Widget registration replacement and update retain numeric identity and original
sequence. Map update validates and copies complete mutable state before changing
the record and retains handle, identity, and sequence. Definitions are copied;
later mutation of caller tables does not change registration-owned snapshots.

Open sessions strongly own copied definition data and callbacks but weakly own
source, root, and optional map owner. Current selection revalidates weak session
sources and exact map identity/coordinate, but the current backend opens only
one contribution and does not implement the proposal's composed immutable
multi-contribution snapshot.

The current callback context exposes raw numeric `registration_identity` plus
internal target/anchor discriminator values. That conflicts with the proposal's
rule that composite registration identity remains internal unless represented
by an opaque handle and requires an explicit version 1 schema decision.

## Required refactoring boundaries

- Argument validation must move ahead of every eager service/prerequisite load.
- One process runtime record must replace distributed generation authority for
  provider acquisition and API staleness.
- Existing module-load predecessor retirement must become explicit,
  idempotent initialization or explicit core reload behavior.
- Widget keys must change from `widget` to `(namespace, widget)` without losing
  weak collection.
- Map handles need private composite ownership without any secondary strong
  reference.
- Physical widget target sequence must be separated from namespace contribution
  sequence.
- Tooltip winner resolution and context-menu contribution composition must run
  only after namespace-neutral physical target selection.
- Context-menu open sessions must snapshot and revalidate every included
  composite contribution before dispatch.
- World/map unload cannot continue to imply generic clearing of every consumer;
  consumer-owned namespace cleanup must be explicit.
- Public provider APIs must not inherit the existing diagnostic functions or
  expose raw registration identities.
