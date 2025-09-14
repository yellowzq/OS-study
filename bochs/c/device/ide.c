#include "ide.h"
#include "sync.h"
#include "io.h"
#include "stdio.h"
#include "stdio-kernel.h"
#include "interrupt.h"
#include "memory.h"
#include "debug.h"
#include "console.h"
#include "timer.h"
#include "string.h"
#include "list.h"

/* 定义硬盘各寄存器的端口号 */
#define reg_data(channel)      (channel->port_base + 0)    //数据寄存器
#define reg_error(channel)     (channel->port_base + 1)    //错误寄
#define reg_sect_cnt(channel) (channel->port_base + 2)    //扇区数寄存器
#define reg_lba_l(channel)    (channel->port_base + 3)    //lba低8位
#define reg_lba_m(channel)    (channel->port_base + 4)    //lba中8位
#define reg_lba_h(channel)    (channel->port_base + 5)    //lba高8位
#define reg_dev(channel)      (channel->port_base + 6)    //设备寄存器
#define reg_status(channel)   (channel->port_base + 7)    //状态寄存器
#define reg_cmd(channel)      (reg_status(channel))    //命令寄存器
#define reg_alt_status(channel) (channel->port_base + 0x206) //辅助状态寄存器
#define reg_ctl(channel)      (reg_alt_status(channel)) //控制寄存器

/* reg_alt_status 寄存器的一些关键位 */
#define BIT_ALT_STAT_BSY     0x80    // 硬盘忙
#define BIT_ALT_STAT_DRDY    0x40    // 驱动器准备好
#define BIT_ALT_STAT_DRQ     0x08    // 数据传输准备好了
/* device寄存器的一些关键位 */
#define BIT_DEV_MBS          0xa0    // 第 7 位和第 5 位必须为 1
#define BIT_DEV_LBA          0x40    // 该位置 1 表示使用 LBA 模式
#define BIT_DEV_DEV         0x10    // 该位置 1 表示从盘，0 表示主盘

/* 一些硬盘操作的指令 */
#define CMD_IDENTIFY        0xec    // identify 指令
#define CMD_READ_SECTOR    0x20    // 读扇区指令
#define CMD_WRITE_SECTOR   0x30    // 写扇区指令

/* 定义可读写的最大扇区数，调试用的 */
#define max_lba ((80*1024*1024/512) - 1)  // 80MB

uint8_t channel_cnt;       // 按硬盘数计算的通道数
struct ide_channel channels[2]; // 有两个ide通道

/* 用于记录总扩展分区的起始lba，初始为0，partition_sacn时以此为标记 */
int32_t ext_lba_base = 0;

uint8_t p_no = 0, l_no = 0;  // 用于给主分区和逻辑分区命名
struct list partition_list;  // 分区队列

/* 构建一个 16 字节大小的结构体，用来存分区表项 */
struct partition_table_entry {
    uint8_t bootable;       // 是否可引导
    uint8_t start_head;     // 起始磁头号
    uint8_t start_sec;      // 起始扇区号
    uint8_t start_chs;      // 起始柱面号
    uint8_t fs_type;        // 分区类型
    uint8_t end_head;       // 结束磁头号
    uint8_t end_sec;        // 结束扇区号
    uint8_t end_chs;        // 结束柱面号
    uint32_t start_lba;     // 本分区起始扇区的lba地址
    uint32_t sec_cnt;       // 本分区的扇区数
} __attribute__ ((packed)); // __attribute__((packed)) 用于取消编译器的对齐优化

/* 引导扇区,mbr或edr所在扇区 */
struct boot_sector {
    uint8_t other[446]; // 引导代码
    struct partition_table_entry partition_table[4]; // 4 个分区表项
    uint16_t signature; // 启动扇区的结束标志 0x55 0xaa
} __attribute__ ((packed));

/* 选择读写的硬盘 */
static void select_disk(struct disk* hd) {
    uint8_t reg_device = BIT_DEV_MBS | BIT_DEV_LBA;
    if (hd->dev_no == 1) {
        reg_device |= BIT_DEV_DEV; // 从盘
    }
    outb(reg_dev(hd->my_channel), reg_device);
}

/* 向硬盘控制器写入起始扇区地址及要读写的扇区数 */
static void select_sector(struct disk* hd, uint32_t lba, uint8_t sec_cnt) {
    ASSERT(lba <= max_lba);
    struct ide_channel* channel = hd->my_channel;

    /* 写入要读写的扇区数 */
    outb(reg_sect_cnt(channel), sec_cnt);       // 如果 sec_cnt 为 0 则表示 256 个扇区

    /* 写入 lba 逻辑块地址，即扇区号 */
    outb(reg_lba_l(channel), (uint8_t)(lba & 0xFF));         // lba 低 8 位
    outb(reg_lba_m(channel), (uint8_t)((lba >> 8) & 0xFF));  // lba 中 8 位
    outb(reg_lba_h(channel), (uint8_t)((lba >> 16) & 0xFF)); // lba 高 8 位

    /* 写入设备寄存器 */
    outb(reg_dev(channel), BIT_DEV_MBS | BIT_DEV_LBA |(hd->dev_no == 1 ? BIT_DEV_DEV : 0) | lba >> 24);
}

