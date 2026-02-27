import pytest

from breadbox.components.ram.device import RamDevice
from breadbox.components.rom.device import RomDevice
from breadbox.errors import ConfigError
from breadbox.memory import resolve_memory_layout
from breadbox.types.component_identifier import ComponentIdentifier


def make_ram(component_id="RAM", address="$0000", size=0x4000, segments=None):
    return RamDevice(
        id=ComponentIdentifier(component_id),
        address=address,
        size=size,
        segments=segments or [],
    )


def make_rom(component_id="ROM", address="$8000", size=0x8000, segments=None):
    return RomDevice(
        id=ComponentIdentifier(component_id),
        address=address,
        size=size,
        segments=segments or [],
    )


class TestMemoryCoverage:
    """Validate that required address ranges are covered."""

    def test_no_ram_raises(self):
        rom = make_rom()
        with pytest.raises(ConfigError, match="at least one RAM"):
            resolve_memory_layout([], [rom])

    def test_no_rom_raises(self):
        ram = make_ram()
        with pytest.raises(ConfigError, match="at least one ROM"):
            resolve_memory_layout([ram], [])

    def test_ram_not_covering_zeropage_raises(self):
        ram = make_ram(address="$0200", size=0x1000)
        rom = make_rom()
        with pytest.raises(ConfigError, match="zero page"):
            resolve_memory_layout([ram], [rom])

    def test_ram_not_covering_stack_raises(self):
        ram = make_ram(address="$0000", size=0x0100)
        rom = make_rom()
        with pytest.raises(ConfigError, match="stack"):
            resolve_memory_layout([ram], [rom])

    def test_rom_not_covering_vectors_raises(self):
        ram = make_ram()
        rom = make_rom(address="$8000", size=0x4000)
        with pytest.raises(ConfigError, match="vectors"):
            resolve_memory_layout([ram], [rom])

    def test_minimal_valid_config(self):
        ram = make_ram(address="$0000", size=0x0200)
        rom = make_rom(address="$FFFA", size=6)
        layout = resolve_memory_layout([ram], [rom])
        assert layout is not None


class TestMemoryOverlap:
    """Memory devices must not overlap each other."""

    def test_overlapping_ram_raises(self):
        ram1 = make_ram("RAM1", address="$0000", size=0x4000)
        ram2 = make_ram("RAM2", address="$2000", size=0x4000)
        rom = make_rom()
        with pytest.raises(ConfigError, match="overlap"):
            resolve_memory_layout([ram1, ram2], [rom])

    def test_overlapping_ram_rom_raises(self):
        ram = make_ram(address="$0000", size=0x9000)
        rom = make_rom(address="$8000", size=0x8000)
        with pytest.raises(ConfigError, match="overlap"):
            resolve_memory_layout([ram], [rom])

    def test_adjacent_regions_ok(self):
        ram = make_ram(address="$0000", size=0x8000)
        rom = make_rom(address="$8000", size=0x8000)
        layout = resolve_memory_layout([ram], [rom])
        assert layout is not None


class TestDefaultSegments:
    """When no segments specified, defaults are generated."""

    def test_default_ram_segment_uses_component_id(self):
        ram = make_ram("RAM", address="$0000", size=0x4000)
        rom = make_rom()
        layout = resolve_memory_layout([ram], [rom])
        seg_names = [s.name for s in layout.segments]
        assert "RAM" in seg_names

    def test_default_rom_segment_uses_component_id(self):
        ram = make_ram()
        rom = make_rom("ROM")
        layout = resolve_memory_layout([ram], [rom])
        seg_names = [s.name for s in layout.segments]
        assert "ROM" in seg_names

    def test_kernalrom_auto_assigned_to_vectors_rom(self):
        ram = make_ram()
        rom = make_rom()
        layout = resolve_memory_layout([ram], [rom])
        kernal = [s for s in layout.segments if s.name == "KERNALROM"]
        assert len(kernal) == 1
        assert kernal[0].load == "ROM"

