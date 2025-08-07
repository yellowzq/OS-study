;@filename: loader.S
%include "boot.inc"
section loader vstart=LOADER_BASE_ADDR
LOADER_STACK_TOP equ LOADER_BASE_ADDR
;jmp loader_start

;构建 gdt 及其内部的描述符
GDT_BASE:   dd  0x00000000
            dd  0x00000000

CODE_DESC:  dd  0x0000FFFF
            dd  DESC_CODE_HIGH4

DATA_STACK_DESC:    dd  0x0000FFFF
                    dd  DESC_DATA_HIGH4

VIDEO_DESC:     dd  0x80000007  ;limit=(0xbffff-0xb8000)/4k=0x7
                dd  DESC_VIDEO_HIGH4    ;此时dp1为0

GDT_SIZE    equ $-GDT_BASE
GDT_LIMIT  equ GDT_SIZE-1
times 60 dq 0       ;此处预留60个描述符的空位

SELECTOR_CODE   equ (0x0001<<3) + TI_GDT + RPL0     ;相当于（CODE_DESC-GDT_BASE）/8+TI_GDT+RPL0
SELECTOR_DATA   equ (0x0002<<3) + TI_GDT + RPL0
SELECTOR_VIDEO   equ (0x0003<<3) + TI_GDT + RPL0

; total_mem_bytes 用于保存内存容量，以字节为单位，此位置比较好记
; 当前偏移 loader.bin 文件头 0x200字节
; loader.bin 的加载地址是 0x900
; 故 total_mem_bytes 内存中的地址是 0xb00
; 将来在内核中咱们会引用此地址
total_mem_bytes dd 0
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;以下是 gdt 的指针，前2字节是gdt界限，后4字节是 gdt 的起始地址
gdt_ptr dw  GDT_LIMIT
        dd  GDT_BASE

;人工对齐： total_mem_bytes4 + gdt_ptr6 + ards_buf244 + ards_nr2 共256字节
ards_buf times 244 db 0
ards_nr dw 0                ;用于记录 ARDS 结构体数量

loader_start:
;------ int 15h eax=0x0000e820, edx=0x534d4150 ('SMAP')获取内存布局
;功能：利用BIOS中断0x15 子功能 0xe820获取内存
;内存信息的内容用地址范围描述符（ARDS）来描述
    xor ebx,ebx
    mov di,ards_buf
    mov edx,0x534d4150                  ;签名，循环过程中EDX不变
.e820_mem_get_loop:                     ;循环获取每个 ARDS 内存范围描述结构
    mov eax,0x0000e820                  ;执行完 int 0x15后，eax=0x534d4150
    mov ecx,20
    int 0x15
    jc .e820_failed_so_try_e801         ;若cf位为1则有错误发生，尝试0xe801子功能
    add di,cx
    inc word [ards_nr]                  ;记录 ARDS 数量
    cmp ebx,0                           ;若ebx为0且cf不为1，这说明ards全部返回
    jnz .e820_mem_get_loop

;在所有 ards 结构中，找出(base_add_low + length_low)的最大值，即内存的容量
    mov cx,[ards_nr]
;遍历每一个 ARDS 结构体，循环次数是 ARDS 的数量
    mov ebx, ards_buf
    xor edx, edx                        ;edx为最大的内存容量，在此先清 0

.find_max_mem_area:
;无需判断 type 是否为 1，最大的内存块一定是可被使用的
    mov eax, [ebx]                      ;base_add_low
    add eax, [ebx+8]                    ;length_low
    add ebx, 20                         ;指向缓冲区中下一个 ards结构
    cmp edx, eax
;冒泡排序，找出最大，edx寄存器始终是最大的内存容量
    jge .next_ards
    mov edx, eax                        ;edx为总内存大小
.next_ards:
    loop .find_max_mem_area
    jmp .mem_get_ok

;-------- int 15h ax = e801h 获取内存大小，最大支持4G
;返回后，ax cx值一样，以 KB 为单位，bx dx值一样，以64KB为单位
;在ax和cx寄存器中为低16MB，在bx和dx寄存器中为16MB到4GB
.e820_failed_so_try_e801:
    mov ax, 0xe801
    int 0x15
    jc .e801_failed_so_try88            ;若当前 e801 方法失败，就尝试0x88方法

; 1 先算出低15MB内存
; ax和cx中是以KB为单位的内存数量，将其转换为以byte为单位
    mov cx,0x400                        ;cx和ax值一样，cx用作乘数
    mul cx
    shl edx,16
    and eax,0x0000ffff
    or edx,eax
    add edx,0x100000                    ;ax知识15MB，故要加1MB
    mov esi,edx                         ;先把低15MB的内存容量存入esi寄存器备份
