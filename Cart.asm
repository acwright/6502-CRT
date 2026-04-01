.setcpu "65C02"

.include "6502.inc"

.segment "CART"

Reset:
  ; Your code goes here!

.segment "VECTORS"

.word   Reset         ; NMI vector
.word   Reset         ; RESET vector
.word   Reset         ; IRQ vector