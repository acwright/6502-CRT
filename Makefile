TARGET = Cart

# VDP=1 builds for an ACE with a 6502-PICOVDP and BIOS 2.x (6502-VDP.inc).
# The default builds for BIOS 1.x and the TMS9918A (6502.inc).
# ROM=path runs the build on that BIOS image instead of the bundled one.
VDP ?= 0
ifeq ($(VDP),1)
  SUFFIX   = -VDP
  ASFLAGS  = --asm-define VDP
  # --vdp picovdp needs 6502-EMULATOR 3.x or later
  RUNFLAGS = --vdp picovdp
else
  SUFFIX   =
  ASFLAGS  =
  RUNFLAGS =
endif

# FLASH=128K|256K|512K|1M builds a banked Flash Cart image instead of a 32K ROM
# cart: a byte-exact SST39SF0x0 image, switchable 8 KB banks at $C000-$DFFF and
# a fixed bank at $E000-$FFFF. The naming is 6502-VCS PLAN.md §1 — -VDP first,
# then the target — so `make VDP=1 FLASH=1M` is Cart-VDP-1M.crt, never
# Cart-1M-VDP.crt. This is the one place that ordering can be enforced.
FLASH_TARGETS = 128K 256K 512K 1M
FLASH ?=
ifeq ($(FLASH),)
  CONFIG = 6502
else
  ifeq ($(filter $(FLASH),$(FLASH_TARGETS)),)
    $(error FLASH=$(FLASH) is not a cart target — use one of: $(FLASH_TARGETS))
  endif
  SUFFIX  := $(SUFFIX)-$(FLASH)
  CONFIG   = 6502-$(FLASH)
  ASFLAGS += --asm-define FLASH
endif

OUT = $(TARGET)$(SUFFIX)

RUNFLAGS += $(if $(ROM),--rom $(ROM))

.PHONY: all build all-flash view size run eeprom flash configs check-configs verify-layout clean

all: build

build: $(TARGET).asm
	cl65 -t none $(ASFLAGS) -C $(CONFIG).cfg -l $(OUT).lst -m $(OUT).map -o $(OUT).crt $(TARGET).asm

# Every flash target for the current VDP setting, one after the other.
all-flash:
	@for t in $(FLASH_TARGETS); do \
	  $(MAKE) --no-print-directory build FLASH=$$t VDP=$(VDP) || exit 1; \
	done

view:
	hexdump -C $(OUT).crt

# How full each bank is — the one number a banked cart author wants constantly
# and has nowhere good to look for. ld65's map says which segments ended up with
# something in them; the linker config says how big each one could have been.
# The report reads both, and works for the flat 32K cart too.
size: build
	@node tools/size-report.mjs $(CONFIG).cfg $(OUT).map $(OUT).crt

run:
	6502 run $(RUNFLAGS) --cart $(OUT).crt

# The EEPROM path belongs to the 32K ROM cart alone. A 512K image silently
# truncated into a 28C256 is a confusing afternoon, so refuse and say where to
# go instead.
eeprom:
	@if [ -n "$(FLASH)" ]; then \
	  echo "make eeprom writes a 28C256, which holds 32K — a $(FLASH) image does not fit." >&2; \
	  echo "A Flash Cart is burnt through the Flash Helper: make flash FLASH=$(FLASH)" >&2; \
	  exit 1; \
	fi
	minipro -p AT28C256 -w $(OUT).crt

# Burn a Flash Cart through the Flash Helper. `6502-flash program` reads the
# .crt and nothing else — there is no flag that folds a .sav into what it
# writes, by design (6502-VCS PLAN.md §4).
flash:
	@if [ -z "$(FLASH)" ]; then \
	  echo "make flash needs a cart target, as in: make flash FLASH=512K" >&2; \
	  echo "The 32K ROM cart is burnt with make eeprom." >&2; \
	  exit 1; \
	fi
	6502-flash program $(OUT).crt

# The four banked configs are generated — 15 to 127 near-identical stanzas is
# how a hand-written set drifts — and committed, so they can be read, diffed
# and copied into 6502-ASM and 6502-C. check-configs fails on a stale one.
configs:
	node tools/make-cart-cfg.mjs

check-configs:
	node tools/make-cart-cfg.mjs --check

# The banked configs rest on one guarantee: ld65 writes each MEMORY area that
# names a file to that file in the order the areas are declared, and that order
# IS the flash's linear layout. Nothing else in the build depends on it and
# nothing else would notice if it changed — a future ld65 that reordered areas
# would produce a valid-looking image with every bank in the wrong place. This
# builds a cart with a distinct marker in every bank and checks the offsets.
verify-layout:
	@node tools/verify-layout.mjs

clean:
	rm -f $(TARGET).crt $(TARGET).lst $(TARGET).map
	rm -f $(TARGET)-VDP.crt $(TARGET)-VDP.lst $(TARGET)-VDP.map
	@for t in $(FLASH_TARGETS); do \
	  rm -f $(TARGET)-$$t.crt $(TARGET)-$$t.lst $(TARGET)-$$t.map; \
	  rm -f $(TARGET)-VDP-$$t.crt $(TARGET)-VDP-$$t.lst $(TARGET)-VDP-$$t.map; \
	done
