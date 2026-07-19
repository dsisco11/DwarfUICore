# Singleton tooltip registration decision

## Status

Phase 8 accepts a registration-only API as the Phase 9 implementation
direction, with one essential invariant: DwarfUI displays at most one tooltip
process-wide.

The renderer is therefore not owned by each consumer root. One transparent,
screen-sized `gui.ZScreen` owns one renderer and arbitrates every registered
control. The executable prototype remains experimental until Phase 9 completes
compatibility and live DFHack checks.

Phase 8 was entered under the explicit Phase 7 waiver recorded in
`Docs/tooltip-system-port.todo`. All evidence in this decision is local
automation and source inspection, not live DFHack proof.

## Corrected architecture

```text
registered controls (weak keys)
              |
              v
singleton target resolver -- one pointer sample, one winning control
              |
              v
transparent TooltipServiceScreen -- one TooltipRenderer, rendered last
```

Controls register themselves. They do not construct a renderer, agent, root
adapter, or lifecycle hook. A control may register before or after attachment.
The service recomputes its current top-level root from `parent_view` on every
tick, so ordinary attachment and reparenting require no new registration.

The service screen exists while at least one registration exists. It renders
the complete parent screen stack, samples registered controls once, and renders
the single tooltip afterward with a full-screen painter. This makes tooltip
placement independent of a consumer root's clipping rectangle.

## Registration contract evaluated by the prototype

```lua
local tooltips = reqscript(
    'dwarfui/tooltip_registration_experimental')
tooltips.register(widget)
```

- `register(widget)` accepts an arbitrary widget, including an unattached one.
- Duplicate registration is idempotent and returns `false`.
- `unregister(widget)` is available but never required for normal lifetime
  cleanup; registrations use weak keys.
- At most one service screen, renderer, target, and visible tooltip exist.
- Within one root, the existing reverse-subview pointer dispatcher determines
  the actual topmost target and honors window/modal blockers.
- Across independently rendered roots, the most recently registered winning
  control has deterministic priority. Phase 9 may replace this tie-break only
  if live evidence exposes a reliable cross-root render-order signal.
- Pointer enter, update, and leave callbacks run only for the global winner.
- Dynamic callbacks mutate tooltip text before the renderer reads it.
- Hidden/inactive ancestors, removal from a root, mouse-out, and explicit
  unregistration clear the current global target on the next service tick.
- Overlay controls are eligible only while their root is the enabled widget
  instance currently owned by the overlay framework; disable and replacement
  therefore clear stale targets without consumer hooks.
- Same-version reload preserves weak registrations but replaces the old screen
  and renderer so installed methods do not retain an old module generation.
- Conflicting service versions fail before mutating the existing singleton.

## DFHack lifecycle and stacking audit

The audit used the local DFHack 53.15-r1 source checkout recorded by Phase 0.

| Seam | Observed API | Singleton consequence |
|---|---|---|
| Widget attachment | `View:addviews()` sets `parent_view` (`library/lua/gui.lua:664`) | Registration does not need an attachment hook; the parent chain is read when sampling. |
| Layout and clipping | `View:updateLayout()` maintains frame and clipped body rectangles (`gui.lua:783`) | Detached or unlaid-out controls are skipped. Reparented controls use their current geometry after layout. |
| Native target order | `View:renderSubviews()` and the DwarfUI dispatcher traverse subviews in opposite render/hit-test order (`gui.lua:804`; `dwarfui/pointer`) | The resolver can preserve existing within-root z-order and modal blocking without registering roots. |
| Parent-first screen rendering | `Screen:renderParent()` renders the complete native parent (`gui.lua:921`) | The service can render underlying screens and overlays first, then draw one tooltip above them. |
| Screen creation | `Screen:show()` attaches a Lua screen above the current viewscreen (`gui.lua:939`) | The singleton can be created lazily on the first registration. |
| Transparent input | `Screen:sendInputToParent()` forwards keys (`gui.lua:933`); ordinary `ZScreen:onInput()` still handles dismissal and some keys itself | The service must override `onInput()` and forward every input table unchanged. |
| Parent logic | `ZScreen:onIdle()` advances its parent logic (`gui.lua:1057`) | Keeping the service current does not freeze the underlying screen. |
| Z-order recovery | `ZScreen:raise()` is the supported z-order operation (`gui.lua:1156`) | After another screen opens above the service, its idle callback can raise the singleton again. |
| Resize | `Screen:onResize()` updates full-screen layout (`gui.lua:975`) | The renderer continues to clamp against the actual screen after a resize. |
| Overlay clipping | Overlay widgets render through panel-sized painters, while the service owns a screen-sized painter | The renderer no longer needs overlay-specific attachment or render interception. |
| Overlay ownership | `plugins.overlay` exposes enabled configuration and its current widget database through `isOverlayEnabled()` and `get_state()` | Disabled or replaced overlay instances can be excluded without wrapping their lifecycle methods. |

