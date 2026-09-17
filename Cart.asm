.setcpu "65C02"

; make VDP=1 builds for an ACE with a 6502-PICOVDP on BIOS 2.x;
; the default builds for the TMS9918A on BIOS 1.x.
.ifdef VDP
.include "6502-VDP.inc"
.else
.include "6502.inc"
.endif

.segment "CART"

; =============================================================================
;   CartReset — Cartridge entry point
; =============================================================================
;   Called on power-on / hardware reset.  The cartridge ROM overlays
;   $C000-$FFFF, so the CPU vectors below point here.
;
;   KernalInit ($A078) initializes all hardware:
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

.ifdef VDP
  ; --- VDP build only: refuse to run on BIOS 1.x ---
  ; A cartridge built with 6502-VDP.inc may call 2.x Kernal entries that are
  ; bare RTS slots on 1.x, so it says so and stops instead.
  jsr KernalVersion             ; A = major, X = minor
  cmp #2
  bcs @Bios2
  lda #<NeedsBios2Msg
  ldy #>NeedsBios2Msg
  jsr PrintStr
@Halt:
  bra @Halt                     ; A cartridge has nothing to return to
@Bios2:
.endif

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

  lda #<HelloMsg                ; A = string addr low
  ldy #>HelloMsg                ; Y = string addr high
  jsr PrintStr                  ; Print the message (Kernal $A090)

@Loop:
  bra @Loop                     ; Loop forever

; =============================================================================
;   Data
; =============================================================================

HelloMsg:
  .byte "Hello from Cartridge!", CHAR_CR, CHAR_LF, $00

.ifdef VDP
NeedsBios2Msg:
  .byte "NEEDS BIOS 2 AND A 6502-PICOVDP", CHAR_CR, CHAR_LF, $00
.endif

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