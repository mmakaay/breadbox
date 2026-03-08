"""
Memory layout resolution for linker configuration.

Resolves RAM/ROM devices and user-defined segments into a complete
memory map with all auto-assigned segments (ZEROPAGE, STACK, VECTORS,
VECTORS, KERNALROM, KERNALRAM, CODE, DATA) placed correctly.
"""

from __future__ import annotations

from dataclasses import dataclass, field

from breadbox.errors import ConfigError

RESERVED_SEGMENTS = frozenset({"ZEROPAGE", "STACK", "VECTORS"})
"""Segment names that are always auto-assigned and cannot be used by the user."""

AUTO_ROM_SEGMENTS = frozenset({"KERNALROM", "CODE", "DATA"})
"""
Segment names that are auto-assigned to the vectors ROM by default,
but can be overridden to a different ROM by including them in that ROM's
segments list. Cannot be assigned to RAM.
"""

AUTO_RAM_SEGMENTS = frozenset({"KERNALRAM"})
"""
Segment names that are auto-assigned to the main RAM device by default,
but can be overridden to a different RAM by including them in that RAM's
segments list. Cannot be assigned to ROM.
"""

@dataclass
class MemoryRegion:
    """A resolved memory region for the linker MEMORY {} block."""

    name: str
    start: int
    size: int
    type: str  # "rw" for RAM, "ro" for ROM
    file: str  # "" for RAM, "%O" for ROM
    fill: bool = False

    @property
    def end(self) -> int:
        """Exclusive end address."""
        return self.start + self.size


@dataclass
class Segment:
    """A resolved segment for the linker SEGMENTS {} block."""

    name: str
    load: str  # Name of the MemoryRegion
    type: str  # "zp", "bss", "ro"


@dataclass
class MemoryLayout:
    """Complete resolved memory layout for linker.cfg generation."""

    regions: list[MemoryRegion] = field(default_factory=list)
    segments: list[Segment] = field(default_factory=list)


