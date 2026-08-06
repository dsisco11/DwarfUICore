# Input Event UI Root Resolution Sub-Proposal

## Status and Authority

This document proposes a replacement for the provisional UI-root adaptation approach explored while automating `MAP_CLICK` behavior. It refines the UI-obstruction and dispatch-order portions of the Input Event Service proposal without changing its public methods, event types, or payload contracts.

The parent proposal remains authoritative for externally observable behavior. Once this direction is approved, its accepted decisions must be reconciled into the parent proposal and implementation todo.

## Problem Statement

`RAW_CLICK` can be produced whenever a mouse input has a DFHack-reported map coordinate. DFHack's `getMousePos()` projects the pointer and validates the resulting world tile; it does not establish that native game UI or DFHack UI is absent from that screen position. Producing `MAP_CLICK` therefore additionally requires evidence that no supported UI element obstructed the pointer and that DFHack's overlay input path did not consume the input.

The provisional collector treated all discovered roots as though they shared the `gui.View` model. Native viewscreen widgets are DF userdata with different traversal, visibility, geometry, and positioning rules. Adapting them into synthetic `gui.View`-shaped tables inside root collection caused several problems:

- root discovery became coupled to recursive element traversal;
- native and Lua object models became indistinguishable after adaptation;
- test doubles could be mistaken for native widgets;
- native positioning and visibility semantics were approximated;
- adaptation failures did not identify which UI domain was uninspectable;
- enabled overlay definitions were confused with overlays applicable to the current viewscreen and focus.

The table-versus-userdata test failure was therefore a symptom of an incorrect responsibility boundary, not a reason to add a userdata special case.

## Goals

- Preserve fail-closed `MAP_CLICK` semantics for recognized, supported UI roots.
- Identify only UI roots applicable to the current input context.
- Preserve each root's object model and classify it explicitly.
- Resolve obstruction through a strategy appropriate to each root kind.
- Traverse native widgets with an explicit, test-backed positioning assumption.
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

### Native Positioning Is an Explicit Compatibility Assumption

DFHack's data definitions expose a native widget `parent`, `rect`, and `flag`, including `GLOBAL_POSITIONING`, but do not document the positioning algorithm further. Core interprets `GLOBAL_POSITIONING=true` as an absolute screen-space rectangle and otherwise treats the rectangle as parent-relative. This assumption is isolated in the native hit tester and protected by native automation.

### Delegation Results Supplement Geometry

Geometric hit testing applies each UI element's established pointer policy. `TARGET` and `BLOCKED` obstruct the map; `PASS`, `NONE`, and `MISS` do not. The existing overlay feed return separately establishes whether DFHack consumed the input. Neither signal replaces the other.

### Applicability Precedes Inspection

An overlay that does not apply to the current viewscreen or focus is not part of the current UI and must not suppress `MAP_CLICK`. An applicable root that cannot be inspected must suppress it.

### Unknown State Fails Closed

Core does not emit `MAP_CLICK` when a recognized, supported, applicable root cannot be inspected reliably. An unrecognized native widget is not inferred to be interactive and therefore does not become a blocker merely because it exists. Globally enabled but context-inapplicable roots must not enter the decision.

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

Descriptors are deduplicated by root object identity before hit testing. If the
same generic Lua root is discovered through multiple sources, the most
context-specific kind wins in this order: `OVERLAY_VIEW`, `LUA_VIEW`, then
`CORE_REGISTERED_VIEW`. Discovering one object under incompatible native and
Lua object-model kinds makes collection unknown rather than guessing a kind.
Deduplication preserves the root's effective front-to-back position and ensures
that each root is inspected at most once per input.

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

### Pointer Obstruction Classifier Hierarchy

Introduce an internal `PointerObstructionClassifier` base class that defines the
common classification boundary for every supported UI object model. Its
`invoke(root, screen_position)` method returns one canonical immutable
classification carrying `TARGET`, `BLOCKED`, `MISS`, or `UNKNOWN`, plus an
conditionally present neutral subject that is required for `TARGET` and
`BLOCKED`, plus a target-local position required for `TARGET`. `MISS` and
`UNKNOWN` carry neither field, as specified by the invariant table below.