static void cmd_out(struct ide_channel* channel, uint8_t cmd) {
    /* 准备好数据传输 */
    channel->expecting_intr = true; // 置为期待硬盘的中断
    outb(reg_cmd(channel), cmd);    // 向命令寄存器写入命令
}

/* 硬盘读入 sec_cnt 个扇区的数据到 buf */
static void read_from_sector(struct disk* hd, void* buf, uint8_t sec_cnt) {
    uint32_t size_in_byte;
    if (sec_cnt == 0) {
        /* 因为 sec_cnt 是 8 位变量,由主调函数将其赋值时,若为 256 则会将最高位的 1 丢掉变为 0 */
        size_in_byte = 256 * 512; // sec_cnt 为 0 时表示读写 256 个扇区
    } else {
        size_in_byte = sec_cnt * 512;
    }
    insw(reg_data(hd->my_channel), buf, size_in_byte / 2);
}

/* 将 buf 中 sec_cnt 个扇区的数据写入硬盘 */
static void write2sector(struct disk* hd, const void* buf, uint8_t sec_cnt) {
    uint32_t size_in_byte;
    if (sec_cnt == 0) {
        /* 因为 sec_cnt 是 8 位变量,由主调函数将其赋值时,若为 256 则会将最高位的 1 丢掉变为 0 */
        size_in_byte = 256 * 512; // sec_cnt 为 0 时表示读写 256 个扇区
    } else {
        size_in_byte = sec_cnt * 512;
    }
    outsw(reg_data(hd->my_channel), buf, size_in_byte / 2);
}

/* 等待 30s */
static bool busy_wait(struct disk* hd) {
    struct ide_channel* channel = hd->my_channel;
    uint16_t time_limit = 30 * 1000; // 最多等待 30 秒
    while (time_limit -= 10 >= 0) {
        if (!(inb(reg_status(channel)) & BIT_ALT_STAT_BSY)) {
            return (inb(reg_status(channel)) & BIT_ALT_STAT_DRQ);
        } else {
            mtime_sleep(10); // 睡眠 10ms 后继续等待
        }
    }
    return false;
}

/* 从硬盘读取 sec_cnt 个扇区到 buf */
void ide_read(struct disk* hd, uint32_t lba, void* buf, uint32_t sec_cnt) {
    ASSERT(lba <= max_lba);
    ASSERT(sec_cnt > 0);
    lock_acquire(&hd->my_channel->lock); // 获取通道锁

    /* 选择操作的硬盘 */
    select_disk(hd);

    uint32_t secs_op;   // 每次操作的扇区数
    uint32_t secs_done = 0; // 已经读入的扇区
    while( secs_done < sec_cnt ) {
        /* 由于一次读写扇区数不能超过 256 个,故在此循环 */
        if ((secs_done + 256) <= sec_cnt) {
            secs_op = 256;
        } else {
            secs_op = sec_cnt - secs_done;
        }

        /* 写入待读取的扇区数和起始扇区号 */
        select_sector(hd, lba + secs_done, (uint8_t)secs_op);

        /* 向硬盘发出读命令 */
        cmd_out(hd->my_channel, CMD_READ_SECTOR);

        /* 等待硬盘准备好 */
        sema_down(&hd->my_channel->disk_done);

        /* 检测硬盘状态是否可读 */
        if (!busy_wait(hd)) {
            char error[64];
            sprintf(error, "%s read sector %d failed!!!\n", hd->name, lba);
            PANIC(error);
        }

        /* 从硬盘读取数据 */
        read_from_sector(hd, (void*)((uint32_t)buf + secs_done * 512), (uint8_t)secs_op);

        secs_done += secs_op; // 累计已读入的扇区数
    }
    lock_release(&hd->my_channel->lock); // 释放通道锁
}

