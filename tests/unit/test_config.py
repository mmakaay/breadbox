import pytest

from breadbox.components.core.device import CoreDevice
from breadbox.config import BreadboxConfig
from breadbox.errors import ConfigError
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
