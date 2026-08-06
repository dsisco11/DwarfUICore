# Input Event UI Root Resolution Sub-Proposal

## Status and Authority

This document proposes a replacement for the provisional UI-root adaptation approach explored while automating `MAP_CLICK` behavior. It refines the UI-obstruction portion of the Input Event Service proposal without changing the public event, interception, observation, or payload contracts.

The parent proposal remains authoritative for externally observable behavior. Once this direction is approved, its accepted decisions must be reconciled into the parent proposal and implementation todo.

## Problem Statement

`RAW_CLICK` can be produced whenever a mouse input has a DFHack-reported map coordinate. Producing `MAP_CLICK` additionally requires evidence that no supported UI element obstructed the pointer.

The provisional collector treated all discovered roots as though they shared the `gui.View` model. Native viewscreen widgets are DF userdata with different traversal, visibility, geometry, and positioning rules. Adapting them into synthetic `gui.View`-shaped tables inside root collection caused several problems:

- root discovery became coupled to recursive element traversal;
- native and Lua object models became indistinguishable after adaptation;
- test doubles could be mistaken for native widgets;
- native positioning and visibility semantics were approximated;
- adaptation failures did not identify which UI domain was uninspectable;
- enabled overlay definitions were confused with overlays applicable to the current viewscreen and focus.

The table-versus-userdata test failure was therefore a symptom of an incorrect responsibility boundary, not a reason to add a userdata special case.

## Goals

- Preserve fail-closed `MAP_CLICK` semantics.
- Identify only UI roots applicable to the current input context.
- Preserve each root's object model and classify it explicitly.
- Resolve obstruction through a strategy appropriate to each root kind.
- Keep root discovery shallow and recursive traversal in dedicated hit testers.
- Make unsupported or malformed UI state diagnosable internally.
- Allow tooltip, context-menu, prompt, and future systems to share one obstruction decision.

## Non-Goals

- Changing `RAW_CLICK` or `MAP_CLICK` payloads.
- Adding event-specific public `observe` or `intercept` methods.
- Changing input-hook ownership or placement.
- Changing reload behavior.
- Modifying DFHack's overlay plugin or native viewscreen implementation.
- Claiming support for UI models Core has not explicitly classified.

## Design Principles

### Discovery Is Not Hit Testing

The collector identifies applicable root surfaces. It does not recursively scan descendants, synthesize replacement objects, or decide whether a root blocks the pointer.

### Root Kinds Are Explicit

Every root carries a closed discriminator describing its object model. Runtime Lua type checks validate descriptors but do not select production behavior.

### Applicability Precedes Inspection

An overlay that does not apply to the current viewscreen or focus is not part of the current UI and must not suppress `MAP_CLICK`. An applicable root that cannot be inspected must suppress it.

### Unknown State Fails Closed

Core does not emit `MAP_CLICK` when a supported, applicable root cannot be inspected reliably. Globally enabled but context-inapplicable roots must not enter the decision.

## Proposed Internal Model

### Root Kind

Add an immutable numeric enum internal to the input-event subsystem:

```lua
---@enum UiRootKind
UiRootKind = {
    NATIVE_WIDGET_TREE = 1,
    LUA_VIEW = 2,
    OVERLAY_VIEW = 3,
    CORE_REGISTERED_VIEW = 4,
}
```

### Root Descriptor

The collector returns immutable internal descriptors:

```lua
---@class UiRootDescriptor
---@field kind UiRootKind
---@field root unknown
---@field identity string|nil
```

`identity` is optional diagnostic metadata and never enters public event payloads. The descriptor preserves the original root object; a native widget container remains DF userdata.

### Collection Result

Root collection must distinguish a successfully collected empty set from an incomplete or malformed context. It returns either a complete descriptor list or an explicit unknown result. It must not silently omit an applicable root after an inspection error.

### Obstruction Result

Each hit tester returns an immutable numeric result:

```lua
---@enum UiObstructionResult
UiObstructionResult = {
    MISS = 1,
    BLOCK = 2,
    UNKNOWN = 3,
}
```

- `MISS`: the root was inspected and does not obstruct the pointer.
- `BLOCK`: a visible applicable element obstructs the pointer.
- `UNKNOWN`: the applicable root could not be inspected reliably.

