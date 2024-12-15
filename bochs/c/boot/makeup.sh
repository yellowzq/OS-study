#!/bin/sh
# 制作镜像
rm ../../sakura.img && ../../bin/bximage -hd -mode="flat" -size=60 -q ../../sakura.img

# 编译并写入mbr&loader
nasm -I include/ -o mbr.bin mbr.S
dd if=./mbr.bin of=../../sakura.img bs=512 count=1 conv=notrunc

# 编译并写入loader
nasm -I include -o loader.bin loader.S
dd if=./loader.bin of=../../sakura.img bs=512 count=4 seek=2 conv=notrunc

# 编译并写入kernel
#gcc -c -o ../kernel/main.o ../kernel/main.c &&
#ld ../kernel/main.o -Ttext 0xc0001500 -e main -o ../kernel/kernel.bin &&
#dd if=../kernel/kernel.bin of=../../sakura.img bs=512 count=200 seek=9 conv=notrunc