# Breadbox Code Generation — Reference Document

## Vision

Breadbox parses a YAML hardware configuration and generates ca65/ld65 assembly code
that provides macros and functions for driving all configured devices from user-written
assembly. The user's workflow:

1. Describe hardware in `config.yaml`
2. Run `breadbox` in the project directory
3. Get generated code in `build/breadbox/` (constants, macros, functions, core assembly)
4. Write assembly code using `.include "breadbox.inc"` — which pulls in everything
5. Build with ca65/ld65 (include path pointed at `build/breadbox/`)

## Project Structure

```
projects/my-project/
├── config.yaml                          ← user writes this
├── project.s                            ← user's assembly code
├── build/                              ← breadbox generates everything here
│   ├── breadbox/                       ← ca65 include path root (-I build/breadbox/)
│   │   ├── breadbox.inc                ← master include (generated, pulls in everything)
│   │   ├── breadbox.cfg                ← ld65 linker config (generated)
│   │   ├── hardware.inc                ← device constants + macros (from config.yaml)
│   │   ├── hardware.s                  ← device init functions + scoped subroutines
│   │   └── core/                       ← pre-processed core assembly
│   │       ├── boot.s / boot.inc
│   │       ├── vectors.s / vectors.inc
│   │       ├── delay.s / delay.inc
│   │       └── cpu_shims.s / cpu_shims.inc
│   ├── project/                        ← copied user source files
│   │   └── project.s
│   └── rom.bin                         ← final binary
```

### How It Fits Together

The **Python package** (`breadbox/`) owns all source material:
- Component Python code lives at `breadbox/components/{type}/`
- Assembly source files live alongside the Python code, e.g. `breadbox/components/core/src/`
- Jinja2 processes templates → writes output to `build/breadbox/`

The **build directory** (`build/`) isolates all generated and build artifacts:
- `build/breadbox/` — ca65 include path root (`-I build/breadbox/`)
- `.include "breadbox.inc"` resolves to `build/breadbox/breadbox.inc`
- `breadbox.inc` includes `"core/boot.inc"` → resolves to `build/breadbox/core/boot.inc`
- `breadbox.inc` includes `"hardware.inc"` → resolves to `build/breadbox/hardware.inc`
- User source files are copied to `build/project/` for assembly
- Final ROM output is written to `build/rom.bin`

The **`src/` directory** is legacy reference material from before the Python tool.
It is not used by the new system.

## Rename: cpu → core

The `cpu` component is renamed to `core`. This better reflects its role as the
foundation component that every project needs. The `core` component provides:

- CPU type selection (6502 / 65c02) → drives `.setcpu` directive
- Clock speed → drives `CPU_CLOCK` constant (used by delay macros)
- Core assembly: boot routine, vectors, delay functions, cpu shims
- Future: memory map settings

Field rename: `type` → `cpu` (the field describes which CPU is used).

Config example:
```yaml
CORE:
  cpu: 65c02
  clock_mhz: 1.0
```

The core component ships its own assembly templates:
```
breadbox/components/core/
├── __init__.py
├── device.py                ← CoreDevice dataclass
├── component.py             ← resolver
└── src/                     ← assembly source files
    ├── boot.s
    ├── boot.inc
    ├── vectors.s
    ├── vectors.inc
    ├── delay.s
    ├── delay.inc
    ├── cpu_shims.s
    └── cpu_shims.inc
```

These get pre-processed by Jinja2 (e.g., `.setcpu` and `CPU_CLOCK` injected based on
config) and written to `build/breadbox/core/`.

Files to change for the rename:
- `breadbox/components/cpu/` → `breadbox/components/core/`
- `CpuDevice` → `CoreDevice`
- Field `type` → `cpu`
- `tests/unit/components/test_cpu.py` → `test_core.py`
- `config.yaml`: `CPU:` → `CORE:`

## ca65 Naming Rules

### Identifiers

