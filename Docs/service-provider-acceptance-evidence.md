# Service-provider acceptance evidence matrix

This matrix maps each proposal acceptance row to its authoritative evidence.
`DwarfUI` rows are separate consumer-integration evidence, not DwarfUICore test
dependencies. Live entries require a terminal result and `cleanup_confirmed`.

| Proposal scenario | Focused evidence | Final evidence kind |
| --- | --- | --- |
| Cold tooltip construction | `tests/service_provider/providers.spec.lua`; `provider_contract.ds.lua` | unit and live |
| Cold context-menu construction | `tests/service_provider/providers.spec.lua`; `provider_contract.ds.lua` | unit and live |
| Missing constructor arguments | `tests/service_provider/providers.spec.lua` | unit |
| Contract rejection | `tests/service_provider/contracts.spec.lua` | unit |
| Namespace rejection | `tests/service_provider/namespace.spec.lua` | unit |
| Stable constructor errors | `tests/service_provider/acquisition.spec.lua` | unit |
| Stable API errors | `tests/service_provider/api.spec.lua` | unit |
| Public diagnostic boundary | `tests/service_provider/api.spec.lua`; `provider_contract.ds.lua` | unit and live |
| Handle error precedence | `tests/service_provider/api.spec.lua` | unit |
| Repeated construction | `tests/service_provider/providers.spec.lua`; `provider_contract.ds.lua` | unit and live |
| Multiple entrypoints | `tests/service_provider/api.spec.lua` | unit |
| Multiple consumers | `tests/service_provider/api.spec.lua` | unit |
| Same-widget ownership | `tests/tooltip/registration.spec.lua`; `tests/context_menu/registration.spec.lua` | unit |
| Foreign handle rejection | `tests/service_provider/api.spec.lua` | unit |
| Tooltip collision | `tests/tooltip/registration.spec.lua`; `tooltip_screen_final_render.ds.lua` | unit and live |
| Context-menu composition | `tests/context_menu/registration.spec.lua`; `screen_interaction.ds.lua` | unit and live |
| Namespace-neutral targeting | `tests/tooltip/registration.spec.lua` | unit |
| Physical target lifetime | `tests/service_provider/weak_store.spec.lua`; `tests/tooltip/registration.spec.lua` | unit |
| Open-menu definition update | `tests/context_menu/service.spec.lua`; `screen_interaction.ds.lua` | unit and live |
| Open-menu ownership loss | `tests/context_menu/service.spec.lua`; `failure_lifecycle.ds.lua` | unit and live |
| Selection revalidation | `tests/context_menu/service.spec.lua`; `failure_lifecycle.ds.lua` | unit and live |
| Namespace cleanup | `tests/service_provider/api.spec.lua`; `provider_contract.ds.lua` | unit and live |
| API object lifetime | `tests/service_provider/api.spec.lua`; `provider_contract.ds.lua` | unit and live |
| Weak widget lifetime | `tests/service_provider/weak_store.spec.lua` | unit |
| Weak map-handle lifetime | `tests/service_provider/weak_store.spec.lua`; `tests/tooltip/map_target.spec.lua` | unit |
| Explicit consumer cleanup | `tests/service_provider/api.spec.lua`; `failure_lifecycle.ds.lua` | unit and live |
| Cross-service construction | `tests/service_provider/providers.spec.lua` | unit |
| Runtime preservation | `tests/service_provider/runtime.spec.lua`; `tooltip_pointer_scheduler.ds.lua` | unit and live |
| Partial state | `tests/service_provider/acquisition.spec.lua` | unit |
| Unhealthy service | `tests/service_provider/acquisition.spec.lua` | unit |
| Initialization failure | `tests/service_provider/acquisition.spec.lua`; `failure_lifecycle.ds.lua` | unit and live |
| Development separation | `tests/service_provider/api.spec.lua`; `tests/dwarfuicore_command.spec.lua` | unit |
| Failed core reload | `tests/dwarfuicore_command.spec.lua`; `provider_contract.ds.lua` | unit and live |
| DwarfUI reload isolation | DwarfUI `tests/service_provider/reload_isolation.ds.lua` | separate consumer live |
| Coordinated DwarfUI release | DwarfUI package-contract and integration setup | separate consumer package |
| Cross-version rejection | Core and DwarfUI package-contract tests | unit and separate consumer package |
| Legacy direct API removal | `tests/package_contract.spec.lua`; archive inspection | unit and package |
| Package contract | `tests/package_contract.spec.lua`; `tools/Publish.ps1` | unit and package |
| Installation resolution | Core `provider_contract.ds.lua`; DwarfUI integration setup | Core live and separate consumer package |
