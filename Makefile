TARGET = Cart
CONFIG = 6502

.PHONY: all build view run eeprom clean

all: build

build: $(TARGET).asm
	cl65 -t none -C $(CONFIG).cfg -l $(TARGET).lst -o $(TARGET).crt $(TARGET).asm 
	
view:
	hexdump -C $(TARGET).crt

run:
	6502 run --cart $(TARGET).crt

eeprom:
	minipro -p AT28C256	-w $(TARGET).crt

clean:
	rm -f $(TARGET).crt $(TARGET).lst
