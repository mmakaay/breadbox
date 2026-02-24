; Macros that make `phx`, `plx`, `phy` and `ply` available for 6502 CPUs.
; These only exist on 65C02.

.if .not .ismnemonic(phx)
    .importzp __core_cpu_shim_scratch_byte

    .macro phx
        sta __core_cpu_shim_scratch_byte  ; save A
        txa
        pha                               ; push X
        lda __core_cpu_shim_scratch_byte  ; restore A
    .endmacro

    .macro plx
        sta __core_cpu_shim_scratch_byte  ; save A
        pla                               ; A = value to go into X
        tax
        lda __core_cpu_shim_scratch_byte  ; restore A
    .endmacro

    .macro phy
        sta __core_cpu_shim_scratch_byte  ; save A
        tya
        pha                               ; push Y
        lda __core_cpu_shim_scratch_byte  ; restore A
    .endmacro

    .macro ply
        sta __core_cpu_shim_scratch_byte  ; save A
        pla                               ; A = value to go into Y
        tay
        lda __core_cpu_shim_scratch_byte  ; restore A
    .endmacro

.endif


