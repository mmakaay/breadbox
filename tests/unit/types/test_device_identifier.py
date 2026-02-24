import pytest

from breadbox.types.device_identifier import DeviceIdentifier


class TestValidIdentifiers:
    @pytest.mark.parametrize("value", ["CPU", "VIA0", "LED", "PROGRESS_LEDS1", "e", "Z9_test", "PIN_RTS"])
    def test_valid_identifiers(self, value):
        result = DeviceIdentifier(value)
        assert result == value
        assert isinstance(result, DeviceIdentifier)
        assert isinstance(result, str)

    def test_preserves_case(self):
        assert DeviceIdentifier("MyDevice") == "MyDevice"


class TestInvalidFormat:
    @pytest.mark.parametrize("value", ["", "0BAD", "_bad", "has space", "has-dash", "hello!"])
    def test_invalid_format_raises(self, value):
        with pytest.raises(ValueError):
            DeviceIdentifier(value)


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
            DeviceIdentifier(value)

    @pytest.mark.parametrize("value", ["rts", "lda", "brk", "Rts", "nop", "sp"])
    def test_reserved_words_case_insensitive(self, value):
        with pytest.raises(ValueError, match="reserved word"):
            DeviceIdentifier(value)


class TestNonStringInput:
    @pytest.mark.parametrize("value", [123, None, True, 3.14, ["a"]])
    def test_non_string_raises(self, value):
        with pytest.raises(ValueError):
            DeviceIdentifier(value)


class TestIdempotency:
    def test_returns_same_instance(self):
        original = DeviceIdentifier("FOO")
        wrapped = DeviceIdentifier(original)
        assert wrapped is original


class TestRepr:
    def test_repr_format(self):
        assert repr(DeviceIdentifier("CPU")) == "DeviceIdentifier('CPU')"
