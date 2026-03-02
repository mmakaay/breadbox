import pytest

from breadbox.types.component_identifier import ComponentIdentifier


class TestValidIdentifiers:
    @pytest.mark.parametrize("value", ["CPU", "VIA0", "LED", "PROGRESS_LEDS1", "RTS_PIN"])
    def test_valid_identifiers(self, value):
        result = ComponentIdentifier(value)
        assert result == value
        assert isinstance(result, ComponentIdentifier)
        assert isinstance(result, str)

    def test_preserves_value(self):
        assert ComponentIdentifier("MY_DEVICE") == "MY_DEVICE"

class TestInvalidFormat:
    @pytest.mark.parametrize("value", ["", "0BAD", "_bad", "has space", "has-dash", "hello!", "lower", "mixedCase"])
    def test_invalid_format_raises(self, value):
        with pytest.raises(ValueError):
            ComponentIdentifier(value)


class TestReservedWords:
    @pytest.mark.parametrize(
        "value",
        [
            "RTS",
            "LDA",
            "BRK",
            "A",
            "X",
            "Y",
            "SP",
            "PC",
            "S",
            "BBR0",
            "SMB7",
            "BBS3",
            "RMB5",
            "NOP",
            "JMP",
            "JSR",
            "STA",
            "BRA",
            "PHX",
            "STZ",
            "WAI",
            "STP",
        ],
    )
    def test_reserved_words_rejected(self, value):
        with pytest.raises(ValueError, match="reserved word"):
            ComponentIdentifier(value)


class TestNonStringInput:
    @pytest.mark.parametrize("value", [123, None, True, 3.14, ["a"]])
    def test_non_string_raises(self, value):
        with pytest.raises(ValueError):
            ComponentIdentifier(value)


class TestIdempotency:
    def test_returns_same_instance(self):
        original = ComponentIdentifier("FOO")
        wrapped = ComponentIdentifier(original)
        assert wrapped is original


class TestRepr:
    def test_repr_format(self):
        assert repr(ComponentIdentifier("CPU")) == "ComponentIdentifier('CPU')"
