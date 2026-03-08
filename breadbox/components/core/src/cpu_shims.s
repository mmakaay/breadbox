.segment "ZEROPAGE"

    {{ zp_def("cpu_shim_scratch_byte") }}: .res 1  ; Used for swap operations as defined in `cpu_shims_macros.inc`.
