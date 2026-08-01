# DwarfUICore Namespaced Service Provider Proposal

## Status

Proposed and unimplemented. The repository split is complete, but this document
defines a future public service-provider contract only. It does not implement
providers, namespaces, composite identities, exact service-contract version
negotiation, immutable service APIs, or migration of consumer plugins.

## Decision summary

DwarfUICore now owns the process-wide tooltip, context-menu, pointer,
registration, and presentation infrastructure extracted from DwarfUI. This
proposal defines a later provider and namespace layer over that current system.

DwarfUICore exposes one public root module and one explicitly named provider
class per supported service. Every provider construction requires both an exact
integer contract major and the stable namespace of the consuming plugin:

```lua
local dwarfuiCore = reqscript('dwarfuicore')

local tooltipService =
    dwarfuiCore.services.TooltipServiceProvider:new(1, 'dwarfdirect')

tooltipService:register(widget)
```

Context menus use the parallel provider:

```lua
local dwarfuiCore = reqscript('dwarfuicore')

local contextMenuService =
    dwarfuiCore.services.ContextMenuServiceProvider:new(1, 'dwarfdirect')

contextMenuService:register(widget, definition)
```

The returned object is a namespace-bound service API. Consumers never pass a
namespace to individual service methods and cannot use the object to operate on
another namespace.

There is no global `get()` function, public service discriminator, string
service name, consumer-visible module registry, or automatic development
reload.

## Proposed project boundary

### DwarfUICore owns

The proposed provider layer would assign DwarfUICore these public concerns in
addition to its current reusable process-wide infrastructure:

- the public `dwarfuicore` dependency entry point;
- typed service providers and namespace-bound service APIs;
- consumer namespace validation and composite identity allocation;
- widget-extension contracts needed by core services;
- pointer sampling, projection, root discovery, and arbitration used by core
  services;
- tooltip registration, targeting, mediation, presentation, and hooks;
- context-menu registration, targeting, mediation, presentation, input, and
  hooks;
- process-wide singleton state and service health;
- service contract negotiation and installation-coherence validation; and
- the explicit DwarfUICore development reload command.

The extraction must include the transitive dependencies that these systems own.
Internal module paths are selected during implementation and are not public
contracts.

### DwarfUI retains

DwarfUI remains the higher-level component and feature library. It currently
retains:

- reusable visual components such as asset buttons and hover-action rails;
- popovers and feature-specific view models;
- UI hotkeys and feature overlays;
- minecart, mood, and unit-card integrations; and
- other feature-specific behavior that consumes core services.

DwarfUI will become a normal DwarfUICore provider consumer only when this
proposal is approved and implemented. Its future core service handles would
use the stable namespace `dwarfui`.

External plugin migration is separate future work. A migrated plugin would
depend directly on DwarfUICore rather than DwarfUI's internal layout or
initialization.

## Proposed public root contract

Nothing in this contract exists in the repository today. In particular,
`dwarfuicore.services`, the provider classes, `new(version, namespace)`,
namespace-bound service APIs, and their collision and lifecycle rules are all
unimplemented. The current module entrypoints are documented in the repository
README and remain separate from this proposal.

The root module exports a closed, read-only `services` namespace:

```lua
local dwarfuiCore = reqscript('dwarfuicore')

local tooltipProvider = dwarfuiCore.services.TooltipServiceProvider
local contextMenuProvider = dwarfuiCore.services.ContextMenuServiceProvider
```

The provider names are public compatibility contracts. Internal module paths,
registry entries, load order, implementation classes, and facade module
identity are not.

The namespace is implemented as an empty proxy with private backing storage so
assignment cannot replace an existing provider export. Consumers cannot add or
register provider types.

## Consumer namespace contract

A consumer namespace is a stable identifier for one plugin's ownership domain.
It is not a display label and must not change between entrypoints, saves, or
releases merely because implementation files move.

Namespace validation requires:

- a Lua string between 1 and 64 bytes;
- lowercase ASCII letters, digits, hyphens, underscores, and periods only;
- a leading lowercase ASCII letter;
- no leading, trailing, or repeated period;
- exact byte-for-byte comparison after validation, with no implicit case or
  punctuation normalization.

