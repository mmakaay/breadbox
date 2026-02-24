import pytest

from breadbox.types.pin_direction import PinDirection


class TestValidDirections:
    @pytest.mark.parametrize("value", ["in", "out", "both"])
    def test_valid_lowercase(self, value):
        result = PinDirection(value)
        assert result == value
        assert isinstance(result, PinDirection)
        assert isinstance(result, str)

    @pytest.mark.parametrize(
        "value,expected",
        [
            ("IN", "in"),
            ("Out", "out"),
            ("BOTH", "both"),
        ],
    )
    def test_case_insensitive(self, value, expected):
        assert PinDirection(value) == expected

    def test_whitespace_stripped(self):
        assert PinDirection(" in ") == "in"
        assert PinDirection(" out ") == "out"


class TestInvalidInput:
    @pytest.mark.parametrize("value", ["input", "output", "neither", "", "inout"])
    def test_invalid_string(self, value):
        with pytest.raises(ValueError):
            PinDirection(value)

    @pytest.mark.parametrize("value", [123, None, True])
    def test_non_string(self, value):
        with pytest.raises(ValueError):
            PinDirection(value)


class TestIdempotency:
    def test_returns_same_instance(self):
        original = PinDirection("in")
        wrapped = PinDirection(original)
        assert wrapped is original


class TestRepr:
    def test_repr_format(self):
        assert repr(PinDirection("in")) == "PinDirection(in)"
        assert repr(PinDirection("out")) == "PinDirection(out)"
        assert repr(PinDirection("both")) == "PinDirection(both)"
