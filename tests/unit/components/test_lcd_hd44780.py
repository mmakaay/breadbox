import pytest

from breadbox.components.lcd_hd44780.device import CmndSettings, DataSettings, LcdHd44780Device
from breadbox.components.lcd_hd44780.resolve import resolve
from breadbox.components.via_w65c22.device import ViaW65c22Device
from breadbox.components.via_w65c22.gpio_group.device import ViaW65c22GpioGroupDevice
from breadbox.config import BreadboxConfig
from breadbox.types.address16 import Address16
from breadbox.types.component_identifier import ComponentIdentifier


def make_config(*devices):
    config = object.__new__(BreadboxConfig)
    config.components = {d.id: d for d in devices}
    return config


class TestCmndSettings:
    def test_construction(self):
        cmnd = CmndSettings(bus="VIA0", rwb_pin="PA0", en_pin="PA1", rs_pin="PA2")
        assert cmnd.rwb_pin == "PA0"
        assert cmnd.en_pin == "PA1"
        assert cmnd.rs_pin == "PA2"

    def test_bus_coerced_to_component_identifier(self):
        cmnd = CmndSettings(bus="VIA0", rwb_pin="PA0", en_pin="PA1", rs_pin="PA2")
        assert isinstance(cmnd.bus, ComponentIdentifier)
        assert cmnd.bus == "VIA0"


class TestDataSettings:
    def test_construction_4bit(self):
        data = DataSettings(bus="VIA0", mode="4bit", port="B")
        assert data.mode == "4bit"
        assert data.port == "B"

    def test_construction_8bit(self):
        data = DataSettings(bus="VIA0", mode="8bit", port="B")
        assert data.mode == "8bit"

    def test_mode_lowercased(self):
        data = DataSettings(bus="VIA0", mode="4BIT", port="B")
        assert data.mode == "4bit"

    def test_invalid_mode(self):
        with pytest.raises(ValueError, match="Invalid mode"):
            DataSettings(bus="VIA0", mode="16bit", port="B")

    def test_bus_coerced_to_component_identifier(self):
        data = DataSettings(bus="VIA0", mode="4bit", port="B")
        assert isinstance(data.bus, ComponentIdentifier)


class TestLcdHd44780Device:
    def test_construction(self):
        device = LcdHd44780Device(id=ComponentIdentifier("LCD0"), mode="8bit", rs_pin="PA0", rwb_pin="PA1")
        assert device.id == "LCD0"
        assert device.mode == "8bit"
        assert len(device.children) == 0

    def test_mode_4bit(self):
        device = LcdHd44780Device(id=ComponentIdentifier("LCD0"), mode="4bit", rs_pin="PA0", rwb_pin="PA1")
        assert device.mode == "4bit"

    def test_invalid_mode_raises(self):
        with pytest.raises(ValueError, match="Invalid mode"):
            LcdHd44780Device(id=ComponentIdentifier("LCD0"), mode="16bit", rs_pin="PA0", rwb_pin="PA1")

    def test_sub_device_accessors(self):
        via = ViaW65c22Device(id=ComponentIdentifier("VIA0"), address=Address16("$6000"))
        config = make_config(via)

        settings = {
            "cmnd": {"bus": "VIA0", "rwb_pin": "PA0", "en_pin": "PA1", "rs_pin": "PA2"},
            "data": {"bus": "VIA0", "mode": "8bit", "port": "B"},
        }
        device = resolve(config, ComponentIdentifier("LCD0"), settings)

        assert str(device.ctrl.id) == "CTRL"
        assert isinstance(device.ctrl, ViaW65c22GpioGroupDevice)
        assert str(device.pin_en.id) == "PIN_EN"
        assert str(device.data.id) == "DATA"

    def test_sub_device_accessor_missing_raises(self):
        device = LcdHd44780Device(id=ComponentIdentifier("LCD0"), mode="8bit", rs_pin="PA0", rwb_pin="PA1")
        with pytest.raises(ValueError, match="Child component.*not found"):
            _ = device.ctrl

    def test_rs_bit_and_rwb_bit(self):
        via = ViaW65c22Device(id=ComponentIdentifier("VIA0"), address=Address16("$6000"))
        config = make_config(via)

        settings = {
            "cmnd": {"bus": "VIA0", "rs_pin": "PB0", "rwb_pin": "PB1", "en_pin": "PB2"},
            "data": {"bus": "VIA0", "mode": "4bit", "port": "B"},
        }
        device = resolve(config, ComponentIdentifier("LCD0"), settings)

        # PB0 = bit 0, PB1 = bit 1
        assert device.rs_bit == 0x01
        assert device.rwb_bit == 0x02

    def test_rs_bit_and_rwb_bit_reversed(self):
        via = ViaW65c22Device(id=ComponentIdentifier("VIA0"), address=Address16("$6000"))
        config = make_config(via)

        # Swap RS and RWB pin assignments
        settings = {
            "cmnd": {"bus": "VIA0", "rs_pin": "PA5", "rwb_pin": "PA3", "en_pin": "PA1"},
            "data": {"bus": "VIA0", "mode": "4bit", "port": "B"},
        }
        device = resolve(config, ComponentIdentifier("LCD0"), settings)

        # PA5 = bit 5, PA3 = bit 3
        assert device.rs_bit == 0x20
        assert device.rwb_bit == 0x08