/* 将 buf 中的 sec_cnt 个扇区数据写入硬盘 */
void ide_write(struct disk* hd, uint32_t lba, void* buf, uint32_t sec_cnt) {
    ASSERT(lba <= max_lba);
    ASSERT(sec_cnt > 0);
    lock_acquire(&hd->my_channel->lock); // 获取通道锁

    /* 选择操作的硬盘 */
    select_disk(hd);

    uint32_t secs_op;   // 每次操作的扇区数
    uint32_t secs_done = 0; // 已经写入的扇区
    while( secs_done < sec_cnt ) {
        /* 由于一次读写扇区数不能超过 256 个,故在此循环 */
        if ((secs_done + 256) <= sec_cnt) {
            secs_op = 256;
        } else {
            secs_op = sec_cnt - secs_done;
        }

        /* 写入待读取的扇区数和起始扇区号 */
        select_sector(hd, lba + secs_done, (uint8_t)secs_op);

        /* 向硬盘发出写命令 */
        cmd_out(hd->my_channel, CMD_WRITE_SECTOR);

        /* 检测硬盘状态是否可写 */
        if (!busy_wait(hd)) {
            char error[64];
            sprintf(error, "%s write sector %d failed!!!\n", hd->name, lba);
            PANIC(error);
        }

        /* 将数据写入硬盘 */
        write2sector(hd, (const void*)((uint32_t)buf + secs_done * 512), (uint8_t)secs_op);
        
        /* 等待硬盘写入完毕 */
        sema_down(&hd->my_channel->disk_done);
        secs_done += secs_op; // 累计已写入的扇区数
    }
    lock_release(&hd->my_channel->lock); // 释放通道锁
}



/* 将 dst中len个相邻字节交换位置后存入 buf */
static void swap_pairs_bytes(const char* dst, char* buf, uint32_t len) {
    uint8_t idx;
    for (idx = 0; idx < len; idx += 2) {
        buf[idx + 1] = *dst++;
        buf[idx] = *dst++;
    }
    buf[idx] = '\0';
}

/* 获得硬盘参数信息 */
static void identify_disk(struct disk* hd) {
    char id_info[512];
    select_disk(hd); // 选择要操作的硬盘

    /* 向硬盘发送 identify 指令 */
    cmd_out(hd->my_channel, CMD_IDENTIFY);

    /* 等待硬盘驱动器准备好 */
    sema_down(&hd->my_channel->disk_done);

    /* 检测硬盘状态是否可读 */
    if (!busy_wait(hd)) {
        char error[64];
        sprintf(error, "%s identify failed!!!\n", hd->name);
        PANIC(error);
    }

    /* 读取硬盘参数信息 */
    read_from_sector(hd, id_info, 1);

    /* 读取硬盘型号 */
    char buf[64];
    uint8_t sn_start = 10*2, sn_len = 20, md_start = 27*2, md_len = 40;
    swap_pairs_bytes(&id_info[sn_start], buf, sn_len);
    printk("    disk %s info:\n      SN: %s\n", hd->name, buf);
    memset(buf, 0, sizeof(buf));
    swap_pairs_bytes(&id_info[md_start], buf, md_len);
    printk("      MODULE: %s\n", buf);
    uint32_t sectors = *((uint32_t*)&id_info[60*2]);
    printk("      SECTORS: %d\n", sectors);
    printk("      CAPACITY: %dMB\n", sectors * 512 / 1024 / 1024);
}

/* 扫描硬盘hd中地址为 ext_lba的扇区中的所有分区 */
static void partition_scan(struct disk* hd, uint32_t ext_lba) {
    struct boot_sector* bs = (struct boot_sector*)sys_malloc(sizeof(struct boot_sector));
    if (bs == NULL) {
        PANIC("ide.c: partition_scan: sys_malloc for boot_sector failed");
    }
    memset(bs, 0, sizeof(struct boot_sector));
    ide_read(hd, ext_lba, bs, 1); // 读取引导扇区到bs

    uint8_t part_idx = 0;
    struct partition_table_entry* p = &bs->partition_table[part_idx];

    /* 遍历 4 个分区表项 */
    while(part_idx++ < 4) {
        if (p->fs_type == 0x5) { // 该分区是扩展分区
            if (ext_lba_base != 0) {
                /* 扩展分区的起始lba地址 */
                partition_scan(hd, p->start_lba + ext_lba_base);
            } else {
                /* 第一次执行时，获取扩展分区的起始lba地址 */
                ext_lba_base = p->start_lba;
                partition_scan(hd, p->start_lba);
            }
        } else if (p->fs_type != 0) { // 如果是有效的分区类型
            if (ext_lba == 0) { // 主分区
                hd->prim_parts[p_no].start_lba = ext_lba + p->start_lba;
                hd->prim_parts[p_no].sec_cnt = p->sec_cnt;
                hd->prim_parts[p_no].my_disk = hd;
                list_append(&partition_list, &hd->prim_parts[p_no].part_tag);
                sprintf(hd->prim_parts[p_no].name, "%s%d", hd->name, p_no + 1);
                p_no++;
                ASSERT(p_no < 4);
            } else { // 逻辑分区
                hd->logic_parts[l_no].start_lba = ext_lba + p->start_lba;
                hd->logic_parts[l_no].sec_cnt = p->sec_cnt;
                hd->logic_parts[l_no].my_disk = hd;
                list_append(&partition_list, &hd->logic_parts[l_no].part_tag);
                sprintf(hd->logic_parts[l_no].name, "%s%d", hd->name, l_no + 5);
                l_no++;
                if (l_no >= 8) {
                    return;
                }
            }
        }
        p++; // 下一个分区表项
    }
    sys_free(bs);
}

