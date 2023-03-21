DISKDIM_DRIVE_OFFSET            EQU 0
DISKDIM_HEADS_OFFSET            EQU DISKDIM_DRIVE_OFFSET + 1
DISKDIM_SEGMENTSPERTRACK_OFFSET EQU DISKDIM_HEADS_OFFSET + 1

DISADDRPACK_SIZE_OFFSET     EQU 0
DISADDRPACK_ZERO            EQU 1
DISADDRPACK_SECTORS         EQU 2
DISADDRPACK_SEGMENT         EQU 4
DISADDRPACK_BUFFER          EQU 6
DISADDRPACK_LOW_LOW         EQU 8
DISADDRPACK_LOW_HIGH        EQU 10
DISADDRPACK_UPPER_LOW       EQU 12
DISADDRPACK_UPPER_HIGH      EQU 14
; uses: ax, bx, cx, dx
; param 1 disk_dim_struct
;
; the param 1 MUST contain the drive.
bios_get_dimensions:
    ; retrieve param 1
    mov bx, sp
    mov bx, WORD[ss:bx+2]
    ; get the drive
    mov dl, [bx+DISKDIM_DRIVE_OFFSET]
    mov ah, 8
    int 0x13
    ; heads
    inc dh
    ; sectors per track
    and cl, 0x3f
    ; 
    mov [bx+DISKDIM_HEADS_OFFSET], dh
    mov [bx+DISKDIM_SEGMENTSPERTRACK_OFFSET], cl    
    ret

; param 1 lba16b
; param 2 disk dim struct
;
; return c
; return h
; return s
; Stack: [c][h][s][param 2][param 1][call]
lba16_to_chs:
    ; temp = lba / (sectors per track)
    ; sector = (lba % sectors per track) + 1
    ; head = temp % heads
    ; cylinder = temp / heads
    ; ax / reg8/mem8 => al = ax / reg8/mem8, ah = remainder
    ; load in ax the lba address
    mov bx, sp
    mov ax, WORD[ss:bx+2]
    ; load the struct address in bx
    mov bx, WORD[ss:bx+4]
    ; load sectors per track
    mov cl, BYTE[bx+DISKDIM_SEGMENTSPERTRACK_OFFSET]
    mov ch, 0
    div cl
    inc ah
    ; mov the remainder into segments return
    mov cl, ah
    mov bx, sp
    mov WORD[ss:bx+6], cx
    ; al is the low byte of the quotint so making ah = 0 => ax = quotinet
    mov ah, 0
    ; load the struct addres in bx
    mov bx, WORD[ss:bx+4]
    mov cl, BYTE[bx+DISKDIM_HEADS_OFFSET]
    div cl
    mov bx, sp
    ; saving head
    mov cl, ah
    mov WORD[ss:bx+8], cx
    ; saving cylinder
    mov cl, al
    mov WORD[ss:bx+10], cx
    ret

; param 1 drive
; param 2 cylinder
; param 3 head
; param 4 sector
; param 5 buffer
; return error (error = 1)
bios_load_chs:
    mov bx, sp
    ; drive, param 1
    mov ax, WORD[ss:bx+2]
    mov dl, al
    ; cylinder, param 2 
    mov ax, WORD[ss:bx+4]
    mov ch, al
    ; head, param 3
    mov ax, WORD[ss:bx+6]
    mov dh, al
    ; sector, param 4
    mov ax, WORD[ss:bx+8]
    mov cl, al
    ; buffer, param 5 (write location is in es:bx)
    mov bx, WORD[ss:bx+10]
    mov ah, 2
    ; reading only one segment, explanation why: https://wiki.osdev.org/Disk_access_using_the_BIOS_(INT_13h)
    mov al, 1
    clc
    int 0x13
    mov bx, sp
    ; error handeling
    jnc BIOSLOADSHSNOERROR
    mov WORD[ss:bx+12], 1
    ret
BIOSLOADSHSNOERROR:
    mov WORD[ss:bx+12], 0
    ret

; return 1 if true
has_lba:
    ; look if supported
    mov ah, 0x41
    mov bx, 0x55aa
    mov dl, 0x80
    clc
    int 0x13
    mov bx, sp
    ; return values
    jc NOLBA
    mov WORD[ss:bx+2], 1
    ret
NOLBA:
    mov WORD[ss:bx+2], 0
    ret

