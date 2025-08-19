#include "print.h"
#include "init.h"
#include "thread.h"
#include "interrupt.h"
#include "console.h"
#include "process.h"
#include "syscall-init.h"
#include "syscall.h"
#include "stdio.h"

void k_thread_a(void*);
void k_thread_b(void*);
void u_prog_a(void);
void u_prog_b(void);

int main(void) {
    put_str("I am kernel\n");
    init_all();

    process_execute(u_prog_a, "u_prog_a");
    process_execute(u_prog_b, "u_prog_b");

    console_put_str(" main_pid:0x");
    console_put_int(sys_getpid());
    console_put_char('\n');
    intr_enable();
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
    while (1);
}

/* 在线程中运行的函数*/
void k_thread_b(void* arg){
    char* para = arg;
    console_put_str(" thread_b_pid:0x");
    console_put_int(sys_getpid());
    console_put_char('\n');
    while (1);
}

/* 用户程序 A */
void u_prog_a(void) {
    char* name = "prog_a";
    printf(" prog_a_name: %s, prog_a_pid: 0x%x\n", name, getpid());
    while (1);
}

/* 用户程序 B */
void u_prog_b(void) {
    char* name = "prog_b";
    printf(" prog_b_name: %s, prog_b_pid: 0x%x\n", name, getpid());
    while (1);
}