The following is non-executable interface pseudocode; the implementation must
provide the validation and immutable-result factories described below.

```lua
---@enum PointerClassificationKind
PointerClassificationKind = {
    TARGET = 1,
    BLOCKED = 2,
    MISS = 3,
    UNKNOWN = 4,
}

---@class PointerClassification
---@field kind PointerClassificationKind
---@field subject unknown|nil Object classified as TARGET or BLOCKED.
---@field local_position Position2D|nil Target-local position populated only for TARGET.

---@class PointerObstructionClassifier
PointerObstructionClassifier = {}

---Safely classifies one root at an immutable screen position.
---@param root unknown
---@param screen_position Position2D
---@return PointerClassification
function PointerObstructionClassifier:invoke(root, screen_position)
    -- pseudocode: validate inputs, safely invoke _classify(), validate output,
    -- and return a canonical UNKNOWN classification for any failure
end

---Implements object-model-specific pointer classification.
---@protected
---@param root unknown
---@param screen_position Position2D
---@return PointerClassification
function PointerObstructionClassifier:_classify(root, screen_position)
    error('PointerObstructionClassifier:_classify must be implemented')
end
```

Canonical result invariants are exact:

| Classification kind | `subject` | `local_position` |
| --- | --- | --- |
| `TARGET` | Required | Required |
| `BLOCKED` | Required | Forbidden |
| `MISS` | Forbidden | Forbidden |
| `UNKNOWN` | Forbidden | Forbidden |

Both classifier subclasses can derive target-local coordinates from resolved
geometry. If a purported target cannot supply them, the result is invalid and
`invoke()` converts it to `UNKNOWN`.

The base class owns the result contract and common validation only. It does not
infer an object model from Lua runtime type. Callers never invoke the protected
overridable `_classify()` method directly. The public final-style non-throwing
`invoke()` boundary validates arguments, contains subclass exceptions, validates
the returned classification, records internal failure diagnostics, and returns
`UNKNOWN` for every failure. Both the root-kind obstruction resolver and
`PointerDispatcher` must use this boundary, ensuring identical failure
transport.

Two initial subclasses implement the model-specific logic:

- `GuiViewPointerObstructionClassifier` owns `gui.View` activity, visibility,
  geometry, clipping, reverse descendant traversal, and `PointerPolicy` logic;
- `NativeUiPointerObstructionClassifier` owns native widget traversal,
  positioning, visibility flags, and the exact-type interaction compatibility
  registry.

The root-kind obstruction resolver selects the classifier explicitly from
`UiRootKind`, invokes it once, and maps `TARGET` and `BLOCKED` to obstruction,
`MISS` to no obstruction, and `UNKNOWN` to fail-closed suppression.

The existing `PointerDispatcher` ceases to own `gui.View` obstruction logic.
Its `resolve(root, screen_position)` operation delegates to
`GuiViewPointerObstructionClassifier` and returns the canonical
`PointerClassification` directly. The former `PointerResultKind` enum and
per-axis result `x` and `y` fields are retired; every direct consumer migrates
to `PointerClassificationKind` and immutable `local_position`.

`PointerDispatcher.sample()` retains optional coordinate sampling,
current-target state, and pointer enter, leave, and update lifecycle dispatch.
It creates one immutable `Position2D`, delegates classification, and unpacks
`local_position` only when invoking the established lifecycle callback
signatures. This keeps tooltip and context-menu callback behavior compatible
without retaining a second result shape.

An `UNKNOWN` classification has channel-specific meaning. The obstruction
resolver fails closed for the current `MAP_CLICK`. Continuous
`PointerDispatcher.sample()` treats it as an indeterminate sample: it records
the classification, preserves the previous target, and emits no enter, leave,
or update callback. The next determinate sample compares against that preserved
target normally.

For determinate continuous samples, only `TARGET` assigns
`context.target = classification.subject`. `BLOCKED` and `MISS` clear the
current lifecycle target and emit `on_pointer_leave` when applicable. A blocking
subject is retained in the classification for diagnostics but never becomes a
pointer lifecycle target.

