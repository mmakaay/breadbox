.if .not .ismnemonic(phx)

    .exportzp {{ symbol("cpu_shim_scratch_byte") }}

    .segment "ZEROPAGE" : zeropage
        {{ symbol("cpu_shim_scratch_byte") }}: .res 1  ; Used for swap operations as defined in `cpu_shims.inc`.

.endif
