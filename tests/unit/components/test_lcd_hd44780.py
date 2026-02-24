import pytest

from breadbox.components.lcd_hd44780.device import CmndSettings, DataSettings, LcdHd44780Device
from breadbox.components.lcd_hd44780.component import resolve
from breadbox.components.via_w65c22.device import ViaW65c22Device
from breadbox.components.via_w65c22.gpio_group.device import ViaW65c22GpioGroupDevice
from breadbox.config import BreadboxConfig
from breadbox.types.address16 import Address16
from breadbox.types.device_identifier import DeviceIdentifier


def make_config(*devices):
    config = object.__new__(BreadboxConfig)
    config.devices = {d.id: d for d in devices}
    return config


class TestCmndSettings:
    def test_construction(self):
        cmnd = CmndSettings(bus="VIA0", rwb_pin="PA0", en_pin="PA1", rs_pin="PA2")
        assert cmnd.rwb_pin == "PA0"
        assert cmnd.en_pin == "PA1"
        assert cmnd.rs_pin == "PA2"

    def test_bus_coerced_to_device_identifier(self):
        cmnd = CmndSettings(bus="VIA0", rwb_pin="PA0", en_pin="PA1", rs_pin="PA2")
        assert isinstance(cmnd.bus, DeviceIdentifier)
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

    def test_bus_coerced_to_device_identifier(self):
        data = DataSettings(bus="VIA0", mode="4bit", port="B")
        assert isinstance(data.bus, DeviceIdentifier)


class TestLcdHd44780Device:
    def test_construction(self):
        device = LcdHd44780Device(id=DeviceIdentifier("LCD0"))
        assert device.id == "LCD0"
        assert len(device.devices) == 0


class TestResolve:
    def test_resolve_creates_sub_devices(self):
        via = ViaW65c22Device(id=DeviceIdentifier("VIA0"), address=Address16("$6000"))
        config = make_config(via)

        settings = {
            "cmnd": {"bus": "VIA0", "rwb_pin": "PA0", "en_pin": "PA1", "rs_pin": "PA2"},
            "data": {"bus": "VIA0", "mode": "4bit", "port": "B"},
        }
        device = resolve(config, DeviceIdentifier("LCD0"), settings)

        assert isinstance(device, LcdHd44780Device)
        assert device.id == "LCD0"
        assert len(device.devices) == 4

        sub_ids = [str(d.id) for d in device.devices]
        assert "PIN_RS" in sub_ids
        assert "PIN_RWB" in sub_ids
        assert "PIN_EN" in sub_ids
        assert "DATA" in sub_ids

    def test_resolve_8bit_mode(self):
        via = ViaW65c22Device(id=DeviceIdentifier("VIA0"), address=Address16("$6000"))
        config = make_config(via)

        settings = {
            "cmnd": {"bus": "VIA0", "rwb_pin": "PA0", "en_pin": "PA1", "rs_pin": "PA2"},
            "data": {"bus": "VIA0", "mode": "8bit", "port": "B"},
        }
        device = resolve(config, DeviceIdentifier("LCD0"), settings)

        data_device = next(d for d in device.devices if str(d.id) == "DATA")
        assert isinstance(data_device, ViaW65c22GpioGroupDevice)
        assert data_device.bits == 0xFF

    def test_sub_devices_have_parent(self):
        via = ViaW65c22Device(id=DeviceIdentifier("VIA0"), address=Address16("$6000"))
        config = make_config(via)

        settings = {
            "cmnd": {"bus": "VIA0", "rwb_pin": "PA0", "en_pin": "PA1", "rs_pin": "PA2"},
            "data": {"bus": "VIA0", "mode": "4bit", "port": "B"},
        }
        device = resolve(config, DeviceIdentifier("LCD0"), settings)

        for sub in device.devices:
            assert sub.parent is device


class TestDuplicatePinValidation:
    def test_valid_config_no_duplicates(self):
        via = ViaW65c22Device(id=DeviceIdentifier("VIA0"), address=Address16("$6000"))
        config = make_config(via)

        settings = {
            "cmnd": {"bus": "VIA0", "rwb_pin": "PA0", "en_pin": "PA1", "rs_pin": "PA2"},
            "data": {"bus": "VIA0", "mode": "4bit", "port": "B"},
        }
        # Should not raise -- cmnd pins on port A, data pins on port B
        device = resolve(config, DeviceIdentifier("LCD0"), settings)
        assert len(device.devices) == 4

    def test_duplicate_cmnd_pin_raises(self):
        via = ViaW65c22Device(id=DeviceIdentifier("VIA0"), address=Address16("$6000"))
        config = make_config(via)

        settings = {
            "cmnd": {"bus": "VIA0", "rwb_pin": "PA0", "en_pin": "PA1", "rs_pin": "PA0"},
            "data": {"bus": "VIA0", "mode": "4bit", "port": "B"},
        }
        with pytest.raises(ValueError, match="Duplicate pin assignment"):
            resolve(config, DeviceIdentifier("LCD0"), settings)

    def test_cmnd_pin_overlaps_data_raises(self):
        via = ViaW65c22Device(id=DeviceIdentifier("VIA0"), address=Address16("$6000"))
        config = make_config(via)

        # rs_pin PB4 overlaps with 4bit data on port B (PB4-PB7)
        settings = {
            "cmnd": {"bus": "VIA0", "rwb_pin": "PA0", "en_pin": "PA1", "rs_pin": "PB4"},
            "data": {"bus": "VIA0", "mode": "4bit", "port": "B"},
        }
        with pytest.raises(ValueError, match="Duplicate pin assignment"):
            resolve(config, DeviceIdentifier("LCD0"), settings)

    def test_different_buses_no_conflict(self):
        via0 = ViaW65c22Device(id=DeviceIdentifier("VIA0"), address=Address16("$6000"))
        via1 = ViaW65c22Device(id=DeviceIdentifier("VIA1"), address=Address16("$7000"))
        config = make_config(via0, via1)

        # Same pin names but different buses -- should not raise
        settings = {
            "cmnd": {"bus": "VIA0", "rwb_pin": "PA0", "en_pin": "PA1", "rs_pin": "PA2"},
            "data": {"bus": "VIA1", "mode": "4bit", "port": "A"},
        }
        device = resolve(config, DeviceIdentifier("LCD0"), settings)
        assert len(device.devices) == 4
