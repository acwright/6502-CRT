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

; =============================================================================
;   SAVES — a cartridge writing to its own flash       (COMMENTED OUT ON PURPOSE)
; =============================================================================
;   A cart that erases a sector every time it runs is not a good default, so
;   this ships as comments.  Uncomment it, set SAVE_BANK for your target, and
;   call SaveGame / LoadGame.
;
;   The command set is 6502-VCS PLAN.md §3.  The runnable version of this, with
;   a chapter around it, is the 6502-DOCS sample `flash-save.asm` and *Bigger
;   cartridges*; what is here is the same thing shaped as something you would
;   keep.
;
;   WHERE A SAVE GOES
;   -----------------
;   By convention across the whole rollout, saves live in the TOP SECTOR OF THE
;   HIGHEST USABLE BANK.  The unit is the chip's 4 KB erase sector, which is
;   also the record size of the `.sav` sidecar (6502-VCS PLAN.md §4) — so
;   `6502-flash merge` and every emulator's save file are talking about the same
;   4 KB as this routine is.
;
;   Each bank is 8 KB, which is two sectors.  The top one is the upper half of
;   the window, $D000-$DFFF:
;
;     target   highest usable bank   fixed bank   that bank's sectors   save
;     ------   -------------------   ----------   -------------------   ----
;     128K     $0E                   $0F          28, 29                29
;     256K     $1E                   $1F          60, 61                61
;     512K     $3E                   $3F          124, 125              125
;     1M       $7F  (U2's last)      $3F  (U1)    254, 255              255
;
;   On a -1M cart only U1's bank $3F is fixed, so U2's $7F is usable and is the
;   highest bank there is.
;
;   WHY IT RUNS FROM RAM
;   --------------------
;   While the primary chip is programming or erasing, EVERY read of it returns
;   status bits instead of data — the fixed region included, which is where this
;   code and the vectors live.  A routine that erases a sector and then fetches
;   its own next instruction reads status and goes somewhere else entirely.  So
;   it is copied to RAM and called there, with SEI, and with the video card's
;   interrupt off if you have enabled it: an IRQ during the window fetches a
;   vector out of a chip that is answering with status.
;
;   6502-EMULATOR models that busy window, so a routine that gets this wrong
;   hangs there exactly as it would on the board.  The PicoCalc port and the DB
;   Emulator complete instantly and would run it happily — which is why the
;   emulator is where a self-programming cart gets developed.  It is recorded in
;   6502-DOCS ACCURACY.md as A76.
;
;   The copy needs no relocating: every address below is an absolute constant
;   and every branch is relative, so the same bytes work wherever they land.
;   That is worth re-checking whenever you change it — one `jsr` to a label
;   inside the routine would silently jump back into the copy in the fixed
;   region and run there, which is the bug this whole section exists to avoid.
;
;   SETTING THE BANK BEFORE EVERY COMMAND CYCLE
;   -------------------------------------------
;   The unlock addresses are FLASH addresses and you can only reach them through
;   the window.  Flash $5555 is offset $1555 of bank $02; flash $2AAA is offset
;   $0AAA of bank $01.  There is no way to write both without a bank switch in
;   between, so the register is set before EVERY cycle — not once at the start.
;   Getting this wrong is the single commonest way a save routine does nothing
;   at all.
;
;   Writing the register between command cycles is safe: those writes go to
;   $E000+ and never assert flash WEB, so they are not themselves part of the
;   sequence.
;
;   WRITING TO U2 IS EASIER
;   -----------------------
;   On a -1M cart, U2 only sees a bus cycle while CE2B is low — that is, only
;   while bit 6 of the register is set.  So a routine that programs U2 can stay
;   in FIXED on U1 and never be copied to RAM at all: U1 stays readable the
;   whole time.  Set bit 6 in every bank value used in the sequence.
;
; -----------------------------------------------------------------------------
;
; SAVE_BANK   = $0E             ; the table above — change this for your target
; SAVE_ADDR   = $D000           ; the top 4 KB sector of that bank
; RAM_ROUTINE = $0800           ; free RAM; a cartridge has all of it
;
; ; The two unlock cycles, as the CPU sees them.
; UNLOCK1_BANK = $02
; UNLOCK1      = $D555          ; = flash $5555
; UNLOCK2_BANK = $01
; UNLOCK2      = $CAAA          ; = flash $2AAA
;
; ; ---------------------------------------------------------------------------
; ;   LoadGame — A = the saved byte, or $FF if nothing has been saved
; ; ---------------------------------------------------------------------------
; ;   Reading needs no command sequence at all: select the bank and read.  $FF is
; ;   what an erased sector holds, and the linker fills every unused byte of the
; ;   image with $FF for exactly this reason, so "erased" and "never written"
; ;   are the same answer and you do not need a separate valid flag.
; ;
; ;   Called from FIXED, like everything that switches banks.
; ; ---------------------------------------------------------------------------
;
; LoadGame:
;   lda BANKSHDW                ; remember what the caller had selected
;   pha
;   lda #SAVE_BANK
;   jsr SetBank
;   lda SAVE_ADDR               ; the save
;   tax
;   pla
;   jsr SetBank                 ; put the caller's bank back
;   txa
;   rts
;
; ; ---------------------------------------------------------------------------
; ;   SaveGame — A = the byte to save
; ; ---------------------------------------------------------------------------
; ;   Copies the RAM routine down and calls it there.  Erases the sector, then
; ;   programs one byte into it.  Both are needed: a byte program can only turn
; ;   bits OFF (new = old AND data), so a byte that has ever been written cannot
; ;   be changed to a larger value without erasing the 4 KB it lives in first.
; ;
; ;   Real saves are a structure, not a byte.  Erase once, then program the
; ;   whole record in a loop before the sector is used again — an erase per byte
; ;   would spend the sector's ~100,000 cycles in an afternoon.
; ; ---------------------------------------------------------------------------
;
; SaveGame:
;   sta SaveValue               ; the RAM routine reads it from here
;   ldx #$00
; @Copy:
;   lda RamSave,x
;   sta RAM_ROUTINE,x
;   inx
;   cpx #(RamSaveEnd - RamSave)
;   bne @Copy
;   jmp RAM_ROUTINE             ; jmp, not jsr: it rts's to SaveGame's caller
;
; SaveValue:
;   .byte $00
;
; ; ---------------------------------------------------------------------------
; ;   RamSave — runs at RAM_ROUTINE, never where it is assembled
; ; ---------------------------------------------------------------------------
;
; RamSave:
;   sei                         ; a vector fetch during the busy window would
;                               ;   read status bits instead of an address
;
;   ; --- Sector erase: $5555<-AA, $2AAA<-55, $5555<-80,
;   ;                   $5555<-AA, $2AAA<-55, sector<-30
;   lda #UNLOCK1_BANK
;   sta BANK
;   lda #$AA
;   sta UNLOCK1
;   lda #UNLOCK2_BANK
;   sta BANK
;   lda #$55
;   sta UNLOCK2
;   lda #UNLOCK1_BANK
;   sta BANK
;   lda #$80
;   sta UNLOCK1
;   lda #UNLOCK1_BANK
;   sta BANK
;   lda #$AA
;   sta UNLOCK1
;   lda #UNLOCK2_BANK
;   sta BANK
;   lda #$55
;   sta UNLOCK2
;   lda #SAVE_BANK
;   sta BANK
;   lda #$30
;   sta SAVE_ADDR               ; any address in the sector picks the sector
;
;   ; DQ7 data polling.  DQ7 reads 0 for the whole ~25 ms erase and 1 once the
;   ; sector is $FF again, so this is just "wait for the top bit".
; @EraseWait:
;   lda SAVE_ADDR
;   bpl @EraseWait
;
;   ; The DQ6 toggle loop is the alternative, and works for an erase or a
;   ; program without knowing what was written: DQ6 flips on every read while
;   ; the chip is busy and stops flipping when it is done, so two reads that
;   ; agree mean finished.  Either loop is correct; use one.
;   ;
;   ; @EraseWait:
;   ;   lda SAVE_ADDR
;   ;   eor SAVE_ADDR
;   ;   and #$40
;   ;   bne @EraseWait
;
;   ; --- Byte program: $5555<-AA, $2AAA<-55, $5555<-A0, target<-data
;   lda #UNLOCK1_BANK
;   sta BANK
;   lda #$AA
;   sta UNLOCK1
;   lda #UNLOCK2_BANK
;   sta BANK
;   lda #$55
;   sta UNLOCK2
;   lda #UNLOCK1_BANK
;   sta BANK
;   lda #$A0
;   sta UNLOCK1
;   lda #SAVE_BANK
;   sta BANK
;   lda SaveValue
;   sta SAVE_ADDR
;
;   ; DQ7 is the COMPLEMENT of the bit just written until the ~20 us window
;   ; closes, so the read matches the value only when the chip is done.  It also
;   ; never matches for a bit the chip could not set — a 0 asked to become a 1
;   ; without an erase — which is the hardware telling you about bug 2 above.
; @ProgramWait:
;   lda SAVE_ADDR
;   eor SaveValue
;   and #$80
;   bne @ProgramWait
;
;   stz BANK                    ; leave the register and its shadow agreed and
;   stz BANKSHDW                ;   at 0, the way reset left them
;   cli
;   rts
;
; RamSaveEnd:
;
; ; The copy loop counts in X, so the routine has to fit in a page.
; .assert (RamSaveEnd - RamSave) < 256, error, "the RAM save routine no longer fits in one page"
;
; =============================================================================

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