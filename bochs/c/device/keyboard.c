#include "keyboard.h"
#include "print.h"
#include "interrupt.h"
#include "io.h"
#include "global.h"
#include "ioqueue.h"

#define KBD_BUF_PORT 0x60        //键盘缓冲区寄存器端口号

/* 用转义字符定义部分控制字符 */
#define esc   '\033'  // ESC键
#define backspace '\b'  // 退格键
#define tab   '\t'  // Tab键
#define enter '\r'  // Enter键
#define delete '\177'  // Delete键

/* 以下不可见字符一律定义为0 */
#define char_invisible 0  // 不可见字符
#define ctrl_l_char    char_invisible
#define ctrl_r_char    char_invisible
#define shift_l_char   char_invisible
#define shift_r_char   char_invisible
#define alt_l_char     char_invisible
#define alt_r_char     char_invisible
#define caps_lock_char char_invisible

/* 定义控制字符的通码和断码 */
#define shift_l_make 0x2A  // 左Shift键的按下码
#define shift_r_make 0x36  // 右Shift键的按下码
#define alt_l_make   0x38  // 左Alt键的按下码
#define alt_r_make   0xE038  // 右Alt键的按下
#define ctrl_l_make  0x1D  // 左Ctrl键的按下码
#define ctrl_r_make  0xE01D  // 右Ctrl键的按下码
#define ctrl_r_break 0xE09D  // 右Ctrl键的弹起码
#define caps_lock_make 0x3A  // Caps Lock键的按下码

struct ioqueue kbd_buf;  // 定义键盘缓冲区

/* 定义以下变量记录相应建是否按下的状态，
 * ext_scancode 用于记录makecode是否以0xe0开头 */
static bool ctrl_status = false, shift_status = false;
static bool alt_status = false, caps_lock_status = false;
static bool ext_scancode = false;

static bool shift_down_last;    // 记录上一次是否按下shift键
static bool caps_lock_last;     // 记录上一次是否开启caps lock

/* 以通码 make_code 为索引的二维数组 */
static char keymap[][2] = {
    /* 0x00 */ {0, 0}, 
    /* 0x01 */ {esc, esc},
    /* 0x02 */ {'1', '!'},
    /* 0x03 */ {'2', '@'},
    /* 0x04 */ {'3', '#'},
    /* 0x05 */ {'4', '$'},
    /* 0x06 */ {'5', '%'},
    /* 0x07 */ {'6', '^'},
    /* 0x08 */ {'7', '&'},
    /* 0x09 */ {'8', '*'},
    /* 0x0A */ {'9', '('},
    /* 0x0B */ {'0', ')'},
    /* 0x0C */ {'-', '_'},
    /* 0x0D */ {'=', '+'},
    /* 0x0E */ {backspace, backspace},
    /* 0x0F */ {tab, tab},
    /* 0x10 */ {'q', 'Q'},
    /* 0x11 */ {'w', 'W'},
    /* 0x12 */ {'e', 'E'},
    /* 0x13 */ {'r', 'R'},
    /* 0x14 */ {'t', 'T'},
    /* 0x15 */ {'y', 'Y'},
    /* 0x16 */ {'u', 'U'},
    /* 0x17 */ {'i', 'I'},
    /* 0x18 */ {'o', 'O'},
    /* 0x19 */ {'p', 'P'},
    /* 0x1A */ {'[', '{'},
    /* 0x1B */ {']', '}'},
    /* 0x1C */ {enter, enter},
    /* 0x1D */ {ctrl_l_char, ctrl_r_char},  // 左Ctrl和右Ctrl键
    /* 0x1E */ {'a', 'A'},
    /* 0x1F */ {'s', 'S'},
    /* 0x20 */ {'d', 'D'},
    /* 0x21 */ {'f', 'F'},
    /* 0x22 */ {'g', 'G'},
    /* 0x23 */ {'h', 'H'},
    /* 0x24 */ {'j', 'J'},
    /* 0x25 */ {'k', 'K'},
    /* 0x26 */ {'l', 'L'},
    /* 0x27 */ {';', ':'},
    /* 0x28 */ {'\'', '"'},
    /* 0x29 */ {'`', '~'},
    /* 0x2A */ {shift_l_char, shift_r_char},  // 左Shift和右Shift键
    /* 0x2B */ {'\\', '|'},
    /* 0x2C */ {'z', 'Z'},
    /* 0x2D */ {'x', 'X'},
    /* 0x2E */ {'c', 'C'},
    /* 0x2F */ {'v', 'V'},
    /* 0x30 */ {'b', 'B'},
    /* 0x31 */ {'n', 'N'},
    /* 0x32 */ {'m', 'M'},
    /* 0x33 */ {',', '<'},
    /* 0x34 */ {'.', '>'},
    /* 0x35 */ {'/', '?'},
    /* 0x36 */ {shift_l_char, shift_r_char},  // 左Shift和右Shift键
    /* 0x37 */ {'*', '*'},  //  // 右侧的*键
    /* 0x38 */ {alt_l_char, alt_r_char},  // 左Alt和右Alt键
    /* 0x39 */ {' ', ' '},  // 空格键
    /* 0x3A */ {caps_lock_char, caps_lock_char},  // Caps Lock键
    /* 其他按键暂不处理 */
};