class TestFixedSegments:
    """ZEROPAGE, KERNALZP, STACK, and VECTORS are always auto-assigned."""

    def test_zeropage_present(self):
        ram = make_ram()
        rom = make_rom()
        layout = resolve_memory_layout([ram], [rom])
        zp = [s for s in layout.segments if s.name == "ZEROPAGE"]
        assert len(zp) == 1
        assert zp[0].type == "zp"

    def test_stack_present(self):
        ram = make_ram()
        rom = make_rom()
        layout = resolve_memory_layout([ram], [rom])
        stack = [s for s in layout.segments if s.name == "STACK"]
        assert len(stack) == 1
        assert stack[0].type == "bss"

    def test_vectors_present(self):
        ram = make_ram()
        rom = make_rom()
        layout = resolve_memory_layout([ram], [rom])
        vectors = [s for s in layout.segments if s.name == "VECTORS"]
        assert len(vectors) == 1
        assert vectors[0].type == "ro"

    def test_zeropage_region_correct(self):
        ram = make_ram()
        rom = make_rom()
        layout = resolve_memory_layout([ram], [rom])
        zp = [r for r in layout.regions if r.name == "ZEROPAGE"]
        assert len(zp) == 1
        assert zp[0].start == 0x0000
        assert zp[0].size == 0x0100

    def test_stack_region_correct(self):
        ram = make_ram()
        rom = make_rom()
        layout = resolve_memory_layout([ram], [rom])
        stack = [r for r in layout.regions if r.name == "STACK"]
        assert len(stack) == 1
        assert stack[0].start == 0x0100
        assert stack[0].size == 0x0100

    def test_vectors_region_correct(self):
        ram = make_ram()
        rom = make_rom()
        layout = resolve_memory_layout([ram], [rom])
        vectors = [r for r in layout.regions if r.name == "VECTORS"]
        assert len(vectors) == 1
        assert vectors[0].start == 0xFFFA
        assert vectors[0].size == 0x0006


class TestUserSegments:
    """User-defined segments are placed correctly."""

    def test_user_ram_segments(self):
        ram = make_ram(segments=["APPDATA", "BSS"])
        rom = make_rom()
        layout = resolve_memory_layout([ram], [rom])
        seg_names = [s.name for s in layout.segments]
        assert "APPDATA" in seg_names
        assert "BSS" in seg_names

    def test_user_rom_segments(self):
        ram = make_ram()
        rom = make_rom(segments=["CODE", "RODATA"])
        layout = resolve_memory_layout([ram], [rom])
        seg_names = [s.name for s in layout.segments]
        assert "CODE" in seg_names
        assert "RODATA" in seg_names

    def test_user_segments_load_correct_region(self):
        ram = make_ram()
        rom = make_rom("MYROM", segments=["CODE"])
        layout = resolve_memory_layout([ram], [rom])
        code = [s for s in layout.segments if s.name == "CODE"]
        assert len(code) == 1
        assert code[0].load == "MYROM"


class TestReservedSegments:
    """Reserved segment names are rejected."""

    def test_zeropage_reserved(self):
        ram = make_ram(segments=["ZEROPAGE"])
        rom = make_rom()
        with pytest.raises(ConfigError, match="reserved"):
            resolve_memory_layout([ram], [rom])

    def test_stack_reserved(self):
        ram = make_ram(segments=["STACK"])
        rom = make_rom()
        with pytest.raises(ConfigError, match="reserved"):
            resolve_memory_layout([ram], [rom])

    def test_vectors_reserved(self):
        rom1 = make_rom("ROM1", address="$C000", size=0x4000)
        rom2 = make_rom("ROM2", address="$8000", size=0x4000, segments=["VECTORS"])
        ram = make_ram()
        with pytest.raises(ConfigError, match="reserved"):
            resolve_memory_layout([ram], [rom1, rom2])


class TestKernalromOverride:
    """KERNALROM segment can be explicitly assigned to a different ROM."""

    def test_kernalrom_default_in_vectors_rom(self):
        ram = make_ram()
        rom = make_rom("ROM")
        layout = resolve_memory_layout([ram], [rom])
        kernal = [s for s in layout.segments if s.name == "KERNALROM"]
        assert kernal[0].load == "ROM"

    def test_kernalrom_override_to_different_rom(self):
        ram = make_ram()
        rom0 = make_rom("ROM0", address="$8000", size=0x4000, segments=["KERNALROM"])
        rom1 = make_rom("ROM1", address="$C000", size=0x4000)
        layout = resolve_memory_layout([ram], [rom0, rom1])
        kernal = [s for s in layout.segments if s.name == "KERNALROM"]
        assert len(kernal) == 1
        assert kernal[0].load == "ROM0"

    def test_kernalrom_in_ram_raises(self):
        ram = make_ram(segments=["KERNALROM"])
        rom = make_rom()
        with pytest.raises(ConfigError, match="ROM device"):
            resolve_memory_layout([ram], [rom])

    def test_component_id_matching_auto_rom_segment_no_duplicate(self):
        """ROM device named KERNALROM with segments=[KERNALROM] must not emit KERNALROM twice."""
        ram = make_ram()
        kernal_rom = make_rom("KERNALROM", address="$8000", size=0x2000, segments=["KERNALROM"])
        rom = make_rom("ROM", address="$A000", size=0x6000)
        layout = resolve_memory_layout([ram], [kernal_rom, rom])
        kernal_segs = [s for s in layout.segments if s.name == "KERNALROM"]
        assert len(kernal_segs) == 1
        assert kernal_segs[0].load == "KERNALROM"

