.if .not .ismnemonic(phx)

    .segment "ZEROPAGE"
        scratch_byte: .res 1  ; Used for swap operations as defined in `cpu_shims.inc`.

    .exportzp __core_cpu_shim_scratch_byte = scratch_byte

.endif
