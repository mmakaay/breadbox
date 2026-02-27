import importlib
from pathlib import Path
from typing import Any

import yaml

from breadbox.errors import ConfigError
from breadbox.memory import MemoryLayout, resolve_memory_layout
from breadbox.types.component import Component
from breadbox.types.component_identifier import ComponentIdentifier
from breadbox.visitors.config_printer import ConfigPrinter


class BreadboxConfig:
    def __init__(self, config_path: Path) -> None:
        self.config_path = self._resolve_config_path(config_path)
        self.project_dir = self.config_path.parent
        self.config_data = self._load_config_data()
        self.components: dict[ComponentIdentifier, Component] = {}
        self.memory_layout: MemoryLayout | None = None
        self._resolve_config()
        self._inject_default_memory()
        self._validate()

    def get(self, component_id: ComponentIdentifier) -> Component:
        try:
            return self.components[component_id]
        except KeyError:
            raise ValueError(f"Component '{component_id}' not found") from None

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
                component_id = ComponentIdentifier(raw_id)

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

                component: Component = module.resolve(self, component_id, settings)
                self.components[component_id] = component
            except ConfigError:
                raise
            except (ValueError, TypeError, KeyError) as e:
                raise ConfigError(f"Error in '{raw_id}': {e}") from None

    def print_config(self, console: Any) -> None:
        printer = ConfigPrinter(console)
        for component in self.components.values():
            # Only print top-level components (children are visited recursively).
            if component.parent is None:
                component.accept(printer)

    def _validate(self) -> None:
        """
        Validate the resolved configuration.
        """
        self._validate_single_core()
        self._collect_bus_clients()
        self._validate_bus_clients()
        self._validate_unique_prefixes()
        self._resolve_memory()

    def _validate_single_core(self) -> None:
        from breadbox.components.core.device import CoreDevice

        cores = [c for c in self.components.values() if isinstance(c, CoreDevice)]
        if len(cores) == 0:
            raise ConfigError("Configuration must include a CORE device")
        if len(cores) > 1:
            ids = ", ".join(str(c.id) for c in cores)
            raise ConfigError(f"Configuration must have exactly one CORE device, found {len(cores)}: {ids}")

    def _collect_bus_clients(self) -> None:
        """
        Walk the component tree and register bus clients on their bus devices.

        Must run before bus client validation so that bus devices can
        answer queries about their clients (e.g. port exclusivity, pin conflicts).
        """
        from breadbox.visitors.bus_client_collector import BusClientCollector

        collector = BusClientCollector()
        for component in self.components.values():
            if component.parent is None:
                component.accept(collector)

    def _validate_bus_clients(self) -> None:
        """
        Ask each device to validate its registered bus clients.
        """
        from breadbox.types.device import Device

        for component in self.components.values():
            if isinstance(component, Device):
                try:
                    component.validate_bus_clients()
                except ValueError as e:
                    raise ConfigError(str(e)) from None

    def _validate_unique_prefixes(self) -> None:
        """
        Check that no two components produce the same symbol prefix.

        The symbol_prefix (e.g. CONSOLE_PIN_RTS) is derived from the
        component tree path using underscores. A flat component named A_B
        and a nested component A > B would both produce prefix 'A_B',
        causing symbol collisions in the generated assembly.
        """
        prefixes: dict[str, Component] = {}
        for component in self._all_components():
            prefix = component.symbol_prefix
            if prefix in prefixes:
                other = prefixes[prefix]
                raise ConfigError(
                    f"Symbol prefix collision: components '{other.component_path}' and"
                    f" '{component.component_path}' both produce prefix '{prefix}'"
                )
            prefixes[prefix] = component

    def _all_components(self) -> list[Component]:
        """
        Flatten the component tree into a list of all components.
        """
        result: list[Component] = []

        def _walk(component: Component) -> None:
            result.append(component)
            for sub in component.children:
                _walk(sub)

        for component in self.components.values():
            if component.parent is None:
                _walk(component)
        return result

    def _inject_default_memory(self) -> None:
        """
        Inject default RAM and ROM devices when none are present in the config.

        Default RAM: $0000, size $4000 (16 KB, matches Ben Eater layout).
        Default ROM: $8000, size $8000 (32 KB, top half of address space).
        """
        from breadbox.components.ram.device import RamDevice
        from breadbox.components.rom.device import RomDevice

        has_ram = any(isinstance(c, RamDevice) for c in self.components.values())
        has_rom = any(isinstance(c, RomDevice) for c in self.components.values())

        if not has_ram:
            device = RamDevice(id=ComponentIdentifier("RAM"), address="$0000", size=0x4000)
            self.components[device.id] = device

        if not has_rom:
            device = RomDevice(id=ComponentIdentifier("ROM"), address="$8000", size=0x8000)
            self.components[device.id] = device

    def _resolve_memory(self) -> None:
        """
        Resolve memory devices into a complete memory layout for linker.cfg.
        """
        from breadbox.components.ram.device import RamDevice
        from breadbox.components.rom.device import RomDevice

        ram_devices = [c for c in self.components.values() if isinstance(c, RamDevice)]
        rom_devices = [c for c in self.components.values() if isinstance(c, RomDevice)]
        if ram_devices or rom_devices:
            self.memory_layout = resolve_memory_layout(ram_devices, rom_devices)