Recommended namespaces are the canonical DFHack plugin or mod identifier, such
as `dwarfui`, `dwarfdirect`, or `author.plugin-name`.

Namespaces are ownership boundaries, not security principals. DFHack cannot
prove which script called a Lua function. Two independently authored plugins
that deliberately claim the same namespace will share that namespace's state.
Documentation must instruct authors to choose a unique stable identifier.

DwarfUICore does not reserve, allocate, register, or globally claim namespace
strings. It validates their syntax only. Any consumer can request any valid
namespace, and no separate namespace-acquisition step exists.

Multiple scripts and entrypoints belonging to the same plugin should reuse the
same namespace. They receive separate API objects but intentionally share the
namespace's registrations and identity sequence.

### How namespaces affect runtime behavior

The namespace is bound once when a provider constructs an API object and is
stored in that object's private backing record. Service methods do not accept a
namespace argument; they delegate with the bound value automatically.

The namespace partitions ownership inside a shared service rather than creating
a service instance:

- all namespaces for one service use the same process-wide backend, hooks,
  presenter, pointer infrastructure, and health state;
- widget registrations are keyed by `(namespace, widget)`;
- map registrations receive opaque handles whose private ownership includes the
  namespace;
- composite registration identities retain the namespace through detection,
  presentation, callback dispatch, update, removal, and diagnostics;
- API objects for the same service and namespace intentionally share
  registrations, while different namespaces cannot update, remove, or inspect
  one another's registrations;
- using the same namespace for tooltip and context-menu APIs does not merge the
  two services' state; service kind remains part of identity and ownership;
- `clear_namespace()` clears only the bound service and namespace; and
- dropping an API object performs no cleanup because ownership belongs to the
  namespace, not to one handle object.

When different namespaces contribute to the same target, the service's
versioned collision rule applies: tooltip contributions compete by registration
sequence, while context-menu contributions compose in registration order.
Explicit DwarfUICore reload invalidates all namespaces in the retired runtime
generation. A consumer-specific reload clears and rebuilds only that consumer's
namespace.

## Provider construction contract

Provider construction has this common signature:

```lua
---Creates a namespace-bound service API for an exact contract major.
---@param contractVersion integer
---@param consumerNamespace string
---@return dwarfuicore.TooltipServiceApi
function TooltipServiceProvider:new(contractVersion, consumerNamespace)
end
```

Both arguments are mandatory. Construction rejects a missing, non-integer,
zero, negative, or unsupported contract version. It also rejects an invalid
consumer namespace.

The requested contract version is exact. `new(1, namespace)` never silently
binds to contract 2. An installed implementation may support multiple majors
through separate internal adapters, but it must reject any major for which it
cannot provide the complete documented contract.

Construction raises a Lua error with a stable prefix:

```text
DwarfUICore TooltipServiceProvider: <reason>
DwarfUICore ContextMenuServiceProvider: <reason>
```

Consumers that want recoverable dependency handling use `pcall`. Constructors
do not return `nil, error` and do not call `qerror()`.

## Namespace-bound service APIs

Each `new()` call returns a distinct immutable API object. The object contains
no authoritative runtime or registration state. Private backing storage records:

- the validated service facade;
- the exact contract major;
- the consumer namespace; and
- the active DwarfUICore runtime generation.

Every public method validates the generation before delegating. An API object
from a retired development generation raises a clear stale-handle error.

Consumers cannot attach fields, replace methods, inspect the private facade, or
change the bound namespace. This makes future additive methods compatible and
prevents one consumer from mutating another consumer's API object.

API objects are non-owning namespace handles. They are not namespace leases,
are not reference counted, and expose no `close()` or `release()` operation.
Garbage collection of an API object never changes registration state.

### Tooltip service API version 1