class TestCodeSegment:
    """CODE segment (ca65 default) is auto-assigned like KERNALROM."""

    def test_code_auto_assigned_to_vectors_rom(self):
        ram = make_ram()
        rom = make_rom("ROM")
        layout = resolve_memory_layout([ram], [rom])
        code = [s for s in layout.segments if s.name == "CODE"]
        assert len(code) == 1
        assert code[0].load == "ROM"

    def test_code_override_to_different_rom(self):
        ram = make_ram()
        rom0 = make_rom("ROM0", address="$8000", size=0x4000, segments=["CODE"])
        rom1 = make_rom("ROM1", address="$C000", size=0x4000)
        layout = resolve_memory_layout([ram], [rom0, rom1])
        code = [s for s in layout.segments if s.name == "CODE"]
        assert len(code) == 1
        assert code[0].load == "ROM0"

    def test_code_in_ram_raises(self):
        ram = make_ram(segments=["CODE"])
        rom = make_rom()
        with pytest.raises(ConfigError, match="ROM device"):
            resolve_memory_layout([ram], [rom])

    def test_kernalrom_and_code_on_different_roms(self):
        ram = make_ram()
        rom0 = make_rom("ROM0", address="$8000", size=0x4000, segments=["CODE"])
        rom1 = make_rom("ROM1", address="$C000", size=0x4000, segments=["KERNALROM"])
        layout = resolve_memory_layout([ram], [rom0, rom1])
        code = [s for s in layout.segments if s.name == "CODE"]
        kernal = [s for s in layout.segments if s.name == "KERNALROM"]
        assert code[0].load == "ROM0"
        assert kernal[0].load == "ROM1"

class TestDataSegment:
    """DATA segment is auto-assigned to vectors ROM like CODE."""

    def test_data_auto_assigned_to_vectors_rom(self):
        ram = make_ram()
        rom = make_rom("ROM")
        layout = resolve_memory_layout([ram], [rom])
        data = [s for s in layout.segments if s.name == "DATA"]
        assert len(data) == 1
        assert data[0].load == "ROM"

    def test_data_override_to_different_rom(self):
        ram = make_ram()
        rom0 = make_rom("ROM0", address="$8000", size=0x4000, segments=["DATA"])
        rom1 = make_rom("ROM1", address="$C000", size=0x4000)
        layout = resolve_memory_layout([ram], [rom0, rom1])
        data = [s for s in layout.segments if s.name == "DATA"]
        assert len(data) == 1
        assert data[0].load == "ROM0"

    def test_data_in_ram_raises(self):
        ram = make_ram(segments=["DATA"])
        rom = make_rom()
        with pytest.raises(ConfigError, match="ROM device"):
            resolve_memory_layout([ram], [rom])

class TestSegmentUniqueness:
    """No segment name can appear in multiple devices."""

    def test_duplicate_segment_raises(self):
        ram = make_ram(segments=["SHARED"])
        rom = make_rom(segments=["SHARED"])
        with pytest.raises(ConfigError, match="defined in both"):
            resolve_memory_layout([ram], [rom])

    def test_unique_segments_pass(self):
        ram = make_ram(segments=["APPDATA"])
        rom = make_rom(segments=["CODE"])
        layout = resolve_memory_layout([ram], [rom])
        assert layout is not None


