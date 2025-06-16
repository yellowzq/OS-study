#ifndef __THEAD_SYNC_H__
#define __THEAD_SYNC_H__
#include "list.h"
#include "stdint.h"
#include "thread.h"

/*信号量结构*/
struct semaphore {
    uint32_t value;                // 信号量的值
    struct list waiters;           // 等待信号量的线程队列
};

/*锁结构*/
struct lock {
    struct task_struct* holder;    // 锁的持有者
    struct semaphore semaphore;     // 信号量，用于实现锁的等待
    uint32_t holder_repeat_nr;      // 锁的持有者重复获取次数
};

void sema_init(struct semaphore* psema,uint32_t value);
void sema_down(struct semaphore* psema);
void sema_up(struct semaphore* psema);
void lock_init(struct lock* plock);
void lock_acquire(struct lock* plock);
void lock_release(struct lock* plock);
#endif // __THEAD_SYNC_H__