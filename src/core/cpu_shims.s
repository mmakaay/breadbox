.if .not .ismnemonic(phx)

    .exportzp __core_cpu_shim_scratch_byte = scratch_byte

    .segment "ZEROPAGE"
        scratch_byte: .res 1
.endif