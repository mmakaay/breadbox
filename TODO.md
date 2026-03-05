# BREADBOX TODOs

- Impement console functionality.
- Change PRINT macro to accept a device scope, instead of a function. When we have
  CONSOLE::write, there is no reason anymore to pass the write function directly
  (which was used to be able to use UART::write-console).
- Move macros for ticker timing to a better place (out of VIA driver code)
- Let enabling interrupse with cli be a task of BREADBOX. Now it's in various
  places in driver code, but this should be a global concern instead.
