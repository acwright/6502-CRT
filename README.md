6502-CRT
========

Assembly code template for a cartridge for the [A.C. Wright 6502 project](https://github.com/acwright/6502).

## Building

To build, navigate to the directory and use `make`.

### Prerequisites

#### CC65 Compiler

On macOS, install via Homebrew:
```bash
brew install cc65
```

For other platforms or installation methods, refer to the [cc65 project](https://github.com/cc65/cc65).

#### bin2woz

Install from NPM (recommended):
```bash
npm install -g bin2woz
```

Or build from source:
1. Clone the repository:
   ```bash
   git clone https://github.com/acwright/bin2woz.git
   cd bin2woz
   ```

2. Install dependencies and build:
   ```bash
   npm install
   npm run build
   ```

3. Link globally (optional):
   ```bash
   npm link
   ```

For more information, see the [bin2woz project](https://github.com/acwright/bin2woz).

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

