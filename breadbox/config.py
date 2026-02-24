import importlib
import sys
from pathlib import Path
from typing import Any, NoReturn

import yaml
from rich.console import Console

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

    @staticmethod
    def error(msg) -> NoReturn:
        console.print(f"[red]{msg}[/red]")
        sys.exit(1)

    def get(self, device_id: DeviceIdentifier) -> Device:
        try:
            return self.devices[device_id]
        except KeyError:
            raise ValueError(f"Device ID {device_id!r} not found") from None

    def _find_config_path(self) -> Path:
        config_paths = [
            self.project_dir / "config.yml",
            self.project_dir / "config.yaml",
        ]
        try:
            config_path = next(p for p in config_paths if p.exists())
        except StopIteration:
            self.error("No config.yaml found in project directory")

        return config_path

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
                self.error(f"No implementation found for component type {component_type!r}")

            device: Device = module.resolve(self, device_id, settings)
            self.devices[device_id] = device

    def _print_config(self) -> None:
        printer = ConfigPrinter(console)
        for device in self.devices.values():
            # Only print top-level devices (sub-devices are visited recursively).
            if device.parent is None:
                device.accept(printer)
