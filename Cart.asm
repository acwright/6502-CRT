.setcpu "65C02"

.include "6502.inc"

.segment "CART"

; =============================================================================
;   CartReset — Cartridge entry point
; =============================================================================
;   Called on power-on / hardware reset.  The cartridge ROM overlays
;   $C000-$FFFF, so the CPU vectors below point here.
;
;   KernalInit ($A072) initializes all hardware:
;     - CLD, SEI (clears decimal mode, disables interrupts)
;     - IRQ / BRK / NMI RAM vectors (default handlers)
;     - Probes & inits all detected I/O cards
;     - Sets HW_PRESENT, IO_MODE (auto-detect video/serial)
;     - Does NOT reset the stack pointer — caller must do this
;     - Does NOT enable interrupts — caller must CLI
;     - Does NOT halt if no console is found
; =============================================================================

CartReset:
  ldx #$ff
  txs                           ; Reset the stack pointer
  jsr KernalInit                ; Initialize all hardware (interrupts left disabled)

  ; --- Optional: play startup beep for audible feedback ---
  jsr Beep                      ; Skips silently if no SID present

  ; --- Optional: override interrupt vectors ---
  ; lda #<MyIrqHandler
  ; sta IRQ_PTR
  ; lda #>MyIrqHandler
  ; sta IRQ_PTR + 1

  cli                           ; Enable interrupts

  ; === Your cartridge program starts here ===

  ; Example: clear screen and print a message
  jsr VideoClear                ; Clear video screen (safe even if no video card)

  lda #<HelloMsg
  sta STR_PTR
  lda #>HelloMsg
  sta STR_PTR + 1
  jsr PrintStr                  ; Print the message

@Loop:
  bra @Loop                     ; Loop forever

; =============================================================================
;   PrintStr — Print a null-terminated string via Chrout
;   In: STR_PTR ($02-$03) = pointer to string
; =============================================================================
PrintStr:
  ldy #$00
@PrintLoop:
  lda (STR_PTR),y
  beq @PrintDone                ; Null terminator — done
  jsr Chrout
  iny
  bne @PrintLoop                ; Max 256 chars per call
@PrintDone:
  rts

; =============================================================================
;   Data
; =============================================================================

HelloMsg:
  .byte "Hello from Cartridge!", CHAR_CR, CHAR_LF, $00

; =============================================================================
;   IRQ handler — Cartridge must provide this since it owns the IRQ vector
; =============================================================================
;   The default Kernal IRQ handler (set up by KernalInit via IRQ_PTR) handles
;   keyboard and serial input.  If your cartridge doesn't need custom IRQ
;   processing, simply point the IRQ hardware vector to IrqTrampoline below,
;   which jumps through the RAM vector that KernalInit already configured.

IrqTrampoline:
  jmp (IRQ_PTR)                 ; Dispatch through the RAM-based IRQ vector

NmiTrampoline:
  jmp (NMI_PTR)                 ; Dispatch through the RAM-based NMI vector

; =============================================================================
;   CPU Vectors — Cart owns $FFFA-$FFFF
; =============================================================================

.segment "VECTORS"

.word   NmiTrampoline            ; NMI vector  — dispatch through NMI_PTR
.word   CartReset                ; RESET vector — cartridge entry point
.word   IrqTrampoline            ; IRQ vector  — dispatch through IRQ_PTR