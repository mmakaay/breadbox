; GPIO group: {{ component_id }} (port {{ port }} on {{ provider_device.id }}, mask {{ bits | hex }})

.include "{{ provider_device.component_path }}/constants.inc"

{% set PORT_REG = "PORT" ~ port %}
{% set DDR_REG = "DDR" ~ port %}
{% set MASK = bits | int %}
{% set INV_MASK = 255 - MASK %}
{% set BIDIR = (direction == "both") %}

; Per-pin bitmask constants (named by pin, preserving caller's order).
{% for bitmask in pin_bitmasks %}
BIT_{{ pins[loop.index0] }} = {{ bitmask | bin }}
{% endfor %}

{% if direction in ("out", "both") and not exclusive_port %}
.segment "ZEROPAGE"

{{ var("tmp") }}: .res 1                   ; Internal temporary for read-modify-write

{% endif %}
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
        lda #{{ MASK | bin }}
        sta {{ DDR_REG }}
{% if default == "on" %}
        sta {{ PORT_REG }}
{% elif default == "off" %}
        lda #$00
        sta {{ PORT_REG }}
{% endif %}
{% else %}
        lda {{ DDR_REG }}
        ora #{{ MASK | bin }}
        sta {{ DDR_REG }}
{% if default == "on" %}
        lda {{ PORT_REG }}
        ora #{{ MASK | bin }}
        sta {{ PORT_REG }}
{% elif default == "off" %}
        lda {{ PORT_REG }}
        and #{{ INV_MASK | bin }}
        sta {{ PORT_REG }}
{% endif %}
{% endif %}
        rts
    .endproc
    .constructor {{ my("init") }}, 16
{% endif %}
{% if direction in ("out", "both") %}

    ; =====================================================================
    ; Set all {{ component_id }} outputs high.
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
        lda #{{ MASK | bin }}
        sta {{ DDR_REG }}
        sta {{ PORT_REG }}
    {% else %}
        lda #{{ MASK | bin }}
        sta {{ PORT_REG }}
    {% endif %}
{% else %}
    {% if BIDIR %}
        lda {{ DDR_REG }}
        ora #{{ MASK | bin }}
        sta {{ DDR_REG }}
    {% endif %}
        lda {{ PORT_REG }}
        ora #{{ MASK | bin }}
        sta {{ PORT_REG }}
{% endif %}
        rts
    .endproc

    ; =====================================================================
    ; Set all {{ component_id }} outputs low.
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
        lda #{{ MASK | bin }}
        sta {{ DDR_REG }}
{% endif %}
        lda #$00
        sta {{ PORT_REG }}
{% else %}
{% if BIDIR %}
        lda {{ DDR_REG }}
        ora #{{ MASK | bin }}
        sta {{ DDR_REG }}
{% endif %}
        lda {{ PORT_REG }}
        and #{{ INV_MASK | bin }}
        sta {{ PORT_REG }}
{% endif %}
        rts
    .endproc

    ; =====================================================================
    ; Toggle all {{ component_id }} outputs.
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
        rts
    .endproc

    ; =====================================================================
    ; Write the accumulator to {{ component_id }}.
    ;
    ; Does NOT change DDR direction. For bidirectional groups, call
    ; {{ api("set_output") }} first if the port was set to input.
    ;
    ; The value in A must have bits positioned within the group mask ({{ MASK | bin }}).
    ; Bits outside the mask are ignored{% if not exclusive_port %} and preserved{% endif %}.
    ;
    ; In:
    ;   A = byte value to write (pre-positioned in {{ MASK | bin }})
    ; Out:
    ;   A = clobbered

{% if exclusive_port %}
    .proc {{ api_def("write") }}
        sta {{ PORT_REG }}
        rts
    .endproc
{% else %}
    .proc {{ api_def("write") }}
        and #{{ MASK | bin }}
        sta {{ var("tmp") }}
        lda {{ PORT_REG }}
        and #{{ INV_MASK | bin }}
        ora {{ var("tmp") }}
        sta {{ PORT_REG }}
        rts
    .endproc
{% endif %}
{% endif %}
{% if direction in ("in", "both") %}

    ; =====================================================================
    ; Read {{ component_id }} input state (with DDR handling).
    ;
{% if BIDIR %}
    ; Switches DDR to input before reading.
    ;
{% endif %}
    ; Out:
    ;   A = group state (masked to {{ MASK | bin }})

    .proc {{ api_def("read") }}
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
        rts
    .endproc

    ; =====================================================================
    ; Read {{ component_id }} port value without changing DDR.
    ;
    ; Out:
    ;   A = group state (masked to {{ MASK | bin }})

    .proc {{ api_def("read_port") }}
        lda {{ PORT_REG }}
        and #{{ MASK | bin }}
        rts
    .endproc
{% endif %}
{% if direction == "both" %}

    ; =====================================================================
    ; Switch {{ component_id }} DDR to output mode.
    ;
    ; Out:
    ;   A = clobbered

{% if exclusive_port %}
    .proc {{ api_def("set_output") }}
        lda #{{ MASK | bin }}
        sta {{ DDR_REG }}
        rts
    .endproc
{% else %}
    .proc {{ api_def("set_output") }}
        lda {{ DDR_REG }}
        ora #{{ MASK | bin }}
        sta {{ DDR_REG }}
        rts
    .endproc
{% endif %}

    ; =====================================================================
    ; Switch {{ component_id }} DDR to input mode.
    ;
    ; Out:
    ;   A = clobbered

{% if exclusive_port %}
    .proc {{ api_def("set_input") }}
        lda #$00
        sta {{ DDR_REG }}
        rts
    .endproc
{% else %}
    .proc {{ api_def("set_input") }}
        lda {{ DDR_REG }}
        and #{{ INV_MASK | bin }}
        sta {{ DDR_REG }}
        rts
    .endproc
{% endif %}
{% endif %}
