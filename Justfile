help:
    @just --list

# Build ROM from invocation directory
build: clean
    #!/bin/bash
    echo "Building rom.bin for project ..."
    PROJECT="{{invocation_directory()}}"
    SRC="{{justfile_directory()}}/src"
    ca65 -I "$PROJECT" -I "$SRC" src/core/boot.s
    ca65 -I "$PROJECT" -I "$SRC" src/core/vectors.s
    ca65 -I "$PROJECT" -I "$SRC" src/core/delay.s
    ca65 -I "$PROJECT" -I "$SRC" src/core/cpu_shims.s
    cd "$PROJECT"
    ca65 -I "$PROJECT" -I "$SRC" project.s
    ld65 \
        --config "{{justfile_directory()}}/src/breadbox.cfg" \
        {{justfile_directory()}}/src/core/*.o \
        project.o \
        -o rom.bin

dump:
    hexdump -C "{{invocation_directory()}}/rom.bin"

dis:
    da65 --cpu 6502 "{{invocation_directory()}}/rom.bin"

# Build and write ROM from invocation directory to EEPROM
write:
    #!/bin/bash
    cd "{{invocation_directory()}}"
    minipro -p AT28C256 -w rom.bin

write-u:
    #!/bin/bash
    cd "{{invocation_directory()}}"
    minipro -u -p AT28C256 -w rom.bin

# Clean up in invocation directory
clean:
    #!/bin/bash
    find src/ -type f -name '*.o' -exec rm {} \;
    find src/ -type f -name '*.a' -exec rm {} \;
    cd "{{invocation_directory()}}"
    rm -f *.bin *.o *.a


