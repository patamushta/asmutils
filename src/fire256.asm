;Copyright (C) 2000 Paul Furber <m@verick.co.za>
;
;$Id: fire256.asm,v 1.3 2001/11/24 09:46:18 konst Exp $

;;  This program is free software; you can redistribute it and/or modify
;;  it under the terms of the GNU General Public License as published by
;;  the Free Software Foundation; either version 2 of the License, or
;;  (at your option) any later version.
;;  This program is distributed in the hope that it will be useful,
;;  but WITHOUT ANY WARRANTY; without even the implied warranty of
;;  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;;  GNU General Public License for more details.

%include "system.inc"

%assign SIZE_X 640
%assign SIZE_Y 480
%assign	BPP 8

%assign VMEM_SIZE SIZE_X*SIZE_Y*BPP/8

%assign	FRAMES 1000
	
CODESEG

ALIGN 16
START:
	mov	edi,	VMEM_SIZE
	mov	ebp,	Params

	lea	ebx,	[ebp]		;fb-Params
	sys_open EMPTY,	O_RDWR		; open the framebuffer device

	test	eax,	eax		;have we opened file?
	js	near my_exit

	;; get the fixed screen info 
	mov	[fd],	eax		; save our file descriptor
	mov	ebp,	fix_label
	lea	ebx,	[ebp]		; point ebx to fix
	
	sys_ioctl eax, FBIOGET_FSCREENINFO, ebp; from the kernel source

	test	eax,	eax		; did we get the screen info?
	js	near	my_exit

	;; get the variable screen info 
	mov	eax,	[fd]		; get our file descriptor
	mov	ebp,	var_label
	lea	ebx,	[ebp]		; point ebx to var
	
	sys_ioctl eax, FBIOGET_VSCREENINFO, ebp

	test	eax,	eax		; did we get the screen info?
	js	near	my_exit

	;; memory map the screen mem

	mov	eax,	[fd]		; get saved fd
	mov	edi,	VMEM_SIZE

	_push	0			;.offset
	_push	eax			;.fd
	_push	MAP_SHARED		;.flags
	_push	PROT_READ|PROT_WRITE	;.prot
	_push	edi			;.len
	_push	0			;.addr
	sys_oldmmap esp

	test	eax,	eax		;have we mmaped it?
	js	near	my_exit		; argh
	
	mov	[fix.mmio_start],eax	;  save this
	mov	[fix.mmio_len],	edi	;  and this 

	;; we want to change to this mode
	mov	[var.xres], dword SIZE_X
	mov	[var.yres], dword SIZE_Y
	mov	[var.xres_virtual], dword SIZE_X
	mov	[var.yres_virtual], dword SIZE_Y	;  only one page
	mov	[var.bits_per_pixel], dword BPP
	
	;; set the variable screen info 
	mov	eax,	[fd]		; get our file descriptor
	mov	ebp,	var_label
	lea	ebx,	[ebp]		; point ebx to var
	sys_ioctl eax, FBIOPUT_VSCREENINFO, ebp; set mode to our new parms

	test	eax,	eax		; did we set the screen info?
	js	near	my_exit		; nope :(

	mov	[cmap.start],	dword 0
	mov	[cmap.len],	dword 256
	lea	eax,	[r_val_label]
	mov	[cmap.r_ptr],	eax
	lea	eax,	[g_val_label]
	mov	[cmap.g_ptr],	eax
	lea	eax,	[b_val_label]
	mov	[cmap.b_ptr],	eax
	mov	[cmap.t_ptr],	dword 0

	mov	eax,	[fd]
	mov	ebp,	cmap_label
	lea	ebx,	[ebp]
	sys_ioctl eax, FBIOGETCMAP, ebp;  grab the colour map
	
	test	eax,	eax		; did we get the colour map?
	js	near	my_exit		; nope - bomb

;-------------------------------------------------------------------------
;	set the palette
;-------------------------------------------------------------------------
	
	mov	esi,	[cmap.r_ptr]
	mov	edi,	[cmap.g_ptr]
	mov	ebx,	[cmap.b_ptr]
	xor	edx,	edx
	mov	ecx,	edx
.wloop:
	mov	eax,	ecx
	shl	eax,	8
	mov	[esi],	ax
	mov	[edi],	dx
	mov	[ebx],	dx
	add	esi,	2
	add	edi,	2
	add	ebx,	2
	inc	ecx
	cmp	ecx,	256
	jnz	.wloop
	
	mov	eax,	[fd]
	mov	ebp,	cmap_label
	lea	ebx,	[ebp]
	sys_ioctl eax, FBIOPUTCMAP, ebp;  set the new colour map

	test	eax,	eax		; did we get the colour map?
	js	near	my_exit		; nope - bomb
	
	mov	eax,	0x8088405
	mov	[randfactor],	eax
	mov	eax,	0x13047934
	mov	[randseed],	eax

	sys_gettimeofday start_time,NULL; start measuring
		
	mov	ecx,	FRAMES
mainloop:	
	push	ecx		
	
;-------------------------------------------------------------------------
;	seed the bottom
;-------------------------------------------------------------------------

	lea	esi,	[screen_buffer]
	push	esi
	add	esi,	SIZE_X*(SIZE_Y-1)
	mov	ecx,	SIZE_X/4
;-------------------------------------------------------------------------
; random routine courtesy of LSD a.k.a Mark Webster - thanks!
.randloop:
	mov	eax,	[randseed]
	mul	dword [randfactor]
	inc	eax
	mov	[randseed],eax
	mov	[esi],	eax
	add	esi,	4
	dec	ecx
	jnz	.randloop

;-------------------------------------------------------------------------
;	do the fire
;-------------------------------------------------------------------------
	pop	esi
	movq	mm7,	[shr1mask]
	mov	edi,	[fix.mmio_start]
	movq	mm6,	[sub_value]
	mov	ecx,	SIZE_X*(SIZE_Y-2)/8
.fireloop:
	movq	mm0,	[esi+(SIZE_X*2)-1]
	paddusb	mm0,	[esi+(SIZE_X*2)+1]
	psrlw	mm0,	1
	pand	mm0,	mm7
	psubusb	mm0,	mm6

	movq	[esi],	mm0
	add	esi,	byte 8
	movq	[edi],	mm0
	add	edi,	byte 8
	
	dec	ecx
	jnz	.fireloop

;-------------------------------------------------------------------------
	pop	ecx
	dec	ecx
	jnz	near	mainloop
				
;-------------------------------------------------------------------------
	sys_gettimeofday end_time,NULL
	mov	eax,	[end_time.tv_sec]
	sub	eax,	[start_time.tv_sec]
	mov	ecx,	1000
	mul	ecx
	mov	ebx,	eax
	xor	edx,	edx
	mov	eax,	[end_time.tv_usec]
	sub	eax,	[start_time.tv_usec]
	cdq	
	idiv	ecx
	add	eax,	ebx		; eax now has milliseconds elapsed
;-------------------------------------------------------------------------
	mov	ebx,	eax
	mov	eax,	FRAMES*1000
	xor	edx,	edx
	div	ebx
	lea	ecx,	[dummy]
	call	write_num
	sys_write STDOUT,nl,1
;-------------------------------------------------------------------------

	emms
	xor	eax,	eax		;  no error
			
my_exit:
	sys_exit eax

;-------------------------------------------------------------------------

write_num:
	pushad
	xor	ebx,	ebx
	push	ebx		; length counter
	mov	bl,	10	; radix
.l:
	dec	ecx		; point ecx at the output buffer
	inc	dword [esp]
	xor	edx,	edx
	div	ebx
	or	dl,	'0'
	mov	[ecx],	dl
	test	eax,	eax
	jnz	.l
	pop	edx		; count
syswrite:
	sys_write STDOUT
	popad
	ret
;-------------------------------------------------------------------------
nl	db	__n
ALIGN 16	
shr2mask dd 00111111001111110011111100111111b,00111111001111110011111100111111b
shr1mask dd 01111111011111110111111101111111b,01111111011111110111111101111111b
sub_value dd 0x02010101, 0x01010101
Params:				
fb	db	"/dev/fb0",EOL

	
UDATASEG
ALIGN 4, resb 1
screen_buffer:	
			U8	SIZE_X*SIZE_Y	; off screen buffer
	
fix_label:		
fix	I_STRUC fb_fix
	.id		CHAR	16
	.smem_start	ULONG	1
	.smem_len	U32	1
	.type		U32	1
	.type_aux	U32	1
	.visual		U32	1
	.xpanstep	U16	1
	.ypanstep	U16	1
	.ywrapstep	U16	1
	.line_length	U32	1
	.mmio_start	ULONG	1
	.mmio_len	U32	1
	.accel		U32	1
	.reserved	U16	3
I_END

var_label:		
var	I_STRUC fb_var
	.xres		U32	1
	.yres		U32	1
	.xres_virtual	U32	1
	.yres_virtual	U32	1
	.xoffset	U32	1
	.yoffset	U32	1
		
	.bits_per_pixel	U32	1
	.grayscale	U32	1
	;; fixme! this is a hack
	.red_offset	U32	1
	.red_length	U32	1
	.red_msb_right	U32	1
	.green_offset	U32	1
	.green_length	U32	1
	.green_msb_right	U32	1
	.blue_offset	U32	1
	.blue_length	U32	1
	.blue_msb_right	U32	1
	.transp_offset	U32	1
	.transp_length	U32	1
	.transp_msb_right	U32	1
	

	.nonstd		U32	1
	.activate	U32	1
	.height		U32	1
	.width		U32	1

	.accel_flags	U32	1

	.pixclock	U32	1
	.left_margin	U32	1
	.right_margin	U32	1
	.upper_margin	U32	1
	.lower_margin	U32	1
	.hsync_len	U32	1
	.vsync_len	U32	1
	.sync		U32	1
	.vmode		U32	1
	.reserved	U32	6																							
	
I_END

cmap_label:	
cmap	I_STRUC	fb_cmap
	.start		U32	1
	.len		U32	1
	.r_ptr		U32	1
	.g_ptr		U32	1
	.b_ptr		U32	1
	.t_ptr		U32	1
I_END

r_val_label:	
	r_vals		U16	256
g_val_label:	
	g_vals		U16	256
b_val_label:	
	b_vals		U16	256
			

start_time I_STRUC timeval
.tv_sec		ULONG	1
.tv_usec	ULONG	1
I_END			

end_time I_STRUC timeval
.tv_sec			ULONG	1
.tv_usec		ULONG	1
I_END			

fd			UINT	1
randfactor		U32	1
randseed		U32	1
	
outbuf:
    resd 3		; 12 digits for time display
dummy:
    resd 2		; 

END
