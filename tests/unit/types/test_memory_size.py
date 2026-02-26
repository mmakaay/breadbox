import pytest

from breadbox.types.memory_size import MemorySize


class TestMemorySizeParsing:
    def test_from_int(self):
        assert MemorySize(256) == 256

    def test_from_hex_string(self):
        assert MemorySize("$4000") == 0x4000

    def test_from_0x_string(self):
        assert MemorySize("0x8000") == 0x8000

    def test_from_decimal_string(self):
        assert MemorySize("1024") == 1024

    def test_zero(self):
        assert MemorySize(0) == 0

    def test_max_64k(self):
        assert MemorySize(0x10000) == 0x10000

    def test_identity(self):
        ms = MemorySize(100)
        assert MemorySize(ms) is ms

    def test_negative_raises(self):
        with pytest.raises(ValueError, match="negative"):
            MemorySize(-1)

    def test_exceeds_16bit_raises(self):
        with pytest.raises(ValueError, match="exceeds"):
            MemorySize(0x10001)

    def test_bad_type_raises(self):
        with pytest.raises(ValueError, match="Cannot parse"):
            MemorySize([1, 2])


class TestMemorySizeDisplay:
    def test_str_bytes(self):
        assert str(MemorySize(100)) == "100 ($0064, 100 B)"

    def test_str_kilobytes_exact(self):
        assert str(MemorySize(1024)) == "1024 ($0400, 1 kB)"

    def test_str_16k(self):
        assert str(MemorySize(0x4000)) == "16384 ($4000, 16 kB)"

    def test_str_32k(self):
        assert str(MemorySize(0x8000)) == "32768 ($8000, 32 kB)"

    def test_str_fractional_kb(self):
        assert str(MemorySize(1536)) == "1536 ($0600, 1.5 kB)"

    def test_str_zero(self):
        assert str(MemorySize(0)) == "0 ($0000, 0 B)"

    def test_repr(self):
        assert repr(MemorySize(0x4000)) == "MemorySize($4000)"


class TestMemorySizeArithmetic:
    """MemorySize is an int subclass, arithmetic should work normally."""

    def test_addition(self):
        assert MemorySize(100) + 50 == 150

    def test_comparison(self):
        assert MemorySize(100) > 50
        assert MemorySize(100) == 100