class TestMultipleMemoryDevices:
    """Multiple RAM and ROM devices work correctly."""

    def test_two_rom_devices(self):
        ram = make_ram()
        rom0 = make_rom("ROM0", address="$8000", size=0x4000, segments=["CODE"])
        rom1 = make_rom("ROM1", address="$C000", size=0x4000, segments=["RODATA"])
        layout = resolve_memory_layout([ram], [rom0, rom1])

        region_names = [r.name for r in layout.regions]
        assert "ROM0" in region_names
        assert "ROM1" in region_names
        assert "VECTORS" in region_names

    def test_vectors_carved_from_correct_rom(self):
        ram = make_ram()
        rom0 = make_rom("ROM0", address="$8000", size=0x4000, segments=["CODE"])
        rom1 = make_rom("ROM1", address="$C000", size=0x4000)
        layout = resolve_memory_layout([ram], [rom0, rom1])

        vectors = [r for r in layout.regions if r.name == "VECTORS"]
        assert len(vectors) == 1

        # ROM1 region should be reduced by 6 bytes for VECTORS
        rom1_region = [r for r in layout.regions if r.name == "ROM1"]
        assert rom1_region[0].size == 0x4000 - 6

    def test_ram_at_minimum_zp_stack_only(self):
        """RAM of exactly $0200 has no remaining space for a user segment."""
        ram = make_ram(address="$0000", size=0x0200)
        rom = make_rom()
        layout = resolve_memory_layout([ram], [rom])

        # Should have ZEROPAGE and STACK regions, but no RAM region
        region_names = [r.name for r in layout.regions]
        assert "ZEROPAGE" in region_names
        assert "STACK" in region_names
        assert "RAM" not in region_names

    def test_regions_sorted_by_address(self):
        ram = make_ram()
        rom = make_rom()
        layout = resolve_memory_layout([ram], [rom])

        starts = [r.start for r in layout.regions]
        assert starts == sorted(starts)


class TestDefaultLayout:
    """Default RAM ($0000, $4000) + ROM ($8000, $8000) matches old static config."""

    def test_matches_old_linker_config(self):
        ram = make_ram(address="$0000", size=0x4000)
        rom = make_rom(address="$8000", size=0x8000, segments=["CODE"])
        layout = resolve_memory_layout([ram], [rom])

        region_names = [r.name for r in layout.regions]
        assert region_names == ["ZEROPAGE", "STACK", "RAM", "ROM", "VECTORS"]

        seg_names = [s.name for s in layout.segments]
        assert "ZEROPAGE" in seg_names
        assert "STACK" in seg_names
        assert "RAM" in seg_names
        assert "KERNALROM" in seg_names
        assert "CODE" in seg_names
        assert "DATA" in seg_names
        assert "VECTORS" in seg_names
        assert "KERNALZP" in seg_names
        assert "KERNALRAM" in seg_names


class TestKernalzpSegment:
    """KERNALZP segment is auto-assigned to the ZEROPAGE memory region."""

    def test_kernalzp_present(self):
        ram = make_ram()
        rom = make_rom()
        layout = resolve_memory_layout([ram], [rom])
        kzp = [s for s in layout.segments if s.name == "KERNALZP"]
        assert len(kzp) == 1
        assert kzp[0].type == "zp"
        assert kzp[0].load == "ZEROPAGE"

    def test_kernalzp_before_zeropage_in_segment_order(self):
        ram = make_ram()
        rom = make_rom()
        layout = resolve_memory_layout([ram], [rom])
        seg_names = [s.name for s in layout.segments]
        assert seg_names.index("KERNALZP") < seg_names.index("ZEROPAGE")

    def test_kernalzp_reserved(self):
        ram = make_ram(segments=["KERNALZP"])
        rom = make_rom()
        with pytest.raises(ConfigError, match="reserved"):
            resolve_memory_layout([ram], [rom])


class TestKernalramSegment:
    """KERNALRAM segment is auto-assigned to the main RAM device."""

    def test_kernalram_present(self):
        ram = make_ram()
        rom = make_rom()
        layout = resolve_memory_layout([ram], [rom])
        kram = [s for s in layout.segments if s.name == "KERNALRAM"]
        assert len(kram) == 1
        assert kram[0].type == "bss"
        assert kram[0].load == "RAM"

    def test_kernalram_override_to_different_ram(self):
        ram0 = make_ram("RAM0", address="$0000", size=0x2000)
        ram1 = make_ram("RAM1", address="$2000", size=0x2000, segments=["KERNALRAM"])
        rom = make_rom()
        layout = resolve_memory_layout([ram0, ram1], [rom])
        kram = [s for s in layout.segments if s.name == "KERNALRAM"]
        assert len(kram) == 1
        assert kram[0].load == "RAM1"

    def test_kernalram_in_rom_raises(self):
        ram = make_ram()
        rom = make_rom(segments=["KERNALRAM"])
        with pytest.raises(ConfigError, match="RAM device"):
            resolve_memory_layout([ram], [rom])

    def test_kernalram_default_on_main_ram(self):
        """KERNALRAM defaults to the RAM covering $0000 (main RAM)."""
        ram0 = make_ram("RAM0", address="$0000", size=0x2000)
        ram1 = make_ram("RAM1", address="$2000", size=0x2000)
        rom = make_rom()
        layout = resolve_memory_layout([ram0, ram1], [rom])
        kram = [s for s in layout.segments if s.name == "KERNALRAM"]
        assert len(kram) == 1
        assert kram[0].load == "RAM0"
