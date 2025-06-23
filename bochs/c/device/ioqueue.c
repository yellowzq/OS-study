#include "ioqueue.h"
#include "interrupt.h"
#include "global.h"
#include "debug.h"

/* 初始化环形队列 */
void ioqueue_init(struct ioqueue *ioq) {
    lock_init(&ioq->lock);
    ioq->producer = NULL;
    ioq->consumer = NULL;
    ioq->head = 0;
    ioq->tail = 0;
}

static uint32_t next_pos(uint32_t pos) {
    return (pos + 1) % bufsize;  // 返回下一个位置
}

/* 判断队列是否已满 */
bool ioq_full(struct ioqueue *ioq) {
    ASSERT(intr_get_status() == INTR_OFF);  // 确保中断被关闭
    return next_pos(ioq->head) == ioq->tail;  // 如果下一个位置是队尾,则队列已满
}

/* 判断队列是否为空 */
static bool ioq_empty(struct ioqueue *ioq) {
    ASSERT(intr_get_status() == INTR_OFF);  // 确保中断被关闭
    return ioq->head == ioq->tail;  // 如果队首和队尾相同,则队列为空
}
/* 使当前生产者或消费者在此缓冲区上等待 */
static void ioq_wait(struct task_struct **waiter) {
    ASSERT(*waiter == NULL && waiter != NULL);
    *waiter = running_thread();  // 将当前线程设置为等待者
    thread_block(TASK_BLOCKED);  // 阻塞当前线程
}

/* 唤醒waiter */
static void wakeup(struct task_struct **waiter) {
    ASSERT(*waiter != NULL);
    thread_unblock(*waiter);  // 唤醒等待者
    *waiter = NULL;  // 清空等待者
}

/* 消费者从 ioq 队列中获取一个字符 */
char ioq_getchar(struct ioqueue *ioq) {
    ASSERT(intr_get_status() == INTR_OFF);  // 确保中断被关闭
    while (ioq_empty(ioq)) {
        lock_acquire(&ioq->lock);  // 获取锁
        ioq_wait(&ioq->consumer);  // 等待消费者
        lock_release(&ioq->lock);  // 释放锁
    }
    
    char byte = ioq->buf[ioq->tail];  // 从队列中获取字符
    ioq->tail = next_pos(ioq->tail);  // 更新队尾位置

    if (ioq->producer != NULL) {
        wakeup(&ioq->producer);  // 唤醒生产者
    }
    return byte;
}

void ioq_putchar(struct ioqueue *ioq, char byte) {
    ASSERT(intr_get_status() == INTR_OFF);  // 确保中断被关闭
    while (ioq_full(ioq)) {
        lock_acquire(&ioq->lock);  // 获取锁
        ioq_wait(&ioq->producer);  // 等待生产者
        lock_release(&ioq->lock);  // 释放锁
    }
    
    ioq->buf[ioq->head] = byte;  // 将字符放入队列
    ioq->head = next_pos(ioq->head);  // 更新队首位置

    if (ioq->consumer != NULL) {
        wakeup(&ioq->consumer);  // 唤醒消费者
    }
}