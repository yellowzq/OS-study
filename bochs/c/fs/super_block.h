#ifndef __FS_SUPER_BLOCK_H
#define __FS_SUPER_BLOCK_H
#include "stdint.h"

/* 超级块 */
struct super_block {
    uint32_t magic;              // 魔数
    uint32_t sec_cnt;            // 本分区总扇区数
    uint32_t inode_cnt;          // 本分区inode节点数
    uint32_t part_lba_base;      // 本分区起始lba地址

    uint32_t block_bitmap_lba;   // 块位图本身起始扇区地址
    uint32_t block_bitmap_sects; // 块位图占用的扇区数

    uint32_t inode_bitmap_lba;   // i节点位图起始扇区地址
    uint32_t inode_bitmap_sects; // i节点位图占用的扇区数

    uint32_t inode_table_lba;   // i节点表起始扇区地址
    uint32_t inode_table_sects; // i节点表占用的扇区数

    uint32_t data_start_lba;    // 数据区起始扇区地址
    uint32_t root_inode_no;   // 根目录所在的i节点号
    uint32_t dir_entry_size;      // 目录项大小

    uint8_t  padding[460];      // 填充使结构体 512 字节大小
} __attribute__ ((packed)); // __attribute

#endif