#!/bin/sh
rm sakura.img
../bin/bximage -hd -mode="flat" -size=60 -q ../sakura.img

nasm -I include/ -o mbr.bin mbr.S
dd if=./mbr.bin of=../sakura.img bs=512 count=1 conv=notrunc
nasm -I include -o loader.bin loader.S
dd if=./loader.bin of=../sakura.img bs=512 count=4 seek=2 conv=notrunc