Default valid characters: `[A-Za-z_][A-Za-z0-9_]*`

Optional extensions (via `.feature`):
- `at_in_identifiers` → allows `@` inside identifiers
- `dollar_in_identifiers` → allows `$` inside identifiers
- `leading_dot_in_identifiers` → allows `.` as first character

**Critical constraints:**
- `.` (dot) is NOT valid inside identifier names → `LCD0.PIN_EN.turn_on` is invalid
- `::` is the scope resolution operator, not part of identifiers
- Macros are GLOBAL — they cannot be scoped inside `.scope` or `.proc`

### Naming Scheme

Since macros must be global and cannot use `.` or `::`, we use **underscores** as
the separator in macro names:

```
{DEVICE}_{SUB_DEVICE}_{action}
```

Examples:
```asm
LCD0_PIN_EN_turn_on          ; macro — inlined, zero overhead
LCD0_PIN_EN_turn_off
LCD0_DATA_write              ; macro for writing to data bus
STATUS_LED_turn_on
STATUS_LED_toggle
```

For functions (subroutines), we use nested `.scope` with `::` access:

```asm
LCD0::PIN_EN::turn_on        ; function — JSR/RTS overhead
LCD0::DATA::write
STATUS_LED::turn_on
```

### Macro ↔ Function Relationship

**Macros are the primitives.** They contain the actual inline implementation.
Functions wrap the same body but as a callable subroutine.

```asm
; MACRO — the primitive. Inlined at call site. Zero overhead.
.macro LCD0_PIN_EN_turn_on
    lda VIA0_PORTA
    ora #%01000000
    sta VIA0_PORTA
.endmacro

; FUNCTION — wraps the same code as a subroutine.
; The body is the same as the macro (NOT a JSR to it).
.scope LCD0
.scope PIN_EN
    .proc turn_on
        lda VIA0_PORTA
        ora #%01000000
        sta VIA0_PORTA
        rts
    .endproc
.endscope
.endscope

; User picks based on need:
    LCD0_PIN_EN_turn_on      ; inline macro — fast, larger code
    jsr LCD0::PIN_EN::turn_on  ; function call — smaller code, adds JSR/RTS cycles
```

**Why macros contain the code, not the other way around:**
If a macro called a function (`jsr ...`), it would always have JSR overhead,
defeating the purpose. Macros must be self-contained inline code to guarantee
minimum cycle count.

## Code Generation Architecture

### Jinja2 Templating

Use Jinja2 for all assembly output. Add `jinja2` to project dependencies.

**Why Jinja2:**
- Flexible templating with conditionals, loops, includes
- Same template variables available to both breadbox templates and user templates
- Custom filters for domain-specific formatting (hex, binary, bit patterns)
- Template inheritance for shared structure across components

**Environment configuration:**
```python
from jinja2 import Environment, PackageLoader, StrictUndefined

env = Environment(
    loader=PackageLoader("breadbox", "templates"),
    undefined=StrictUndefined,    # fail on missing variables
    keep_trailing_newline=True,   # preserve trailing newlines in output
    lstrip_blocks=True,           # strip leading whitespace from block tags
    trim_blocks=True,             # strip newline after block tags
)
```

The default `{{ }}` / `{% %}` delimiters do not conflict with ca65 syntax.

### Template Organization

Each component owns its templates alongside its Python code:

```
breadbox/
├── templates/                           ← top-level templates
│   ├── breadbox.inc                    ← master include file
│   ├── breadbox.cfg                    ← linker config
│   ├── hardware.inc                    ← device constants + macros
│   └── hardware.s                      ← device init + scoped functions
└── components/
    ├── core/
    │   ├── device.py
    │   ├── component.py
    │   └── src/                       ← core assembly source files
    │       ├── boot.s / boot.inc
    │       ├── vectors.s / vectors.inc
    │       ├── delay.s / delay.inc
    │       └── cpu_shims.s / cpu_shims.inc
    ├── via_w65c22/
    │   ├── device.py
    │   ├── component.py
    │   └── src/                       ← VIA-specific source files (if needed)
    │       └── ...
    └── ...
```

