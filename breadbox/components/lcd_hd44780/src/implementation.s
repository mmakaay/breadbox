; HD44780 LCD: {{ component_id }} ({{ mode }} mode, {{ width }}x{{ height }}, {{ characters }})
;
; Control  : RS   = {{ ctrl_pins.provider }}[{{ ctrl_pins.pins[0] }}]
;            RWB  = {{ ctrl_pins.provider }}[{{ ctrl_pins.pins[1] }}]
;            EN   = {{ en_pin.provider }}[{{ en_pin.pin }}]
; Data     : DATA = {{ data_pins.provider }}{{ data_pins.pins }}

{# The order of the pins is set by the resolver. #}
{% set RS_BIT = ctrl_pins.pin_bit(ctrl_pins.pins[0]) %}
{% set RWB_BIT = ctrl_pins.pin_bit(ctrl_pins.pins[1]) %}

.include "CORE/delay_macros.inc"
.include "{{ component_path }}/constants.inc"

; Select register + read or write mode                                      RS RWB
CTRL_CMD_WR  = $00                                       ; 0  0  write command
CTRL_CMD_RD  = {{ RWB_BIT | bin }}                       ; 0  1  read status
CTRL_DATA_WR = {{ RS_BIT | bin }}                        ; 1  0  write data
CTRL_DATA_RD = {{ RS_BIT | bin }} | {{ RWB_BIT | bin }}  ; 1  1  read data

.constructor {{ my("init") }}

; =========================================================================
; Shadow registers for composite commands.
;
; The HD44780 command registers are write-only. Shadow copies in RAM track
; the current state so individual bits can be modified without affecting
; unrelated settings in the same register.
; =========================================================================

.segment "KERNALRAM"

    {{ var("shadow_display") }}: .res 1   ; Display Control bits (D, C, B)
    {{ var("shadow_entry") }}:   .res 1   ; Entry Mode Set bits (I/D, S)

.segment "KERNALROM"

; Load mode-specific driver code.
.include "{{ component_path }}/{{ mode }}.inc"

; =========================================================================
; Private helpers
; =========================================================================

    ; -----------------------------------------------------------------
    ; Pulse EN high then low, with at least 450ns pulse time (per spec).
    ;
    ; Ensuring the required pulse time is done by injecting the number
    ; of nop operations that is required for reaching the pulse time,
    ; based on the configured CPU clock speed.
    ;
    ; This method allows for driving the display on higher clock speeds,
    ; without breaking the data transfers. Most tutorials related to
    ; this end up with the conclusion that the CPU is slow enough to
    ; get the timing right. While that is true for a 1 MHz setup, where
    ; instructions take 2us - 6us (way above the required 450ns), on a
    ; 14 MHz system we're looking at 143ns - 428ns.
    ;
    ; Out:
    ;   A = clobbered

    {# Pulse timing computation, to make sure 450ns is reached #}
    {% set EN_MIN_NS    = 450 %}
    {% set NOP_CYCLES   = 2 %}
    {% set NS_PER_CYCLE = (1_000_000_000 / clock_hz) %}
    {% set NS_PER_NOP   = NOP_CYCLES * NS_PER_CYCLE %}
    {% set NOP_COUNT    = (EN_MIN_NS / NS_PER_NOP) | round(0, 'ceil') | int %}

    .proc {{ my_def("pulse_en") }}
        jsr {{ en_pin.api("turn_on") }}
        {% for _ in range(NOP_COUNT) %}
        nop
        {% endfor %}
        jsr {{ en_pin.api("turn_off") }}
        rts
    .endproc

    ; -----------------------------------------------------------------
    ; Write a raw byte to the data bus (used during init only).
    ;
    ; During the power-up sequence the LCD is in 8-bit mode regardless of
    ; the target configuration. This writes data and pulses EN, without
    ; checking the busy flag.
    ;
    ; In:
    ;   A = byte to write
    ; Out:
    ;   A = clobbered

    .proc {{ my_def("write_init") }}
        jsr {{ data_pins.api("write") }}
        jsr {{ my("pulse_en") }}
        rts
    .endproc

    ; -----------------------------------------------------------------
    ; Power up sequence — force LCD into 8-bit mode.
    ;
    ; Executes the initialization procedure as described in the datasheet,
    ; until the point where the display is guaranteed to be switched into
    ; 8-bit mode.
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

        rts
    .endproc

    ; -----------------------------------------------------------------
    ; Write command byte without busy-flag check.
    ;
    ; Sets RS=0 (command), RWB=0 (write), writes data, pulses EN.
    ; Used internally — public API should use write_cmnd which polls BF.
    ;
    ; In:
    ;   A = command byte to write
    ; Out:
    ;   A = clobbered

    .proc {{ my_def("write_cmnd_raw") }}
        pha
        lda #CTRL_CMD_WR
        jsr {{ ctrl_pins.api("write") }}
        pla
        jsr {{ my("write_byte") }}
        rts
    .endproc

    ; -----------------------------------------------------------------
    ; Poll busy flag until the LCD is ready.
    ;
    ; Reads the busy flag (D7) by switching the data bus to input,
    ; setting RWB=1 (read mode), and pulsing EN. Loops until BF=0.
    ;
    ; Out:
    ;   A = clobbered

    .proc {{ my_def("wait_ready") }}
        ; Switch data pins to input.
        jsr {{ data_pins.api("set_input") }}

        ; Set control: RS=0 (status), RWB=1 (read).
        lda #CTRL_CMD_RD
        jsr {{ ctrl_pins.api("write") }}
    @loop:
        ; Read data from the port.
        jsr {{ my("read_byte") }}

        ; Check busy flag, and wait for "not busy".
        and #BUSY_FLAG
        bne @loop

        ; Restore data pins to output.
        jsr {{ data_pins.api("set_output") }}

        ; Restore control to write mode.
        lda #CTRL_CMD_WR
        jsr {{ ctrl_pins.api("write") }}

        rts
    .endproc

    ; -----------------------------------------------------------------
    ; Send Display Control command from shadow register.
    ;
    ; Out:
    ;   A = clobbered

    .proc {{ my_def("send_display") }}
        jsr {{ my("wait_ready") }}
        lda {{ var("shadow_display") }}
        ora #CMD_DISPLAY
        jsr {{ my("write_cmnd_raw") }}
        rts
    .endproc

    ; -----------------------------------------------------------------
    ; Send Entry Mode Set command from shadow register.
    ;
    ; Out:
    ;   A = clobbered

    .proc {{ my_def("send_entry") }}
        jsr {{ my("wait_ready") }}
        lda {{ var("shadow_entry") }}
        ora #CMD_ENTRYMODE
        jsr {{ my("write_cmnd_raw") }}
        rts
    .endproc

    ; =========================================================================
    ; DDRAM row offset table ({{ height }} rows, {{ width }} columns)
    ; =========================================================================

    {{ my("row_offsets") }}:
    {% for offset in row_offsets %}
        .byte {{ offset | hex }}
    {% endfor %}

    ; =====================================================================
    ; Initialize the LCD display.
    ;
    ; Performs the full power-up sequence, configures the display mode,
    ; initializes shadow registers, and clears the screen.
    ; Called automatically via .constructor.
    ;
    ; Out:
    ;   A, X, Y = clobbered

    .proc {{ my("init") }}
        ; Set data pins to output.
        jsr {{ data_pins.api("set_output") }}

        ; Set control pins low (EN=0, CTRL=CMD_WR).
        jsr {{ en_pin.api("turn_off") }}
        lda #CTRL_CMD_WR
        jsr {{ ctrl_pins.api("write") }}

        ; Power-up, set the device to the correct bus mode.
        jsr {{ my("power_up") }}

        ; Hook for mode-specific initialization.
        jsr {{ my("init_for_mode") }}

        ; Configure Function Set (init only, computed from config).
        jsr {{ my("wait_ready") }}
        lda #{{ funcset_value | hex }}
        jsr {{ my("write_cmnd_raw") }}

        ; Initialize display shadow: display on, cursor off, blink off.
        lda #BIT_DISPLAY_ON
        sta {{ var("shadow_display") }}
        jsr {{ my("send_display") }}

        ; Initialize entry mode shadow: increment, no shift.
        lda #BIT_ENTRY_INC
        sta {{ var("shadow_entry") }}
        jsr {{ my("send_entry") }}

        ; Clear screen.
        jsr {{ my("wait_ready") }}
        lda #CMD_CLEAR
        jsr {{ my("write_cmnd_raw") }}

        rts
    .endproc

; =========================================================================
; Output API
; =========================================================================

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
        lda #CTRL_DATA_WR
        jsr {{ ctrl_pins.api("write") }}
        pla
        jsr {{ my("write_byte") }}
        rts
    .endproc

    ; =====================================================================
    ; Clear the screen and return cursor to home.
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

    ; =====================================================================
    ; Set cursor position by row and column.
    ;
    ; In:
    ;   X = row (0-based)
    ;   Y = column (0-based)
    ; Out:
    ;   A = clobbered

    .proc {{ api_def("move_cursor") }}
        tya
        clc
        adc {{ my("row_offsets") }},x
        ora #CMD_SETDDRAM
        jsr {{ api("write_cmnd") }}
        rts
    .endproc

    ; =====================================================================
    ; Set CGRAM address for custom character definition.
    ;
    ; After this call, subsequent write() calls store data into CGRAM.
    ; Use `move_cursor` to return to DDRAM when done.
    ;
    ; In:
    ;   A = CGRAM address (6-bit, $00-$3F)
    ; Out:
    ;   A = clobbered

    .proc {{ api_def("set_cgram_addr") }}
        and #$3F
        ora #CMD_SETCGRAM
        jsr {{ api("write_cmnd") }}
        rts
    .endproc

    ; =====================================================================
    ; Get the display dimensions.
    ;
    ; Out:
    ;   X = width (columns)
    ;   Y = height (rows)

    .proc {{ api_def("get_size") }}
        ldx #{{ width }}
        ldy #{{ height }}
        rts
    .endproc

; =========================================================================
; Display Control (shadow-based)
; =========================================================================

    ; =====================================================================
    ; Turn the display on (show DDRAM contents).
    ;
    ; Out:
    ;   A = clobbered

    .proc {{ api_def("display_on") }}
        lda {{ var("shadow_display") }}
        ora #BIT_DISPLAY_ON
        sta {{ var("shadow_display") }}
        jmp {{ my("send_display") }}
    .endproc

    ; =====================================================================
    ; Turn the display off (blank, DDRAM contents preserved).
    ;
    ; Out:
    ;   A = clobbered

    .proc {{ api_def("display_off") }}
        lda {{ var("shadow_display") }}
        and #<~BIT_DISPLAY_ON
        sta {{ var("shadow_display") }}
        jmp {{ my("send_display") }}
    .endproc

    ; =====================================================================
    ; Show the cursor (underline at current position).
    ;
    ; Out:
    ;   A = clobbered

    .proc {{ api_def("cursor_on") }}
        lda {{ var("shadow_display") }}
        ora #BIT_CURSOR_ON
        sta {{ var("shadow_display") }}
        jmp {{ my("send_display") }}
    .endproc

    ; =====================================================================
    ; Hide the cursor.
    ;
    ; Out:
    ;   A = clobbered

    .proc {{ api_def("cursor_off") }}
        lda {{ var("shadow_display") }}
        and #<~BIT_CURSOR_ON
        sta {{ var("shadow_display") }}
        jmp {{ my("send_display") }}
    .endproc

    ; =====================================================================
    ; Enable cursor blink (alternating block).
    ;
    ; Out:
    ;   A = clobbered

    .proc {{ api_def("blink_on") }}
        lda {{ var("shadow_display") }}
        ora #BIT_BLINK_ON
        sta {{ var("shadow_display") }}
        jmp {{ my("send_display") }}
    .endproc

    ; =====================================================================
    ; Disable cursor blink.
    ;
    ; Out:
    ;   A = clobbered

    .proc {{ api_def("blink_off") }}
        lda {{ var("shadow_display") }}
        and #<~BIT_BLINK_ON
        sta {{ var("shadow_display") }}
        jmp {{ my("send_display") }}
    .endproc

; =========================================================================
; Entry Mode (shadow-based)
; =========================================================================

    ; =====================================================================
    ; Set cursor direction to left-to-right (increment address after write).
    ;
    ; Out:
    ;   A = clobbered

    .proc {{ api_def("left_to_right") }}
        lda {{ var("shadow_entry") }}
        ora #BIT_ENTRY_INC
        sta {{ var("shadow_entry") }}
        jmp {{ my("send_entry") }}
    .endproc

    ; =====================================================================
    ; Set cursor direction to right-to-left (decrement address after write).
    ;
    ; Out:
    ;   A = clobbered

    .proc {{ api_def("right_to_left") }}
        lda {{ var("shadow_entry") }}
        and #<~BIT_ENTRY_INC
        sta {{ var("shadow_entry") }}
        jmp {{ my("send_entry") }}
    .endproc

    ; =====================================================================
    ; Enable auto-shift (display shifts horizontally on each write).
    ;
    ; Out:
    ;   A = clobbered

    .proc {{ api_def("auto_shift_on") }}
        lda {{ var("shadow_entry") }}
        ora #BIT_ENTRY_SHIFT
        sta {{ var("shadow_entry") }}
        jmp {{ my("send_entry") }}
    .endproc

    ; =====================================================================
    ; Disable auto-shift.
    ;
    ; Out:
    ;   A = clobbered

    .proc {{ api_def("auto_shift_off") }}
        lda {{ var("shadow_entry") }}
        and #<~BIT_ENTRY_SHIFT
        sta {{ var("shadow_entry") }}
        jmp {{ my("send_entry") }}
    .endproc

; =========================================================================
; Cursor/Display Shift (stateless one-shot commands)
; =========================================================================

    ; =====================================================================
    ; Move the cursor one position to the left.
    ;
    ; Out:
    ;   A = clobbered

    .proc {{ api_def("cursor_left") }}
        lda #CMD_SHIFT
        jsr {{ api("write_cmnd") }}
        rts
    .endproc

    ; =====================================================================
    ; Move the cursor one position to the right.
    ;
    ; Out:
    ;   A = clobbered

    .proc {{ api_def("cursor_right") }}
        lda #CMD_SHIFT | BIT_SHIFT_RIGHT
        jsr {{ api("write_cmnd") }}
        rts
    .endproc

    ; =====================================================================
    ; Shift the entire display one position to the left.
    ;
    ; Out:
    ;   A = clobbered

    .proc {{ api_def("shift_left") }}
        lda #CMD_SHIFT | BIT_SHIFT_DISPLAY
        jsr {{ api("write_cmnd") }}
        rts
    .endproc

    ; =====================================================================
    ; Shift the entire display one position to the right.
    ;
    ; Out:
    ;   A = clobbered

    .proc {{ api_def("shift_right") }}
        lda #CMD_SHIFT | BIT_SHIFT_DISPLAY | BIT_SHIFT_RIGHT
        jsr {{ api("write_cmnd") }}
        rts
    .endproc