An unavailable or incomplete pointer sample does not reach classifier
invocation and is not `UNKNOWN`. It produces a determinate `MISS`, clears the
current target, and emits `on_pointer_leave` when a previous target exists,
preserving existing continuous-pointer behavior. `UNKNOWN` is reserved for a
failure after a valid root and `Position2D` reach `invoke()`.

## Root Discovery

### Native Viewscreen Root

Collect the current viewscreen's native widget container as `NATIVE_WIDGET_TREE` without adapting it into a synthetic `gui.View`.

Missing native-widget support on a viewscreen is not automatically an error. A malformed root advertised as present is unknown and fails closed.

### Current Lua Screen

Collect the current Lua screen or its documented root view as `LUA_VIEW` when it participates in the current input context. Do not infer Lua-screen ownership from unrelated module state.

If the screen exists but Core cannot identify a supported root boundary, collection reports unknown rather than silently omitting it.

### Active Overlay Roots

The overlay definition database is not an active-root list. DFHack's authoritative `active_viewscreen_widgets` mapping is private to `plugins.overlay`; `get_state()` exposes only the complete definition database. Core therefore uses one isolated compatibility adapter. Overlay roots must satisfy the same applicability conditions as DFHack overlay input dispatch:

- enabled state;
- current viewscreen applicability;
- current focus applicability;
- active state; and
- visible state.

The adapter receives the same `vs_name` and native viewscreen supplied to `feed_viewscreen_widgets`, starts from enabled definitions, and applies viewscreen and focus matching. It does not evaluate dynamic `active` or `visible` values. For roots that pass those context predicates, the existing pointer classifier remains the sole owner of active and visible evaluation and evaluates each value once during geometric resolution. Together these stages reproduce DFHack's applicability predicates without duplicating pointer-classification responsibilities. The adapter requires contract tests across representative viewscreen and focus transitions.

This filtering is required for correctness, not optimization. A globally enabled overlay can target another viewscreen or focus mode. Treating it as current UI can execute dynamic state outside its valid context, falsely suppress `MAP_CLICK`, or raise an error such as the observed caravan overlay failure when no caravan exists.

Errors evaluating a context-inapplicable overlay do not affect the result because it should already have been excluded. Pointer-classifier errors while evaluating an applicable overlay's active or visible state produce unknown.

### Core-Registered Roots

Core-owned surfaces not represented by the current Lua screen or overlay roots are registered explicitly. The current integration sources are the input manager's context roots and the priority consumer's optional root. Registration carries `CORE_REGISTERED_VIEW` and follows existing generation and reload ownership rules.

This remains an internal integration surface unless an external consumer requirement is demonstrated.

## Domain-Specific Hit Testing

### Lua and Overlay Views

Lua and overlay roots use `GuiViewPointerObstructionClassifier` where they conform to its supported `gui.View` contract. That classifier is the sole owner of active state, visibility, frames, descendant order, clipping, and pointer-policy evaluation. Each dynamic value is evaluated at most once per root or descendant during one geometric-resolution pass. `PointerDispatcher` delegates to the same classifier instead of maintaining a second implementation.

An exception while inspecting an applicable root produces `UNKNOWN`; it is not evidence of a miss.

### Native Widget Trees

Native traversal belongs in `NativeUiPointerObstructionClassifier`. It must account for:

- `widget_container` child traversal and display order;
- native active and visible flags, including ancestor visibility;
- widget rectangles;
- clipping or containment semantics exposed by DFHack;
- recognition of widget classes and flags that reasonably imply normal input interaction.

The native hit tester traverses userdata directly and never converts the tree into synthetic `gui.View` objects. It computes absolute geometry as follows:

- a root begins in absolute screen space;
- `GLOBAL_POSITIONING=true` makes that widget's `rect` absolute screen space;
- otherwise, the widget's `rect` origin is relative to its parent's resolved absolute origin;
- malformed ancestry, flags, or geometry on a recognized interactive widget produce `UNKNOWN`.

Native hit testing must map recognized interactive native widget behavior onto the established generic pointer-policy outcomes. A widget obstructs `MAP_CLICK` only when Core has an educated, documented basis for treating that widget class or flag combination as normally interactive and resolution produces `TARGET` or `BLOCKED`; `PASS`, `NONE`, and `MISS` remain non-obstructing. An absent native widget root, an unrecognized widget variant, or occupied native geometry with no recognized interaction signal resolves as `MISS`. This is an intentionally approximate compatibility policy: Core does not inspect native game input logic and must not infer interaction from visibility alone.

