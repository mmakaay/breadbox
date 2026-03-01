; GPIO pin: {{ component_id }} ({{ pin }} on {{ bus_device.id }}, port {{ port }})

{% set PORT_REG = bus_device.id ~ "_PORT" ~ port %}
{% set DDR_REG = bus_device.id ~ "_DDR" ~ port %}
{% set MASK = bitmask %}
{% set INV_MASK = 255 - bitmask %}
{% set BIDIR = (direction == "both") %}
{% if direction in ("out", "both") %}

; =========================================================================
; Set {{ component_id }} output high.
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
    lda #{{ MASK | hex }}
    sta {{ DDR_REG }}
    sta {{ PORT_REG }}
{% else %}
    lda #{{ MASK | hex }}
    sta {{ PORT_REG }}
{% endif %}
.endmacro
{% else %}
.macro {{ symbol_prefix }}_on
{% if BIDIR %}
    lda {{ DDR_REG }}
    ora #{{ MASK | hex }}
    sta {{ DDR_REG }}
{% endif %}
    lda {{ PORT_REG }}
    ora #{{ MASK | hex }}
    sta {{ PORT_REG }}
.endmacro
{% endif %}

; =========================================================================
; Set {{ component_id }} output low.
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
    lda #{{ MASK | hex }}
    sta {{ DDR_REG }}
{% endif %}
    lda #$00
    sta {{ PORT_REG }}
.endmacro
{% else %}
.macro {{ symbol_prefix }}_off
{% if BIDIR %}
    lda {{ DDR_REG }}
    ora #{{ MASK | hex }}
    sta {{ DDR_REG }}
{% endif %}
    lda {{ PORT_REG }}
    and #{{ INV_MASK | hex }}
    sta {{ PORT_REG }}
.endmacro
{% endif %}

; =========================================================================
; Toggle {{ component_id }} output.
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
    lda #{{ MASK | hex }}
    sta {{ DDR_REG }}
{% else %}
    lda {{ DDR_REG }}
    ora #{{ MASK | hex }}
    sta {{ DDR_REG }}
{% endif %}
{% endif %}
    lda {{ PORT_REG }}
    eor #{{ MASK | hex }}
    sta {{ PORT_REG }}
.endmacro
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
;   A = pin state (bit {{ pin[-1] }}, masked)

.macro {{ symbol_prefix }}_read
{% if BIDIR %}
{% if exclusive_port %}
    lda #$00
    sta {{ DDR_REG }}
{% else %}
    lda {{ DDR_REG }}
    and #{{ INV_MASK | hex }}
    sta {{ DDR_REG }}
{% endif %}
{% endif %}
    lda {{ PORT_REG }}
    and #{{ MASK | hex }}
.endmacro
{% endif %}
