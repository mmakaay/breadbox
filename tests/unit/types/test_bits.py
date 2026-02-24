import pytest

from breadbox.types.bits import Bits


class TestFromInteger:
    @pytest.mark.parametrize(
        "value,expected",
        [
            (0, 0),
            (255, 255),
            (197, 197),
            (1, 1),
            (128, 128),
        ],
    )
    def test_valid_integers(self, value, expected):
        result = Bits(value)
        assert result == expected
        assert isinstance(result, Bits)
        assert isinstance(result, int)


class TestFromHexString:
    @pytest.mark.parametrize(
        "value,expected",
        [
            ("$FF", 255),
            ("$00", 0),
            ("$ff", 255),
            ("$C5", 197),
            ("0xFF", 255),
            ("0x00", 0),
            ("0xff", 255),
        ],
    )
    def test_valid_hex_strings(self, value, expected):
        assert Bits(value) == expected


class TestFromBinaryString:
    @pytest.mark.parametrize(
        "value,expected",
        [
            ("11000101", 197),
            ("00000000", 0),
            ("11111111", 255),
            ("0b11000101", 197),
            ("0b00000000", 0),
            ("0b11111111", 255),
            ("00000001", 1),
            ("10000000", 128),
        ],
    )
    def test_valid_binary_strings(self, value, expected):
        assert Bits(value) == expected


class TestFromList:
    def test_list_lsb_first(self):
        # [1,0,1,0,0,0,1,1] → bit0=1, bit2=1, bit6=1, bit7=1 → 1+4+64+128 = 197
        assert Bits([1, 0, 1, 0, 0, 0, 1, 1]) == 197

    def test_all_zeros(self):
        assert Bits([0, 0, 0, 0, 0, 0, 0, 0]) == 0

    def test_all_ones(self):
        assert Bits([1, 1, 1, 1, 1, 1, 1, 1]) == 255

    def test_single_bit(self):
        assert Bits([1, 0, 0, 0, 0, 0, 0, 0]) == 1  # bit 0
        assert Bits([0, 0, 0, 0, 0, 0, 0, 1]) == 128  # bit 7


class TestOutOfRange:
    @pytest.mark.parametrize("value", [256, -1, 1000])
    def test_out_of_range_int(self, value):
        with pytest.raises(ValueError):
            Bits(value)


class TestInvalidInput:
    def test_short_list(self):
        with pytest.raises(ValueError):
            Bits([1, 0, 1])

    def test_list_with_invalid_element(self):
        with pytest.raises(ValueError):
            Bits([1, 0, 1, 0, 0, 0, 1, 2])

    def test_long_list(self):
        with pytest.raises(ValueError):
            Bits([1, 0, 1, 0, 0, 0, 1, 1, 0])

    @pytest.mark.parametrize("value", [None, 3.14, {"a": 1}])
    def test_invalid_type(self, value):
        with pytest.raises(ValueError):
            Bits(value)

    def test_invalid_string(self):
        with pytest.raises(ValueError):
            Bits("hello")


class TestPositions:
    @pytest.mark.parametrize(
        "value,expected_positions",
        [
            (0b00000101, [0, 2]),
            (0, []),
            (255, [0, 1, 2, 3, 4, 5, 6, 7]),
            (0b10000000, [7]),
            (0b00000001, [0]),
            (0b11000101, [0, 2, 6, 7]),
        ],
    )
    def test_positions(self, value, expected_positions):
        assert Bits(value).positions == expected_positions


class TestStringRepresentation:
    def test_str(self):
        assert str(Bits(197)) == "0b11000101"

    def test_str_zero(self):
        assert str(Bits(0)) == "0b00000000"

    def test_str_max(self):
        assert str(Bits(255)) == "0b11111111"

    def test_repr_matches_str(self):
        b = Bits(197)
        assert repr(b) == str(b)


class TestIdempotency:
    def test_returns_same_instance(self):
        original = Bits(197)
        wrapped = Bits(original)
        assert wrapped is original
