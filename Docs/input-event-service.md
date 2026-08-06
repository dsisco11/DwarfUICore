# Input Event Service

`InputEventServiceProvider` supplies contract-major-1, namespace-bound APIs for
observing or intercepting mouse input that DFHack associates with a map tile.
Acquire it from `reqscript('dwarfuicore/services')` with the same exact-version
provider pattern used by the other DwarfUICore services.

```lua
local services = reqscript('dwarfuicore/services')
local input_events = services.InputEventServiceProvider:new(1, namespace)

input_events:observe(input_events.EventType.MAP_CLICK, function(event)
    local tile = event.map_position
    -- React after the inherited handler has run.
end)
```

## Event types

`EventType.MAP_CLICK` means a host-classified mouse input occurred over an exact
map tile and complete generic UI resolution proved that no UI target or blocker
obstructed it. Pass-through UI does not obstruct this event. Unsupported or
unknown UI-resolution surfaces do obstruct it.

`EventType.RAW_CLICK` means a host-classified mouse input occurred while DFHack
reported an exact map coordinate. It does not guarantee that the pointer was
not over UI. Known UI obstruction and UI-resolution failure alone do not
suppress this event.

Both event types include every host-classified mouse key in the intercepted
input table: button boundaries, presses, releases, wheel input, and future
host-classified mouse boundaries. They are not limited to left or right clicks.
Non-mouse input, missing map coordinates, and input consumed by a private Core
consumer produce neither event.

## Registration and delivery

Use `observe(event_type, callback)` for post-delegation notification. Observer
return values are ignored. Use `intercept(event_type, handler)` for
pre-delegation arbitration; handlers must return exactly
`Disposition.PASS` or `Disposition.CONSUME`. The first `CONSUME` stops later
interceptors and inherited handling. A consumed public event is still observed
after delegation is skipped.

```lua
local handle = input_events:intercept(
    input_events.EventType.RAW_CLICK,
    function(event)
        if should_claim(event) then
            return input_events.Disposition.CONSUME
        end
        return input_events.Disposition.PASS
    end)

input_events:unsubscribe(handle)
```

Each successful registration returns an opaque handle. Handles are valid only
for their service, contract major, namespace, runtime generation, and
registration identity. `is_subscribed(handle)` reports whether a local handle
is active; `clear_namespace()` removes only registrations owned by the API's
namespace.

Event values, their positions, and their sorted `mouse_inputs` collections are
immutable. `screen_position` is optional; `map_position` is exact when present.
Positions are immutable `ScreenPosition` and `MapTilePosition` values rather
than independent coordinate axes.

Interceptor exceptions and invalid dispositions are contained, recorded
privately, and treated as `PASS`. Observer exceptions are also contained and do
not prevent later observers or change inherited input results. Registrations
added during a callback do not receive the event already being dispatched;
registrations removed before their turn are skipped.
