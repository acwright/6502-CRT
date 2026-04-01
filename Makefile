TARGET = Cart
CONFIG = 6502

.PHONY: all clean

all: build

build: $(TARGET).asm
	cl65 -t none -C $(CONFIG).cfg -l $(TARGET).lst -o $(TARGET).crt $(TARGET).asm 
	
view:
	hexdump -C $(TARGET).crt

eeprom:
	minipro -p AT28C256	-w $(TARGET).crt

clean:
	rm $(TARGET).crt
	rm $(TARGET).lst