```lua
---Provides namespace-scoped access to the shared tooltip runtime.
---@class dwarfuicore.TooltipServiceApi

---Returns the exact contract major implemented by this API object.
---@return integer
function TooltipServiceApi:get_contract_version()
end

---Returns the consumer namespace permanently bound to this API object.
---@return string
function TooltipServiceApi:get_namespace()
end

---Registers a widget in this API object's namespace.
---@param widget gui.View
---@return boolean created
function TooltipServiceApi:register(widget)
end

---Unregisters this namespace's registration for a widget.
---@param widget gui.View
---@return boolean removed
function TooltipServiceApi:unregister(widget)
end

---Registers one exact map tile in this API object's namespace.
---@param options dwarfuicore.MapTileTooltipRegistrationOptions
---@return dwarfuicore.MapTileTooltipRegistration
function TooltipServiceApi:register_map_tile(options)
end

---Updates this namespace's exact map-tile registration atomically.
---@param handle dwarfuicore.MapTileTooltipRegistration
---@param update dwarfuicore.MapTileTooltipUpdate
---@return boolean updated
function TooltipServiceApi:update_map_tile(handle, update)
end

---Removes this namespace's exact map-tile registration.
---@param handle dwarfuicore.MapTileTooltipRegistration
---@return boolean removed
function TooltipServiceApi:unregister_map_tile(handle)
end

---Removes every tooltip registration owned by this namespace.
---@return boolean changed
function TooltipServiceApi:clear_namespace()
end

---Returns copied diagnostics restricted to this namespace and shared health.
---@return dwarfuicore.TooltipNamespaceDiagnostics
function TooltipServiceApi:get_diagnostics()
end
```

### Context-menu service API version 1

```lua
---Provides namespace-scoped access to the shared context-menu runtime.
---@class dwarfuicore.ContextMenuServiceApi

---Returns the exact contract major implemented by this API object.
---@return integer
function ContextMenuServiceApi:get_contract_version()
end

---Returns the consumer namespace permanently bound to this API object.
---@return string
function ContextMenuServiceApi:get_namespace()
end

---Registers or replaces this namespace's widget menu contribution.
---@param widget gui.View
---@param definition dwarfuicore.ContextMenuDefinition
---@return boolean created
function ContextMenuServiceApi:register(widget, definition)
end

---Updates this namespace's existing widget menu contribution.
---@param widget gui.View
---@param definition dwarfuicore.ContextMenuDefinition
---@return boolean updated
function ContextMenuServiceApi:update(widget, definition)
end

---Removes this namespace's widget menu contribution.
---@param widget gui.View
---@return boolean removed
function ContextMenuServiceApi:unregister(widget)
end

---Registers one exact map-tile menu contribution in this namespace.
---@param options dwarfuicore.ContextMenuMapRegistrationOptions
---@return dwarfuicore.ContextMenuMapRegistration
function ContextMenuServiceApi:register_map_tile(options)
end

---Updates this namespace's exact map-tile menu contribution atomically.
---@param handle dwarfuicore.ContextMenuMapRegistration
---@param update dwarfuicore.ContextMenuMapRegistrationUpdate
---@return boolean updated
function ContextMenuServiceApi:update_map_tile(handle, update)
end

---Removes this namespace's exact map-tile menu contribution.
---@param handle dwarfuicore.ContextMenuMapRegistration
---@return boolean removed
function ContextMenuServiceApi:unregister_map_tile(handle)
end

---Removes every context-menu registration owned by this namespace.
---@return boolean changed
function ContextMenuServiceApi:clear_namespace()
end

---Returns copied diagnostics restricted to this namespace and shared health.
---@return dwarfuicore.ContextMenuNamespaceDiagnostics
function ContextMenuServiceApi:get_diagnostics()
end
```

All referenced option, update, handle, definition, and diagnostic types are
public versioned data contracts and must receive complete LuaDoc definitions in
the implementation. Registration handles are opaque immutable values.

## Composite identity and ownership

Every registration identity is allocated by DwarfUICore and contains, at
minimum:

```text
runtime generation + service kind + consumer namespace + local identity
```

The composite identity remains internal unless represented by an opaque public
handle. A consumer never supplies its own local identity.

All lookup, update, removal, diagnostics, presentation callbacks, and stale
checks retain the namespace component. A service API rejects a handle issued to
a different namespace, service kind, contract major, or runtime generation.

Widget registrations are keyed by `(namespace, widget)`, not by widget alone:

- repeated registration of the same widget in the same namespace is
  idempotent;
- different namespaces may register the same widget independently;
- unregistering through one namespace never removes another namespace's
  registration; and
- `clear_namespace()` affects only the service and namespace bound to the API
  object.