def resolve_memory_layout(ram_devices: list, rom_devices: list) -> MemoryLayout:
    """
    Resolve RAM/ROM devices into a complete memory layout.

    Steps:
    1. Collect user-defined segments from all devices.
    2. Reject reserved names (ZEROPAGE, STACK, VECTORS).
    3. Allow KERNALROM, CODE and DATA as explicit overrides (ROM only).
    4. Allow KERNALRAM as explicit override (RAM only).
    5. Check uniqueness across all user segments.
    6. Build memory regions with auto-carved fixed segments.
    7. Assign KERNALROM, CODE and DATA to vectors ROM if not explicitly claimed.
    8. Assign KERNALRAM to main RAM if not explicitly claimed.
    9. Create default segments for devices with no explicit segments.
    """
    from breadbox.components.ram.device import RamDevice
    from breadbox.components.rom.device import RomDevice

    layout = MemoryLayout()

    # --- Validate memory coverage ---
    _validate_memory_coverage(ram_devices, rom_devices)
    _validate_no_overlap(ram_devices + rom_devices)

    # --- Collect and validate user segments ---
    user_segments: dict[str, str] = {}  # segment_name -> component_id
    auto_rom_overrides: dict[str, str] = {}  # segment_name -> component_id (for KERNALROM, CODE, DATA)
    auto_ram_overrides: dict[str, str] = {}  # segment_name -> component_id (for KERNALRAM)
    for device in ram_devices + rom_devices:
        for seg_name in device.segments:
            seg_upper = seg_name.upper()
            if seg_upper in RESERVED_SEGMENTS:
                raise ConfigError(
                    f"Segment name '{seg_upper}' is reserved and cannot be"
                    f" used in '{device.id}' segments list"
                )
            if seg_upper in AUTO_ROM_SEGMENTS:
                if not isinstance(device, RomDevice):
                    raise ConfigError(
                        f"{seg_upper} segment can only be assigned to a ROM device,"
                        f" not RAM device '{device.id}'"
                    )
                auto_rom_overrides[seg_upper] = str(device.id)
            if seg_upper in AUTO_RAM_SEGMENTS:
                if not isinstance(device, RamDevice):
                    raise ConfigError(
                        f"{seg_upper} segment can only be assigned to a RAM device,"
                        f" not ROM device '{device.id}'"
                    )
                auto_ram_overrides[seg_upper] = str(device.id)
            if seg_upper in user_segments:
                raise ConfigError(
                    f"Segment '{seg_upper}' is defined in both"
                    f" '{user_segments[seg_upper]}' and '{device.id}'"
                )
            user_segments[seg_upper] = str(device.id)

    # --- Find the vectors ROM ---
    vectors_rom: RomDevice | None = None
    for device in rom_devices:
        if device.covers(0xFFFA, 0x10000):
            vectors_rom = device
            break
    assert vectors_rom is not None  # Already validated in _validate_memory_coverage

    # --- Assign auto ROM segments to vectors ROM if not explicitly claimed ---
    for seg_name in sorted(AUTO_ROM_SEGMENTS):
        if seg_name not in auto_rom_overrides:
            auto_rom_overrides[seg_name] = str(vectors_rom.id)

    # --- Find the main RAM (covers $0000) for auto RAM segment assignment ---
    main_ram = None
    for device in ram_devices:
        if device.covers(0x0000, 0x0100):
            main_ram = device
            break
    assert main_ram is not None  # Already validated in _validate_memory_coverage

    # --- Assign auto RAM segments to main RAM if not explicitly claimed ---
    for seg_name in sorted(AUTO_RAM_SEGMENTS):
        if seg_name not in auto_ram_overrides:
            auto_ram_overrides[seg_name] = str(main_ram.id)

    # --- Build memory regions and segments ---

    # Process RAM devices (sorted by address for deterministic output)
    for device in sorted(ram_devices, key=lambda d: int(d.address)):
        addr = int(device.address)
        size = device.size
        component_id = str(device.id)

        # Carve ZEROPAGE and STACK from the RAM that covers them
        if device.covers(0x0000, 0x0100):
            layout.regions.append(
                MemoryRegion(
                    name="ZEROPAGE",
                    start=0x0000,
                    size=0x0100,
                    type="rw",
                    file="",
                )
            )
            layout.segments.append(
                Segment(
                    name="ZEROPAGE",
                    load="ZEROPAGE",
                    type="zp",
                )
            )

        if device.covers(0x0100, 0x0200):
            layout.regions.append(
                MemoryRegion(
                    name="STACK",
                    start=0x0100,
                    size=0x0100,
                    type="rw",
                    file="",
                )
            )
            layout.segments.append(
                Segment(
                    name="STACK",
                    load="STACK",
                    type="bss",
                )
            )

        # Remaining RAM after carving ZP and STACK
        ram_start = addr
        ram_size = size
        if device.covers(0x0000, 0x0100):
            carved = 0x0100 - addr
            ram_start = 0x0100
            ram_size -= carved
        if device.covers(0x0100, 0x0200) and ram_start < 0x0200:
            carved = 0x0200 - ram_start
            ram_start = 0x0200
            ram_size -= carved

        if ram_size > 0:
            layout.regions.append(
                MemoryRegion(
                    name=component_id,
                    start=ram_start,
                    size=ram_size,
                    type="rw",
                    file="",
                )
            )

            # User-defined segments (excluding auto segments, handled separately)
            device_segments = [
                s.upper() for s in device.segments
                if s.upper() not in AUTO_ROM_SEGMENTS
                and s.upper() not in AUTO_RAM_SEGMENTS
            ]
            if not device_segments:
                device_segments = [component_id]

            for seg_name in device_segments:
                layout.segments.append(
                    Segment(
                        name=seg_name,
                        load=component_id,
                        type="bss",
                    )
                )

            # Auto RAM segments (KERNALRAM) assigned to this device
            for seg_name, target_id in auto_ram_overrides.items():
                if target_id == component_id:
                    layout.segments.append(
                        Segment(
                            name=seg_name,
                            load=component_id,
                            type="bss",
                        )
                    )

    # Process ROM devices (sorted by address)
    for device in sorted(rom_devices, key=lambda d: int(d.address)):
        addr = int(device.address)
        size = device.size
        component_id = str(device.id)
        is_vectors_rom = device is vectors_rom

        # Main ROM region (minus VECTORS if this is the vectors ROM)
        rom_size = size
        if is_vectors_rom:
            rom_size = size - 6  # Reserve last 6 bytes for VECTORS

        if rom_size > 0:
            layout.regions.append(
                MemoryRegion(
                    name=component_id,
                    start=addr,
                    size=rom_size,
                    type="ro",
                    file="%O",
                    fill=True,
                )
            )

            # Auto ROM segments (KERNALROM, CODE, DATA) assigned to this device
            auto_for_device: set[str] = set()
            for seg_name, target_id in auto_rom_overrides.items():
                if target_id == component_id:
                    auto_for_device.add(seg_name)
                    layout.segments.append(
                        Segment(
                            name=seg_name,
                            load=component_id,
                            type="ro",
                        )
                    )
            # User-defined segments (excluding auto ROM segments, handled above)
            device_segments = [
                s.upper() for s in device.segments
                if s.upper() not in AUTO_ROM_SEGMENTS
                and s.upper() not in AUTO_RAM_SEGMENTS
            ]
            if not device_segments and component_id not in auto_for_device:
                # No user segments and component_id not already emitted
                # as an auto ROM segment: add default segment named after device
                device_segments = [component_id]

            for seg_name in device_segments:
                layout.segments.append(
                    Segment(
                        name=seg_name,
                        load=component_id,
                        type="ro",
                    )
                )

        # VECTORS region (always carved from the vectors ROM)
        if is_vectors_rom:
            layout.regions.append(
                MemoryRegion(
                    name="VECTORS",
                    start=0xFFFA,
                    size=0x0006,
                    type="ro",
                    file="%O",
                    fill=True,
                )
            )
            layout.segments.append(
                Segment(
                    name="VECTORS",
                    load="VECTORS",
                    type="ro",
                )
            )

    return layout


