import pytest

from breadbox.types.on_off import OnOff


class TestFromString:
    @pytest.mark.parametrize(
        "value,expected",
        [
            ("on", "on"),
            ("off", "off"),
            ("true", "on"),
            ("false", "off"),
            ("1", "on"),
            ("0", "off"),
            ("yes", "on"),
            ("no", "off"),
        ],
    )
    def test_valid_strings(self, value, expected):
        result = OnOff(value)
        assert result == expected
        assert isinstance(result, OnOff)
        assert isinstance(result, str)

    @pytest.mark.parametrize("value", ["ON", "True", "YES", "On", "TRUE"])
    def test_case_insensitive_on(self, value):
        assert OnOff(value) == "on"

    @pytest.mark.parametrize("value", ["OFF", "False", "NO", "Off", "FALSE"])
    def test_case_insensitive_off(self, value):
        assert OnOff(value) == "off"

    def test_whitespace_stripped(self):
        assert OnOff(" on ") == "on"
        assert OnOff(" off ") == "off"


class TestFromBool:
    def test_true(self):
        assert OnOff(True) == "on"

    def test_false(self):
        assert OnOff(False) == "off"


class TestFromInt:
    def test_one(self):
        assert OnOff(1) == "on"

    def test_zero(self):
        assert OnOff(0) == "off"

    @pytest.mark.parametrize("value", [2, -1, 42])
    def test_invalid_int(self, value):
        with pytest.raises(ValueError):
            OnOff(value)


class TestInvalidInput:
    @pytest.mark.parametrize("value", ["maybe", "yes please", "nope", ""])
    def test_invalid_string(self, value):
        with pytest.raises(ValueError):
            OnOff(value)

    @pytest.mark.parametrize("value", [None, [], 3.14])
    def test_invalid_type(self, value):
        with pytest.raises(ValueError):
            OnOff(value)


class TestIdempotency:
    def test_returns_same_instance(self):
        original = OnOff("on")
        wrapped = OnOff(original)
        assert wrapped is original


class TestRepr:
    def test_repr_on(self):
        assert repr(OnOff("on")) == "on"

    def test_repr_off(self):
        assert repr(OnOff("off")) == "off"
