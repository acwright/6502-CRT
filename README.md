6502-CRT
========

Assembly code cartridge template for the [A.C. Wright 6502 project](https://github.com/acwright/6502).

## Building

To build, navigate to the directory and use `make`.

### Prerequisites

#### CC65 Compiler

On macOS, install via Homebrew:
```bash
brew install cc65
```

For other platforms or installation methods, refer to the [cc65 project](https://github.com/cc65/cc65).

### Available Targets

- `make` or `make all` - Build the program
- `make view` - Display hexdump of the built program
- `make eeprom` - Write the binary file to an eeprom
- `make clean` - Remove build artifacts

### Example

```bash
cd <directory-name>
make        # Build the program
make view   # View the hexdump
make eeprom # Write the binary file to an eeprom using minipro
```

