#include "console.h"
#include "print.h"
#include "stdint.h"
#include "sync.h"
#include "thread.h"
static struct lock console_lock; // 控制台锁

/* 初始化终端 */
void console_init(void) {
    lock_init(&console_lock); // 初始化控制台锁
}

/* 获取终端 */
void console_acquire(void) {
    lock_acquire(&console_lock); // 获取控制台锁
}

/* 释放终端 */
void console_release(void) {
    lock_release(&console_lock); // 释放控制台锁
}

/* 终端中输出字符串 */
void console_put_str(const char* str) {
    console_acquire(); // 获取控制台锁
    put_str(str); // 调用打印函数输出字符串
    console_release(); // 释放控制台锁
}

/* 终端中输出字符 */
void console_put_char(uint8_t char_asci) {
    console_acquire(); // 获取控制台锁
    put_char(char_asci); // 调用打印函数输出字符
    console_release(); // 释放控制台锁
}

/* 终端中输出十六进制数 */
void console_put_hex(uint32_t num) {
    console_acquire(); // 获取控制台锁
    put_int(num); // 调用打印函数输出十六进制数
    console_release(); // 释放控制台锁
}