Map registrations are independently owned opaque handles and follow the same
namespace rules.

### Registration lifetime and consumer lifecycle

Individual registrations retain the existing weak lifetime model:

- a widget registration is removed when its weak widget key is collected;
- a map registration is removed when its opaque handle is collected;
- DwarfUICore must not keep a widget or map handle alive merely because it is
  registered; and
- explicit `unregister()` and `unregister_map_tile()` remain available for
  immediate deterministic removal.

The weak indexes and any secondary detection indexes must preserve this
contract even when registration values contain plugin callbacks or other
objects that refer back to the widget, handle, or plugin environment.

Dropping an API object does not remove registrations. This supports multiple
entrypoints in one plugin and avoids garbage collection changing namespace
ownership. DwarfUICore does not infer that a Lua consumer has unloaded from API
object reachability, script-environment clearing, overlay rescanning, map/world
unload, or garbage collection.

Namespace-wide cleanup is explicit through `clear_namespace()`. A consumer
that implements reload, disable, teardown, or an applicable save/map/world
lifecycle handler calls `clear_namespace()` for each service it owns before
discarding or rebuilding its registrations. Map or world unload is not itself a
generic consumer-unload event; consumers decide whether their own namespace
state should survive that boundary.

Explicit `dwarfuicore reload` remains the only operation that retires every
namespace and registration in the active core generation.

## Physical target selection and contribution resolution

Target selection and namespace contribution resolution are separate steps.
Namespaces partition ownership but never change hit-testing geometry, render
order, blocking behavior, widget-over-map precedence, or root precedence.

DwarfUICore first selects one physical target using the existing
namespace-neutral service rules:

- within one eligible UI root, reverse render order determines the widget hit;
- across eligible roots, the physical widget target with the greatest stable
  target sequence wins;
- existing blockers continue to suppress map fallback when no eligible widget
  target wins; and
- map fallback uses the exact sampled map coordinate.

A physical widget target receives its target sequence when its first namespace
contribution is registered. That target sequence remains unchanged while at
least one namespace contribution for the widget remains. Adding, updating, or
removing another namespace's contribution does not reorder the physical target.
Removing the final contribution removes the physical target record; a later
registration creates a new target sequence.

Each new `(namespace, widget)` contribution and each map registration also has
its own process-wide service contribution sequence. Idempotent widget
registration and context-menu definition replacement or update retain the
existing contribution sequence.

Only after a physical target is selected does the service apply its versioned
namespace contribution rule. Tooltip selects the eligible contribution with the
greatest contribution sequence for that target. Context menu combines all
eligible contributions for that target in ascending contribution sequence,
preserving entry order within each definition.

## Cross-namespace target collisions

Namespacing preserves contributions; it does not by itself decide how multiple
contributions for one target are presented. Version 1 defines deterministic
rules.

For tooltips, the most recently registered eligible contribution wins. Older
eligible contributions remain registered and become visible again if the
winner is removed or becomes ineligible. A widget registered by multiple
namespaces with the same widget-owned tooltip text still has distinct ownership
records and a deterministic winning identity.

For context menus, every eligible namespace contributes entries to one menu.
Contributions are ordered by their process-wide contribution sequence, and
entry order within each definition is preserved. Every rendered entry retains
its composite source identity so selection invokes exactly the callback that
contributed it. Removing one namespace leaves the other contributions intact.

Any future priority, grouping, replacement, or suppression mechanism is a
versioned public contract and must not be inferred from namespace spelling.

## Runtime singleton semantics

Provider objects and runtime services have intentionally different lifetimes:

- every `new()` call returns a distinct immutable API object;
- API objects for the same service and namespace share namespace state;
- API objects for different namespaces share the backend but not ownership;
- all tooltip APIs delegate to one process-wide tooltip runtime;
- all context-menu APIs delegate to one process-wide context-menu runtime;
- ordinary construction never replaces a singleton, registration manager,
  presenter, hook manager, namespace state, or active generation; and
- active registrations, intent, menus, hooks, and diagnostics survive repeated
  construction.

Private process state lives under DwarfUICore-owned keys in
`dfhack.dwarfuicore`. Correctness does not depend only on DFHack retaining the
root script environment.

## Installation coherence and service health

DwarfUICore publishes a private process-wide installation manifest containing:

