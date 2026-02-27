import pytest

from breadbox.components.core.device import CoreDevice
from breadbox.components.ram.device import RamDevice
from breadbox.components.rom.device import RomDevice
from breadbox.components.via_w65c22.device import ViaW65c22Device
from breadbox.components.via_w65c22.gpio_pin.device import ViaW65c22GpioPinDevice
from breadbox.config import BreadboxConfig
from breadbox.errors import ConfigError
from breadbox.types.address16 import Address16
from breadbox.types.component import Component
from breadbox.types.component_identifier import ComponentIdentifier


def make_config(**components: Component) -> BreadboxConfig:
    """
    Build a BreadboxConfig with pre-populated components, bypassing __init__.
    """
    config = object.__new__(BreadboxConfig)
    config.components = {ComponentIdentifier(k): v for k, v in components.items()}
    return config


def make_core(component_id: str = "CORE", cpu: str = "65c02", clock_mhz: float = 1.0) -> CoreDevice:
    return CoreDevice(id=ComponentIdentifier(component_id), cpu=cpu, clock_mhz=clock_mhz)


class TestValidateCoreDevice:
    """
    BreadboxConfig._validate() must enforce exactly one CORE device.
    """

    def test_single_core_passes(self):
        config = make_config(CORE=make_core())
        config._validate()

    def test_no_core_raises(self):
        config = make_config()
        with pytest.raises(ConfigError, match="must include a CORE device"):
            config._validate()



class TestValidateFromYaml:
    """
    Validation runs during normal config loading from YAML.
    """

    def test_missing_core_in_yaml(self, tmp_path):
        """
        A YAML file with no CORE section should fail validation.
        """
        config_path = tmp_path / "config.yaml"
        config_path.write_text("VIA:\n  component: via_w65c22\n  address: '$6000'\n")
        with pytest.raises(ConfigError, match="must include a CORE device"):
            BreadboxConfig(config_path)

    def test_valid_yaml_passes(self, tmp_path):
        config_path = tmp_path / "config.yaml"
        config_path.write_text("CORE:\n  cpu: '65c02'\n  clock_mhz: 1.0\n")
        config = BreadboxConfig(config_path)
        assert ComponentIdentifier("CORE") in config.components


class TestValidateUniquePrefixes:
    """
    BreadboxConfig._validate() must reject configs where two devices
    produce the same symbol prefix (symbol_prefix).
    """

    def test_no_collision_passes(self):
        via = ViaW65c22Device(id=ComponentIdentifier("VIA"), address=Address16("$6000"))
        config = make_config(CORE=make_core(), VIA=via)
        config._validate()

    def test_nested_vs_flat_collision_raises(self):
        """
        A flat device VIA_LED and a nested VIA > LED both produce prefix 'VIA_LED'.
        """
        via = ViaW65c22Device(id=ComponentIdentifier("VIA"), address=Address16("$6000"))
        led = ViaW65c22Device(id=ComponentIdentifier("LED"), address=Address16("$6001"))
        via.add(led)
        via_led = ViaW65c22Device(id=ComponentIdentifier("VIA_LED"), address=Address16("$6002"))
        config = make_config(CORE=make_core(), VIA=via, VIA_LED=via_led)
        with pytest.raises(ConfigError, match="Symbol prefix collision.*VIA_LED"):
            config._validate()

    def test_deeply_nested_collision_raises(self):
        """
        FOO > BAR > BAZ produces prefix 'FOO_BAR_BAZ',
        which collides with a flat device named FOO_BAR_BAZ.
        """
        foo = ViaW65c22Device(id=ComponentIdentifier("FOO"), address=Address16("$6000"))
        bar = ViaW65c22Device(id=ComponentIdentifier("BAR"), address=Address16("$6001"))
        baz = ViaW65c22Device(id=ComponentIdentifier("BAZ"), address=Address16("$6002"))
        foo.add(bar)
        bar.add(baz)

        flat = ViaW65c22Device(id=ComponentIdentifier("FOO_BAR_BAZ"), address=Address16("$6003"))

        config = make_config(CORE=make_core(), FOO=foo, FOO_BAR_BAZ=flat)
        with pytest.raises(ConfigError, match="Symbol prefix collision.*FOO_BAR_BAZ"):
            config._validate()

    def test_distinct_nested_devices_pass(self):
        """
        Nested devices with unique prefixes should not collide.
        """
        via = ViaW65c22Device(id=ComponentIdentifier("VIA"), address=Address16("$6000"))
        led = ViaW65c22Device(id=ComponentIdentifier("LED"), address=Address16("$6001"))
        btn = ViaW65c22Device(id=ComponentIdentifier("BTN"), address=Address16("$6002"))
        via.add(led)
        via.add(btn)
        config = make_config(CORE=make_core(), VIA=via)
        config._validate()