; 2 再将16MB以上的内存转换为byte单位
;寄存器bx和dx中是以64kb为单位的内存数量
    xor eax,eax
    mov ax,bx
    mov ecx,0x10000                     ;0x10000十进制为64kb
    mul ecx                             ;32为乘法，默认的被乘数是eax，积为64位
                                        ;高32为存入edx，低32位存入eax
    add esi,eax				;由于此方法只能测出 4GB 以内的内存，故32位eax足够了
    ;edx肯定为0，只加eax便可
    mov edx,esi                         ;edx为总内存大小
    jmp .mem_get_ok

;------- int 15h ah=0x88 获取内存大小，只能获取 64MB 之内 --------
.e801_failed_so_try88:
    ;int 15后，ax存入的是以KB为单位的内存容量
    mov ah,0x88
    int 0x15
    jc .error_hlt
    and eax,0x0000ffff

    ;16位乘法，被乘数是ax，积为32位。积的高16位在dx中
    ;积的低16位在ax中
    mov cx,0x400                        ;0x400等于1024，将ax中的内存容量换位以byte为单位
    mul cx
    shl edx,16                          ;把dx移到高16位
    or edx,eax                          ;把积的低16为组合到edx，为32位的积
    add edx,0x100000                    ;0x88子功能只会返回1MB以上的内存
                                        ;故实际内存大小要加上1MB


.mem_get_ok:
	mov [total_mem_bytes], edx            ;将内存换为bytes为单位然后存入total_mem_bytes中

;---------------- 准备进入保护模式 ------------------
;1 打开A20
;2 加载gdt
;3.将CR0的PE位置0,

	;-------------- 打开A20 --------------
  	in al,0x92
  	or al,0000_0010B
  	out 0x92,al

  	;------------- 加载GDT --------------
  	lgdt [gdt_ptr]

  	;------------- CR0第0位置1 ----------
  	mov eax, cr0
  	or eax, 0x00000001
  	mov cr0, eax

  	jmp dword SELECTOR_CODE:p_mode_start ;刷新流水线
.error_hlt:
    hlt

[bits 32]
p_mode_start:
  	mov ax, SELECTOR_DATA
  	mov ds, ax
  	mov es, ax
  	mov ss, ax
  	mov esp, LOADER_STACK_TOP
  	mov ax, SELECTOR_VIDEO
  	mov gs, ax

;----------------- 加载kernel -----------------
  	mov eax, KERNEL_START_SECTOR ; kernel.bin 所在的扇区号
  	mov ebx, KERNEL_BIN_BASE_ADDR ; 内核加载到的内存地址
  	; 从磁盘读出后，写入到ebx指定的地址
  	mov ecx, 200      ;读入的扇区数
  	call rd_disk_m_32

;创建页目录及页表并初始化页内存位图
  	call setup_page

;要将描述符表地址及偏移量写入内存gdt_ptr,一会儿用新地址重新加载
 	sgdt [gdt_ptr]      ;存储到原来gdt所有的位置

;将gdt描述符中视频段描述符中的段基址+0xc0000000
	mov ebx, [gdt_ptr + 2]        ;加上2是因为gdt_ptr的低2字节是偏移量，高四字节才是GDT地址
	or dword [ebx + 0x18 + 4], 0xc0000000   ;视频段是第3个段描述符，每个描述符是8字节，故为0x18，这里再加上4是因为咱们要的是高4字节，这里或的含义就类似与加，因为目前最高位肯定为0
;段描述符高四字节的最高位是段基址的第31～24位

;将gdt的基址加上0xc0000000使其成为内核所在的高地址
  	add dword [gdt_ptr + 2], 0xc0000000

  	add esp, 0xc0000000   ;将栈指针同样映射到内核地址

  	;把也目录地址附给cr3
  	mov eax, PAGE_DIR_TABLE_POS
  	mov cr3, eax

  	;打开cr0的pg位（第31位）
  	mov eax, cr0
  	or eax, 0x80000000
  	mov cr0, eax

  	;在开启分页后，用gdt新的地址重新加载
  	lgdt [gdt_ptr]    ;重新加载

;;;;;;;;;;;;;;;;;;;;;;;;;;;; 此时不刷新流水线也没问题 ;;;;;;;;;;;;;;;;;;;;;;;;
;由于一直处在 32 位下，原则上不需要强制刷新
;经过实际测试没有以下这两句也没问题
;但以防万一，还是加上啦，免得将来出来莫名其妙的问题
  	jmp SELECTOR_CODE:enter_kernel ;强制刷新流水线，更新 gdt
enter_kernel:
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  	call kernel_init
  	mov esp, 0xc009f000
  	jmp KERNEL_ENTRY_POINT ; 用地址 0x1500 访问测试，结果 ok


