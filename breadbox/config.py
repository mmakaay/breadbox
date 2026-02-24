import importlib
from pathlib import Path
from typing import Any

import yaml
from rich.console import Console

from breadbox.errors import ConfigError
from breadbox.types.device import Device
from breadbox.types.device_identifier import DeviceIdentifier
from breadbox.visitor import ConfigPrinter

console = Console()


class BreadboxConfig:
    def __init__(self, project_dir: Path) -> None:
        self.project_dir = project_dir
        self.config_path = self._find_config_path()
        self.config_data = self._load_config_data()
        self.devices: dict[DeviceIdentifier, Device] = {}
        self._resolve_config()
        self._print_config()

    def get(self, device_id: DeviceIdentifier) -> Device:
        try:
            return self.devices[device_id]
        except KeyError:
            raise ConfigError(f"Device '{device_id}' not found") from None

    def _find_config_path(self) -> Path:
        config_paths = [
            self.project_dir / "config.yml",
            self.project_dir / "config.yaml",
        ]
        try:
            return next(p for p in config_paths if p.exists())
        except StopIteration:
            raise ConfigError("No config.yaml found in project directory") from None

    def _load_config_data(self) -> dict[str, Any]:
        console.print(f"[green]Load config from:[/green] {self.config_path}")
        with self.config_path.open("r") as f:
            data = yaml.safe_load(f)
        return data

    def _resolve_config(self) -> None:
        for raw_id, settings in self.config_data.items():
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
                raise ConfigError(f"No implementation found for component type '{component_type}'") from None

            try:
                device: Device = module.resolve(self, device_id, settings)
            except (ValueError, TypeError, KeyError) as e:
                raise ConfigError(f"Error in '{device_id}' ({component_type}): {e}") from None

            self.devices[device_id] = device

    def _print_config(self) -> None:
        printer = ConfigPrinter(console)
        for device in self.devices.values():
            # Only print top-level devices (sub-devices are visited recursively).
            if device.parent is None:
                device.accept(printer)
