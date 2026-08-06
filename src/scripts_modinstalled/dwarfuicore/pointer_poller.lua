--@ module=true

-- Private compatibility export for the Input Event pointer poller.

local pointer_poller = reqscript('dwarfuicore/input_event/pointer_poller')

PointerPoller = pointer_poller.PointerPoller
PointerDemandTracker = pointer_poller.PointerDemandTracker