; Macros that make `phx`, `plx`, `phy` and `ply` available for 6502 CPUs.
; These only exist on 65C02. These are mainly convenience shims, so we can
; use txa, tya, plx and ply in our code, and still compile for for 6502
; and 65C02 CPUs (saving some cycles on 65C02, losing some on 6502).

.if .not .ismnemonic(phx)
    .importzp {{ zp("cpu_shim_scratch_byte") }}

    .macro phx
        sta {{ zp("cpu_shim_scratch_byte") }}  ; save A
        txa
        pha                                    ; push X
        lda {{ zp("cpu_shim_scratch_byte") }}  ; restore A
    .endmacro

    .macro plx
        sta {{ zp("cpu_shim_scratch_byte") }}  ; save A
        pla                                    ; A = value to go into X
        tax
        lda {{ zp("cpu_shim_scratch_byte") }}  ; restore A
    .endmacro

    .macro phy
        sta {{ zp("cpu_shim_scratch_byte") }}  ; save A
        tya
        pha                                    ; push Y
        lda {{ zp("cpu_shim_scratch_byte") }}  ; restore A
    .endmacro

    .macro ply
        sta {{ zp("cpu_shim_scratch_byte") }}  ; save A
        pla                                    ; A = value to go into Y
        tay
        lda {{ zp("cpu_shim_scratch_byte") }}  ; restore A
    .endmacro

.endif
