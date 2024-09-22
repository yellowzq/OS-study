;@filename: loader.S
%include "include/boot.inc"
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
    add esi,eax
;由于此方法只能测出 4GB 以内的内存，故32位eax足够了
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

.error_hlt:
    jmp $


.mem_get_ok:
  mov [total_mem_bytes], edx            ;将内存换为bytes为单位然后存入total_mem_bytes中

;---------------- 准备进入保护模式 ------------------
;1 打开A20
;2 加载gdt
;3.将CR0的PE位置0,

  ;------------=- 打开A20 --------------
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

[bits 32]
p_mode_start:
  mov ax, SELECTOR_DATA
  mov ds, ax
  mov es, ax
  mov ss, ax
  mov esp, LOADER_STACK_TOP
  mov ax, SELECTOR_VIDEO
  mov gs, ax

  mov byte [gs:160], 'p'

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

  mov byte [gs:160], 'V'    ;视频段段基址已经被更新，用字符V表示vitual addr

  jmp $

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