The native compatibility registry stores `PointerPolicy` values; it does not
store `PointerClassificationKind`. Policy describes configured traversal and
ownership behavior, while classification describes the outcome at one resolved
coordinate. The native classifier applies the same policy semantics as the GUI
classifier:

- `TARGET` produces canonical `TARGET` only when the eligible widget contains
  the pointer; otherwise it produces `MISS`;
- `PASS` traverses eligible descendants and produces their result or `MISS`;
- `BLOCK` traverses eligible descendants first, then produces `BLOCKED` when
  the widget's blocking region contains the pointer, or `MISS` otherwise; and
- `NONE` produces `MISS` without traversing descendants.

The initial native compatibility table is:

| Native signal | Registry policy or classification behavior | Rationale |
| --- | --- | --- |
| A button-family widget | `TARGET` | Native definitions explicitly identify these as button controls. The initial exact-type set is `widget_better_button`, `widget_interface_main_button`, `widget_interface_pets_livestock_button`, `widget_interface_small_button`, `widget_item_sheet_button`, `widget_job_details_button`, `widget_recenter_button`, `widget_sheet_button`, and `widget_unit_sheet_button`. |
| A recognized selection or editing control | `TARGET` | These controls normally own selection, navigation, scrolling, sorting, or text input. The initial exact-type set is `widget_dropdown`, `widget_filter`, `widget_folder`, `widget_menu`, `widget_radio_rows`, `widget_scroll_rows`, `widget_sort_widget`, `widget_table`, `widget_tabs`, `widget_textbox`, `widget_unit_list`, and `widget_unit_sort_widget`. |
| A widget with `CAN_KEY_ACTIVATE` and no exact registry entry | `TARGET` fallback policy | This is the available native indication that the widget participates in activation, although Core cannot prove the exact mouse path. |
| A recognized structural container | `PASS` | The initial exact-type set is `widget_container`, `widget_columns_container`, `widget_params_container`, `widget_rows_container`, and `widget_stack`. These widgets do not claim the pointer, but their descendants remain eligible. |
| A recognized presentation-only widget | `NONE` | The initial exact-type set is `widget`, `widget_anchored_tile`, `widget_character`, `widget_creature_portrait`, `widget_graphics_switcher`, `widget_item_name`, `widget_item_portrait`, `widget_keybinding_display`, `widget_nineslice`, `widget_nineslice_horizontal`, `widget_text`, `widget_text_multiline`, `widget_text_truncated`, `widget_unit_name`, and `widget_unit_portrait`. These widgets neither claim the pointer nor expose eligible descendants. |
| An unrecognized concrete widget type or recognized widget without an interaction signal | Self resolves as `MISS`; supported container descendants remain traversable | Core does not infer mouse interaction from visibility or occupied geometry alone, but an unrecognized container must not hide recognized interactive descendants. |
| A recognized interactive widget whose activity, visibility, ancestry, rectangle, or clipping cannot be inspected | `UNKNOWN` | Core identified a likely input owner but cannot determine whether it contains the pointer. |

This table is implemented as an immutable exact-concrete-type registry whose values are `PointerPolicy` members. Exact-type lookup runs before the separate `CAN_KEY_ACTIVATE` fallback rule. No inheritance or name-pattern matching is permitted for self-policy classification. Types absent from the registry and lacking that flag cannot claim or block the pointer and therefore resolve themselves as canonical `MISS`.

Structural fallback traversal is a separate capability check used only when a concrete type has no exact registry entry and no `CAN_KEY_ACTIVATE` fallback. If that otherwise-unclassified object exposes the supported native `widget_container` child interface, the native classifier traverses its children in display order as it would for `PASS` while the container itself remains `MISS`. Exact registry policy always takes precedence, so registered `TARGET` and `NONE` widgets retain their terminal semantics, and the activation fallback retains `TARGET` semantics. This capability check does not classify the container as interactive and does not use inheritance to select a pointer policy. `UNKNOWN` is produced by failed inspection, not stored in the registry. The registry is an isolated compatibility policy, not a claim about exact native game logic. New native widget types remain self-`MISS` until source evidence or native automation justifies adding them. Changes to the table require focused unit coverage and representative DwarfSpec automation.

