# BREADBOX TODOs

- Implement console functionality.
- Change PRINT macro to accept a device scope, instead of a function. When we have
  CONSOLE::write, there is no reason anymore to pass the write function directly
  (which was used to be able to use UART::write-console).
- Let enabling interrupts with cli be a task of BREADBOX. Now it's in various
  places in driver code, but this should be a global concern instead.
- Fix a scary case-insensitive filesystem issue: when creating a TICKER device,
  code generation will create build/breadbox/TICKER, but also (to include the
  ticker implementation's macros.inc file) build/breadbox/ticker. They are on
  macOS the same directory though, and the source files get mixed up in a single
  directory. It does work, but only because there are no overlapping files in the
  two source directories. This can easily go wrong, and we need config-time
  checks for this (or maybe code-generation-time).
