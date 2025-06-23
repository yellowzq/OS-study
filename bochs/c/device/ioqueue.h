#ifndef __DEVICE_IOQUEUE_H
#define __DEVICE_IOQUEUE_H

#include "stdint.h"
#include "thread.h"
#include "sync.h"

#define bufsize 64

/* 环形队列*/
struct ioqueue {
    // 生产者消费者问题
    struct lock lock;  // 锁
    struct task_struct *producer;  // 生产者
    struct task_struct *consumer;  // 消费者
    char buf[bufsize];  // 缓冲区
    uint32_t head;  // 队首
    uint32_t tail;  // 队尾
};

bool ioq_full(struct ioqueue *ioq);
char ioq_getchar(struct ioqueue *ioq);
void ioq_putchar(struct ioqueue *ioq, char byte);
void ioqueue_init(struct ioqueue *ioq);
bool ioq_empty(struct ioqueue *ioq);

#endif