/* 打印分区信息 */
static bool partition_info(struct list_elem* pelem, int arg UNUSED) {
   struct partition* part = elem2entry(struct partition, part_tag, pelem);
   printk("   %s start_lba:0x%x, sec_cnt:0x%x\n",part->name, part->start_lba, part->sec_cnt);

/* 在此处return false与函数本身功能无关,
 * 只是为了让主调函数list_traversal继续向下遍历元素 */
   return false;
}

/* 硬盘中断处理程序 */
void intr_hd_handler(uint8_t irq_no) {
    ASSERT(irq_no == 0x2e || irq_no == 0x2f);
    uint8_t ch_no = irq_no - 0x2e; // 计算是哪个通
    struct ide_channel* channel = &channels[ch_no];
    ASSERT(channel->irq_no == irq_no);
    /* 不用担心中断是否对应的是这一次的 expectiong_intr, 
    *  每次读写硬盘时会申请锁，从而保证同步一致性 */
    if (channel->expecting_intr) {
        channel->expecting_intr = false; // 关闭硬盘中断
        sema_up(&channel->disk_done);    // 唤醒阻塞在此信号量上的线程
        /* 读取状态寄存器以通知硬盘已经处理完中断 */
        inb(reg_status(channel));
    }
}


/* 硬盘数据结构初始化 */
void ide_init() {
   printk("ide_init start\n");
   uint8_t hd_cnt = *((uint8_t*)(0x475));	      // 获取硬盘的数量
   printk("   ide_init hd_cnt:%d\n",hd_cnt);
   ASSERT(hd_cnt > 0);
   list_init(&partition_list);
   channel_cnt = DIV_ROUND_UP(hd_cnt, 2);	   // 一个ide通道上有两个硬盘,根据硬盘数量反推有几个ide通道
   struct ide_channel* channel;
   uint8_t channel_no = 0, dev_no = 0; 

   /* 处理每个通道上的硬盘 */
   while (channel_no < channel_cnt) {
      channel = &channels[channel_no];
      sprintf(channel->name, "ide%d", channel_no);

      /* 为每个ide通道初始化端口基址及中断向量 */
      switch (channel_no) {
	 case 0:
	    channel->port_base	 = 0x1f0;	   // ide0通道的起始端口号是0x1f0
	    channel->irq_no	 = 0x20 + 14;	   // 从片8259a上倒数第二的中断引脚,温盘,也就是ide0通道的的中断向量号
	    break;
	 case 1:
	    channel->port_base	 = 0x170;	   // ide1通道的起始端口号是0x170
	    channel->irq_no	 = 0x20 + 15;	   // 从8259A上的最后一个中断引脚,我们用来响应ide1通道上的硬盘中断
	    break;
      }

      channel->expecting_intr = false;		   // 未向硬盘写入指令时不期待硬盘的中断
      lock_init(&channel->lock);		     

   /* 初始化为0,目的是向硬盘控制器请求数据后,硬盘驱动sema_down此信号量会阻塞线程,
   直到硬盘完成后通过发中断,由中断处理程序将此信号量sema_up,唤醒线程. */
      sema_init(&channel->disk_done, 0);

      register_handler(channel->irq_no, intr_hd_handler);

      /* 分别获取两个硬盘的参数及分区信息 */
      while (dev_no < 2) {
	 struct disk* hd = &channel->devices[dev_no];
	 hd->my_channel = channel;
	 hd->dev_no = dev_no;
	 sprintf(hd->name, "sd%c", 'a' + channel_no * 2 + dev_no);
	 identify_disk(hd);	 // 获取硬盘参数
	 if (dev_no != 0) {	 // 内核本身的裸硬盘(hd60M.img)不处理
	    partition_scan(hd, 0);  // 扫描该硬盘上的分区  
	 }
	 p_no = 0, l_no = 0;
	 dev_no++; 
      }
      dev_no = 0;			  	   // 将硬盘驱动器号置0,为下一个channel的两个硬盘初始化。
      channel_no++;				   // 下一个channel
   }

   printk("\n   all partition info\n");
   /* 打印所有分区信息 */
   list_traversal(&partition_list, partition_info, (int)NULL);
   printk("ide_init done\n");
}