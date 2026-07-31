# Tooltip registration decision

## Status

Superseded. The transparent singleton `TooltipServiceScreen` design described
by the earlier version of this document was removed because a `gui.ZScreen`
cannot be invisible to DFHack focus, input, logic, and viewscreen lifecycle
systems.

The current implementation keeps the stable automatic registration API but
separates input observation from presentation. The active execution contract
and supporting evidence are recorded in `Docs/tooltip-render-hook.todo`.

## Current architecture

```text
weak widget registrations
          |
          v
pointer poller and target detector
          |
          v
presentation-neutral tooltip intent service
          |
          v
presenter selected by intent source root
          |
          +-- native root: final native-overlay render hook
          |
          `-- Lua screen: final instance onRender hook
```

Registration creates no screen, overlay widget, focus owner, input recipient,
or renderer. Input polling publishes immutable intent through the tooltip
service. The presenter subscribes to service notifications, selects one render
transport from the intent's opaque source root, and reads the authoritative
intent when the selected hook runs.

Native-root tooltips append to the existing DFHack overlay render pipeline.
Foreground Lua-screen tooltips temporarily wrap only the owning instance's
effective `onRender()` method. The wrapper does not add subviews or change
focus, input, logic, dismissal, parent, or screen configuration state.

## Stable registration contract

```lua
local tooltip = reqscript('dwarfui/tooltip/api')
tooltip.register(widget)
```

`dwarfui/tooltip/api` is the only supported consumer entry point. Modules
elsewhere under `dwarfui/tooltip/` are internal implementation details.

- `register(widget)` accepts an arbitrary widget, including an unattached one.
- Duplicate registration is idempotent and returns `false`.
- `unregister(widget)` is available for immediate removal, but normal lifetime
  cleanup relies on weak registrations.
- At most one tooltip intent and one visible tooltip exist process-wide.
- Within a root, reverse-subview hit testing preserves normal target and modal
  blocker ordering.
- Hidden or inactive ancestors, detachment, pointer departure, and explicit
  unregistration clear the current target.
- Overlay controls are eligible only while their root is the enabled
  registry-owned overlay instance for the current native viewscreen.
- Reload preserves weak registrations while replacing the poller and presenter
  generations and repairing the render hooks.

## Rejected design

The earlier design created a transparent, screen-sized `gui.ZScreen` and tried
to keep it above every other viewscreen. Although that gave the renderer a
full-window painter, the screen was still a real viewscreen:

- it participated in current-view and focus queries;
- it could become the recipient of input;
- it affected parent logic and dismissal behavior;
- keeping it topmost required lifecycle operations such as `raise()`; and
- creating it before a compatible loaded-game state could interfere with game
  startup.

Special-casing native screens and forwarding lifecycle behavior could address
individual symptoms, but could not make the service screen globally invisible.
Separating polling from rendering and borrowing existing render seams preserves
full-window, final painting without introducing another viewscreen.

## Decision

Keep `tooltip.register(widget)` as the public API. Keep registration, hit
testing, and intent mediation presentation-neutral. Present only through the
existing native-overlay render seam or the exact foreground Lua-screen
instance that owns the registered control. Do not construct a tooltip
`ZScreen`, register a tooltip overlay, or give the tooltip system independent
focus, input, or logic ownership.
