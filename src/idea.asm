;  $Id: idea.asm,v 1.1 2002/11/04 11:39:07 konst Exp $
;
;  idea.asm
;
;  guesss... & enjoy! ;^)
;
;  (c) 2k2.10(18-25) Maciej Hrebien with dedication
;     to Dominika Ferenc (miss You all the time!)
;
;  based on: Bruce Schneier's "Applied Cryptography"
;            (Polish edition WNT W-wa 1995, page 314..321
;               & code examples at the end of the book)
;  NOTE:
;     IDEA algorithm is patented by Ascom-Tech AG but
;         free of charge for non-commercial users
;
;  2k2.11(01) + read from stdin if no file(s) specified

%include "system.inc"

%assign PADchr ' '	; padding at the end of not full block

CODESEG

; multiply ax with bx modulo (2**16)+1
;       the result goes to ax
; NOTE: the MSBs of eax must be zeroed!

 mod_mul:
	or	eax,eax
	jz	short _a0

	or	bx,bx
	jz	short _b0

	push	edx
	push	ebx

	xor	edx,edx
	mul	bx
	shl	edx,16
	xchg	dx,ax
	xchg	edx,eax
	mov	ebx,65537
	div	ebx
	xchg	ax,dx
	
	pop	ebx
	pop	edx
	ret

 _a0:	mov	ax,bx
 _b0:	neg	ax
	inc	ax
	ret


; ax's multiplicative inversion (brutal method)
;      NOTE: the MSBs of eax are zeroed!

 inv:
	and	eax,0xffff

	or	eax,eax
	jz	short inv_ret

	push	ebx
	push	ecx
	push	edx

	_mov	ecx,65535
	lea	ebx,[ecx+2]
 inv_lp:
	xor	edx,edx
	push	eax

	mul	ecx
	div	ebx

	pop	eax

	dec	edx
	jz	short inv_done

	loop	inv_lp
 inv_done:
	xchg	ecx,eax
	pop	edx
	pop	ecx
	pop	ebx
 inv_ret:
	ret


; encode key generator
; in:  esi - user_key[16]
; out: edi - en_key[52]

 gen_en_key:
	pusha
	push	edi

	_mov	ecx,8
	rep	movsw		; memcpy(en_key,user_key,2*8)

	pop	esi
	inc	ecx		; i = 1
	xor	ebx,ebx		; b = 0
 gek_lp:
	push	ecx

	and	ecx,7		; ax = en_key[b+(i&7)]
	lea	edx,[ebx+ecx]
	mov	ax,[esi+edx*2]

	inc	ecx		; dx = en_key[b+((i+1)&7)]
	and	ecx,7
	lea	edx,[ebx+ecx]
	mov	dx,[esi+edx*2]

	shl	ax,9		; en_key[j++] = (ax << 9)|(dx >> 7)
	shr	dx,7
	or	ax,dx
	stosw

	pop	ecx

	mov	eax,ecx		; b += (!((i++)&7))*8
	and	eax,7
	sub	al,1
	setc	al
	shl	eax,3
	add	ebx,eax

	inc	ecx
	cmp	ecx,44
	jle	short gek_lp

	popa
	ret


; decode key generator
; in:  esi - en_key[52]
; out: edi - de_key[52]

 gen_de_key:
	pusha
	xor	eax,eax

	mov	ax,[esi+2*48]		; de_key[0]=inv(en_key[48])
	call	inv
	stosw

	mov	ax,[esi+2*49]		; de_key[1]=-en_key[49]
	neg	ax
	stosw

	mov	ax,[esi+2*50]		; de_key[2]=-en_key[50]
	neg	ax
	stosw

	mov	ax,[esi+2*51]		; de_key[3]=inv(en_key[51])
	call	inv
	stosw
					; k = 42
	_mov	ecx,42
 gdk_lp:
	mov	eax,[esi+ecx*2+2*4]	; de_key[i++]=en_key[k+4]
	stosd				; de_key[i++]=en_key[k+5]

	mov	ax,[esi+ecx*2]		; de_key[i++]=inv(en_key[k])
	call	inv
	stosw

	mov	ax,[esi+ecx*2+2*2]	; de_key[i++]=-en_key[k+2]
	neg	ax
	stosw

	mov	ax,[esi+ecx*2+2*1]	; de_key[i++]=-en_key[k+1]
	neg	ax
	stosw

	mov	ax,[esi+ecx*2+2*3]	; de_key[i++]=inv(en_key[k+3])
	call	inv
	stosw

	sub	ecx,6
	jnz	short gdk_lp

	mov	eax,[esi+2*4]		; de_key[46]=en_key[4]
	stosd				; de_key[47]=en_key[5]

	lodsw				; de_key[48]=inv(en_key[0])
	call	inv
	stosw

	lodsw				; de_key[49]=-en_key[1]
	neg	ax
	stosw

	lodsw				; de_key[50]=-en_key[2]
	neg	ax
	stosw

	lodsw				; de_key[51]=inv(en_key[3])
	call	inv
	stosw

	popa
	ret


