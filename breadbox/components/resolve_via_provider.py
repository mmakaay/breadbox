import importlib
from pathlib import Path
from typing import Any

from breadbox.config import BreadboxConfig
from breadbox.types.component import Component
from breadbox.types.component_identifier import ComponentIdentifier


def resolve_via_provider(
    breadbox: BreadboxConfig,
    component_id: ComponentIdentifier,
    device_settings: dict[str, Any],
    interface_name: str,
    provider_key: str = "provider",
) -> Component:
    # Get the ID for the provider. The provider is the driver that provides an implementation
    # for the requested interface name.
    provider_id = device_settings.get(provider_key)
    if not provider_id:
        raise ValueError(f"Component {component_id!r}: missing '{provider_key}' field")

    # The provider implementation must provide a resolver module in
    # `<provider's package>.<interface name>.resolve`.
    provider_device = breadbox.get(ComponentIdentifier(provider_id))
    provider_type = provider_device.component_type
    module_name = f"breadbox.components.{provider_type}.{interface_name}.resolve"
    try:
        module = importlib.import_module(module_name)
    except ModuleNotFoundError:
        raise ValueError(
            f"Provider type {provider_type!r} does not support {interface_name} (no module {module_name})"
        ) from None

    # Register the delegation component's src/ directory for code generation, if it exists.
    delegation_dir = Path(__file__).parent / interface_name / "src"
    if delegation_dir.is_dir():
        breadbox.extra_source_dirs.append((interface_name, delegation_dir))

    # Let the resolver process the configuration, to build the component.
    return module.resolve(breadbox, component_id, provider_device, device_settings)
