; HD44780 LCD: {{ component_id }} ({{ mode }} mode)
;
; Control: {{ ctrl.component_path }} (RS+RWB), {{ pin_en.component_path }} (EN)
; Data bus: {{ data.component_path }}

{% set P = symbol_prefix %}
{% set CTRL_P = ctrl.symbol_prefix %}
{% set DATA_P = data.symbol_prefix %}
{% set EN_P = pin_en.symbol_prefix %}
{% set IS_4BIT = (mode == "4bit") %}

.include "hardware.inc"
.include "CORE/delay.inc"
.include "{{ component_path }}/constants.inc"
.include "{{ data.component_path }}/api.inc"
.include "{{ ctrl.component_path }}/api.inc"
.include "{{ pin_en.component_path }}/api.inc"

; CTRL pin ordering: pins[0]=RS, pins[1]=RWB (set by LCD resolver).
{% set RS_PIN = ctrl.pins[0] %}
{% set RWB_PIN = ctrl.pins[1] %}
{% set RS_BIT = ctrl.pin_bit(RS_PIN) %}
{% set RWB_BIT = ctrl.pin_bit(RWB_PIN) %}

; Select register + read or write mode                                       RS RWB
{{ constant("CTRL_CMD_WR") }}  = $00                                       ; 0  0  write command
{{ constant("CTRL_CMD_RD") }}  = {{ RWB_BIT | bin }}                       ; 0  1  read status
{{ constant("CTRL_DATA_WR") }} = {{ RS_BIT | bin }}                        ; 1  0  write data
{{ constant("CTRL_DATA_RD") }} = {{ RS_BIT | bin }} | {{ RWB_BIT | bin }}  ; 1  1  read data

.segment "KERNALROM"

    ; =========================================================================
    ; Private: pulse EN high then low.
    ;
    ; The GPIO subroutines include sufficient instruction cycles for the
    ; HD44780's minimum EN pulse width (450ns). At 1 MHz each instruction
    ; takes 2-6 µs, so no extra delays are needed.
    ;
    ; Out:
    ;   A = clobbered

    .proc {{ my_def("pulse_en") }}
        jsr {{ EN_P }}::turn_on
        jsr {{ EN_P }}::turn_off
        rts
    .endproc

{% if IS_4BIT %}
    ; =========================================================================
    ; Private: write a byte as two nibbles to the 4-bit data bus.
    ;
    ; The register select (RS) must already be configured by the caller.
    ; Sends the high nibble first, then the low nibble, with EN pulses.
    ;
    ; In:
    ;   A = byte to send
    ; Out:
    ;   A = clobbered

    .proc {{ my_def("write_nibbles") }}
        ; High nibble: upper 4 bits are already in position.
        pha
        jsr {{ DATA_P }}::write_a
        jsr {{ my("pulse_en") }}

        ; Low nibble: shift lower 4 bits into upper position.
        pla
        asl
        asl
        asl
        asl
        jsr {{ DATA_P }}::write_a
        jsr {{ my("pulse_en") }}

        rts
    .endproc

{% endif %}
    ; =========================================================================
    ; Private: write a raw byte to the data bus (used during init only).
    ;
    ; During the power-up sequence the LCD is in 8-bit mode regardless of the
    ; target configuration. This writes data and pulses EN, without checking
    ; the busy flag.
    ;
    ; In:
    ;   A = byte to write
    ; Out:
    ;   A = clobbered

    .proc {{ my_def("write_init") }}
        jsr {{ DATA_P }}::write_a
        jsr {{ my("pulse_en") }}
        rts
    .endproc

    ; =========================================================================
    ; Private: power up sequence — force LCD into {{ mode }} mode.
    ;
    ; Executes the intialization procedure as described in the data sheet.
    ;
    ; Out:
    ;   A = clobbered

    .proc {{ my_def("power_up") }}
        ; Wait >15 ms after Vcc rises before sending any commands.
        DELAY_MS 20

        ; Function Set for turning on 8-bit mode.
        lda #$30

        ; 1st Function Set — wait >4.1 ms afterward.
        jsr {{ my("write_init") }}
        DELAY_MS 5

        ; 2nd Function Set — wait >100 µs afterward.
        jsr {{ my("write_init") }}
        DELAY_US 200

        ; 3rd Function Set — LCD is now reliably in 8-bit mode.
        jsr {{ my("write_init") }}
        DELAY_US 200
{% if IS_4BIT %}

        ; Switch the display to 4-bit mode.
        ; After this, all commands use two-nibble transfers.
        lda #$20
        jsr {{ my("write_init") }}
        DELAY_US 200
{% endif %}

        rts
    .endproc

    ; =========================================================================
    ; Private: configure display parameters.
    ;
    ; Sends Function Set, Display On, and Entry Mode Set commands.
    ; Must be called after the LCD is in the correct bus mode.
    ;
    ; Out:
    ;   A = clobbered

    .proc {{ my_def("configure") }}
        jsr {{ my("wait_ready") }}
        {% if IS_4BIT %}
        lda #CMD_FUNCSET_4BIT
{% else %}
        lda #CMD_FUNCSET_8BIT
{% endif %}
        jsr {{ my("write_cmnd_raw") }}

        jsr {{ my("wait_ready") }}
        lda #CMD_DISPLAY_ON
        jsr {{ my("write_cmnd_raw") }}

        jsr {{ my("wait_ready") }}
        lda #CMD_ENTRYMODE
        jsr {{ my("write_cmnd_raw")}}

        rts
    .endproc

    ; =========================================================================
    ; Private: write command byte without busy-flag check.
    ;
    ; Sets RS=0 (command), RWB=0 (write), writes data, pulses EN.
    ; Used internally — public API should use write_cmnd which polls BF.
    ;
    ; In :
    ;   A = command byte to write
    ; Out:
    ;   A = clobbered

    .proc {{ my_def("write_cmnd_raw") }}
        pha
        lda #{{ constant("CTRL_CMD_WR") }}
        jsr {{ CTRL_P }}::write_a
        pla
{% if IS_4BIT %}
        jsr {{ my("write_nibbles") }}
{% else %}
        jsr {{ DATA_P }}::write_a
        jsr {{ my("pulse_en") }}
{% endif %}
        rts
    .endproc

    ; =========================================================================
    ; Private: poll busy flag until the LCD is ready.
    ;
    ; Reads the busy flag (D7) by switching the data bus to input,
    ; setting RWB=1 (read mode), and pulsing EN. Loops until BF=0.
    ;
    ; Out:
    ;   A = clobbered

    .proc {{ my_def("wait_ready") }}
    @loop:
        ; Switch data pins to input.
        jsr {{ DATA_P }}::set_input

        ; Set control: RS=0 (status), RWB=1 (read).
        lda #{{ constant("CTRL_CMD_RD") }}
        jsr {{ CTRL_P }}::write_a

        ; Pulse EN high and read the data port.
        jsr {{ EN_P }}::turn_on
        jsr {{ DATA_P }}::read_port
        pha                          ; save status byte
        jsr {{ EN_P }}::turn_off

