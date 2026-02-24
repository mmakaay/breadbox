import pytest

from breadbox.components.via_w65c22.device import (
    ViaW65c22Device,
    ViaW65c22Port,
    ViaW65c22PortPin,
)
from breadbox.types.address16 import Address16
from breadbox.types.device_identifier import DeviceIdentifier


def make_via(address="$6000"):
    return ViaW65c22Device(id=DeviceIdentifier("VIA0"), address=Address16(address))


class TestViaW65c22Device:
    def test_construction(self):
        via = make_via()
        assert via.id == "VIA0"
        assert via.address == 0x6000

    def test_address_auto_coerced(self):
        """Raw string address is auto-coerced to Address16 by Device base."""
        via = ViaW65c22Device(id=DeviceIdentifier("VIA0"), address="$6000")
        assert isinstance(via.address, Address16)
        assert via.address == 0x6000


class TestGetPort:
    def test_port_a(self):
        via = make_via()
        pins = via.get_port("A")
        assert len(pins) == 8
        assert pins[0] == "PA0"
        assert pins[7] == "PA7"

    def test_port_b(self):
        via = make_via()
        pins = via.get_port("B")
        assert len(pins) == 8
        assert pins[0] == "PB0"
        assert pins[7] == "PB7"

    def test_port_case_insensitive(self):
        via = make_via()
        assert via.get_port("a") == via.get_port("A")

    def test_invalid_port(self):
        via = make_via()
        with pytest.raises((ValueError, KeyError)):
            via.get_port("C")


class TestResolvePins:
    def test_two_pins_port_a(self):
        via = make_via()
        port, bitmask = via.resolve_pins(["PA0", "PA1"])
        assert port == "A"
        assert bitmask == 0b00000011

    def test_high_pins(self):
        via = make_via()
        port, bitmask = via.resolve_pins(["PA6", "PA7"])
        assert port == "A"
        assert bitmask == 0b11000000

    def test_single_pin(self):
        via = make_via()
        port, bitmask = via.resolve_pins(["PB3"])
        assert port == "B"
        assert bitmask == 0b00001000

    def test_all_pins(self):
        via = make_via()
        port, bitmask = via.resolve_pins([f"PA{i}" for i in range(8)])
        assert port == "A"
        assert bitmask == 0xFF

    def test_mixed_ports_raises(self):
        via = make_via()
        with pytest.raises(ValueError, match="same port"):
            via.resolve_pins(["PA0", "PB0"])

    def test_invalid_pin_raises(self):
        via = make_via()
        with pytest.raises(ValueError, match="not a valid pin"):
            via.resolve_pins(["ZZ0"])

    def test_case_insensitive(self):
        via = make_via()
        port, bitmask = via.resolve_pins(["pa0", "pa1"])
        assert port == "A"
        assert bitmask == 0b00000011


class TestViaW65c22PortPin:
    @pytest.mark.parametrize(
        "value,expected",
        [
            ("PA0", "PA0"),
            ("pa0", "PA0"),
            ("PB7", "PB7"),
            ("pb7", "PB7"),
        ],
    )
    def test_valid_pins(self, value, expected):
        result = ViaW65c22PortPin(value)
        assert result == expected

    def test_invalid_pin(self):
        with pytest.raises(ValueError):
            ViaW65c22PortPin("XX0")

    def test_non_string(self):
        with pytest.raises(ValueError):
            ViaW65c22PortPin(123)

    def test_idempotency(self):
        original = ViaW65c22PortPin("PA0")
        wrapped = ViaW65c22PortPin(original)
        assert wrapped is original


class TestViaW65c22Port:
    @pytest.mark.parametrize(
        "value,expected",
        [
            ("A", "A"),
            ("a", "A"),
            ("B", "B"),
            ("b", "B"),
        ],
    )
    def test_valid_ports(self, value, expected):
        result = ViaW65c22Port(value)
        assert result == expected

    def test_invalid_port(self):
        with pytest.raises(ValueError):
            ViaW65c22Port("C")

    def test_non_string(self):
        with pytest.raises(ValueError):
            ViaW65c22Port(123)

    def test_idempotency(self):
        original = ViaW65c22Port("A")
        wrapped = ViaW65c22Port(original)
        assert wrapped is original