def _validate_memory_coverage(ram_devices: list, rom_devices: list) -> None:
    """Validate that required address ranges are covered."""
    # At least one RAM
    if not ram_devices:
        raise ConfigError("Configuration must include at least one RAM device")

    # At least one ROM
    if not rom_devices:
        raise ConfigError("Configuration must include at least one ROM device")

    # RAM must cover ZEROPAGE ($0000-$00FF)
    if not any(d.covers(0x0000, 0x0100) for d in ram_devices):
        raise ConfigError(
            "No RAM device covers zero page ($0000-$00FF). At least one RAM must start at $0000 with size >= $0100."
        )

    # RAM must cover STACK ($0100-$01FF)
    if not any(d.covers(0x0100, 0x0200) for d in ram_devices):
        raise ConfigError("No RAM device covers the stack ($0100-$01FF). At least one RAM must cover $0100-$01FF.")

    # ROM must cover VECTORS ($FFFA-$FFFF)
    if not any(d.covers(0xFFFA, 0x10000) for d in rom_devices):
        raise ConfigError(
            "No ROM device covers the vectors ($FFFA-$FFFF). At least one ROM must end at $FFFF with size >= 6."
        )


def _validate_no_overlap(devices: list) -> None:
    """Validate that no two memory devices overlap."""
    regions = [(int(d.address), d.end_address, str(d.id)) for d in devices]
    regions.sort()

    for i in range(len(regions) - 1):
        _, end_a, id_a = regions[i]
        start_b, _, id_b = regions[i + 1]
        if end_a > start_b:
            raise ConfigError(f"Memory devices '{id_a}' and '{id_b}' overlap")