- an installation/build identity;
- the DwarfUICore package version;
- the active runtime generation;
- initialization status;
- supported public contract majors per service; and
- required internal dependency contract versions.

Every prerequisite, service facade, and cached service record must agree with
the manifest. Method-shape checks alone are insufficient because separately
cached modules from incompatible installations can expose similar names.

Service health is distinct from contract compatibility. Acquisition:

- reuses a compatible healthy singleton;
- rejects a disabled, retired, malformed, or mixed-generation singleton;
- never automatically replaces or repairs an unhealthy singleton;
- never clears a script environment;
- never invokes teardown, reload, or overlay rescan; and
- reports whether reinstall or explicit development reload is appropriate.

## Atomic acquisition

The shared private acquisition helper performs atomic facade publication:

- validate constructor arguments before loading service prerequisites;
- reject acquisition while the runtime generation is initializing or retiring;
- validate the installation manifest and already loaded shared infrastructure;
- initialize missing prerequisites with explicitly idempotent initializers;
- validate the complete service contract and service health;
- publish a facade cache only after all checks succeed;
- clear the in-progress marker after failure; and
- return a new namespace-bound API object over the published facade.

This does not claim that arbitrary Lua module side effects can be rolled back.
Every core initializer must therefore be idempotent and must publish its own
process-owned state only after its local construction succeeds. A failed
acquisition publishes no facade and no healthy service marker; a later retry
may succeed after the installation is corrected or an explicit reload occurs.

## Failure contract

Provider construction rejects:

- invalid or unsupported contract versions;
- invalid namespaces;
- a missing private provider implementation, facade, or prerequisite;
- a missing, malformed, or incompatible installation manifest;
- mixed installation identities or runtime generations;
- a facade missing required versioned operations;
- malformed provider or service process state;
- a disabled, retired, or otherwise unhealthy service;
- prerequisite load failures; and
- reentrant or cyclic initialization.

The lightweight provider classes are defined at the stable root boundary.
Private implementations and service modules load only when `new()` is called,
allowing missing implementation failures to use the provider-specific error
prefix. If `reqscript('dwarfuicore')` itself cannot resolve, DFHack's
missing-script error is the appropriate indication that DwarfUICore is absent.

## Contract versioning policy

The integer passed to `new()` is the exact public major contract for that
service. It is independent of the DwarfUICore package version and of private
module API versions.

Compatible changes within one contract major include:

- adding a new API method;
- adding an optional input field with a defined default; and
- adding a diagnostic field that consumers are documented to ignore when
  unknown.

The following require a new contract major:

- removing or renaming a method;
- changing parameter or return semantics incompatibly;
- changing registration ownership, identity, or collision rules;
- changing an opaque handle's accepted domain;
- removing or changing a public data field incompatibly; and
- changing error transport or documented error categories incompatibly.

API objects are immutable, so newly added method names cannot collide with
consumer-attached fields.

## Development reload boundaries

`dwarfuicore reload` is an explicit global developer operation. It may retire
all core runtime owners, invalidate all namespaces and API objects, clear core
module environments, rebuild one coherent core generation, and rescan core
presentation integrations.

Before destructive teardown, reload marks the current generation as retiring
and invalidates acquisition. It publishes a new healthy generation only after
fresh construction succeeds. If reconstruction fails, no retired facade remains
marked healthy and all old API objects continue to fail as stale.

`dwarfui reload` does not reload DwarfUICore. Reloading DwarfUI must not destroy
registrations belonging to other DwarfUICore consumers. DwarfUI may explicitly
clear and rebuild only its own `dwarfui` namespace as part of its development
workflow.

No provider constructor or service API method can invoke either reload command,
clear script environments, tear down process-wide services, or rescan overlays.

## Future adoption sequence

The eventual implementation should be delivered as coordinated DwarfUICore
project work:

1. Approve this exact public contract, including version negotiation, namespace
   rules, identity and collision behavior, and compatibility policy.
2. Implement the root contract, manifest, namespace system, providers,
   immutable API objects, and focused contract tests in DwarfUICore.
3. Migrate DwarfUI to the approved provider APIs through namespace `dwarfui`
   without introducing a second runtime.