Aggregation is deterministic: any `BLOCK` wins, otherwise any `UNKNOWN` wins, and only all-`MISS` is unobstructed. Both `BLOCK` and `UNKNOWN` suppress `MAP_CLICK`; neither suppresses `RAW_CLICK`.

## Root Discovery

### Native Viewscreen Root

Collect the current viewscreen's native widget container when one exists. Return it as `NATIVE_WIDGET_TREE` without traversal or adaptation.

Missing native-widget support on a viewscreen is not automatically an error. A malformed root advertised as present is unknown and fails closed.

### Current Lua Screen

Collect the current Lua screen or its documented root view as `LUA_VIEW` when it participates in the current input context. Do not infer Lua-screen ownership from unrelated module state.

If the screen exists but Core cannot identify a supported root boundary, collection reports unknown rather than silently omitting it.

### Active Overlay Roots

The overlay definition database is not an active-root list. Overlay roots must satisfy the same applicability conditions as DFHack overlay input dispatch:

- enabled state;
- current viewscreen applicability;
- current focus applicability;
- active state;
- visible state where visibility can safely be evaluated during collection.

The preferred implementation obtains roots from an authoritative active-overlay boundary. If DFHack exposes no such boundary, Core may use one isolated compatibility adapter that reproduces DFHack's predicates. That adapter requires contract tests across representative viewscreen and focus transitions.

Errors evaluating a context-inapplicable overlay do not affect the result because it should already have been excluded. Errors evaluating an applicable overlay produce unknown.

### Core-Registered Roots

Core-owned surfaces not represented by the current Lua screen or overlay roots should be registered explicitly. Registration carries a root kind and follows existing generation and reload ownership rules.

This remains an internal integration surface unless an external consumer requirement is demonstrated.

## Domain-Specific Hit Testing

### Lua and Overlay Views

Lua and overlay roots can use the existing pointer dispatcher where they conform to its supported `gui.View` contract. Visibility, active state, frames, descendant order, clipping, and pointer policy remain centralized there.

An exception while inspecting an applicable root produces `UNKNOWN`; it is not evidence of a miss.

### Native Widget Trees

Native traversal belongs in a dedicated hit tester. It must account for:

- `widget_container` child traversal and display order;
- native active and visible flags;
- widget rectangles;
- global versus parent-relative positioning;
- clipping or containment semantics exposed by DFHack;
- elements occupying screen space without accepting input;
- malformed or newly introduced widget variants.

The native hit tester traverses userdata directly and never converts the tree into synthetic `gui.View` objects. Its initial implementation must document which native properties establish obstruction. Unsupported semantics produce `UNKNOWN`, not an assumed miss.

## Input Pipeline Impact

The existing hook continues to capture each mouse input once and construct one immutable snapshot. Root resolution consumes that snapshot's immutable screen position.

The decision remains:

1. Non-mouse input produces neither click event.
2. A mouse input without a DFHack-reported map coordinate produces neither click event.
3. Otherwise, produce `RAW_CLICK` according to the parent interception and observation contract.
4. Resolve UI obstruction from the same snapshot.
5. Produce `MAP_CLICK` only when the aggregate result is unobstructed.

No second mouse-position or map-position lookup is permitted during resolution.

## Interception and Observation Impact

The public API remains one method per operation with the event type first:

```lua
api:intercept(event_type, callback)
api:observe(event_type, callback)
```

The design introduces no event-specific methods. `RAW_CLICK` and `MAP_CLICK` remain distinct deliveries derived from one physical mouse input.

The parent proposal must remain explicit about whether a `RAW_CLICK` interceptor prevents subsequent `MAP_CLICK` delivery or only downstream host input. This sub-proposal does not redefine that ordering.

## Failure and Diagnostics Impact

Internal diagnostics should distinguish:

- root collection failure;
- unsupported root kind;
- overlay applicability failure;
- native traversal failure;
- Lua-view traversal failure;
- positive obstruction.

Diagnostics may include root kind and stable identity. They must not retain mutable UI objects or expose root descriptors through public callbacks.

A single unknown decision suppresses that `MAP_CLICK`. Whether repeated unknown decisions affect service health must follow an explicit parent service-health rule rather than emerge accidentally from hit testing.

## Reload and Lifecycle Impact

- Root descriptors are per-input and do not survive reload.
- Hit testers are reload-managed modules in registry dependency order.
- Explicit Core-root registrations obey generation ownership and are retired consistently with existing service state.
- The established reload command and generation semantics do not change.
- Overlay and native roots are not reused after viewscreen or focus transitions without revalidation.

