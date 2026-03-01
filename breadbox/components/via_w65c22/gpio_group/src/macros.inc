; GPIO group {{ component_id }}
; Port: (port {{ port }} on {{ bus_device.id }}
; Pin mask: {{ bits | bin }})

{% set PORT_REG = bus_device.id ~ "_PORT" ~ port %}
{% set DDR_REG = bus_device.id ~ "_DDR" ~ port %}
{% set MASK = bits | int %}
{% set INV_MASK = 255 - MASK %}
{% set BIDIR = (direction == "both") %}

; Per-pin bitmask constants (named by pin, preserving caller's order).
{% for bitmask in pin_bitmasks %}
{{ constant("BIT_" ~ pins[loop.index0]) }} = {{ bitmask | bin }}
{% endfor %}
{% if direction in ("out", "both") %}

; Import tmp variable when included by external files.
.ifndef {{ var("tmp") }}
.importzp {{ var("tmp") }}
.endif

{% endif %}
{% if direction in ("out", "both") %}

; =========================================================================
; Write a value to {{ component_id }}.
;
{% if BIDIR %}
; Switches DDR to output before writing.
;
{% endif %}
; The value must use only the bits within the group mask ({{ bits | bin }}).
; Bits outside the mask are ignored{% if not exclusive_port %} and preserved{% endif %}.
;
; In:
;   _value = immediate byte value to write (pre-masked to {{ bits | bin }})
; Out:
;   A = clobbered

{% if exclusive_port %}
.macro {{ symbol_prefix }}_write _value
{% if BIDIR %}
    lda #{{ MASK | bin }}
    sta {{ DDR_REG }}
{% endif %}
    lda #_value
    sta {{ PORT_REG }}
.endmacro
{% else %}
.macro {{ symbol_prefix }}_write _value
{% if BIDIR %}
    lda {{ DDR_REG }}
    ora #{{ MASK | bin }}
    sta {{ DDR_REG }}
{% endif %}
    lda {{ PORT_REG }}
    and #{{ INV_MASK | bin }}
    ora #_value
    sta {{ PORT_REG }}
.endmacro
{% endif %}

; =========================================================================
; Set all {{ component_id }} outputs high.
;
{% if BIDIR %}
; Switches DDR to output before writing.
;
{% endif %}
; Out:
;   A = clobbered

{% if exclusive_port %}
.macro {{ symbol_prefix }}_on
{% if BIDIR %}
    lda #{{ MASK | bin }}
    sta {{ DDR_REG }}
    sta {{ PORT_REG }}
{% else %}
    lda #{{ MASK | bin }}
    sta {{ PORT_REG }}
{% endif %}
.endmacro
{% else %}
.macro {{ symbol_prefix }}_on
{% if BIDIR %}
    lda {{ DDR_REG }}
    ora #{{ MASK | bin }}
    sta {{ DDR_REG }}
{% endif %}
    lda {{ PORT_REG }}
    ora #{{ MASK | bin }}
    sta {{ PORT_REG }}
.endmacro
{% endif %}

; =========================================================================
; Set all {{ component_id }} outputs low.
;
{% if BIDIR %}
; Switches DDR to output before writing.
;
{% endif %}
; Out:
;   A = clobbered

{% if exclusive_port %}
.macro {{ symbol_prefix }}_off
{% if BIDIR %}
    lda #{{ MASK | bin }}
    sta {{ DDR_REG }}
{% endif %}
    lda #$00
    sta {{ PORT_REG }}
.endmacro
{% else %}
.macro {{ symbol_prefix }}_off
{% if BIDIR %}
    lda {{ DDR_REG }}
    ora #{{ MASK | bin }}
    sta {{ DDR_REG }}
{% endif %}
    lda {{ PORT_REG }}
    and #{{ INV_MASK | bin }}
    sta {{ PORT_REG }}
.endmacro
{% endif %}

; =========================================================================
; Toggle all {{ component_id }} outputs.
;
{% if BIDIR %}
; Switches DDR to output before writing.
;
{% endif %}
; Out:
;   A = clobbered

.macro {{ symbol_prefix }}_toggle
{% if BIDIR %}
{% if exclusive_port %}
    lda #{{ MASK | bin }}
    sta {{ DDR_REG }}
{% else %}
    lda {{ DDR_REG }}
    ora #{{ MASK | bin }}
    sta {{ DDR_REG }}
{% endif %}
{% endif %}
    lda {{ PORT_REG }}
    eor #{{ MASK | bin }}
    sta {{ PORT_REG }}
.endmacro

; =========================================================================
; Write the accumulator to {{ component_id }}.
;
; Does NOT change DDR direction. For bidirectional groups, call
; {{ symbol_prefix }}_set_output first if the bus was set to input.
;
; The value in A must have bits positioned within the group mask ({{ bits | bin }}).
; Bits outside the mask are ignored{% if not exclusive_port %} and preserved{% endif %}.
;
; In:
;   A = byte value to write (pre-positioned in {{ bits | bin }})
; Out:
;   A = clobbered

{% if exclusive_port %}
.macro {{ symbol_prefix }}_write_a
    sta {{ PORT_REG }}              ; Only device on the port, write byte directly.
.endmacro
{% else %}
.macro {{ symbol_prefix }}_write_a
    and #{{ MASK | bin }}           ; Mask value to only include pins that can be written.
    sta {{ symbol("tmp") }}         ; Backup the resulting value.
    lda {{ PORT_REG }}              ; Load the current pin values from the port.
    and #{{ INV_MASK | bin }}       ; Set all pin values that can be written to value 0.
    ora {{ symbol("tmp") }}         ; Set requested values for pins that can be written.
    sta {{ PORT_REG }}              ; Write combined data to the port.
.endmacro
{% endif %}
{% endif %}
{% if direction in ("in", "both") %}

; =========================================================================
; Read {{ component_id }} input state.
;
{% if BIDIR %}
; Switches DDR to input before reading.
;
{% endif %}
; Out:
;   A = group state (masked to {{ bits | bin }})

.macro {{ symbol_prefix }}_read
{% if BIDIR %}
{% if exclusive_port %}
    lda #$00
    sta {{ DDR_REG }}
{% else %}
    lda {{ DDR_REG }}
    and #{{ INV_MASK | bin }}
    sta {{ DDR_REG }}
{% endif %}
{% endif %}
    lda {{ PORT_REG }}
    and #{{ MASK | bin }}
.endmacro

; =========================================================================
; Read {{ component_id }} port value without changing DDR.
;
; For bidirectional groups, call {{ symbol_prefix }}_set_input first
; if the bus was set to output.
;
; Out:
;   A = group state (masked to {{ bits | bin }})

.macro {{ symbol_prefix }}_read_port
    lda {{ PORT_REG }}
    and #{{ MASK | bin }}
.endmacro
{% endif %}
{% if direction == "both" %}

; =========================================================================
; Switch {{ component_id }} DDR to output mode.
;
; Out:
;   A = clobbered

{% if exclusive_port %}
.macro {{ symbol_prefix }}_set_output
    lda #{{ MASK | bin }}
    sta {{ DDR_REG }}
.endmacro
{% else %}
.macro {{ symbol_prefix }}_set_output
    lda {{ DDR_REG }}
    ora #{{ MASK | bin }}
    sta {{ DDR_REG }}
.endmacro
{% endif %}

; =========================================================================
; Switch {{ component_id }} DDR to input mode.
;
; Out:
;   A = clobbered

{% if exclusive_port %}
.macro {{ symbol_prefix }}_set_input
    lda #$00
    sta {{ DDR_REG }}
.endmacro
{% else %}
.macro {{ symbol_prefix }}_set_input
    lda {{ DDR_REG }}
    and #{{ INV_MASK | bin }}
    sta {{ DDR_REG }}
.endmacro
{% endif %}

{% endif %}