/* 键盘中断处理程序 */
static void intr_keyboard_handler(void) {
    bool break_code;
    uint16_t scancode = inb(KBD_BUF_PORT);

    /* 若扫描码 scancode 是0xe0开头的，表示此键的按下将产生多个扫描码，
     * 所以马上结束此次中断处理函数，等待下一个扫描码进来 */
    if (scancode == 0xe0) {
        ext_scancode = true;
        return;
    }

    /* 如果上次是以0xe0开头的，将扫描码合并 */
    if (ext_scancode) {
        scancode = ((0xe000) | scancode);
        ext_scancode = false;   // 关闭e0标记
    }

    break_code = ((scancode & 0x0080) != 0);   // 获取break_code
    if (break_code) {   // 若是断码break_code(按键弹起时产生的扫描码)
        /* 由于ctrl_r和alt_r的make_code和break_code都是两字节,
         * 所以可用下面的方法取make_code,多字节的扫描码暂不处理 */
        uint16_t make_code = (scancode &= 0xff7f);   // 得到其make_code(按键按下时产生的扫描码)

        /* 若是任意以下三个键弹起了,将状态置为false */
        if (make_code == ctrl_l_make || make_code == ctrl_r_make) {
            ctrl_status = false;
        } else if (make_code == shift_l_make || make_code == shift_r_make) {
            shift_status = false;
        } else if (make_code == alt_l_make || make_code == alt_r_make) {
            alt_status = false;
        }   // caps_lock不是弹起后关闭,所以需要单独处理

        return;   // 直接返回结束此次中断处理程序
    }
    
    /* 若为通码，只处理数组中定义的键以及alt_right和ctrl_right */
    else if ((scancode > 0x00 && scancode < 0x3A) || \
             scancode == alt_r_make || \
             scancode == ctrl_r_make) {
        bool shift = shift_status;   // 判断是否与shift组合
        uint8_t index = (scancode &= 0x00ff);  // 将扫描码的高字节置0,主要是针对高字节是e0的扫描码.

        /* 先处理双字符键 */
        if ((scancode < 0x0e) || (scancode == 0x29) || \
            (scancode == 0x1a) || (scancode == 0x1b) || \
            (scancode == 0x2b) || (scancode == 0x27) || \
            (scancode == 0x28) || (scancode == 0x33) || \
            (scancode == 0x34) || (scancode == 0x35)) {
            if (shift) {  // 如果同时按下了shift键
                index = 1;
            } else {
                index = 0;
            }
        } else {  // 字母键
            if (shift ^ caps_lock_status) {  // 如果shift和caps_lock任一被按下
                index = 1;
            } else {  // 如果shift和caps_lock同时按下或同时没有按下
                index = 0;
            }
        }

        char cur_char = keymap[scancode][index];
        
        /* 只处理ASCII码不为0的键 */
        if (cur_char) {
            if(!ioq_full(&kbd_buf)) {  
                put_char(cur_char);
                ioq_putchar(&kbd_buf, cur_char);  // 将字符放入键盘缓冲区
            }
            return;
        }

        /* 记录本次是否按下了控制键 */
        if (scancode == ctrl_l_make || scancode == ctrl_r_make) {
            ctrl_status = true;
        } else if (scancode == shift_l_make || scancode == shift_r_make) {
            shift_status = true;
        } else if (scancode == alt_l_make || scancode == alt_r_make) {
            alt_status = true;
        } else if (scancode == caps_lock_make) {
            caps_lock_status = !caps_lock_status;
        }
    }
}

void keyboard_init(void) {
    put_str("keyboard_init start\n");
    ioqueue_init(&kbd_buf);  // 初始化键盘缓冲区
    register_handler(0x21, intr_keyboard_handler);  //注册键盘中断处理程序
    put_str("keyboard_init done\n");
}