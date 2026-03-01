; GPIO pin: {{ component_id }} ({{ pin }} on {{ bus_device.id }}, port {{ port }})

.include "hardware.inc"
.include "{{ bus_device.component_path }}/registers.inc"

{% set PORT_REG = bus_device.id ~ "_PORT" ~ port %}
{% set DDR_REG = bus_device.id ~ "_DDR" ~ port %}
{% set MASK = bitmask %}
{% set INV_MASK = 255 - bitmask %}
{% set BIDIR = (direction == "both") %}

.segment "KERNALROM"
{% if direction in ("out", "both") or default is not none %}

    ; =========================================================================
    ; Initialize {{ component_id }}: set DDR to output{% if default is not none %} and apply default ({{ default }}){% endif %}.
    ;
    ; Called automatically during boot via .constructor.
    ;
    ; Out:
    ;   A = clobbered

    .proc {{ my_def("init") }}
{% if exclusive_port %}
        lda #{{ MASK | hex }}
        sta {{ DDR_REG }}
{% if default == "on" %}
        sta {{ PORT_REG }}
{% elif default == "off" %}
        lda #$00
        sta {{ PORT_REG }}
{% endif %}
{% else %}
        lda {{ DDR_REG }}
        ora #{{ MASK | hex }}
        sta {{ DDR_REG }}
{% if default == "on" %}
        lda {{ PORT_REG }}
        ora #{{ MASK | hex }}
        sta {{ PORT_REG }}
{% elif default == "off" %}
        lda {{ PORT_REG }}
        and #{{ INV_MASK | hex }}
        sta {{ PORT_REG }}
{% endif %}
{% endif %}
        rts
    .endproc
    .constructor {{ my("init") }}, 16
{% endif %}

{% if direction in ("out", "both") %}
    ; =====================================================================
    ; Set {{ component_id }} output high.
    ;
{% if BIDIR %}
    ; Switches DDR to output before writing.
    ;
{% endif %}
    ; Out:
    ;   A = clobbered

    .proc {{ api_def("turn_on") }}
{% if exclusive_port %}
{% if BIDIR %}
        lda #{{ MASK | hex }}
        sta {{ DDR_REG }}
        sta {{ PORT_REG }}
{% else %}
        lda #{{ MASK | hex }}
        sta {{ PORT_REG }}
{% endif %}
{% else %}
{% if BIDIR %}
        lda {{ DDR_REG }}
        ora #{{ MASK | hex }}
        sta {{ DDR_REG }}
{% endif %}
        lda {{ PORT_REG }}
        ora #{{ MASK | hex }}
        sta {{ PORT_REG }}
{% endif %}
        rts
    .endproc

    ; =====================================================================
    ; Set {{ component_id }} output low.
    ;
{% if BIDIR %}
    ; Switches DDR to output before writing.
    ;
{% endif %}
    ; Out:
    ;   A = clobbered

    .proc {{ api_def("turn_off") }}
{% if exclusive_port %}
{% if BIDIR %}
        lda #{{ MASK | hex }}
        sta {{ DDR_REG }}
{% endif %}
        lda #$00
        sta {{ PORT_REG }}
{% else %}
{% if BIDIR %}
        lda {{ DDR_REG }}
        ora #{{ MASK | hex }}
        sta {{ DDR_REG }}
{% endif %}
        lda {{ PORT_REG }}
        and #{{ INV_MASK | hex }}
        sta {{ PORT_REG }}
{% endif %}
        rts
    .endproc

    ; =====================================================================
    ; Toggle {{ component_id }} output.
    ;
{% if BIDIR %}
    ; Switches DDR to output before writing.
    ;
{% endif %}
    ; Out:
    ;   A = clobbered

    .proc {{ api_def("toggle") }}
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
        rts
    .endproc
{% endif %}
{% if direction in ("in", "both") %}

    ; =====================================================================
    ; Read {{ component_id }} input state.
    ;
{% if BIDIR %}
    ; Switches DDR to input before reading.
    ;
{% endif %}
    ; Out:
    ;   A = pin state (bit {{ pin[-1] }}, masked)

    .proc {{ api_def("read") }}
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
        rts
    .endproc
{% endif %}
