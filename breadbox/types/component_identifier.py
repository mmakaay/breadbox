import re
from typing import Self

_DEVICE_ID_RE = re.compile(r"^[A-Z][A-Z0-9_]*$")

# 6502/65C02 mnemonics and register names.
_RESERVED_WORDS = frozenset({
    # Registers
    "A", "X", "Y", "S", "SP", "PC",
    # 6502 mnemonics
    "ADC", "AND", "ASL", "BCC", "BCS", "BEQ", "BIT", "BMI", "BNE", "BPL",
    "BRK", "BVC", "BVS", "CLC", "CLD", "CLI", "CLV", "CMP", "CPX", "CPY",
    "DEC", "DEX", "DEY", "EOR", "INC", "INX", "INY", "JMP", "JSR", "LDA",
    "LDX", "LDY", "LSR", "NOP", "ORA", "PHA", "PHP", "PLA", "PLP", "ROL",
    "ROR", "RTI", "RTS", "SBC", "SEC", "SED", "SEI", "STA", "STX", "STY",
    "TAX", "TAY", "TSX", "TXA", "TXS", "TYA",
    # 65C02 additions
    "BRA", "PHX", "PHY", "PLX", "PLY", "STZ", "TRB", "TSB", "WAI", "STP",
    # 65C02 bit manipulation (BBR0-7, BBS0-7, RMB0-7, SMB0-7)
    *[f"BBR{i}" for i in range(8)], *[f"BBS{i}" for i in range(8)],
    *[f"RMB{i}" for i in range(8)], *[f"SMB{i}" for i in range(8)],
})


class ComponentIdentifier(str):
    """
    Device identifier: starts with a letter, letters/digits/underscores only.

    Reserved words (6502/65C02 mnemonics and register names) are forbidden.
    """

    def __new__(cls, value: object) -> Self:
        if isinstance(value, cls):
            return value
        if not isinstance(value, str):
            raise ValueError(f"Expected a string, got {type(value).__name__!r}")
        if not _DEVICE_ID_RE.match(value):
            raise ValueError(
                f"{value!r} is not a valid ComponentIdentifier "
                f"(must start with an upper-case letter, upper-case letters/digits/underscores only)"
            )
        if value in _RESERVED_WORDS:
            raise ValueError(
                f"{value!r} is a reserved word (6502 mnemonic or register name) "
                f"and cannot be used as a device identifier"
            )
        return super().__new__(cls, value)

    def __repr__(self) -> str:
        return f"ComponentIdentifier({str(self)!r})"
