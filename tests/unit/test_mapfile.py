import pytest

from breadbox.mapfile import SegmentEntry, parse_ld65_map, format_memory_map
from breadbox.memory import MemoryLayout, MemoryRegion, Segment


# Sample ld65 map output (minimal, based on real blink project output).
SAMPLE_LD65_MAP = """\
Modules list:
-------------
boot.o:
    ZEROPAGE           Offs=000000  Size=000004  Align=00001  Fill=0000
    KERNALROM         Offs=000000  Size=000040  Align=00001  Fill=0000
vectors.o:
    ZEROPAGE           Offs=000007  Size=000006  Align=00001  Fill=0000
    KERNALROM         Offs=000064  Size=000068  Align=00001  Fill=0000
    VECTORS           Offs=000000  Size=000006  Align=00001  Fill=0000
project.o:
    CODE              Offs=000000  Size=00003D  Align=00001  Fill=0000


Segment list:
-------------
Name                   Start     End    Size  Align
----------------------------------------------------
ZEROPAGE              000000  00000C  00000D  00001
CODE                  008000  00803C  00003D  00001
KERNALROM             00803D  00812C  0000F0  00001
VECTORS               00FFFA  00FFFF  000006  00001


Exports list by name:
---------------------
main                      008000 RLA
"""


# Beneater-style map with KERNALRAM.
BENEATER_LD65_MAP = """\
Segment list:
-------------
Name                   Start     End    Size  Align
----------------------------------------------------
ZEROPAGE              000000  00001B  00001C  00001
KERNALRAM             000200  0003FF  000200  00001
CODE                  008000  008032  000033  00001
KERNALROM             008033  008469  000437  00001
VECTORS               00FFFA  00FFFF  000006  00001

"""


def _make_default_layout():
    """Build a default layout matching RAM=$0000/$4000 + ROM=$8000/$8000."""
    return MemoryLayout(
        regions=[
            MemoryRegion(name="ZEROPAGE", start=0x0000, size=0x0100, type="rw", file=""),
            MemoryRegion(name="STACK", start=0x0100, size=0x0100, type="rw", file=""),
            MemoryRegion(name="RAM", start=0x0200, size=0x3E00, type="rw", file=""),
            MemoryRegion(name="ROM", start=0x8000, size=0x7FFA, type="ro", file="%O", fill=True),
            MemoryRegion(name="VECTORS", start=0xFFFA, size=0x0006, type="ro", file="%O", fill=True),
        ],
        segments=[
            Segment(name="ZEROPAGE", load="ZEROPAGE", type="zp"),
            Segment(name="STACK", load="STACK", type="bss"),
            Segment(name="RAM", load="RAM", type="bss"),
            Segment(name="KERNALRAM", load="RAM", type="bss"),
            Segment(name="CODE", load="ROM", type="ro"),
            Segment(name="KERNALROM", load="ROM", type="ro"),
            Segment(name="VECTORS", load="VECTORS", type="ro"),
        ],
    )


class TestParseLd65Map:
    """Parse segment list from ld65 map output."""

    def test_parses_all_segments(self):
        entries = parse_ld65_map(SAMPLE_LD65_MAP)
        names = [e.name for e in entries]
        assert "ZEROPAGE" in names
        assert "CODE" in names
        assert "KERNALROM" in names
        assert "VECTORS" in names

    def test_segment_count(self):
        entries = parse_ld65_map(SAMPLE_LD65_MAP)
        assert len(entries) == 4

    def test_segment_addresses(self):
        entries = parse_ld65_map(SAMPLE_LD65_MAP)
        by_name = {e.name: e for e in entries}

        kzp = by_name["ZEROPAGE"]
        assert kzp.start == 0x0000
        assert kzp.end == 0x000C
        assert kzp.size == 0x000D

        code = by_name["CODE"]
        assert code.start == 0x8000
        assert code.end == 0x803C
        assert code.size == 0x003D

        vectors = by_name["VECTORS"]
        assert vectors.start == 0xFFFA
        assert vectors.end == 0xFFFF
        assert vectors.size == 6

    def test_sorted_by_start_address(self):
        entries = parse_ld65_map(SAMPLE_LD65_MAP)
        starts = [e.start for e in entries]
        assert starts == sorted(starts)

    def test_parses_kernalram(self):
        entries = parse_ld65_map(BENEATER_LD65_MAP)
        by_name = {e.name: e for e in entries}
        assert "KERNALRAM" in by_name
        kram = by_name["KERNALRAM"]
        assert kram.start == 0x0200
        assert kram.end == 0x03FF
        assert kram.size == 0x0200

    def test_empty_map_returns_empty(self):
        entries = parse_ld65_map("")
        assert entries == []

    def test_no_segment_list_returns_empty(self):
        entries = parse_ld65_map("Modules list:\n-------------\n")
        assert entries == []


class TestFormatMemoryMap:
    """Format a clean memory map from parsed segments."""

    def test_contains_all_regions(self):
        entries = parse_ld65_map(SAMPLE_LD65_MAP)
        layout = _make_default_layout()
        output = format_memory_map(entries, layout)

        assert "[ZEROPAGE]" in output
        assert "[STACK]" in output
        assert "[RAM]" in output
        assert "[ROM]" in output
        assert "[VECTORS]" in output

    def test_shows_zeropage_placement(self):
        entries = parse_ld65_map(SAMPLE_LD65_MAP)
        layout = _make_default_layout()
        output = format_memory_map(entries, layout)

        assert "ZEROPAGE" in output
        assert "$0000-$000C" in output

    def test_shows_free_space_in_zeropage(self):
        entries = parse_ld65_map(SAMPLE_LD65_MAP)
        layout = _make_default_layout()
        output = format_memory_map(entries, layout)

        assert "(free)" in output
        # ZEROPAGE ends at $000C, so free starts at $000D
        assert "$000D-$00FF" in output

    def test_shows_kernalram_placement(self):
        entries = parse_ld65_map(BENEATER_LD65_MAP)
        layout = _make_default_layout()
        output = format_memory_map(entries, layout)

        assert "KERNALRAM" in output
        assert "$0200-$03FF" in output

    def test_shows_free_ram_after_kernalram(self):
        entries = parse_ld65_map(BENEATER_LD65_MAP)
        layout = _make_default_layout()
        output = format_memory_map(entries, layout)

        # KERNALRAM ends at $03FF, so free RAM starts at $0400
        assert "$0400-$3FFF" in output

    def test_shows_rom_segments_in_order(self):
        entries = parse_ld65_map(SAMPLE_LD65_MAP)
        layout = _make_default_layout()
        output = format_memory_map(entries, layout)

        # CODE before KERNALROM (sorted by start address in ld65 output)
        code_pos = output.index("CODE")
        krom_pos = output.index("KERNALROM")
        assert code_pos < krom_pos
