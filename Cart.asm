.setcpu "65C02"

; make VDP=1 builds for an ACE with a 6502-PICOVDP on BIOS 2.x;
; the default builds for the TMS9918A on BIOS 1.x.
.ifdef VDP
.include "6502-VDP.inc"
.else
.include "6502.inc"
.endif

; =============================================================================
;   THE FLASH CART BUILD  (make FLASH=128K|256K|512K|1M)
; =============================================================================
;   A Flash Cart is banked: $C000-$DFFF is an 8 KB window onto whichever bank
;   the bank register last selected, and $E000-$FFFF is a fixed 8 KB that is
;   always the primary chip's last bank, whatever the register holds.  The
;   vectors live there and can never be banked out.
;
;   Everything new here is inside `.ifdef FLASH`, so `make` with no arguments
;   produces the same 32,768 bytes it always has.
;
;   The mapper is specified in 6502-VCS PLAN.md §2 and is not re-decided here.
; =============================================================================

.ifdef FLASH

; The bank register.  Write-only, 8 bits, at ANY address in $E000-$FFFF; this
; one by convention.  A write latches it and reaches no flash — WEB is not
; asserted there — so writing the register is never also a flash write.
;
; Bit 6 selects the secondary chip on a -1M cart.  Bit 7 is latched and goes
; nowhere.  Bits above the part's bank count alias down: on a 128K part the
; high address pins are not bonded, so $10 is $00.
BANK      = $E000

; The register cannot be read back, so a cart that loses track of which bank it
; selected has no way to recover it.  The template keeps a shadow in the first
; byte of the zero page that 6502.inc §1 marks "Free for a program that has
; taken the machine over" — and a cartridge is by definition such a program.
;
; A cart that pulls in library code has to know this address is claimed.
BANKSHDW  = $3A

.segment "FIXED"

; =============================================================================
;   SetBank — select which 8 KB bank appears at $C000-$DFFF
; =============================================================================
;   A = the bank value.  Preserves X and Y.  Must live in FIXED, and must be
;   called from FIXED: see "the two bugs" below.
;
;   The shadow is written FIRST.  If an interrupt lands between the two stores,
;   the handler sees a shadow one instruction ahead of the hardware rather than
;   one behind, and restoring the hardware from the shadow on the way out puts
;   the two back in agreement.  The other order leaves them permanently
;   disagreed.
; =============================================================================

SetBank:
  sta BANKSHDW                  ; shadow first — see above
  sta BANK                      ; latch the register
  rts

; =============================================================================
;   THE TWO BUGS
; =============================================================================
;   1. SWITCHING BANKS FROM INSIDE A BANK.  `jsr SetBank` from code at
;      $C000-$DFFF returns to an address that no longer holds the calling code.
;      The machine does not fault; it executes whatever the new bank has there.
;      Always bank-switch from FIXED.
;
;   2. AN INTERRUPT DURING A BANK-RELATIVE SEQUENCE.  The default Kernal IRQ
;      handler lives at $A000-$BFFF and is unaffected.  A cart's OWN handler
;      that touches banked data must live in FIXED, and must save the current
;      bank from BANKSHDW, select its own, and restore through SetBank before
;      it returns.
; =============================================================================

.else

.segment "CART"

.endif

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

.ifdef FLASH
  ; RESB clears the bank register to 0 — its /MR is on the reset line — so the
  ; shadow starts honest rather than only becoming so at the first SetBank.
  stz BANKSHDW
.endif

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

.ifdef FLASH
  jsr PrintBankedMsg            ; …and one that lives in bank $01
.endif

@Loop:
  bra @Loop                     ; Loop forever

; =============================================================================
;   Data
; =============================================================================

HelloMsg:
  .byte "Hello from Cartridge!", CHAR_CR, CHAR_LF, $00

.ifdef FLASH

; =============================================================================
;   PrintBankedMsg — a worked cross-bank call
; =============================================================================
;   The shape of this is the whole skill, so the template ships one that runs.
;
;   The caller is in FIXED, the data is in bank $01, and the segment name is
;   the value you write: `.segment "BANK01"` is reached with `lda #$01`.  The
;   bank's contents appear at $C000-$DFFF and nowhere else, so BankedMsg is a
;   $C0xx address in both builds of the listing — that is the window, not the
;   file offset.
;
;   Note what is NOT here: no save and restore of the previous bank.  This runs
;   from CartReset, which knows the register is 0, and it does not return to
;   anything that cares.  A routine called from somewhere that does care reads
;   BANKSHDW first and puts it back through SetBank afterwards.
; =============================================================================

PrintBankedMsg:
  lda #$01                      ; the bank value IS the segment's name
  jsr SetBank                   ; BankedMsg is now at $C000-$DFFF
  lda #<BankedMsg
  ldy #>BankedMsg
  jsr PrintStr                  ; PrintStr is in the Kernal at $A090, not in a
                                ;   bank, so the window stays selected across it
  stz BANKSHDW                  ; leave bank 0 selected, shadow and all
  stz BANK
  rts

.segment "BANK01"

BankedMsg:
  .byte "Hello from bank $01!", CHAR_CR, CHAR_LF, $00

.segment "FIXED"

.endif

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