import pytest

from breadbox.components.cpu.device import CpuDevice
from breadbox.components.cpu.component import resolve
from breadbox.config import BreadboxConfig
from breadbox.types.device_identifier import DeviceIdentifier


def make_config():
    config = object.__new__(BreadboxConfig)
    config.devices = {}
    return config


class TestCpuDevice:
    def test_valid_6502(self):
        cpu = CpuDevice(id=DeviceIdentifier("CPU"), type="6502", clock_mhz=1.0)
        assert cpu.type == "6502"
        assert cpu.clock_mhz == 1.0

    def test_valid_65c02(self):
        cpu = CpuDevice(id=DeviceIdentifier("CPU"), type="65c02", clock_mhz=2.5)
        assert cpu.type == "65c02"
        assert cpu.clock_mhz == 2.5

    def test_default_type(self):
        cpu = CpuDevice(id=DeviceIdentifier("CPU"), clock_mhz=1.0)
        assert cpu.type == "6502"

    def test_invalid_type(self):
        with pytest.raises(ValueError, match="Invalid CPU type"):
            CpuDevice(id=DeviceIdentifier("CPU"), type="z80", clock_mhz=1.0)

    @pytest.mark.parametrize("clock", [0, -1, -0.5])
    def test_invalid_clock(self, clock):
        with pytest.raises(ValueError, match="clock_mhz must be positive"):
            CpuDevice(id=DeviceIdentifier("CPU"), clock_mhz=clock)

    def test_clock_mhz_coerced_to_float(self):
        cpu = CpuDevice(id=DeviceIdentifier("CPU"), clock_mhz=1)
        assert isinstance(cpu.clock_mhz, float)
        assert cpu.clock_mhz == 1.0


class TestClockHz:
    @pytest.mark.parametrize(
        "mhz,expected_hz",
        [
            (1.0, 1_000_000),
            (2.5, 2_500_000),
            (0.001, 1_000),
        ],
    )
    def test_clock_hz(self, mhz, expected_hz):
        cpu = CpuDevice(id=DeviceIdentifier("CPU"), clock_mhz=mhz)
        assert cpu.clock_hz == expected_hz


class TestResolve:
    def test_resolve_creates_device(self):
        config = make_config()
        device_id = DeviceIdentifier("CPU")
        settings = {"type": "65c02", "clock_mhz": 1.0}
        device = resolve(config, device_id, settings)
        assert isinstance(device, CpuDevice)
        assert device.id == "CPU"
        assert device.type == "65c02"
        assert device.clock_mhz == 1.0