class TestResolve:
    def test_resolve_creates_sub_devices(self):
        via = ViaW65c22Device(id=ComponentIdentifier("VIA0"), address=Address16("$6000"))
        config = make_config(via)

        settings = {
            "cmnd": {"bus": "VIA0", "rwb_pin": "PA0", "en_pin": "PA1", "rs_pin": "PA2"},
            "data": {"bus": "VIA0", "mode": "4bit", "port": "B"},
        }
        device = resolve(config, ComponentIdentifier("LCD0"), settings)

        assert isinstance(device, LcdHd44780Device)
        assert device.id == "LCD0"
        assert len(device.children) == 3

        sub_ids = [str(d.id) for d in device.children]
        assert "CTRL" in sub_ids
        assert "PIN_EN" in sub_ids
        assert "DATA" in sub_ids

    def test_resolve_8bit_mode(self):
        via = ViaW65c22Device(id=ComponentIdentifier("VIA0"), address=Address16("$6000"))
        config = make_config(via)

        settings = {
            "cmnd": {"bus": "VIA0", "rwb_pin": "PA0", "en_pin": "PA1", "rs_pin": "PA2"},
            "data": {"bus": "VIA0", "mode": "8bit", "port": "B"},
        }
        device = resolve(config, ComponentIdentifier("LCD0"), settings)

        data_device = next(d for d in device.children if str(d.id) == "DATA")
        assert isinstance(data_device, ViaW65c22GpioGroupDevice)
        assert data_device.bits == 0xFF
        assert device.mode == "8bit"

    def test_resolve_4bit_mode_data_bits(self):
        via = ViaW65c22Device(id=ComponentIdentifier("VIA0"), address=Address16("$6000"))
        config = make_config(via)

        settings = {
            "cmnd": {"bus": "VIA0", "rwb_pin": "PA0", "en_pin": "PA1", "rs_pin": "PA2"},
            "data": {"bus": "VIA0", "mode": "4bit", "port": "B"},
        }
        device = resolve(config, ComponentIdentifier("LCD0"), settings)

        assert device.mode == "4bit"
        data_device = next(d for d in device.children if str(d.id) == "DATA")
        assert isinstance(data_device, ViaW65c22GpioGroupDevice)
        assert data_device.bits == 0xF0

    def test_sub_devices_have_parent(self):
        via = ViaW65c22Device(id=ComponentIdentifier("VIA0"), address=Address16("$6000"))
        config = make_config(via)

        settings = {
            "cmnd": {"bus": "VIA0", "rwb_pin": "PA0", "en_pin": "PA1", "rs_pin": "PA2"},
            "data": {"bus": "VIA0", "mode": "4bit", "port": "B"},
        }
        device = resolve(config, ComponentIdentifier("LCD0"), settings)

        for sub in device.children:
            assert sub.parent is device


class TestDuplicatePinValidation:
    def test_valid_config_no_duplicates(self):
        via = ViaW65c22Device(id=ComponentIdentifier("VIA0"), address=Address16("$6000"))
        config = make_config(via)

        settings = {
            "cmnd": {"bus": "VIA0", "rwb_pin": "PA0", "en_pin": "PA1", "rs_pin": "PA2"},
            "data": {"bus": "VIA0", "mode": "4bit", "port": "B"},
        }
        # Should not raise -- cmnd pins on port A, data pins on port B
        device = resolve(config, ComponentIdentifier("LCD0"), settings)
        assert len(device.children) == 3

    def test_duplicate_cmnd_pin_raises(self):
        via = ViaW65c22Device(id=ComponentIdentifier("VIA0"), address=Address16("$6000"))
        config = make_config(via)

        settings = {
            "cmnd": {"bus": "VIA0", "rwb_pin": "PA0", "en_pin": "PA1", "rs_pin": "PA0"},
            "data": {"bus": "VIA0", "mode": "4bit", "port": "B"},
        }
        with pytest.raises(ValueError, match="Duplicate pin assignment"):
            resolve(config, ComponentIdentifier("LCD0"), settings)

    def test_cmnd_pin_overlaps_data_raises(self):
        via = ViaW65c22Device(id=ComponentIdentifier("VIA0"), address=Address16("$6000"))
        config = make_config(via)

        # CTRL pins PB4+PB5 overlap with 4bit data on port B (PB4-PB7)
        settings = {
            "cmnd": {"bus": "VIA0", "rs_pin": "PB4", "rwb_pin": "PB5", "en_pin": "PA1"},
            "data": {"bus": "VIA0", "mode": "4bit", "port": "B"},
        }
        with pytest.raises(ValueError, match="Duplicate pin assignment"):
            resolve(config, ComponentIdentifier("LCD0"), settings)

    def test_different_buses_no_conflict(self):
        via0 = ViaW65c22Device(id=ComponentIdentifier("VIA0"), address=Address16("$6000"))
        via1 = ViaW65c22Device(id=ComponentIdentifier("VIA1"), address=Address16("$7000"))
        config = make_config(via0, via1)

        # Same pin names but different buses -- should not raise
        settings = {
            "cmnd": {"bus": "VIA0", "rwb_pin": "PA0", "en_pin": "PA1", "rs_pin": "PA2"},
            "data": {"bus": "VIA1", "mode": "4bit", "port": "A"},
        }
        device = resolve(config, ComponentIdentifier("LCD0"), settings)
        assert len(device.children) == 3
