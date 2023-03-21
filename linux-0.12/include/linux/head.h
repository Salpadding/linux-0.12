#ifndef _HEAD_H
#define _HEAD_H

#ifdef __ASSEMBLY__
#define _AC(X,Y) (X)
#else
#define _AC(X,Y) (X##Y)
#endif


#ifndef __ASSEMBLY__
/* 段描述符的数据结构。该结构仅说明每个描述符是由8个字节构成，每个描述符表共有256项。 */
typedef struct desc_struct {
	unsigned long a,b;
} desc_table[256];

extern unsigned long pg_dir[1024];	/* 内存页目录数组。每个目录项为4字节，从物理地址0开始 */
extern desc_table idt, gdt;		/* 中断描述符表，全局描述符表 */
typedef unsigned long pde;
typedef unsigned long pte;
#endif

#define GDT_NUL		0		/* 全局描述符表的第0项,不用 */
#define GDT_CODE	1		/* 第1项，内核代码段描述符项 */
#define GDT_DATA	2		/* 第2项，内核数据段描述符项 */
#define GDT_TMP		3		/* 第3项，系统段描述符(Linux没有使用) */

#define LDT_NUL		0		/* 每个局部描述符表的第0项，不用 */
#define LDT_CODE	1		/* 第1项，用户程序代码段描述符项 */
#define LDT_DATA	2		/* 第2项，用户程序数据段描述符项 */
#define PAGE_OFFSET _AC(0xC0000000,UL)
#define PAGE_RW_MASK (2UL)
#define PAGE_RW_UNMASK (~(PAGE_RW_MASK))
#define PAGE_MASK _AC(4095,UL)
#define PAGE_UNMASK (~(PAGE_MASK))
#define DEFAULT_TTY "/dev/ttyS0"

#define __va(x) (((void*)(x)) + PAGE_OFFSET)
#define __pa(x) (((void*)(x)) - PAGE_OFFSET)

#define loadsegment(seg,value)			\
	asm volatile("\n"			\
		"movw %0,%%" #seg "\n"		\
		: :"m" (*(unsigned short *)&(value)))


#define PD_OF(n) ((_AC(16,UL)<<20)+4096*n)
#define PDE_OF(n) (\
    (unsigned long*)(\
        (\
            (((unsigned long)(n)) >> 22 ) << 2  \
        ) | 0xfffff000UL \
    ) \
)
#define PTE_OF(n) ((unsigned long*)(\
    (\
        (\
            ((unsigned long)(n))>>10 \
            ) \
        &(_AC(0xffffffff,UL)<<2) \
    ) \
    + (_AC(1023,UL)<<22) \
))

#define __pa_of(x) ((*(PTE_OF(x)))&PAGE_UNMASK)

#define __asm_br(name) __asm__ __volatile__(".globl " #name "\n\t" #name ":\n\t")
#endif