## Input Pipeline Impact

The existing hook continues to capture each mouse input once and construct one immutable snapshot. Root resolution consumes that snapshot's immutable screen position.

The trampoline captures root descriptors and geometric obstruction before invoking its predecessor so input-driven UI mutations cannot change the meaning of the current snapshot. The decision is:

1. Non-mouse input produces neither click event.
2. A mouse input without a DFHack-reported map coordinate produces neither click event.
3. Capture applicable roots and resolve geometric obstruction from the immutable snapshot.
4. Dispatch `RAW_CLICK` according to the parent interception and observation contract.
5. If a `RAW_CLICK` interceptor consumes the input, stop: do not invoke the predecessor, dispatch `MAP_CLICK`, or delegate to the native game.
6. Invoke the existing overlay-feed predecessor once and retain its consumed result.
7. If the predecessor consumed the input, suppress `MAP_CLICK` and return consumed to DFHack.
8. If geometric resolution is `BLOCK` or `UNKNOWN`, suppress `MAP_CLICK` and preserve the predecessor's pass result.
9. Otherwise, dispatch `MAP_CLICK` interception and observation.
10. Return consumed if a `MAP_CLICK` interceptor consumed; otherwise return pass so DFHack can delegate to the native game.

No second mouse-position or map-position lookup is permitted during resolution.

## Interception and Observation Impact

The public API remains one method per operation with the event type first:

```lua
api:intercept(event_type, callback)
api:observe(event_type, callback)
```

The design introduces no event-specific methods. `RAW_CLICK` and `MAP_CLICK` remain distinct deliveries derived from one physical mouse input and are dispatched in that order.

Consuming `RAW_CLICK` consumes the physical input as a whole: later `RAW_CLICK` interceptors, all `MAP_CLICK` interceptors and observers, the overlay predecessor, and native game delegation are skipped. This prevents the confusing result where a consumed raw input still appears as a semantic map click.

If `RAW_CLICK` is not consumed, the overlay predecessor runs before `MAP_CLICK` delivery so Core can use its consumed result. Therefore `MAP_CLICK` interception cannot prevent DFHack overlays from seeing the input; it occurs only after those overlays have declined to consume it. A `MAP_CLICK` interceptor can still prevent subsequent native game delegation. Consuming `MAP_CLICK` cannot retroactively affect completed `RAW_CLICK` delivery or the predecessor call.

No second trampoline is required. The existing trampoline performs pre-delegation snapshot and `RAW_CLICK` work, invokes its predecessor exactly once, then performs post-delegation `MAP_CLICK` work.

`RAW_CLICK` observers run after either raw consumption or predecessor completion and before any `MAP_CLICK` callbacks. `MAP_CLICK` observers run after its interceptor decision. Since native game `feed()` executes in C++ only after the Lua trampoline returns, observation is post-Core and post-DFHack-overlay processing, not post-native-game processing. The public documentation must state this boundary explicitly.

## Failure and Diagnostics Impact

Internal diagnostics should distinguish:

- root collection failure;
- unsupported root kind;
- overlay applicability failure;
- native traversal or positioning failure;
- Lua-view traversal failure;
- positive obstruction.

Diagnostics may include root kind and stable identity. They must not retain mutable UI objects or expose root descriptors through public callbacks.