class TestValidatePinConflicts:
    """
    BreadboxConfig._validate() must reject configs where two devices
    claim the same physical pin on a bus device.
    """

    def test_no_pin_conflict_passes(self):
        via = ViaW65c22Device(id=ComponentIdentifier("VIA"), address=Address16("$6000"))
        pin1 = ViaW65c22GpioPinDevice(
            id=ComponentIdentifier("LED1"), bus_device=via, pin="PB0", bus="VIA"
        )
        pin2 = ViaW65c22GpioPinDevice(
            id=ComponentIdentifier("LED2"), bus_device=via, pin="PB1", bus="VIA"
        )
        config = make_config(CORE=make_core(), VIA=via, LED1=pin1, LED2=pin2)
        config._validate()

    def test_same_pin_raises(self):
        via = ViaW65c22Device(id=ComponentIdentifier("VIA"), address=Address16("$6000"))
        pin1 = ViaW65c22GpioPinDevice(
            id=ComponentIdentifier("LED1"), bus_device=via, pin="PB0", bus="VIA"
        )
        pin2 = ViaW65c22GpioPinDevice(
            id=ComponentIdentifier("LED2"), bus_device=via, pin="PB0", bus="VIA"
        )
        config = make_config(CORE=make_core(), VIA=via, LED1=pin1, LED2=pin2)
        with pytest.raises(ConfigError, match="Pin conflict.*PB0"):
            config._validate()

    def test_pin_conflict_from_yaml(self, tmp_path):
        config_path = tmp_path / "config.yaml"
        config_path.write_text(
            "CORE:\n"
            "  cpu: '65c02'\n"
            "  clock_mhz: 1.0\n"
            "VIA:\n"
            "  component: via_w65c22\n"
            "  address: '$6000'\n"
            "LED1:\n"
            "  component: gpio_pin\n"
            "  bus: VIA\n"
            "  pin: PB0\n"
            "  direction: out\n"
            "LED2:\n"
            "  component: gpio_pin\n"
            "  bus: VIA\n"
            "  pin: PB0\n"
            "  direction: out\n"
        )
        with pytest.raises(ConfigError, match="Pin conflict.*PB0"):
            BreadboxConfig(config_path)


class TestDefaultMemoryInjection:
    """
    BreadboxConfig injects default RAM and ROM when none are present.
    """

    def test_injects_default_ram_and_rom(self, tmp_path):
        config_path = tmp_path / "config.yaml"
        config_path.write_text("CORE:\n  cpu: '65c02'\n  clock_mhz: 1.0\n")
        config = BreadboxConfig(config_path)
        ram_devices = [d for d in config.components.values() if isinstance(d, RamDevice)]
        rom_devices = [d for d in config.components.values() if isinstance(d, RomDevice)]
        assert len(ram_devices) == 1
        assert len(rom_devices) == 1
        assert int(ram_devices[0].address) == 0x0000
        assert ram_devices[0].size == 0x4000
        assert int(rom_devices[0].address) == 0x8000
        assert rom_devices[0].size == 0x8000

    def test_does_not_inject_when_present(self, tmp_path):
        config_path = tmp_path / "config.yaml"
        config_path.write_text(
            "CORE:\n  cpu: '65c02'\n  clock_mhz: 1.0\n"
            "MYRAM:\n  component: ram\n  address: '$0000'\n  size: 0x2000\n"
            "MYROM:\n  component: rom\n  address: '$E000'\n  size: 0x2000\n"
        )
        config = BreadboxConfig(config_path)
        ram_devices = [d for d in config.components.values() if isinstance(d, RamDevice)]
        rom_devices = [d for d in config.components.values() if isinstance(d, RomDevice)]
        assert len(ram_devices) == 1
        assert str(ram_devices[0].id) == "MYRAM"
        assert len(rom_devices) == 1
        assert str(rom_devices[0].id) == "MYROM"

    def test_memory_layout_resolved(self, tmp_path):
        config_path = tmp_path / "config.yaml"
        config_path.write_text("CORE:\n  cpu: '65c02'\n  clock_mhz: 1.0\n")
        config = BreadboxConfig(config_path)
        assert config.memory_layout is not None
        region_names = [r.name for r in config.memory_layout.regions]
        assert "ZEROPAGE" in region_names
        assert "VECTORS" in region_names
