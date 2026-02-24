help:
    @just --list

check:
    pyright
    ruff check --fix

test:
    pytest tests/

build:
    #!/bin/bash
    cd "{{invocation_directory()}}"
    breadbox build

dump:
    #!/bin/bash
    cd "{{invocation_directory()}}"
    hexdump -C "./build/rom.bin" | less

dis:
    #!/bin/bash
    cd "{{invocation_directory()}}"
    da65 --cpu 6502 "./build/rom.bin" | less

write: build
    #!/bin/bash
    cd "{{invocation_directory()}}"
    minipro -p AT28C256 -w ./"build/rom.bin"

write-u:
    #!/bin/bash
    cd "{{invocation_directory()}}"
    minipro -u -p AT28C256 -w "./build/rom.bin"

