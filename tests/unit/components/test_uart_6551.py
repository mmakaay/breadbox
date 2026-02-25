import pytest

from breadbox.components.uart_6551.device import Uart6551Device
from breadbox.components.uart_6551.component import resolve
from breadbox.components.via_w65c22.device import ViaW65c22Device
from breadbox.config import BreadboxConfig
from breadbox.types.address16 import Address16
from breadbox.types.device_identifier import DeviceIdentifier
from breadbox.types.on_off import OnOff


def make_config(*devices):
    config = object.__new__(BreadboxConfig)
    config.devices = {d.id: d for d in devices}
    return config


class TestUart6551Device:
    def test_valid_generic(self):
        device = Uart6551Device(id=DeviceIdentifier("UART0"), address=Address16("$5000"))
        assert device.type == "generic"
        assert device.address == 0x5000
        assert device.irq == "on"

    @pytest.mark.parametrize("uart_type", ["w65c51n", "um6551", "r6551", "generic"])
    def test_valid_types(self, uart_type):
        device = Uart6551Device(id=DeviceIdentifier("UART0"), type=uart_type, address=Address16("$5000"))
        assert device.type == uart_type

    def test_type_lowercased(self):
        device = Uart6551Device(id=DeviceIdentifier("UART0"), type="W65C51", address=Address16("$5000"))
        assert device.type == "w65c51n"

    def test_invalid_type(self):
        with pytest.raises(ValueError, match="Invalid UART type"):
            Uart6551Device(id=DeviceIdentifier("UART0"), type="z80uart", address=Address16("$5000"))

    def test_default_type(self):
        device = Uart6551Device(id=DeviceIdentifier("UART0"), address=Address16("$5000"))
        assert device.type == "generic"

    def test_default_irq(self):
        device = Uart6551Device(id=DeviceIdentifier("UART0"), address=Address16("$5000"))
        assert device.irq == OnOff("on")

    def test_irq_off(self):
        device = Uart6551Device(id=DeviceIdentifier("UART0"), address=Address16("$5000"), irq=OnOff("off"))
        assert device.irq == "off"

    def test_address_auto_coerced(self):
        device = Uart6551Device(id=DeviceIdentifier("UART0"), address="$5000")  # type: ignore
        assert isinstance(device.address, Address16)


class TestResolveWithoutRts:
    def test_no_rts_no_sub_devices(self):
        config = make_config()
        settings = {"address": "$5000", "type": "w65c51n"}
        device = resolve(config, DeviceIdentifier("UART0"), settings)

        assert isinstance(device, Uart6551Device)
        assert device.id == "UART0"
        assert len(device.devices) == 0


class TestResolveWithRts:
    def test_rts_creates_sub_device(self):
        via = ViaW65c22Device(id=DeviceIdentifier("VIA0"), address=Address16("$6000"))
        config = make_config(via)

        settings = {"address": "$5000", "rts": {"bus": "VIA0", "pin": "PA0"}}
        device = resolve(config, DeviceIdentifier("UART0"), settings)

        assert isinstance(device, Uart6551Device)
        assert len(device.devices) == 1
        sub = device.devices[0]
        assert sub.id == "PIN_RTS"
        assert sub.parent is device
