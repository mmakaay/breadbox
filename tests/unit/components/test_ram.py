import pytest

from breadbox.components.ram.device import RamDevice
from breadbox.types.component_identifier import ComponentIdentifier


def make_ram(component_id="RAM", address="$0000", size=0x4000, **kwargs):
    return RamDevice(id=ComponentIdentifier(component_id), address=address, size=size, **kwargs)


class TestRamDevice:
    def test_basic_creation(self):
        ram = make_ram()
        assert str(ram.id) == "RAM"
        assert int(ram.address) == 0x0000
        assert ram.size == 0x4000

    def test_size_coerced_to_memory_size(self):
        ram = make_ram()
        assert type(ram.size).__name__ == "MemorySize"

    def test_end_address(self):
        ram = make_ram(address="$0000", size=0x4000)
        assert ram.end_address == 0x4000

    def test_covers_zeropage(self):
        ram = make_ram(address="$0000", size=0x4000)
        assert ram.covers(0x0000, 0x0100)

    def test_covers_stack(self):
        ram = make_ram(address="$0000", size=0x4000)
        assert ram.covers(0x0100, 0x0200)

    def test_does_not_cover_outside_range(self):
        ram = make_ram(address="$0000", size=0x0100)
        assert not ram.covers(0x0100, 0x0200)

    def test_segments_default_empty(self):
        ram = make_ram()
        assert ram.segments == []

    def test_segments_from_config(self):
        ram = make_ram(segments=["DATA", "BSS"])
        assert ram.segments == ["DATA", "BSS"]

    def test_component_type(self):
        ram = make_ram()
        assert ram.component_type == "ram"


class TestRamDeviceValidation:
    def test_zero_size_raises(self):
        with pytest.raises(ValueError, match="positive"):
            make_ram(size=0)

    def test_negative_size_raises(self):
        with pytest.raises(ValueError, match="negative"):
            make_ram(size=-1)

    def test_exceeds_address_space_raises(self):
        with pytest.raises(ValueError, match="exceeds"):
            make_ram(address="$FF00", size=0x0200)

    def test_max_size_at_zero(self):
        ram = make_ram(address="$0000", size=0x10000)
        assert ram.end_address == 0x10000

    def test_string_size_parsed(self):
        ram = make_ram(size="$4000")
        assert ram.size == 0x4000
