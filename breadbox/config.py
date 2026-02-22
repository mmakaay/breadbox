import importlib
import sys
from pathlib import Path
from typing import Any, NoReturn, Protocol
from pydantic import validate_call
import yaml
from rich.console import Console

from breadbox.types.device import Device
from breadbox.types.device_identifier import DeviceIdentifier

console = Console()


class BreadboxConfig:
    def __init__(self, project_dir: Path) -> None:
        self.project_dir = project_dir
        self.config_path = self._find_config_path()
        self.config_data = self._load_config_data()
        self.devices: dict[DeviceIdentifier, Device] = {}
        self._resolve_config()
    
    def error(self, msg) -> NoReturn:
        console.print(f"[red]{msg}[/red]")
        sys.exit(1)
    
    @validate_call
    def get(self, device_id: DeviceIdentifier) -> Device:
        try:
            return self.devices[device_id]
        except KeyError:
            raise ValueError(f"Device ID {device_id!r} not found")
        
    
    def _find_config_path(self) -> Path:
        """
        Check a couple of configuration file name options, to see which one to use.
        """
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
        for device_id, settings in self.config_data.items():
            console.print(f"  [blue]{device_id}[/blue]")

            # Determine the comopnenet type.
            try:
                component_type = settings["component"]
                del settings["component"]
            except KeyError:
                component_type = device_id
                
            # Load the python module for the current component type.
            module_name = f"breadbox.components.{component_type}.component"
            try:
                module = importlib.import_module(module_name)
            except ModuleNotFoundError:
                self.error(f"No implementation found for component type {component_type!r}")

            # Let the module turn the configuration into a device object.              
            device: Device = module.resolve(self, settings)
            self.devices[device_id] = device
            
            # Show information about the resolved device.
            for name, value in device.get_info().items():
                console.print(f"    [bold]{name}[/bold]: {value}")

    