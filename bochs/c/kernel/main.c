#include "print.h"
#include "init.h"
#include "thread.h"
#include "interrupt.h"
#include "console.h"
#include "process.h"
#include "syscall-init.h"
#include "syscall.h"

void k_thread_a(void*);
void k_thread_b(void*);
void u_prog_a(void);
void u_prog_b(void);
int prog_a_pid = 0, prog_b_pid = 0; // 用于测试线程间变量共享

int main(void) {
    put_str("I am kernel\n");
    init_all();
    process_execute(u_prog_a, "u_prog_a");
    process_execute(u_prog_b, "u_prog_b");

    intr_enable();
    console_put_str(" main_pid:0x");
    console_put_int(sys_getpid());
    console_put_char('\n');
    thread_start("k_thread_a", 31, k_thread_a, " A_");
    thread_start("k_thread_b", 31, k_thread_b, " B_");
    while(1);
    return 0;
}

/* 在线程中运行的函数*/
void k_thread_a(void* arg){
    char* para = arg;
    console_put_str(" thread_a_pid:0x");
    console_put_int(sys_getpid());
    console_put_char('\n');
    console_put_str(" prog_a_pid:0x");
    console_put_int(prog_a_pid);
    console_put_str("\n");
    while (1);
}

/* 在线程中运行的函数*/
void k_thread_b(void* arg){
    char* para = arg;
    console_put_str(" thread_b_pid:0x");
    console_put_int(sys_getpid());
    console_put_char('\n');
    console_put_str(" prog_b_pid:0x");
    console_put_int(prog_b_pid);
    console_put_str("\n");
    while (1);
}

/* 用户程序 A */
void u_prog_a(void) {
    prog_a_pid = getpid();
    while (1);
}

/* 用户程序 B */
void u_prog_b(void) {
    prog_b_pid = getpid();
    while (1);
}