A single unknown root-resolution decision suppresses only that input's `MAP_CLICK`. Dynamic host UI state does not transition the service to unhealthy and no failure-count threshold is used. Service health changes remain reserved for structural service failures already defined by the parent contract.

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
- `GLOBAL_POSITIONING` rectangles resolved as absolute;
- other native rectangles accumulated from parent origins;
- malformed native ancestry or geometry on a recognized interactive widget producing unknown;
- unrecognized native widget variants and noninteractive occupied geometry producing miss;
- disabled overlays excluded;
- viewscreen-inapplicable overlays excluded;
- focus-inapplicable overlays excluded;
- applicable malformed overlays producing unknown;
- dynamic overlay active and visible values evaluated exactly once by the pointer classifier;
- the classifier base contract and canonical immutable result validation;
- exact canonical `subject` and `local_position` invariants for every classification kind;
- native registry policy values mapped to canonical classification outcomes;
- structural `PASS` traversal remaining distinct from presentation-only `NONE`;
- recognized interactive descendants remaining discoverable through unregistered native containers;
- subclass exceptions and invalid results converted to `UNKNOWN` by the shared invocation boundary;
- `TARGET` and `BLOCKED` carrying `subject`, with only `TARGET` carrying `local_position`;
- GUI-view and native roots dispatched to their explicit classifier subclasses;
- `PointerDispatcher.resolve()` delegating to the GUI-view classifier;
- `PointerDispatcher.sample()` retaining enter, leave, and update lifecycle behavior after extraction;
- `PointerDispatcher.sample()` preserving its current target and emitting no lifecycle transition for `UNKNOWN`;
- only `TARGET` assigning the classification subject as the lifecycle target;
- `BLOCKED` and `MISS` clearing the lifecycle target normally;
- unavailable or incomplete pointer samples producing `MISS` and the existing leave transition;
- callers using public `invoke()` and subclasses overriding only protected `_classify()`;
- canonical immutable `local_position` replacing result `x` and `y` fields;
- retirement of `PointerResultKind` in favor of `PointerClassificationKind`;
- no duplicate GUI-view obstruction implementation remaining in `PointerDispatcher`;
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
- representative recognized native button and selection controls suppress `MAP_CLICK` when hit;
- representative visible structural or presentation-only native widgets do not suppress `MAP_CLICK`;
- a visible DFHack element with `PASS` or `NONE` pointer policy emits both events;
- a visible DFHack element with `TARGET` or `BLOCKED` pointer policy emits `RAW_CLICK` but not `MAP_CLICK`;
- DFHack overlay consumption suppresses `MAP_CLICK` even when geometric resolution misses;
- mouse inputs other than left and right buttons follow the same contract;
- interception and observation ordering remains consistent;
- consuming `RAW_CLICK` prevents `MAP_CLICK` delivery and host delegation;
- consuming `MAP_CLICK` prevents native game delegation after overlays have declined the input;
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

1. Keep native-to-generic-view adaptation removed.
2. Implement heuristic native traversal that fails closed for recognized interactive widgets, resolves unrecognized widgets as misses, and isolates the `GLOBAL_POSITIONING` assumption.
3. Introduce immutable root-kind and obstruction-result enums.
4. Return shallow tagged descriptors plus explicit collection status.
5. Introduce the classifier base contract and canonical immutable classification result.
6. Extract GUI-view obstruction logic from `PointerDispatcher` into `GuiViewPointerObstructionClassifier`, retaining dispatcher sampling and pointer lifecycle behavior.
7. Replace `PointerResultKind` and legacy result coordinate fields with the canonical classification enum and immutable `local_position`.
8. Migrate every direct classification consumer: tooltip target detection, context-menu target detection, Input Event UI-obstruction resolution, pointer tests, and their service-specific tests.
9. Implement `NativeUiPointerObstructionClassifier` with the native geometry and exact-type compatibility policies.
10. Place both classifiers behind the kind-based obstruction resolver.
11. Replace indiscriminate overlay-database scanning with one isolated compatibility adapter matching DFHack's feed predicates.
12. Deduplicate roots by object identity and reject incompatible duplicate kinds.
13. Tag existing context and priority-consumer roots as explicit Core roots.
14. Split the existing trampoline into pre-predecessor and post-predecessor processing without adding another hook.
15. Update unit and DwarfSpec coverage, including predecessor-consumption and click-consumption ordering.
16. Reconcile accepted decisions into the parent proposal and todo.

## Alternatives Rejected

### Adapt Native Widgets into Generic Views

Rejected because it erases object-model boundaries, approximates native semantics, and obscures failures.

### Use Map Viewport Containment for Native UI

Rejected because native game UI and DFHack UI can render over the gameplay map. Viewport containment does not establish that no UI element is in the way.

### Use Overlay Consumption as the Only Occlusion Signal

