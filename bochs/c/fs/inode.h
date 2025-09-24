#ifndef __FS_INODE_H
#define __FS_INODE_H
#include "stdint.h"
#include "list.h"

/* inode 结构 */
struct inode {
    uint32_t i_no;                // inode编号
    uint32_t i_size;              // 文件大小
    uint32_t i_open_cnts;         // 打开此文件的进程数
    bool     write_deny;          // 写文件不能并行,进程写文件前检查此标志
    uint32_t i_sectors[13];       // 12个直接块,1个一级间接块
    struct list_elem inode_tag;   // 用于加入已打开inode链表
};

#endif