import pytest

from breadbox.types.address16 import Address16


class TestValidIntegers:
    @pytest.mark.parametrize(
        "value,expected",
        [
            (0, 0),
            (255, 255),
            (0x6000, 0x6000),
            (0xFFFF, 0xFFFF),
        ],
    )
    def test_valid_integers(self, value, expected):
        result = Address16(value)
        assert result == expected
        assert isinstance(result, Address16)
        assert isinstance(result, int)


class TestValidStrings:
    @pytest.mark.parametrize(
        "value,expected",
        [
            ("$6000", 0x6000),
            ("$FFFF", 0xFFFF),
            ("$0000", 0x0000),
            ("$ff", 0xFF),
            ("0x6000", 0x6000),
            ("0xFF", 0xFF),
            ("0x0", 0),
        ],
    )
    def test_valid_hex_strings(self, value, expected):
        result = Address16(value)
        assert result == expected

    def test_whitespace_stripped(self):
        assert Address16(" $6000 ") == 0x6000


class TestOutOfRange:
    @pytest.mark.parametrize("value", [-1, 0x10000, 65536])
    def test_out_of_range_int(self, value):
        with pytest.raises(ValueError):
            Address16(value)

    @pytest.mark.parametrize("value", ["$10000", "0x10000"])
    def test_out_of_range_string(self, value):
        with pytest.raises(ValueError):
            Address16(value)


class TestInvalidInput:
    @pytest.mark.parametrize("value", ["not_hex", "zzz"])
    def test_invalid_string(self, value):
        with pytest.raises(ValueError):
            Address16(value)

    @pytest.mark.parametrize("value", [None, [1, 2], 3.14])
    def test_invalid_type(self, value):
        with pytest.raises(ValueError):
            Address16(value)


class TestBoundaryValues:
    def test_minimum(self):
        assert Address16(0) == 0

    def test_maximum(self):
        assert Address16(65535) == 65535


class TestStringRepresentation:
    def test_str(self):
        assert str(Address16(0x6000)) == "$6000"

    def test_str_zero(self):
        assert str(Address16(0)) == "$0000"

    def test_str_max(self):
        assert str(Address16(0xFFFF)) == "$FFFF"

    def test_repr(self):
        assert repr(Address16(0x6000)) == "Address16($6000)"


class TestIdempotency:
    def test_returns_same_instance(self):
        original = Address16(0x6000)
        wrapped = Address16(original)
        assert wrapped is original
