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

write:
    #!/bin/bash
    cd "{{invocation_directory()}}"
    minipro -p AT28C256 -w ./"build/rom.bin"

go: test build write

write-u:
    #!/bin/bash
    cd "{{invocation_directory()}}"
    minipro -u -p AT28C256 -w "./build/rom.bin"

clean:
    #!/bin/bash
    cd "{{invocation_directory()}}"
    if [ -d ./build -a -e ./build/CACHEDIR.TAG ]; then
        rm -fR ./build
    fi