{% if IS_4BIT %}
        ; Clock out the low nibble (ignored).
        jsr {{ my("pulse_en") }}
{% endif %}

        ; Restore data pins to output.
        jsr {{ DATA_P }}::set_output

        ; Restore control to write mode.
        lda #{{ constant("CTRL_CMD_WR") }}
        jsr {{ CTRL_P }}::write_a

        ; Check busy flag.
        pla
        and #BUSY_FLAG
        bne @loop

        rts
    .endproc

; =========================================================================
; Public API
; =========================================================================

    ; =====================================================================
    ; Initialize the LCD display.
    ;
    ; Performs the full power-up sequence, configures the display mode,
    ; and clears the screen. Called automatically via .constructor.
    ;
    ; Out:
    ;   A, X, Y = clobbered

    .proc {{ api_def("init") }}
        ; Set data pins to output.
        jsr {{ DATA_P }}::set_output

        ; Set control pins low (EN=0, CTRL=CMD_WR).
        jsr {{ EN_P }}::turn_off
        lda #{{ constant("CTRL_CMD_WR") }}
        jsr {{ CTRL_P }}::write_a

        ; Power-up, set the device to the correct bit mode.
        jsr {{ my("power_up") }}

        ; Configure display parameters.
        jsr {{ my("configure") }}

        ; Clear screen.
        jsr {{ my("wait_ready") }}
        lda #CMD_CLEAR
        jsr {{ my("write_cmnd_raw") }}

        rts
    .endproc
    .constructor {{ my("init") }}

    ; =====================================================================
    ; Write a command byte to the LCD.
    ;
    ; Waits for the LCD to be ready, then sends the command.
    ;
    ; In:
    ;   A = command byte
    ; Out:
    ;   A = clobbered

    .proc {{ api_def("write_cmnd") }}
        pha
        jsr {{ my("wait_ready") }}
        pla
        jsr {{ my("write_cmnd_raw") }}
        rts
    .endproc

    ; =====================================================================
    ; Write a data byte to the LCD (character output).
    ;
    ; Waits for the LCD to be ready, sets RS=1 (data), then sends the byte.
    ;
    ; In:
    ;   A = data byte
    ; Out:
    ;   A = clobbered

    .proc {{ api_def("write") }}
        pha
        jsr {{ my("wait_ready") }}
        ; RS=1 (data register), RWB=0 (write).
        lda #{{ constant("CTRL_DATA_WR") }}
        jsr {{ CTRL_P }}::write_a
        pla
{% if IS_4BIT %}
        jsr {{ my("write_nibbles") }}
{% else %}
        jsr {{ DATA_P }}::write_a
        jsr {{ my("pulse_en") }}
{% endif %}
        rts
    .endproc

    ; =====================================================================
    ; Clear the display and return cursor to home.
    ;
    ; Out:
    ;   A = clobbered

    .proc {{ api_def("clr") }}
        lda #CMD_CLEAR
        jsr {{ api("write_cmnd") }}
        rts
    .endproc

    ; =====================================================================
    ; Return cursor to home position.
    ;
    ; Out:
    ;   A = clobbered

    .proc {{ api_def("home") }}
        lda #CMD_HOME
        jsr {{ api("write_cmnd") }}
        rts
    .endproc