;--------- 将kernel.bin 中的 segment拷贝到编译的地址 ----------
kernel_init:
  	xor eax, eax
  	xor ebx, ebx        ;ebx 记录程序头表地址
  	xor ecx, ecx        ;cx 记录程序头表中的 program header数量
  	xor edx, edx        ;dx 记录 program header 尺寸，即 e_phentsize

  	mov dx, [KERNEL_BIN_BASE_ADDR + 42]    ;偏移文件42 字节处为e_phentsize，表示 program header 的大小
  	mov ebx, [KERNEL_BIN_BASE_ADDR + 28]    ;偏移文件28 字节处为e_phoff，表示第1个 program header 在文件中的偏移量，
                                          	;其实该值是0x34，不过还是谨慎点，这里来读取实际值
  
  	add ebx, KERNEL_BIN_BASE_ADDR
  	mov cx, [KERNEL_BIN_BASE_ADDR + 44]    ;偏移文件44 字节处为e_phnum，表示程序头表中的 program header 数量

.each_segment:
  	cmp byte [ebx + 0], PT_NULL      ;判断当前段是否为空，为空说明此 program header 未使用
  	je .PTNULL

  	;为函数 memcpy压入参数，参数是从右往左依次压入的
  	;函数原型类似于 memcpy(void *dest, const void *src, size_t n)
  	push dword [ebx + 16]    ;program header 中偏移16字节的地方是 p_filesz 
                             	;压入函数 memcpy 的第三个参数： size
  	mov eax, [ebx + 4]       ;program header 中偏移4字节的地方是 p_offset
  	add eax, KERNEL_BIN_BASE_ADDR   ;加上 kernel.bin 被加载到的物理地址，eax 为该段的物理地址
  	push eax                 ;压入函数 memcpy 的第二个参数： src
  	push dword [ebx + 8]     ;program header 中偏移8字节的地方是 p_vaddr
                             	;压入函数 memcpy 的第一个参数：dst
  	call mem_cpy
  	add esp, 12              ;清理栈

.PTNULL:
  	add ebx, edx              ;edx 为 program header 大小，即 e_phentsize
                             	;在此 ebx 指向下一个 program header
  	loop .each_segment
  	ret

;---------- 逐字节拷贝 mem_cpy（ dst， src， size） ------------
;输入:栈中三个参数(dst, src, size)
;输出:无
;------------------------------------------------------------
mem_cpy:
  	cld
  	push ebp
  	mov ebp, esp
  	push ecx

  	mov edi, [ebp + 8]       ;dst
  	mov esi, [ebp + 12]      ;src
  	mov ecx, [ebp + 16]      ;size
  	rep movsb
  	pop ecx
  	pop ebp
  	ret


;-------------  创建页目录以及页表 ------------
setup_page:
;先把页目录占用的空间逐字清0
  	mov ecx, 4096     ;表示4K
  	mov esi, 0
.clear_page_dir:
  	mov byte [PAGE_DIR_TABLE_POS + esi], 0
  	inc esi
  	loop .clear_page_dir

;开始创建页目录项(PDE)
.create_pde:    ;创建Page Directory Entry
  	mov eax, PAGE_DIR_TABLE_POS
  	add eax, 0x1000   ;此时eax为第一个页表的位置以及属性
  	mov ebx, eax      ;此处为ebx赋值， 是为.create_pte做准备， ebx为基址
;下面将页目录项0和0xc00都存为第一个页表的地址，每个页表表示4MB内存
;这样0xc03fffff以下的地址和0x003fffff以下的地址都指向相同的页表
;这是为将地址映射为内核地址做准备
  	or eax, PG_US_U | PG_RW_W | PG_P
  	;页目录项的属性RW和P位为1,US为1表示用户属性，所有特权级都可以访问
  	mov [PAGE_DIR_TABLE_POS + 0x0], eax       ;第一个目录项
    ;在页目录表中的地一个目录项写入第一个页表的位置（0x101000）及属性
  	mov [PAGE_DIR_TABLE_POS + 0xc00], eax     ;一个页表项占用4字节
  	;0xc00表示第768个页表占用的页表项，0xc00以上的目录项用于内核空间,768用16进制表示为0x300，这个值再加就是刚好属于内核进程了
  	;也就是页表的0xc0000000~0xffffffff供给1G属于内核，0x0~0xbfffffff共计3G属于用户进程
  	sub eax, 0x1000
  	mov [PAGE_DIR_TABLE_POS + 4092], eax      ;使得最后一个目录项地址指向页目录表自己的地址

;开始创建页表项(PTE)
  	mov ecx, 256                  ;1M低端内存/每页大小4K = 256
  	mov esi, 0                    ;该页表用来分配0x0~0x3fffff的物理页，也就是虚拟地址0x0～0x3fffff和虚拟地址0xc0000000~0xc03fffff对应的物理页，我们现在只用了低1MB，所以此时虚拟地址是等于物理地址的
  	mov edx, PG_US_U | PG_RW_W | PG_P     ;同上面类似