Rejected because geometric pointer-policy resolution and actual overlay input consumption are distinct signals. The predecessor result supplements geometric hit testing rather than replacing it.

### Add a Second Post-Input Trampoline

Rejected because one wrapper can perform work before and after its predecessor call. A second hook would add ownership and reload complexity without exposing native game consumption, which occurs later in C++.

### Treat Every Enabled Overlay as Active

Rejected because enabled overlays can be inapplicable to the current viewscreen or focus and can contain invalid dynamic state outside their intended context.

### Ignore Uninspectable Roots

Rejected because this would emit `MAP_CLICK` without establishing that no supported UI element was in the way.

### Infer Root Kind from Lua Runtime Type

Rejected as the primary contract because userdata-versus-table checks make test representation affect semantics.

### Replace the Existing Input Hook

Rejected because existing evidence shows hook placement is not the obstruction-classification failure. Root discovery and hit testing can be corrected independently.

## Resolved Questions

1. DFHack does not expose its private active-overlay mapping, so Core uses one compatibility adapter matching the overlay feed predicates.
2. Native widget interactivity is approximated from recognized widget classes and flags; unrecognized or merely visible native geometry does not count as obstruction.
3. `GLOBAL_POSITIONING` is treated as absolute screen space and other widget origins are accumulated from their parents.
4. The current Lua-screen root is the hooked `Screen:onInput` receiver; no separate global lookup is required.
5. Additional Core roots are the existing context roots and priority consumer root, tagged explicitly.
6. Unknown dynamic UI state suppresses only the current `MAP_CLICK` and does not use an unhealthy threshold.
7. `RAW_CLICK` consumption prevents predecessor invocation, subsequent `MAP_CLICK` delivery, and native game delegation. `MAP_CLICK` occurs only after DFHack overlays decline the input.
8. Overlay viewscreen and focus applicability is resolved by the compatibility adapter, while the existing pointer classifier evaluates dynamic active and visible values exactly once during hit testing.
9. Duplicate root objects are inspected once, with incompatible object-model kinds producing unknown.
10. One `PointerObstructionClassifier` contract governs GUI-view and native classification; `PointerDispatcher` retains sampling and lifecycle responsibilities but delegates GUI-view obstruction classification.
11. All direct resolver consumers use the canonical classification enum, neutral subject, and immutable local position; no legacy result shape remains.
12. Classifier exceptions and invalid results are contained by the shared invocation boundary and become `UNKNOWN` for both obstruction and continuous sampling.
13. An indeterminate continuous sample preserves the current pointer target and emits no lifecycle transition, while an indeterminate obstruction decision suppresses only the current `MAP_CLICK`.
14. An unavailable pointer sample remains a determinate miss and preserves existing pointer-leave behavior.
15. Only a `TARGET` subject becomes the continuous lifecycle target; blocking subjects remain diagnostic classification data.

## Acceptance Criteria

This direction is ready to merge into the parent proposal when:

- every supported UI domain has an explicit root kind;
- every supported root kind selects a `PointerObstructionClassifier` subclass through the root-kind resolver;
- GUI-view obstruction behavior has one implementation shared by the resolver and `PointerDispatcher`;
- every direct pointer-resolution consumer uses PointerClassification with neutral subject and immutable local_position, without legacy enum or per-axis result fields;
- every classifier call crosses the shared non-throwing invocation boundary;
- unavailable pointer coordinates produce a determinate miss before classifier invocation;
- classifier callers use public `invoke()` and subclasses override only protected `_classify()`;
- `UNKNOWN` has explicit fail-closed map-obstruction behavior and non-transitioning continuous-pointer behavior;
- root collection is shallow and never adapts descendants;
- overlay applicability matches the actual current input context;
- native positioning follows the isolated `GLOBAL_POSITIONING` compatibility contract;
- unknown state for a recognized applicable root fails closed without treating unrecognized native widgets as hits or allowing inapplicable roots to interfere;
- public methods, event payloads, reload behavior, and hook ownership remain unchanged, while the revised RAW/predecessor/MAP callback ordering is reconciled into the parent contract;
- open questions affecting observable behavior are resolved in the parent proposal.
