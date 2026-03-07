# BREADBOX TODOs

- Implement console functionality.
- Change PRINT macro to accept a device scope, instead of a function. When we have
  CONSOLE::write, there is no reason anymore to pass the write function directly
  (which was used to be able to use UART::write-console).
