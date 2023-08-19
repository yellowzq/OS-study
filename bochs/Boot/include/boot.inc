;@filename: boot.inc
;--------- loader 和 kernel ----------
LOADER_BASE_ADDR EQU 0X900          	;加载第2个段的地址
LOADER_START_SECTOR EQU 0X2         	;以LBA方式,loader存在第2个扇区,第一个是主引导扇区
