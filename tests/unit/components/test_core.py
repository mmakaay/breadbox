import pytest

from breadbox.components.core.device import CoreDevice
from breadbox.components.core.resolve import resolve
from breadbox.config import BreadboxConfig
from breadbox.types.component_identifier import ComponentIdentifier


def make_config():
    config = object.__new__(BreadboxConfig)
    config.components = {}
    return config


class TestCoreDevice:
    def test_valid_6502(self):
        core = CoreDevice(id=ComponentIdentifier("CORE"), cpu="6502", clock_mhz=1.0)
        assert core.cpu == "6502"
        assert core.clock_mhz == 1.0

    def test_valid_65c02(self):
        core = CoreDevice(id=ComponentIdentifier("CORE"), cpu="65c02", clock_mhz=2.5)
        assert core.cpu == "65c02"
        assert core.clock_mhz == 2.5

    def test_default_cpu(self):
        core = CoreDevice(id=ComponentIdentifier("CORE"), clock_mhz=1.0)
        assert core.cpu == "6502"

    def test_invalid_cpu(self):
        with pytest.raises(ValueError, match="Invalid CPU type"):
            CoreDevice(id=ComponentIdentifier("CORE"), cpu="z80", clock_mhz=1.0)

    @pytest.mark.parametrize("clock", [0, -1, -0.5])
    def test_invalid_clock(self, clock):
        with pytest.raises(ValueError, match="clock_mhz must be positive"):
            CoreDevice(id=ComponentIdentifier("CORE"), clock_mhz=clock)

    def test_clock_mhz_coerced_to_float(self):
        core = CoreDevice(id=ComponentIdentifier("CORE"), clock_mhz=1)
        assert isinstance(core.clock_mhz, float)
        assert core.clock_mhz == 1.0


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
        core = CoreDevice(id=ComponentIdentifier("CORE"), clock_mhz=mhz)
        assert core.clock_hz == expected_hz


class TestResolve:
    def test_resolve_creates_device(self):
        config = make_config()
        component_id = ComponentIdentifier("CORE")
        settings = {"cpu": "65c02", "clock_mhz": 1.0}
        device = resolve(config, component_id, settings)
        assert isinstance(device, CoreDevice)
        assert device.id == "CORE"
        assert device.cpu == "65c02"
        assert device.clock_mhz == 1.0


class TestCoreIdEnforcement:
    def test_id_must_be_core(self):
        with pytest.raises(ValueError, match="must always have id 'CORE'"):
            CoreDevice(id=ComponentIdentifier("CPU"), cpu="65c02", clock_mhz=1.0)

    def test_id_core_accepted(self):
        core = CoreDevice(id=ComponentIdentifier("CORE"), cpu="65c02", clock_mhz=1.0)
        assert core.id == "CORE"