; param 1 lba_address LSB
; param 2 lba_address MID
; param 3 lba_address MSB
; param 4 memory address
; param 5 drive
; return success (1 = error)
bios_load_lba:
    ; segment and address
    mov bx, es
    mov WORD[LBA_SEGMENT], bx
    mov bx, sp ; "load" stack
    mov ax, WORD[ss:bx+8]
    mov WORD[LBA_ADDRES], ax

    ; load lba 48bit address
    mov ax, WORD[ss:bx+2]
    mov WORD[LBA_LOW_LOW32b], ax
    mov ax, WORD[ss:bx+4]
    mov WORD[LBA_LOW_HIGH32b], ax
    mov ax, WORD[ss:bx+6]
    mov WORD[LBA_UPPER_LOW32b], ax
    ; ds * 16 + si = DISK_ADDRESS_PACKET_STRUCTURE
    mov ax, 0
    mov ds, ax
    mov si, DISK_ADDRESS_PACKET_STRUCTURE
    mov ah, 0x42
    ; dx = 00 drive
    ; => dl = drive
    mov dx, WORD[ss:bx+10]
    clc
    int 0x13
    jc BIOSLOADLBAERROR
    mov WORD[ss:bx+12], 0
    ret
BIOSLOADLBAERROR:
    mov WORD[ss:bx+12], 1
    ret

; param 1 drive
; param 2 lba lsb
; param 3 lba mid
; param 4 lba msb
; param 5 memory
; return 1 if error else 0
load_segment:
    ; always check if chs or lba should be used
    cmp BYTE[LBA_COMPATIBLE], 1
    jg LOADSEGMENTUSELBA
    jl LOADSEGMENTUSECHS
    ; [LBA_COMPATIBLE] = 1, we don't know yet
    push 0x0
    call has_lba
    pop ax
    cmp ax, 1
    je LOADSEGMENTFOUNDLBA
    ; if function returned 0 we move 0 for load chs
    mov BYTE[LBA_COMPATIBLE], 0
    jmp load_segment
    ; if function returned 1 we mov 2 for load lba
LOADSEGMENTFOUNDLBA:
    mov BYTE[LBA_COMPATIBLE], 2
    jmp load_segment
LOADSEGMENTUSECHS:
    ; we first try to find the dimensions
    ; drive could differ so each time new
    push DISKDIM
    call bios_get_dimensions
    pop ax ; cleanup
    ; get 2 low byte for lba
    mov bx, sp
    mov ax, WORD[ss:bx+4]
    ; push return values
    push 0x0 ; c
    push 0x0 ; h
    push 0x0 ; s
    push DISKDIM ; param 2
    push ax ; param 1
    call lba16_to_chs
    pop ax ; param 1 delete
    pop ax ; param 2 delete
    ; now get return values
    pop ax ; s
    pop dx ; h
    pop cx ; c
    mov bx, sp
    push 0 ; return
    ; bush last one first (buffer)
    push WORD[ss:bx+10]
    push ax ; s
    push dx ; h
    push cx ; c
    push WORD[ss:bx+2]
    call bios_load_chs
    ; cleanup
    pop ax
    pop ax
    pop ax
    pop ax
    pop ax
    pop ax ; get the return
    mov bx, sp
    mov WORD[ss:bx+12], ax
    ret
LOADSEGMENTUSELBA:
    mov bx, sp
    push 0 ; return
    push WORD[ss:bx+2]
    push WORD[ss:bx+10]
    push WORD[ss:bx+8]
    push WORD[ss:bx+6]
    push WORD[ss:bx+4]
    call bios_load_lba
    pop ax
    pop ax
    pop ax
    pop ax
    pop ax
    pop ax ; get the return
    mov bx, sp
    mov WORD[ss:bx+12], ax
    ret

; CAUTION NOT TESTED JUST COPIED WORKING READ VERSION, JUST CHANGED THE BIOS MODE
; param 1 drive
; param 2 cylinder
; param 3 head
; param 4 sector
; param 5 buffer
; return error (error = 1)
bios_write_chs:
    mov bx, sp
    ; drive, param 1
    mov ax, WORD[ss:bx+2]
    mov dl, al
    ; cylinder, param 2 
    mov ax, WORD[ss:bx+4]
    mov ch, al
    ; head, param 3
    mov ax, WORD[ss:bx+6]
    mov dh, al
    ; sector, param 4
    mov ax, WORD[ss:bx+8]
    mov cl, al
    ; buffer, param 5 (write location is in es:bx)
    mov bx, WORD[ss:bx+10]
    mov ah, 3
    ; reading only one segment, because this segment could be the last on the cylinder and we can't cross that boundry.
    mov al, 1
    clc
    int 0x13
    mov bx, sp
    ; error handeling
    jnc BIOSWRITECHSNOERROR
    mov WORD[ss:bx+12], 1
    ret
BIOSWRITECHSNOERROR:
    mov WORD[ss:bx+12], 0
    ret

