import pytest

from breadbox.components.via_w65c22.device import ViaW65c22Device
from breadbox.components.via_w65c22.gpio_group.component import resolve
from breadbox.components.via_w65c22.gpio_group.device import ViaW65c22GpioGroupDevice
from breadbox.config import BreadboxConfig
from breadbox.types.address16 import Address16
from breadbox.types.bits import Bits
from breadbox.types.device_identifier import DeviceIdentifier


def make_via():
    return ViaW65c22Device(id=DeviceIdentifier("VIA0"), address=Address16("$6000"))


def make_config():
    config = object.__new__(BreadboxConfig)
    config.devices = {}
    return config


class TestPortBitsPath:
    def test_resolve_port_bits(self):
        via = make_via()
        config = make_config()
        settings = {"bus": "VIA0", "port": "A", "bits": 0b00000011}
        device = resolve(config, DeviceIdentifier("LEDS"), via, settings)

        assert isinstance(device, ViaW65c22GpioGroupDevice)
        assert device.id == "LEDS"
        assert device.port == "A"
        assert device.bits == Bits(3)
        assert [str(p) for p in device.pins] == ["PA0", "PA1"]

    def test_high_bits(self):
        via = make_via()
        config = make_config()
        settings = {"bus": "VIA0", "port": "B", "bits": 0b11110000}
        device = resolve(config, DeviceIdentifier("DATA"), via, settings)

        assert isinstance(device, ViaW65c22GpioGroupDevice)
        assert device.port == "B"
        assert [str(p) for p in device.pins] == ["PB4", "PB5", "PB6", "PB7"]


class TestPinsPath:
    def test_resolve_pins(self):
        via = make_via()
        config = make_config()
        settings = {"bus": "VIA0", "pins": ["PA0", "PA1"]}
        device = resolve(config, DeviceIdentifier("LEDS"), via, settings)

        assert isinstance(device, ViaW65c22GpioGroupDevice)
        assert device.port == "A"
        assert device.bits == Bits(3)
        assert [str(p) for p in device.pins] == ["PA0", "PA1"]


class TestPathEquivalence:
    def test_both_paths_produce_same_result(self):
        via = make_via()
        config = make_config()

        port_bits_settings = {"bus": "VIA0", "port": "A", "bits": 0b00000011}
        pins_settings = {"bus": "VIA0", "pins": ["PA0", "PA1"]}

        d1 = resolve(config, DeviceIdentifier("G1"), via, port_bits_settings)
        d2 = resolve(config, DeviceIdentifier("G2"), via, pins_settings)

        assert isinstance(d1, ViaW65c22GpioGroupDevice)
        assert isinstance(d2, ViaW65c22GpioGroupDevice)
        assert d1.port == d2.port
        assert d1.bits == d2.bits
        assert [str(p) for p in d1.pins] == [str(p) for p in d2.pins]


class TestInvalidConfig:
    def test_neither_path_raises(self):
        via = make_via()
        config = make_config()
        settings = {"bus": "VIA0"}
        with pytest.raises(ValueError, match="requires either"):
            resolve(config, DeviceIdentifier("BAD"), via, settings)

    def test_both_paths_raises(self):
        via = make_via()
        config = make_config()
        settings = {"bus": "VIA0", "port": "A", "bits": 0b11, "pins": ["PA0", "PA1"]}
        with pytest.raises(ValueError, match="requires either"):
            resolve(config, DeviceIdentifier("BAD"), via, settings)


class TestDefaults:
    def test_default_direction_and_default(self):
        via = make_via()
        config = make_config()
        settings = {"bus": "VIA0", "port": "A", "bits": 0b00000001}
        device = resolve(config, DeviceIdentifier("LEDS"), via, settings)

        assert isinstance(device, ViaW65c22GpioGroupDevice)
        assert device.direction == "both"
        assert device.default is None

    def test_custom_direction_and_default(self):
        via = make_via()
        config = make_config()
        settings = {"bus": "VIA0", "port": "A", "bits": 0b00000001, "direction": "out", "default": "on"}
        device = resolve(config, DeviceIdentifier("LEDS"), via, settings)

        assert isinstance(device, ViaW65c22GpioGroupDevice)
        assert device.direction == "out"
        assert device.default == "on"
