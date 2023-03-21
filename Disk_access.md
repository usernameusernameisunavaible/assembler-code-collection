# Disk access via BIOS
The following functions follow the following calling convention (as callee):

    push 1_return_value
    push 2_return_value
    ...
    push n_return_value

    push n_argument
    ...
    push 2_argment
    push 1_argument
    call function
    pop 1_argument
    pop 2_argument
    ...
    pop n_argument
    pop n_return_value
    ...
    pop 2_return_value
    pop 1_return_value
    ; the popping is mandatory
All of the pushed/poped values must be or are 2 bytes wide.

The functions will be below denoted as in the following format:
name_of_return_1, name_of_return_2, name_of_return_3 function_name(arg_name1, arg_name2, arg_name_n)

The disk dimensions struct is defined as
Offset 0, size 1, drive
Offset 1, size 1, heads
Offset 2, size 1, segments per track

The Disk address packet structure is documented here: https://wiki.osdev.org/Disk_access_using_the_BIOS_(INT_13h) and
additionally in the source code.

## void bios_get_dimensions(disk_dimensions_struct)
Uses the register ax, bx, cx, dx. Initializes further the given struct according to the containing drive.
WARNING: The disk dimensions struct has to contain an initialized drive.

## cylinder, head, sector, lba16_to_chs(16bit_lba_address)
WARNING: In case of an error read the source code

## error bios_load_chs(drive, cylinder, head, buffer)
The returned error value is 1 if an error occurs. The function reads only 1 sector.

## bool has_lba()
Returns 1 (true) if the underlying BIOS supports lba reading.

## error bios_load_lba(lba_address_lsb, lba_address_mid, lba_address_msb, buffer, drive)
The returned error value is 1 if an error occurs. The function reads only 1 sector.

## error load_segment(drive, lba_address_lsb, lba_address_mid, lba_address_msb, buffer)
The returned error value is 1 if an error occurs. The function reads only 1 sector.
For compability reasons it checks itself if lba is suppoerted, if yes it will use is.
In case lba is not supported, it will use chs addressing.

## error bios_write_chs(drive, cylinder, head, sector, buffer)
The returned error value is 1 if an error occurs. The function writes only 1 sector.

## error bios_write_lba(lba_address_lsb, lba_address_mid, lba_address_msb, buffer, drive)
The returned error value is 1 if an error occurs. The function writes only 1 sector.

## error write_segment(drive, lba_address_lsb, lba_address_mid, lba_address_msb, buffer)
The returned error value is 1 if an error occurs. The function writes only 1 sector.
For compability reasons it checks itself if lba is suppoerted, if yes it will use is.
In case lba is not supported, it will use chs addressing.

