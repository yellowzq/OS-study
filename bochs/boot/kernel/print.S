TI_GDT equ 0
RPL0 equ 0
SELECTOR_VIDEO equ (0x0003<<3) + TI_GDT + RPL0

[bits 32]
section .text
;----------------   put_str     -----------------
;功能描述：通过put_char来打印以0字符结尾的字符串
;输入：栈中参数为打印的字符串
;输出：无
;------------------------------------------------

global  put_str
put_str:
;由于本函数中只用到了 ebx 和 ecx，只备份这两个寄存器
    push ebx
    push ecx
    xor ecx,ecx
    mov ebx,[esp+12]
.goon:
    mov cl,[ebx]
    cmp cl,0
    jz .str_over
    push ecx
    call put_char
    add esp,4
    inc ebx
    jmp .goon
.str_over:
    pop ecx
    pop ebx
    ret

;----------------   put_char    -----------------
;功能描述：把栈中1个字符写入光标所在处
;------------------------------------------------
global put_char
put_char:
    pushad
    ;保证gs中为正确的视频段选择子
    mov ax, SELECTOR_VIDEO
    mov gs, ax

;;;;;;;;;;;; 获取当前光标位置 ;;;;;;;;;;;;;;;
    ;先获得高8位
    mov dx,0x03d4   ;索引寄存器环境
    mov al,0x0e     ;用于提供光标位置的高8位
    out dx,al
    mov dx,0x03d5   ;通过读写数据端口0x03d5来获得或设置光标位置
    in al,dx        ;得到光标位置的高8位
    mov ah,al

    ;再获取低8位
    mov dx,0x03d4
    mov al,0x0f
    out dx,al
    mov dx,0x03d5
    in al,dx

    ;将光标存入bx
    mov bx,ax
    ;下面这行是在栈中获取待打印的字符
    mov ecx, [esp+36]   ;pushad 4x8=32字节,主调函数4字节返回地址
    cmp cl,0xd
    jz .is_carriage_return
    cmp cl,0xa
    jz .is_line_feed

    cmp cl,0x8          ;BS(backspace)
    jz .is_backspace
    jmp .put_other
;;;;;;;;;;;;;;;;;;;;;;
    
.is_backspace:
;;;;;;;;;;;; backspace 的一点说明 ;;;;;;;;;;
; 当为 backspace 时，本质上只要将光标移向前一个显存位置即可.后面再输入的字符自然会覆盖此处的字符
; 但有可能在键入 backspace 后并不再键入新的字符，这时光标已经向前移动到待删除的字符位置，但字符还在原处
; 这就显得好怪异，所以此处添加了空格或空字符 0
    dec bx
    shl bx,1    ;乘2，表示光标对应显存中的偏移字节
    mov byte [gs:bx],0x20   ;将待删除的字节补为0或空格
    inc bx
    mov byte [gs:bx],0x07
    shr bx,1
    jmp .set_cursor
;;;;;;;;;;;;;;;;;;;;;;

.put_other:
    shl bx,1
    mov [gs:bx],cl
    inc bx
    mov byte [gs:bx],0x07
    shr bx,1
    inc bx
    cmp bx,2000
    jl .set_cursor          ;若光标值小于2000，表示为写到显存的最后，则去设置新的光标值；
                            ;若超出屏幕字符数大小（2000），则换行处理。
.is_line_feed:
.is_carriage_return:
;如果是CR(\r)，只要把光标移到首行就够了
    xor dx,dx               ; dx 是被除数的高 16 位，清 0
    mov ax,bx               ; ax 是被除数的低 16 位
    mov si,80               
    div si
    sub bx,dx               ; 光标值减去除 80 的余数便是取整
                            ; 以上 4 行处理\r 的代码

.is_carriage_return_end:
    add bx,80
    cmp bx,2000
.is_line_feed_end:          ; 若是 LF(\n),将光标移+80 便可
    jl .set_cursor

;屏幕行范围是0~24，滚屏的原理是将屏幕的第1~24行搬运到0~23行，再将24行用空格填充
.roll_screen:
    cld
    mov ecx,960             ;2000-80=1920个字符要搬运，共1920*2=3840字节，一次搬运4字节，共3840/4=960次
    mov esi,0xc00b80a0      ;第1行行首
    mov edi,0xc00b8000      ;第0行行首
    rep movsd

;;;;;;;;;;;;;;;;将最后一行填充为空白
    mov ebx,3840
    mov ecx,80
.cls:
    mov word [gs:ebx],0x0720    ;0720是黑底白字的空格键
    add ebx,2
    loop .cls
    mov bx,1920             ;最后一行行首

.set_cursor:
;将光标设置bx值
;;;;;;;;;;;;;;;;;;;;;;;;;;; 1先设置高8位;;;;;;;;;;;;;;;;;;
    mov dx,0x03d4
    mov al,0x0e
    out dx,al
    mov dx,0x03d5
    mov al,bh
    out dx,al

;;;;;;;;;;;;;;;;;;;;;;;;;;; 2再设置低8位;;;;;;;;;;;;;;;;;;
    mov dx,0x03d4
    mov al,0x0f
    out dx,al
    mov dx,0x03d5
    mov al,bl
    out dx,al
.put_char_done:
    popad
    ret