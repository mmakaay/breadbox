import pytest

from breadbox.components.core.device import CoreDevice
from breadbox.components.via_w65c22.device import ViaW65c22Device
from breadbox.components.via_w65c22.gpio_pin.device import ViaW65c22GpioPinDevice
from breadbox.config import BreadboxConfig
from breadbox.errors import ConfigError
from breadbox.types.address16 import Address16
from breadbox.types.device import Device
from breadbox.types.device_identifier import DeviceIdentifier


def make_config(**devices: Device) -> BreadboxConfig:
    """
    Build a BreadboxConfig with pre-populated devices, bypassing __init__.
    """
    config = object.__new__(BreadboxConfig)
    config.devices = {DeviceIdentifier(k): v for k, v in devices.items()}
    return config


def make_core(device_id: str = "CORE", cpu: str = "65c02", clock_mhz: float = 1.0) -> CoreDevice:
    return CoreDevice(id=DeviceIdentifier(device_id), cpu=cpu, clock_mhz=clock_mhz)


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
        assert len(config.devices) == 1


class TestValidateUniquePrefixes:
    """
    BreadboxConfig._validate() must reject configs where two devices
    produce the same symbol prefix (symbol_prefix).
    """

    def test_no_collision_passes(self):
        via = ViaW65c22Device(id=DeviceIdentifier("VIA"), address=Address16("$6000"))
        config = make_config(CORE=make_core(), VIA=via)
        config._validate()

    def test_nested_vs_flat_collision_raises(self):
        """
        A flat device VIA_LED and a nested VIA > LED both produce prefix 'VIA_LED'.
        """
        via = ViaW65c22Device(id=DeviceIdentifier("VIA"), address=Address16("$6000"))
        led = ViaW65c22Device(id=DeviceIdentifier("LED"), address=Address16("$6001"))
        via.add(led)
        via_led = ViaW65c22Device(id=DeviceIdentifier("VIA_LED"), address=Address16("$6002"))
        config = make_config(CORE=make_core(), VIA=via, VIA_LED=via_led)
        with pytest.raises(ConfigError, match="Symbol prefix collision.*VIA_LED"):
            config._validate()

    def test_deeply_nested_collision_raises(self):
        """
        FOO > BAR > BAZ produces prefix 'FOO_BAR_BAZ',
        which collides with a flat device named FOO_BAR_BAZ.
        """
        foo = ViaW65c22Device(id=DeviceIdentifier("FOO"), address=Address16("$6000"))
        bar = ViaW65c22Device(id=DeviceIdentifier("BAR"), address=Address16("$6001"))
        baz = ViaW65c22Device(id=DeviceIdentifier("BAZ"), address=Address16("$6002"))
        foo.add(bar)
        bar.add(baz)

        flat = ViaW65c22Device(id=DeviceIdentifier("FOO_BAR_BAZ"), address=Address16("$6003"))

        config = make_config(CORE=make_core(), FOO=foo, FOO_BAR_BAZ=flat)
        with pytest.raises(ConfigError, match="Symbol prefix collision.*FOO_BAR_BAZ"):
            config._validate()

    def test_distinct_nested_devices_pass(self):
        """
        Nested devices with unique prefixes should not collide.
        """
        via = ViaW65c22Device(id=DeviceIdentifier("VIA"), address=Address16("$6000"))
        led = ViaW65c22Device(id=DeviceIdentifier("LED"), address=Address16("$6001"))
        btn = ViaW65c22Device(id=DeviceIdentifier("BTN"), address=Address16("$6002"))
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
        via = ViaW65c22Device(id=DeviceIdentifier("VIA"), address=Address16("$6000"))
        pin1 = ViaW65c22GpioPinDevice(
            id=DeviceIdentifier("LED1"), bus_device=via, pin="PB0", bus="VIA"
        )
        pin2 = ViaW65c22GpioPinDevice(
            id=DeviceIdentifier("LED2"), bus_device=via, pin="PB1", bus="VIA"
        )
        config = make_config(CORE=make_core(), VIA=via, LED1=pin1, LED2=pin2)
        config._validate()

    def test_same_pin_raises(self):
        via = ViaW65c22Device(id=DeviceIdentifier("VIA"), address=Address16("$6000"))
        pin1 = ViaW65c22GpioPinDevice(
            id=DeviceIdentifier("LED1"), bus_device=via, pin="PB0", bus="VIA"
        )
        pin2 = ViaW65c22GpioPinDevice(
            id=DeviceIdentifier("LED2"), bus_device=via, pin="PB0", bus="VIA"
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
