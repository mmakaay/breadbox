import importlib
from pathlib import Path
from typing import Any

import yaml

from breadbox.errors import ConfigError
from breadbox.types.device import Device
from breadbox.types.device_identifier import DeviceIdentifier
from breadbox.visitors.config_printer import ConfigPrinter


class BreadboxConfig:
    def __init__(self, config_path: Path) -> None:
        self.config_path = self._resolve_config_path(config_path)
        self.project_dir = self.config_path.parent
        self.config_data = self._load_config_data()
        self.devices: dict[DeviceIdentifier, Device] = {}
        self._resolve_config()
        self._validate()

    def get(self, device_id: DeviceIdentifier) -> Device:
        try:
            return self.devices[device_id]
        except KeyError:
            raise ValueError(f"Device '{device_id}' not found") from None

    @staticmethod
    def _resolve_config_path(config_path: Path) -> Path:
        """
        Resolve the configuration file path.

        Falls back to the alternate YAML extension (.yaml ↔ .yml)
        if the given path does not exist.
        """
        if config_path.is_file():
            return config_path
        alt = config_path.with_suffix(".yml" if config_path.suffix == ".yaml" else ".yaml")
        if alt.is_file():
            return alt
        raise ConfigError(f"Configuration file not found: {config_path}")

    def _load_config_data(self) -> dict[str, Any]:
        with self.config_path.open("r") as f:
            data = yaml.safe_load(f)
        return data

    def _resolve_config(self) -> None:
        for raw_id, settings in self.config_data.items():
            try:
                device_id = DeviceIdentifier(raw_id)

                # Determine the component type.
                try:
                    component_type = settings["component"]
                    del settings["component"]
                except KeyError:
                    component_type = raw_id.lower()

                # Load the python module for the current component type.
                module_name = f"breadbox.components.{component_type}.component"
                try:
                    module = importlib.import_module(module_name)
                except ModuleNotFoundError:
                    raise ConfigError(
                        f"No implementation found for component type '{component_type}'"
                    ) from None

                device: Device = module.resolve(self, device_id, settings)
                self.devices[device_id] = device
            except ConfigError:
                raise
            except (ValueError, TypeError, KeyError) as e:
                raise ConfigError(f"Error in '{raw_id}': {e}") from None

    def print_config(self, console: Any) -> None:
        printer = ConfigPrinter(console)
        for device in self.devices.values():
            # Only print top-level devices (sub-devices are visited recursively).
            if device.parent is None:
                device.accept(printer)

    def _validate(self) -> None:
        """
        Validate the resolved configuration.

        Checks:
        - Exactly one CORE device is present.
        - No two devices produce the same symbol prefix.
        - No physical pin is claimed by multiple bus clients.
        """
        self._validate_single_core()
        self._collect_bus_clients()
        self._validate_bus_clients()
        self._validate_unique_prefixes()

    def _validate_single_core(self) -> None:
        from breadbox.components.core.device import CoreDevice

        cores = [d for d in self.devices.values() if isinstance(d, CoreDevice)]
        if len(cores) == 0:
            raise ConfigError("Configuration must include a CORE device")
        if len(cores) > 1:
            ids = ", ".join(str(d.id) for d in cores)
            raise ConfigError(
                f"Configuration must have exactly one CORE device, found {len(cores)}: {ids}"
            )

    def _collect_bus_clients(self) -> None:
        """
        Walk the device tree and register bus clients on their bus devices.

        Must run before bus client validation so that bus devices can
        answer queries about their clients (e.g. port exclusivity, pin conflicts).
        """
        from breadbox.visitors.bus_client_collector import BusClientCollector

        collector = BusClientCollector()
        for device in self.devices.values():
            if device.parent is None:
                device.accept(collector)

    def _validate_bus_clients(self) -> None:
        """
        Ask each device to validate its registered bus clients.
        """
        for device in self.devices.values():
            try:
                device.validate_bus_clients()
            except ValueError as e:
                raise ConfigError(str(e)) from None

    def _validate_unique_prefixes(self) -> None:
        """
        Check that no two devices produce the same symbol prefix.

        The macro_prefix (e.g. CONSOLE_PIN_RTS) is derived from the
        device tree path using underscores. A flat device named A_B
        and a nested device A > B would both produce prefix 'A_B',
        causing symbol collisions in the generated assembly.
        """
        prefixes: dict[str, Device] = {}
        for device in self._all_devices():
            prefix = device.macro_prefix
            if prefix in prefixes:
                other = prefixes[prefix]
                raise ConfigError(
                    f"Symbol prefix collision: devices {other.asm_scope!r} and"
                    f" {device.asm_scope!r} both produce prefix '{prefix}'"
                )
            prefixes[prefix] = device

    def _all_devices(self) -> list[Device]:
        """
        Flatten the device tree into a list of all devices.
        """
        result: list[Device] = []

        def _walk(device: Device) -> None:
            result.append(device)
            for sub in device.devices:
                _walk(sub)

        for device in self.devices.values():
            if device.parent is None:
                _walk(device)
        return result