Top-level templates (`breadbox/templates/`) produce the files at the
`build/breadbox/` root. Component templates produce files in their
respective subdirectory (e.g., `build/breadbox/core/`).

### What Gets Generated

For each device in the config, the generator produces:

**1. Constants (in hardware.inc)**
```asm
; Core
.setcpu "65c02"
CPU_CLOCK = 1000000

; VIA0
VIA0_BASE  = $6000
VIA0_PORTB = VIA0_BASE + $00
VIA0_PORTA = VIA0_BASE + $01
VIA0_DDRB  = VIA0_BASE + $02
VIA0_DDRA  = VIA0_BASE + $03
; ... (T1, T2, SR, ACR, PCR, IFR, IER registers)
```

**2. Macros (in hardware.inc)**

For gpio_pin (direction=out):
```asm
.macro STATUS_LED_turn_on
    lda VIA0_PORTB
    ora #%00000001       ; PA0 mask
    sta VIA0_PORTB
.endmacro

.macro STATUS_LED_turn_off
    lda VIA0_PORTB
    and #%11111110       ; inverted PA0 mask
    sta VIA0_PORTB
.endmacro

.macro STATUS_LED_toggle
    lda VIA0_PORTB
    eor #%00000001
    sta VIA0_PORTB
.endmacro
```

For gpio_pin (direction=in):
```asm
.macro STATUS_LED_read
    lda VIA0_PORTB
    and #%00000001
.endmacro
```

For gpio_group:
```asm
.macro PROGRESS_LEDS1_write value
    ; ... mask and shift based on bits
.endmacro

.macro PROGRESS_LEDS1_read
    lda VIA1_PORTA
    and #%10100011       ; bits mask
.endmacro
```

**3. Init functions (in hardware.s)**
```asm
.segment "KERNAL"

    .proc init_via0
        ; Set DDR bits for all output pins on this VIA
        lda VIA0_DDRA
        ora #%01000101       ; combined mask of all output pins on port A
        sta VIA0_DDRA
        rts
    .endproc
    .constructor init_via0
```

The `.constructor` directive registers init functions with the boot sequence,
which calls them automatically during startup (see `core/boot.s`).

**4. Scoped functions (in hardware.s)**
```asm
.scope STATUS_LED
    .proc turn_on
        lda VIA0_PORTB
        ora #%00000001
        sta VIA0_PORTB
        rts
    .endproc
    .proc turn_off
        lda VIA0_PORTB
        and #%11111110
        sta VIA0_PORTB
        rts
    .endproc
.endscope
```

**5. Core assembly (in core/)**

Pre-processed from `breadbox/components/core/src/`:
- `boot.s` / `boot.inc` — boot sequence, halt, trampoline
- `vectors.s` / `vectors.inc` — interrupt vectors (NMI, RESET, IRQ)
- `delay.s` / `delay.inc` — DELAY, DELAY_US, DELAY_MS macros
- `cpu_shims.s` / `cpu_shims.inc` — 6502 compat (phx/plx/phy/ply)

These are Jinja2-processed so they can receive config values (e.g., `.setcpu`,
`CPU_CLOCK`), but are otherwise close to the reference assembly in `src/core/`.

**6. Master include (breadbox.inc)**

Generated to pull everything together:
```asm
; Auto-generated by breadbox. Do not edit.
.ifndef BREADBOX_INC
BREADBOX_INC = 1

; Generated hardware definitions.
.include "hardware.inc"

; Core includes.
.include "core/cpu_shims.inc"
.include "core/delay.inc"
.include "core/boot.inc"
.include "core/vectors.inc"

.endif
```

**7. Linker config (breadbox.cfg)**

Generated (or copied from a default template), tailored to the project's
memory map. Initially based on the existing `src/breadbox.cfg`.

