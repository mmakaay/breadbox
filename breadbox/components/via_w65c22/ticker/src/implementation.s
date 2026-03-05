; Ticker: {{ component_id }} on {{ provider_device.id }} timer T1, {{ ms_per_tick }}ms/tick
{% if timers %}
; Software timers:
{% for timer in timers %}
;   {{ timer.name }}: {{ timer.ms }}ms ({{ timer.ticks }} tick{{ "s" if timer.ticks != 1 }}, {{ timer.byte_width }} byte{{ "s" if timer.byte_width != 1 }})
{% endfor %}
{% endif %}

.include "CORE/macros.inc"
.include "{{ provider_device.component_path }}/constants.inc"

; Add constructor to BREADBOX, using a high prio, to allow other components
; to make use of the ticker, when required for their initialization.
; Not the highest priority of 32, because that one sets up interrupt vectors,
; which is a requirement for this component.
.constructor {{ my("init") }}, 31

; Add interrupt handler to BREADBOX.
.interruptor {{ my("irq_handler") }}

.segment "KERNALRAM"

    {{ api_def("ticks") }}: .res 3    ; 3 byte counter (~46 hours at 10ms/tick)
{% for timer in timers %}
    {{ api_def(timer.name) }}: .res 1
    {{ my_def(timer.name + "_cd") }}: .res {{ timer.byte_width }}
{% endfor %}

.segment "KERNALROM"

    ; =========================================================================
    ; Initialize {{ component_id }}: configure timer T1 in free-running mode.
    ;
    ; Called automatically during boot via .constructor.
    ;
    ; Out:
    ;   A = clobbered

    .proc {{ my_def("init") }}
        ; Reset the ticker counter.
        lda #0
        sta {{ api("ticks") }}
        sta {{ api("ticks") }} + 1
        sta {{ api("ticks") }} + 2
{% for timer in timers %}

        ; Initialize {{ timer.name }} timer ({{ timer.ms }}ms).
        sta {{ api(timer.name) }}
{% if timer.byte_width == 1 %}
        SET_BYTE {{ my(timer.name + "_cd") }}, #{{ timer.ticks }}
{% elif timer.byte_width == 2 %}
        SET_WORD {{ my(timer.name + "_cd") }}, {{ timer.ticks }}
{% elif timer.byte_width == 3 %}
        lda #<({{ timer.ticks }})
        sta {{ my(timer.name + "_cd") }}
        lda #>({{ timer.ticks }})
        sta {{ my(timer.name + "_cd") }} + 1
        lda #^({{ timer.ticks }})
        sta {{ my(timer.name + "_cd") }} + 2
{% endif %}
{% endfor %}

        ; Configure T1 count down value.
        SET_WORD T1_COUNTER, {{ cycles_per_tick }}

        ; Configure T1 for free-running mode.
        lda ACR                   ; Get existing configuration.
        and #ACR_T1_MASK          ; Clear the T1 settings bits.
        ora #ACR_T1_C             ; Enable continuous interrupts.
        sta ACR                   ; Write back updated configuration.

        ; Enable T1 interrupts.
        SET_BYTE IER, #(IER_TURN_ON | IER_T1)

        cli                       ; Enable interrupts.

        rts
    .endproc

    ; =========================================================================
    ; Handle T1 timer interrupts.
    ;
    ; When the timer triggers, the ticks counter is incremented.
{% if timers %}
    ; Software timer countdowns are decremented; when a countdown reaches
    ; zero, its flag is set and the countdown is reloaded.
{% endif %}

    .proc {{ my_def("irq_handler") }}
        lda #IFR_T1               ; Prepare bit check for T1 interrupt.
        bit IFR                   ; Check if T1 interrupt was triggered.
        beq @done                 ; No interrupt triggered? Then we're done.

        SET_BYTE IFR, #IFR_T1     ; Clear the T1 interrupt flag.

        ; Increment the 3-byte ticks counter.
        inc {{ api("ticks") }}
        bne :+
        inc {{ api("ticks") }} + 1
        bne :+
        inc {{ api("ticks") }} + 2
    :
{% for timer in timers %}

        ; --- {{ timer.name }} ({{ timer.ms }}ms = {{ timer.ticks }} tick{{ "s" if timer.ticks != 1 }}) ---
{% if timer.byte_width == 1 %}
        dec {{ my(timer.name + "_cd") }}
        bne @{{ timer.name }}_done
        inc {{ api(timer.name) }}
        SET_BYTE {{ my(timer.name + "_cd") }}, #{{ timer.ticks }}
    @{{ timer.name }}_done:
{% elif timer.byte_width == 2 %}
        lda {{ my(timer.name + "_cd") }}
        bne :+
        dec {{ my(timer.name + "_cd") }} + 1
    :
        dec {{ my(timer.name + "_cd") }}
        lda {{ my(timer.name + "_cd") }}
        ora {{ my(timer.name + "_cd") }} + 1
        bne @{{ timer.name }}_done
        inc {{ api(timer.name) }}
        SET_WORD {{ my(timer.name + "_cd") }}, {{ timer.ticks }}
    @{{ timer.name }}_done:
{% elif timer.byte_width == 3 %}
        lda {{ my(timer.name + "_cd") }}
        bne :++
        lda {{ my(timer.name + "_cd") }} + 1
        bne :+
        dec {{ my(timer.name + "_cd") }} + 2
    :
        dec {{ my(timer.name + "_cd") }} + 1
    :
        dec {{ my(timer.name + "_cd") }}
        lda {{ my(timer.name + "_cd") }}
        ora {{ my(timer.name + "_cd") }} + 1
        ora {{ my(timer.name + "_cd") }} + 2
        bne @{{ timer.name }}_done
        inc {{ api(timer.name) }}
        lda #<({{ timer.ticks }})
        sta {{ my(timer.name + "_cd") }}
        lda #>({{ timer.ticks }})
        sta {{ my(timer.name + "_cd") }} + 1
        lda #^({{ timer.ticks }})
        sta {{ my(timer.name + "_cd") }} + 2
    @{{ timer.name }}_done:
{% endif %}
{% endfor %}
    @done:
        rts
    .endproc