4. Migrate independent consumer plugins as separately approved work.
5. Publish and verify package contents, installation resolution, and the
   resulting public compatibility contract.

Consumer plugin migration outside DwarfUI is separate work. This proposal does
not authorize edits to those plugins.

Temporary compatibility adapters, if needed for DwarfUI's own transition, must
delegate to DwarfUICore and must not create a second runtime. They are explicitly
deprecated and are not the new public consumer contract.

## Acceptance tests

| Scenario | Required result |
| --- | --- |
| Cold tooltip construction | Exact version and namespace are validated; shared infrastructure initializes privately; a functional namespace-bound API is returned. |
| Cold context-menu construction | Exact version and namespace are validated; context-menu prerequisites initialize privately; a functional namespace-bound API is returned. |
| Missing constructor arguments | Missing version or namespace fails with the provider-specific prefix before service initialization. |
| Contract rejection | Non-integer, non-positive, and unsupported versions fail before an API object is returned. |
| Namespace rejection | Invalid namespaces fail before service initialization. |
| Repeated construction | Distinct API objects for the same namespace delegate to the same singleton and namespace state without repeated setup. |
| Multiple entrypoints | Separate entrypoints using one namespace share registrations without replacing the backend. |
| Multiple consumers | Different namespaces retain independent registrations while sharing one backend service. |
| Same-widget ownership | Two namespaces can register the same widget; either namespace can unregister without removing the other. |
| Foreign handle rejection | A map handle cannot be updated or removed through another namespace, service, contract major, or generation. |
| Tooltip collision | The deterministic winning tooltip is presented; removing it reveals the next eligible contribution. |
| Context-menu composition | Eligible namespace contributions are ordered and combined; each entry dispatches to its original callback. |
| Namespace-neutral targeting | Adding, updating, or removing a namespace contribution on an existing physical widget does not change that widget's target sequence or the service's hit-testing result. |
| Physical target lifetime | The first contribution creates a stable physical widget target sequence; the last removal deletes it; a later first contribution receives a new sequence. |
| Namespace cleanup | `clear_namespace()` removes only the bound namespace and service registrations. |
| API object lifetime | Collecting an API object removes no registration and does not change namespace or service state. |
| Weak widget lifetime | Collecting a registered widget removes only that widget's namespace-specific registration. |
| Weak map-handle lifetime | Collecting an opaque map handle removes only its exact registration without retaining the handle through a secondary index. |
| Explicit consumer cleanup | A consumer-controlled reload, disable, teardown, or applicable lifecycle handler can clear its service namespace without affecting another namespace or the core generation. |
| Cross-service construction | Constructing a second provider reuses shared infrastructure without replacing the first service. |
| Runtime preservation | Registrations, active intent or menu state, hooks, health, and diagnostics survive ordinary repeated construction. |
| Partial state | Construction fails clearly without reload, environment clearing, or singleton replacement. |
| Mixed installation | Conflicting installation identities, generations, and dependency contracts are rejected. |
| Unhealthy service | A disabled or retired singleton fails clearly and is not repaired or replaced by construction. |
| Initialization failure | No facade or healthy marker is published; the in-progress marker clears; a later corrected retry can succeed. |
| Development separation | Constructors and API methods never invoke reload, teardown, environment clearing, or overlay rescan. |
| Failed core reload | No retired facade remains healthy and every old API object fails as stale. |
| DwarfUI reload isolation | Reloading DwarfUI preserves every other DwarfUICore namespace and the core singleton generation. |
| Package contract | The root module, provider classes, private implementations, manifest, service modules, documentation, and tests exist in the DwarfUICore package. |
| Installation resolution | DwarfUI and an independent test consumer resolve the intended packaged DwarfUICore installation. |

## Recommendation

Proceed with DwarfUICore as the reusable dependency boundary and adopt this
canonical pattern:

```lua
local dwarfuiCore = reqscript('dwarfuicore')
local tooltipService =
    dwarfuiCore.services.TooltipServiceProvider:new(1, 'my-plugin')
```

The required version prevents accidental binding to a breaking contract. The
required namespace gives every registration and callback an explicit ownership
domain. DwarfUICore owns the singleton infrastructure, while DwarfUI and other
plugins become isolated consumers of that infrastructure.
