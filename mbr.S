;主引导程序
;LOADER_BASE_ADDR EQU 0X900          	;加载第2个段的地址
;LOADER_START_SECTOR EQU 0X2         	;以LBA方式,loader存在第2个扇区,第一个是主引导扇区

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
    
    jmp $

    times 510-($-$$) db 0
    db 0x55,0xaa            ;魔数
    
