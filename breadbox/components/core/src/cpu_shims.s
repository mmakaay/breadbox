.if .not .ismnemonic(phx)

    .segment "ZEROPAGE"
        {{ symbol("cpu_shim_scratch_byte") }}: .res 1  ; Used for swap operations as defined in `cpu_shims.inc`.

    {{ exportzp("cpu_shim_scratch_byte") }}

.endif
