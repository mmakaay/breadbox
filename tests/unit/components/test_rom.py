import pytest

from breadbox.components.rom.device import RomDevice
from breadbox.types.device_identifier import DeviceIdentifier


def make_rom(device_id="ROM", address="$8000", size=0x8000, **kwargs):
    return RomDevice(id=DeviceIdentifier(device_id), address=address, size=size, **kwargs)


class TestRomDevice:
    def test_basic_creation(self):
        rom = make_rom()
        assert str(rom.id) == "ROM"
        assert int(rom.address) == 0x8000
        assert rom.size == 0x8000

    def test_size_coerced_to_memory_size(self):
        rom = make_rom()
        assert type(rom.size).__name__ == "MemorySize"

    def test_end_address(self):
        rom = make_rom(address="$8000", size=0x8000)
        assert rom.end_address == 0x10000

    def test_covers_vectors(self):
        rom = make_rom(address="$8000", size=0x8000)
        assert rom.covers(0xFFFA, 0x10000)

    def test_small_rom_does_not_cover_vectors(self):
        rom = make_rom(address="$8000", size=0x4000)
        assert not rom.covers(0xFFFA, 0x10000)

    def test_segments_default_empty(self):
        rom = make_rom()
        assert rom.segments == []

    def test_segments_from_config(self):
        rom = make_rom(segments=["CODE", "RODATA"])
        assert rom.segments == ["CODE", "RODATA"]

    def test_component_type(self):
        rom = make_rom()
        assert rom.component_type == "rom"


class TestRomDeviceValidation:
    def test_zero_size_raises(self):
        with pytest.raises(ValueError, match="positive"):
            make_rom(size=0)

    def test_negative_size_raises(self):
        with pytest.raises(ValueError, match="negative"):
            make_rom(size=-1)

    def test_exceeds_address_space_raises(self):
        with pytest.raises(ValueError, match="exceeds"):
            make_rom(address="$FF00", size=0x0200)

    def test_exact_fit_at_top(self):
        rom = make_rom(address="$E000", size=0x2000)
        assert rom.end_address == 0x10000
        assert rom.covers(0xFFFA, 0x10000)