### User Templates

User `.s` files in the project can also use Jinja2 templating via breadbox.
The same variables and filters available to component templates are exposed
to user templates, allowing:

```asm
; In project.s (processed by breadbox as Jinja2 template)
.include "breadbox.inc"
.export main

.proc main
    {{ STATUS_LED }}_turn_on     ; expands to STATUS_LED_turn_on
    DELAY_MS 500
    {{ STATUS_LED }}_turn_off
    HALT
.endproc
```

This is a future enhancement. Initially, users use the generated macro names directly.

## Output Safety

- The `build/` directory is fully managed by breadbox
- Every generated file starts with `; Auto-generated by breadbox. Do not edit.`
- Generation clears the `build/breadbox/` directory before writing (to remove stale files)
- User files outside `build/` are never touched

## Build Integration

When building, ca65 needs the generated directory as include path:

```bash
# Assemble core files
ca65 -I build/breadbox/ build/breadbox/core/boot.s
ca65 -I build/breadbox/ build/breadbox/core/vectors.s
ca65 -I build/breadbox/ build/breadbox/core/delay.s
ca65 -I build/breadbox/ build/breadbox/core/cpu_shims.s

# Assemble generated hardware code
ca65 -I build/breadbox/ build/breadbox/hardware.s

# Assemble user code (copied to build/project/)
ca65 -I build/breadbox/ build/project/project.s

# Link everything
ld65 --config build/breadbox/breadbox.cfg \
    build/breadbox/core/*.o \
    build/breadbox/hardware.o \
    build/project/project.o \
    -o build/rom.bin

The `breadbox build` command drives this entire pipeline: generate + copy user
files + ca65 + ld65, all isolated within the `build/` directory.

## Implementation Plan

### Phase 1: Foundation
1. Rename `cpu` → `core` (component directory, device class, tests, config)
2. Add `jinja2` dependency
3. Create template directory structure
4. Create generator module (`breadbox/generator.py`) with Jinja2 environment setup
5. Wire generator into CLI (after config resolution, call generator)

### Phase 2: Core + VIA Constants
6. Template for core component (`.setcpu`, `CPU_CLOCK`)
7. Template for VIA constants (base address, register offsets)
8. Generate `hardware.inc` with constants section

### Phase 3: GPIO Pin/Group Macros + Functions
9. Templates for gpio_pin macros (turn_on/off/toggle/read based on direction)
10. Templates for gpio_group macros (write/read based on direction)
11. Templates for scoped functions (same bodies + rts)
12. Generate macro and function sections in `hardware.inc` / `hardware.s`

### Phase 4: Init + Constructors
13. Templates for VIA DDR initialization
14. Generate init procs in `hardware.s` with `.constructor` registration
15. Aggregate DDR masks per VIA (multiple pins/groups → single init per VIA)

### Phase 5: LCD + UART
16. LCD-specific templates (init sequence, command/data sending)
17. UART-specific templates (init, send/receive)

### Phase 6: Polish
18. User template processing (Jinja2 pass on project .s files)
19. Full build command (`breadbox build` → generate + ca65 + ld65)
20. Test suite for generated output

## Conventions

- Template files use `.s` / `.inc` extensions (not `.j2`) for editor syntax highlighting
- Generated assembly uses `; Auto-generated by breadbox. Do not edit.` header
- Macro names: `SCREAMING_SNAKE_CASE` with underscores separating device hierarchy
- Function scopes: nested `.scope` / `.proc` matching the device tree
- Constants: `SCREAMING_SNAKE_CASE`
- Init procs: `init_{device_id_lowercase}`
- All generated code goes in `build/breadbox/` subdirectory of the project
- User source files are copied to `build/project/` for assembly
- ROM output is written to `build/rom.bin`
- ca65 include path: `build/breadbox/`
- Assembly source files live alongside their component's Python code in `src/`