; encode/decode routine
; in:  esi - en/de_key[52]
;      edi - input[4]
; out: edi - output[4]

 do_idea:
	pusha
	push	edi

	mov	cx,[edi]	; x1
	mov	dx,[edi+2*1]	; x2
	mov	bp,[edi+2*2]	; x3
	mov	di,[edi+2*3]	; x4

	_mov	eax,8
 di_lp:
	push	eax

	lodsw			; x1 = x1 %* key[i++]
	mov	bx,cx
	call	mod_mul
	xchg	cx,ax

	lodsw			; x2 += key[i++]
	add	dx,ax

	lodsw			; x3 += key[i++]
	add	bp,ax

	lodsw			; x4 = x4 %* key[i++]
	mov	bx,di
	call	mod_mul
	xchg	di,ax

	mov	bx,bp		; tmp1 = (x1^x3) %* key[i++]
	xor	bx,cx
	lodsw
	call	mod_mul
	push	eax

	mov	bx,di		; tmp2 = (tmp1 + (x2^x4)) %* key[i++]
	xor	bx,dx
	add	bx,ax
	lodsw
	call	mod_mul

	pop	ebx		; tmp1 += tmp2
	add	bx,ax

	xor	cx,ax		; x1 ^= tmp2
	xor	bp,ax		; x3 ^= tmp2
	xor	dx,bx		; x2 ^= tmp1
	xor	di,bx		; x4 ^= tmp1

	xchg	bp,dx		; swap(x2,x3)

	pop	eax
	dec	eax
	jnz	short di_lp

	mov	bx,cx		; x1 = x1 %* key[i++]
	lodsw
	call	mod_mul
	xchg	cx,ax

	lodsw			; x2 += key[i++]
	add	bp,ax

	lodsw			; x3 += key[i++]
	add	dx,ax

	mov	bx,di		; x4 = x4 %* key[i++]
	lodsw
	call	mod_mul

	pop	edi		; store..

	mov	[edi],cx	; x1
	mov	[edi+2*1],bp	; x2
	mov	[edi+2*2],dx	; x3
	mov	[edi+2*3],ax	; x4

	popa
	ret


; idea main routine
; in:  esi - in_fd
;      edi - out_fd
;      edx - key[52]
; out: eax eq 0 if no errors detected else eq -1

 idea:
	push	ebx
	push	ecx
	push	ebp

	sub	esp,2*4
	mov	ebp,esp
 i_lp:
	push	edx

	sys_read esi,ebp,8

	pop	edx

	or	eax,eax
	js	short i_err
	jz	short i_ret
 i_pad:
	cmp	eax,8
	jge	short i_ped

	mov	[ebp+eax],byte PADchr

	inc	eax
	jmp	short i_pad
 i_ped:
	push	esi
	push	edi

	mov	esi,edx
	mov	edi,ebp

	call	do_idea

	pop	edi
	pop	esi

	push	edx

	sys_write edi,ebp,8

	pop	edx

	or	eax,eax
	jns	short i_lp
 i_err:
 i_ret:
	add	esp,8
	pop	ebp
	pop	ecx
	pop	ebx
	ret


; main routine :)

 START:
	pop	eax		; argc
	pop	eax		; argv[0]
	pop	esi		; argv[1]

	or	esi,esi
	jz	short help

	lodsb

	cmp	al,'e'
	je	short getkey

	cmp	al,'d'
	jne	short help
 getkey:
	mov	[ed_flag],al

	pop	esi		; argv[2]

	or	esi,esi
	jz	short help

	mov	edi,usr_key
	_mov	ecx,16
	push	edi
 key_cp:
	lodsb
	or	al,al
	jz	short kcped

	stosb
	dec	ecx
	jnz	short key_cp
 kcped:
	pop	esi
	lea	edi,[esi+16]	; = mov	edi,enc_key

	call	gen_en_key

	mov	ebp,edi

	cmp	[ed_flag],byte 'e'
	je	short pre

	mov	esi,edi
	add	edi,2*52	; = mov	edi,dec_key

	call	gen_de_key

	mov	ebp,edi
 pre:
	pop	edx		; argv[3]
	push	edx
	_mov	eax,STDIN
	
	or	edx,edx
	jz	go
 nextf:
	pop	eax		; argv[n]

	or	eax,eax
	jz	short exit

	sys_open eax,O_RDONLY

	or	eax,eax
	js	short err
 go:
	mov	esi,eax
	_mov	edi,STDOUT
	mov	edx,ebp

	call	idea
	push	eax

	sys_close esi

	pop	eax

	or	eax,eax
	js	short err

	jmp	short nextf
 help:
	sys_write STDERR,usage,27
 err:
 exit:
	sys_exit eax

 _rodata:

 usage db "./idea e|d key16 [file(s)]",0xa

UDATASEG

 usr_key resb 16
 enc_key resb 2*52
 dec_key resb 2*52
 ed_flag resb 1

END