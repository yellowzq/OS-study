#include "init.h"
#include "print.h"
#include "interrupt.h"
#include "timer.h"
#include "memory.h"
#include "thread.h"
#include "console.h"
#include "keyboard.h"
#include "tss.h"
#include "syscall-init.h"
#include "ide.h"
#include "fs.h"

/*负责初始化所有模块 */
void init_all(void) {
    put_str("init_all\n");
    idt_init();     //初始化中断
    mem_init();     //初始化内存
    thread_init();
    timer_init();   //初始化PIT
    console_init(); //初始化控制台
    keyboard_init(); //初始化键盘
    tss_init();      //初始化任务状态段
    syscall_init();
    intr_enable();    // 后面的ide_init需要打开中断
    ide_init();	     // 初始化硬盘
    filesys_init();   // 初始化文件系统
}