## Testing Impact

### Unit Tests

Add focused coverage for:

- tagged native, Lua, overlay, and Core descriptors;
- no recursive traversal during collection;
- disabled overlays excluded;
- viewscreen-inapplicable overlays excluded;
- focus-inapplicable overlays excluded;
- applicable malformed overlays producing unknown;
- native userdata delegated only to the native hit tester;
- Lua and overlay views delegated only to the generic resolver;
- `BLOCK` and `UNKNOWN` aggregation precedence;
- all-`MISS` as the only unobstructed result;
- immutable descriptors and enums;
- no roots retained across inputs or reload.

Test doubles declare their root kind explicitly. Their Lua runtime representation does not determine production dispatch.

### DwarfSpec Automation

Automation should establish independently that:

- an unobstructed mouse input with a map coordinate emits both events;
- an overlay obstruction emits `RAW_CLICK` but not `MAP_CLICK`;
- a Lua-screen obstruction emits `RAW_CLICK` but not `MAP_CLICK`;
- a native-widget obstruction emits `RAW_CLICK` but not `MAP_CLICK`;
- mouse inputs other than left and right buttons follow the same contract;
- interception and observation ordering remains consistent;
- cleanup is confirmed.

No tests are required for nonexistent event types.

### Overlay Compatibility Tests

If Core must reproduce DFHack overlay applicability predicates, tests cover representative viewscreen and focus transitions. These protect Core's compatibility boundary but do not replace DFHack's overlay tests.

## Packaging and Documentation Impact

- New production modules enter package verification.
- Module-registry tests cover dependency order and reload management.
- Contributor documentation describes supported root kinds and the fail-closed extension rule.
- Public consumer documentation describes event semantics rather than internal root machinery.

## Migration

1. Remove native-to-generic-view adaptation.
2. Introduce immutable root-kind and obstruction-result enums.
3. Return shallow tagged descriptors plus explicit collection status.
4. Place existing Lua resolution behind a kind-based obstruction resolver.
5. Implement native traversal as a separate hit tester.
6. Replace global overlay-database scanning with authoritative active-root discovery or one isolated compatibility adapter.
7. Add explicit Core-root registration only where another domain does not already expose the root.
8. Update unit and DwarfSpec coverage.
9. Reconcile accepted decisions into the parent proposal and todo.

## Alternatives Rejected

### Adapt Native Widgets into Generic Views

Rejected because it erases object-model boundaries, approximates native semantics, and obscures failures.

### Treat Every Enabled Overlay as Active

Rejected because enabled overlays can be inapplicable to the current viewscreen or focus and can contain invalid dynamic state outside their intended context.

### Ignore Uninspectable Roots

Rejected because this would emit `MAP_CLICK` without establishing that no supported UI element was in the way.

### Infer Root Kind from Lua Runtime Type

Rejected as the primary contract because userdata-versus-table checks make test representation affect semantics.

### Replace the Existing Input Hook

Rejected because existing evidence shows hook placement is not the obstruction-classification failure. Root discovery and hit testing can be corrected independently.

## Open Questions

1. Does DFHack expose an authoritative supported list of overlays participating in current input dispatch, or must Core maintain a compatibility adapter?
2. Which native widget flags and rectangle rules distinguish visible obstruction from non-interactive layout structure?
3. How are native global-positioning and parent-relative rectangles normalized for nested containers?
4. Can every current Lua-screen root be obtained through one supported API?
5. Which Core-owned roots, if any, are not already reachable through the Lua-screen or overlay domains?
6. Should repeated applicable-root inspection failures affect service health, and at what threshold?
7. What is the exact parent-contract ordering when a `RAW_CLICK` interceptor consumes the physical input before potential `MAP_CLICK` delivery?

## Acceptance Criteria

This direction is ready to merge into the parent proposal when:

- every supported UI domain has an explicit root kind;
- root collection is shallow and never adapts descendants;
- overlay applicability matches the actual current input context;
- native widgets have a dedicated documented hit-testing contract;
- unknown applicable state fails closed without allowing inapplicable roots to interfere;
- event payload, interception, observation, reload, and hook contracts remain unchanged;
- open questions affecting observable behavior are resolved in the parent proposal.