## Lifecycle results

| Case | Prototype result |
|---|---|
| First registration | Creates and shows exactly one service screen and renderer. |
| Additional/duplicate registrations | Reuses the singleton; duplicates are no-ops. |
| Registration before attachment | Accepted and skipped until a laid-out root becomes available. |
| Reparenting | The next tick discovers the new root without re-registration. |
| Removal with stale `parent_view` | Root traversal cannot resolve the removed control, so the global target clears. |
| Hidden ancestor | Eligibility fails and pointer leave runs once. |
| Modal/window overlap | The existing root dispatcher blocks targets behind the modal frame. |
| Independently clipped overlay root | Hit testing respects its clip; presentation uses the service screen and escapes it. |
| Overlay disable/replacement | Framework enabled state and widget identity exclude the stale root on the next tick. |
| New screen above service | The service forwards input and calls supported `raise()` from idle. |
| External service-screen dismissal | A one-frame timeout recreates the singleton while registrations remain. |
| Same-version reload | Registrations survive; the old screen is dismissed and a new generation is shown. |
| Conflicting version | Import fails with both version numbers and leaves the service untouched. |
| Explicit final unregistration | Clears the target and dismisses the singleton screen. |
| Garbage collection | Weak keys do not retain otherwise unreachable controls; the next service tick dismisses an unused screen. |

## Comparison with explicit per-root hosting

| Property | Explicit screen/overlay recipes | Singleton registration prototype |
|---|---|---|
| Renderer count | One per independently rendered root | Exactly one process-wide |
| Consumer work | Construct, attach, update, order, and own renderer/agent | Call `register(widget)` |
| Reparenting | Host-specific ownership must remain correct | Current parent chain is rediscovered each tick |
| Overlay clipping | Requires a special parent-painter recipe | Presentation is screen-rooted |
| Modal behavior | Per-root dispatcher | Same dispatcher, applied only to roots containing registrations |
| Input | Owned by each host | Singleton screen forwards every input unchanged |
| Reload | Every host recreates its state | Shared weak registrations migrate to a new singleton screen |
| Multiple simultaneous tooltips | Possible across roots | Prohibited by contract |
| Global state | None | Intentional singleton service state under `dfhack.dwarfui` |

## Decision

Adopt singleton automatic registration as the Phase 9 implementation direction.

The previous root-per-renderer prototype answered the wrong question. Once the
product contract prohibits multiple simultaneous tooltips, renderer ownership
does not need to follow consumer render roots. A screen-rooted singleton removes
the unsafe renderer insertion/removal and host-method interception that caused
the earlier rejection.

Phase 9 must keep the current explicit API available until live DFHack proves
that the transparent service screen remains topmost, forwards all input, does
not disrupt focus-sensitive overlays, excludes enabled overlays that are not
rendered on the current viewscreen, and recreates cleanly across reload. The
cross-root tie-break must also remain documented and deterministic. Subject to
those gates, consumers should need only `register(widget)`.
