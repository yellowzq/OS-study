#include "keyboard.h"
#include "print.h"
#include "interrupt.h"
#include "io.h"
#include "global.h"

#define KBD_BUF_PORT 0x60        //键盘缓冲区寄存器端口号

/* 键盘中断处理程序*/
static void intr_keyboard_handler(void) {
    uint8_t scancode = inb(KBD_BUF_PORT);  //从键盘缓冲区端口读取扫描码
    put_int(scancode);  //将扫描码打印出来
    return;
}

void keyboard_init(void) {
    put_str("keyboard_init start\n");
    register_handler(0x21, intr_keyboard_handler);  //注册键盘中断处理程序
    put_str("keyboard_init done\n");
}