.create_pte:    ;创建Page Table Entry
  	mov [ebx + esi*4], edx    ;此时ebx为第一个页表的首地址，这在上面咱们已经赋值了
  	add edx, 4096
  	inc esi
  	loop .create_pte

;创建内核其他页面的PDE
  	mov eax, PAGE_DIR_TABLE_POS 
  	add eax, 0x2000       ;此时eax为第二个页表的位置
  	or eax, PG_US_U | PG_RW_W | PG_P  ;同上
  	mov ebx, PAGE_DIR_TABLE_POS 
  	mov ecx, 254          ;范围为第769～1022的所有页目录项数量
  	mov esi, 769
.create_kernel_pde:
  	mov [ebx+esi*4], eax
  	inc esi
  	add eax, 0x1000
  	loop .create_kernel_pde
  	ret


;----------------------------------------
;功能：读取硬盘n个扇区
rd_disk_m_32:  ;0xcf6
;---------------------------------------
                        ;eax = 扇区LBA地址
                        ;ebx = 将数据写入的内存地址
                        ;ecx = 读入的扇区数
  	mov esi, eax          ;备份eax
  	mov di, cx          ;备份cx

;读写硬盘：
;第1步：设置要读取的扇区数
  	mov dx, 0x1F2
  	mov al, cl
  	out dx, al        ;读取的扇区数

  	mov eax, esi      ;恢复eax

;第2步：将LBA地址送入0x1F3~0x1F6
  	;将LBA地址0～7存入0x1F3
  	mov dx,0x1F3
  	out dx,al

  	;LBA地址8～15位写入0x1F4
  	mov cl,8          
  	shr eax,cl        ;将eax中数据右移8位，这样就可以接着使用al来取中间8位了
  	mov dx,0x1F4
  	out dx,al

  	;LBA地址16～23位写入0x1F5
  	shr eax,cl
  	mov dx,0x1F5
  	out dx,al

  	shr eax,cl
  	and al,0x0f       ;取LBR第24～27位
  	or al,0xe0        ;设置7～4位为1110,指明LBA寻址模式
  	mov dx,0x1F6
  	out dx,al

;第3步，向0x1F7写入读命令，即为0x20
  	mov dx, 0x1f7
  	mov al, 0x20
  	out dx, al

;第4步：检测硬盘状态
.not_ready:
  	;同一端口，写时表示写入命令字，读时表示读入硬盘状态
  	nop
  	in al, dx     ;此时0x1F7充当Status寄存器
  	and al,0x88

  	cmp al, 0x08  ;判断符号位是否与顺利执行时的符号一致
  	jnz .not_ready

;第5步：从0x1F0端口读取数据
  	mov ax,di   ;edi为之前备份的读入扇区数
  	mov dx, 256
  	mul dx
  	mov cx,ax    ;这里ecx来存放循环次数
	;一个字为2字节，而额我们需要读入一个扇区，即为512字节，每次读入一个字，所以共需edi*256次
  	mov dx, 0x1F0
.go_on_read:
  	in ax,dx
  	mov [ebx], ax
  	add ebx, 2
				; 由于在实模式下偏移地址为16位,所以用bx只会访问到0~FFFFh的偏移。
				; loader的栈指针为0x900,bx为指向的数据输出缓冲区,且为16位，
				; 超过0xffff后,bx部分会从0开始,所以当要读取的扇区数过大,待写入的地址超过bx的范围时，
				; 从硬盘上读出的数据会把0x0000~0xffff的覆盖，
				; 造成栈被破坏,所以ret返回时,返回地址被破坏了,已经不是之前正确的地址,
				; 故程序出会错,不知道会跑到哪里去。
				; 所以改为ebx代替bx指向缓冲区,这样生成的机器码前面会有0x66和0x67来反转。
				; 0X66用于反转默认的操作数大小! 0X67用于反转默认的寻址方式.
				; cpu处于16位模式时,会理所当然的认为操作数和寻址都是16位,处于32位模式时,
				; 也会认为要执行的指令是32位.
				; 当我们在其中任意模式下用了另外模式的寻址方式或操作数大小(姑且认为16位模式用16位字节操作数，
				; 32位模式下用32字节的操作数)时,编译器会在指令前帮我们加上0x66或0x67，
				; 临时改变当前cpu模式到另外的模式下.
				; 假设当前运行在16位模式,遇到0X66时,操作数大小变为32位.
				; 假设当前运行在32位模式,遇到0X66时,操作数大小变为16位.
				; 假设当前运行在16位模式,遇到0X67时,寻址方式变为32位寻址
				; 假设当前运行在32位模式,遇到0X67时,寻址方式变为16位寻址.
  	loop .go_on_read
  	ret