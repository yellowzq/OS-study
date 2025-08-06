;主引导程序

%include "boot.inc"
SECTION MBR VSTART=0X7C00	;程序加载到0x7c00
    ;初始化寄存器
    MOV AX, CS
    MOV DS, AX
    MOV ES, AX
    MOV SS, AX
    MOV FS, AX
    MOV SP, 0X7C00
    MOV AX, 0XB800        	;显存位置
    MOV GS, AX
    
    ;@brief: 清屏
    ;调用BIOS 0x10中断
    MOV AX, 0X0600        	;AH 功能号 AL是上卷的行数(0,表示全部)
    MOV BX, 0X0700        	;BH 上卷行的属性
    MOV CX, 0             	;(CL,CH)->(X0,Y0)左上角
    MOV DX, 0x184F         	;(DL,DH)->(X1,Y1) 右下角 (80,25)
                            ;VGA文本模式中，一行只能容纳80个字符，共25行
                            ;下标从0开始, 所以 0x18=24, 0x4f=79
    INT 0x10               	;调用BIOS 0x10中断
    ;输出背景色绿色, 前景色红色, 并且跳动的字符串"1 MBR"
    MOV BYTE [GS: 0X00], '1'
    MOV BYTE [GS: 0X01], 0XA4     ;A 表示绿色背景闪烁, 4 表示前景色为红色

    MOV BYTE [GS: 0X02], ' '
    MOV BYTE [GS: 0X03], 0XA4

    MOV BYTE [GS: 0X04], 'M'
    MOV BYTE [GS: 0X05], 0XA4

    MOV BYTE [GS: 0X06], 'B'
    MOV BYTE [GS: 0X07], 0XA4

    MOV BYTE [GS: 0X08], 'R'
    MOV BYTE [GS: 0X09], 0XA4

	mov eax, LOADER_START_SECTOR	;起始扇区 LBA 地址
	mov bx, LOADER_BASE_ADDR		;写入的地址
	mov cx, 4						;待读入的扇区数
	call rd_disk_m_16				;以下读取程序的起始部分（一个扇区）

	jmp LOADER_BASE_ADDR + 0x300

;@brief: 读取硬盘 n 个扇区
; eax = LBA 扇区号
; bx = 将数据写入的内存地址
; cx = 读入的扇区数
rd_disk_m_16:
	mov esi, eax					;备份
	mov di, cx

;读写硬盘：
;第1步：设置要读取的扇区数

	mov dx, 0x1f2
	mov al, cl
	out dx, al						;读取的扇区数

	mov eax, esi					;恢复ax

;第2步：将LBA地址存入 0x1f3 ~ 0x1f6
	;LBA地址 7~0位写入端口 0x1f3
	mov dx, 0x1f3
	out dx, al

    ;LBA 地址 15~8位写入端口 0x1f4
    mov cl, 8
    shr eax, cl
    mov dx, 0x1f4
    out dx, al

	;LBA 地址 23~16位写入端口 0x1f5
	shr eax, cl
	mov dx, 0x1f5
	out dx, al

	shr eax, cl
	and al, 0x0f					;lba 第 24~27位
	or al, 0xe0						;设置 7~4位为 1110，表示 LBA模式
	mov dx, 0x1f6
	out dx,al

;第3步：向0x1f7端口写入读命令，0x20
	mov dx,0x1f7
	mov al,0x20
	out dx,al

;第4步：检测硬盘状态
.not_ready:
	;同一端口，些时表示写入命令，读时表示读入硬盘状态
	nop
	in al, dx
	and al, 0x88 					;第4位为 1 表示硬盘控制器已准备号数据传输
									;第7位位 1 表示硬盘忙
	cmp al,0x08
	jnz .not_ready					;若未准备好，继续等

;第5步；从0x1f0端口读数据
	mov ax, di
	mov dx, 256
	mul dx
	mov cx, ax
	;di 为要读取的扇区数，一个扇区有512字节，每次读入一个字
	; 共需 di*512/2次，所以 di*256
	mov dx, 0x1f0
.go_on_read:
	in ax, dx
	mov [bx], ax
	add bx, 2
	loop .go_on_read
	ret

    times 510-($-$$) db 0
    db 0x55,0xaa            ;魔数