TARGET = Cart
CONFIG = 6502

# VDP=1 builds for an ACE with a 6502-PICOVDP and BIOS 2.x (6502-VDP.inc).
# The default builds for BIOS 1.x and the TMS9918A (6502.inc).
# ROM=path runs the build on that BIOS image instead of the bundled one.
VDP ?= 0
ifeq ($(VDP),1)
  OUT      = $(TARGET)-VDP
  ASFLAGS  = --asm-define VDP
  # --vdp picovdp needs 6502-EMULATOR 3.x or later
  RUNFLAGS = --vdp picovdp
else
  OUT      = $(TARGET)
  ASFLAGS  =
  RUNFLAGS =
endif
RUNFLAGS += $(if $(ROM),--rom $(ROM))

.PHONY: all build view run eeprom clean

all: build

build: $(TARGET).asm
	cl65 -t none $(ASFLAGS) -C $(CONFIG).cfg -l $(OUT).lst -o $(OUT).crt $(TARGET).asm

view:
	hexdump -C $(OUT).crt

run:
	6502 run $(RUNFLAGS) --cart $(OUT).crt

eeprom:
	minipro -p AT28C256 -w $(OUT).crt

clean:
	rm -f $(TARGET).crt $(TARGET).lst
	rm -f $(TARGET)-VDP.crt $(TARGET)-VDP.lst