; CAUTION NOT TESTED JUST COPIED WORKING READ VERSION, JUST CHANGED THE BIOS MODE
; param 1 lba_address LSB
; param 2 lba_address MID
; param 3 lba_address MSB
; param 4 memory address
; param 5 drive
; return success (1 = error)
bios_write_lba:
    ; segment and address
    mov bx, es
    mov WORD[LBA_SEGMENT], bx
    mov bx, sp ; "load" stack
    mov ax, WORD[ss:bx+8]
    mov WORD[LBA_ADDRES], ax

    ; write lba 48bit address
    mov ax, WORD[ss:bx+2]
    mov WORD[LBA_LOW_LOW32b], ax
    mov ax, WORD[ss:bx+4]
    mov WORD[LBA_LOW_HIGH32b], ax
    mov ax, WORD[ss:bx+6]
    mov WORD[LBA_UPPER_LOW32b], ax
    ; ds * 16 + si = DISK_ADDRESS_PACKET_STRUCTURE
    mov ax, 0
    mov ds, ax
    mov si, DISK_ADDRESS_PACKET_STRUCTURE
    mov ah, 0x43
    ; dx = 00 drive
    ; => dl = drive
    mov dx, WORD[ss:bx+10]
    clc
    int 0x13
    jc BIOSWRITELBAERROR
    mov WORD[ss:bx+12], 0
    ret
BIOSWRITELBAERROR:
    mov WORD[ss:bx+12], 1
    ret

; CAUTION NOT TESTED JUST COPIED WORKING READ VERSION, JUST CHANGED FUNCTION CALLS
; param 1 drive
; param 2 lba lsb
; param 3 lba mid
; param 4 lba msb
; param 5 memory
; return 1 if error else 0
write_segment:
    ; always check if chs or lba should be used
    cmp BYTE[LBA_COMPATIBLE], 1
    jg WRITESEGMENTUSELBA
    jl WRITESEGMENTUSECHS
    ; [LBA_COMPATIBLE] = 1, we don't know yet
    push 0x0
    call has_lba
    pop ax
    cmp ax, 1
    je WRITESEGMENTFOUNDLBA
    ; if function returned 0 we move 0 for load chs
    mov BYTE[LBA_COMPATIBLE], 0
    jmp write_segment
    ; if function returned 1 we mov 2 for load lba
WRITESEGMENTFOUNDLBA:
    mov BYTE[LBA_COMPATIBLE], 2
    jmp load_segment
WRITESEGMENTUSECHS:
    ; we first try to find the dimensions
    ; drive could differ so each time new
    push DISKDIM
    call bios_get_dimensions
    pop ax ; cleanup
    ; get 2 low byte for lba
    mov bx, sp
    mov ax, WORD[ss:bx+4]
    ; push return values
    push 0x0 ; c
    push 0x0 ; h
    push 0x0 ; s
    push DISKDIM ; param 2
    push ax ; param 1
    call lba16_to_chs
    pop ax ; param 1 delete
    pop ax ; param 2 delete
    ; now get return values
    pop ax ; s
    pop dx ; h
    pop cx ; c
    mov bx, sp
    push 0 ; return
    ; bush last one first (buffer)
    push WORD[ss:bx+10]
    push ax ; s
    push dx ; h
    push cx ; c
    push WORD[ss:bx+2]
    call bios_write_chs ; changed function to write
    ; cleanup
    pop ax
    pop ax
    pop ax
    pop ax
    pop ax
    pop ax ; get the return
    mov bx, sp
    mov WORD[ss:bx+12], ax
    ret
WRITESEGMENTUSELBA:
    mov bx, sp
    push 0 ; return
    push WORD[ss:bx+2]
    push WORD[ss:bx+10]
    push WORD[ss:bx+8]
    push WORD[ss:bx+6]
    push WORD[ss:bx+4]
    call bios_write_lba ; changed function to write
    pop ax
    pop ax
    pop ax
    pop ax
    pop ax
    pop ax ; get the return
    mov bx, sp
    mov WORD[ss:bx+12], ax
    ret

LBA_COMPATIBLE: db 1

DISKDIM: db 0, 0, 0

DISK_ADDRESS_PACKET_STRUCTURE:
    LBA_SIZEOFPACKET:   db 16 ; this structure is 16b large
    LBA_ZERO:           db 0 ; must be zero
    LBA_SECTORS:        dw 1 ; we read always only one
    LBA_ADDRES:         dw 0 ; set by func
    LBA_SEGMENT:        dw 0 ; set by func
    LBA_LOW_LOW32b:     dw 0 ; set by func
    LBA_LOW_HIGH32b:    dw 0 ; set by func
    LBA_UPPER_LOW32b:   dw 0 ; set by func
    LBA_UPPER_HIGH32b:  dw 0 ; must be zero