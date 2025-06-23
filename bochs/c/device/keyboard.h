#ifndef BOCHS_C_DEVICE_KEYBOARD_H
#define BOCHS_C_DEVICE_KEYBOARD_H

void keyboard_init(void);
extern struct ioqueue kbd_buf;  // 声明键盘缓冲区

#endif // BOCHS_C_DEVICE_KEYBOARD_H