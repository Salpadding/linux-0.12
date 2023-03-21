# 1 "boot/head.S"
# 1 "<built-in>"
# 1 "<command-line>"
# 1 "boot/head.S"
# 21 "boot/head.S"
.text
.globl idt, gdt, pg_dir, tmp_floppy_area

pg_dir:

# head.s主要做了四件事：
# 1. 将系统堆栈放置在stack_start指向的数据区（之后，该栈就被用作任务0和任务1共同使用的用户栈）
# 2. 重新加载了新的中断描述符表和全局段描述符表
# 3. 初始化页目录表和4个内核专属的页表
# 4. 通过ret跳转到init/main.c中的main运行
# 1 "include/linux/head.h" 1
# 32 "boot/head.S" 2

.globl startup_32
startup_32:
    movl $0x10, %eax
    mov %ax, %ds
    mov %ax, %es
    mov %ax, %fs
    mov %ax, %gs

# 启用 higher half kernel
# 32MB = 页目录 作 identity mapping
# 33MB = ptes 每个pte
# 自映射页表 这样每个进程可以用同样的方式修改页表了
# 第n个页目录项的地址 = (1023L<<22)+(1023<<12) + 4*n
# 第n个页目录项的第m个页表项的地址= (1023L<<22)+ (n<<12) + 4*m
    movl $((((16)<<20)+4096*0)), %eax
    addl $(1023*4), %eax
    movl $((((16)<<20)+4096*0)+3), (%eax)

    mov $((((16)<<20)+4096*0)+1<<20), %eax # pte 指针
    mov $8192,%ecx
    mov $0, %edx # 物理地址

 .fill_table:
    mov %edx, %esi
    or $7, %esi
    mov %esi, (%eax)
    add $4096, %edx
    add $4,%eax
    loop .fill_table


    mov $1, %ecx
    mov $((((16)<<20)+4096*0)), %eax
    mov $((((16)<<20)+4096*0)+1<<20), %ebx # pte 指针

.fill_u_dirs:
    mov %ebx, %esi
    or $7, %esi
    mov %esi, (%eax)
    add $4096, %ebx
    add $4, %eax
    loop .fill_u_dirs

    mov $8, %ecx
    mov $((((16)<<20)+4096*0)), %eax
    add $(768*4),%eax
    mov $((((16)<<20)+4096*0)+1<<20), %ebx # pte 指针


.fill_sys_dirs:
    mov %ebx, %esi
    or $7, %esi # 为了方便调试 在execve 的时候mask掉
    mov %esi, (%eax)
    add $4096, %ebx
    add $4, %eax
    loop .fill_sys_dirs

    movl $((((16)<<20)+4096*0)), %eax
    movl %eax, %cr3
    # 设置启动使用分页处理(cr0的PG标志，位31)
    movl %cr0, %eax
    orl $0x80000000, %eax # 添上PG标志
    movl %eax, %cr0

    lss stack_start, %esp # 设置系统堆栈

    call setup_idt # 设置中断描述符表
    call setup_gdt # 设置全局描述符表

    # 因为修改了gdt（段描述符中的段限长8MB改成了16MB），所以需要重新装载所有的段寄存器。CS代码段寄存器
    # 已经在setup_gdt中重新加载过了。

    movl $0x10, %eax # reload all the segment registers
    mov %ax, %ds # after changing gdt. CS was already
    mov %ax, %es # reloaded in 'setup_gdt'
    mov %ax, %fs
    mov %ax, %gs
    lss stack_start, %esp

    # 下面代码用于测试A20地址线是否已经开启
    # 采用的方法是向内存地址0x000000处写入任意一个数值，然后看内存地址0x100000(1M)处是否也是这个数值。
    # 如果一直相同的话（表示地址A20线没有选通），就一直比较下去，即死循环。
    xorl %eax, %eax
1: incl %eax # check that A20 really IS enabled
    movl %eax, 0x000000 # loop forever if it isn't
    cmpl %eax, 0x100000
    je 1b
# 131 "boot/head.S"
 # 上面原注释中提到的486CPU中CR0控制器的位16是写保护标志WP，用于禁止超级用户级的程序向一般用户只读
 # 页面中进行写操作。该标志主要用于操作系统在创建新进程时实现写时复制方法。

 # 下面这段程序用于检查数学协处理器芯片是否存在
 # 方法是修改控制寄存器CR0，在假设存在协处理器的情况下执行一个协处理器指令，如果出错的话则说明协处理器
 # 芯片不存在，需要设置CR0中的协处理器仿真位EM(位2)，并复位协处理器存在标志MP(位1)。
    movl %cr0, %eax # check math chip
    andl $0x80000011, %eax # Save PG,PE,ET

    orl $2, %eax # set MP
    movl %eax, %cr0
    call check_x87
    jmp after_page_tables
# 152 "boot/head.S"
# fninit向协处理器发出初始化命令，它会把协处理器置于一个末受以前操作影响的已和状态，设置其控制字为默认值，
# 清除状态字和所有浮点栈式寄存器。非等待形式的这条指令(fninit)还会让协处理器终止执行当前正在执行的任何
# 先前的算术操作。
# fstsw指令取协处理器的状态字。
# 如果系统中存在协处理器的话，那么在执行了fninit指令后其状态字低字节肯定为0。

check_x87:
    fninit
    fstsw %ax
    cmpb $0, %al # 初始化状态字应该为0,否则说明协处理器不存在
    je 1f
    movl %cr0, %eax
    xorl $6, %eax
    movl %eax, %cr0
    ret

.align 4 # 按4字节方式对齐内存地址， 为了提高32位CPU访问内存中代码或数据的速度和效率
    # 两个字节值是80287协处理器指令fsetpm的机器码。其作用是把80287设置为保护模式。
    # 80387无需该指令，并且将会把该指令看作是空操作
1: .byte 0xDB,0xE4 # 287协处理器码
    ret
# 192 "boot/head.S"
setup_idt:
    lea ignore_int, %edx
    movl $0x00080000, %eax # 将选择符0x0008置入eax的高16位中
    movw %dx, %ax
    movw $0x8E00, %dx
                                # 此时edx含有门描述符高4字节的值

    lea idt, %edi # idt是中断描述符表的地址
    mov $256, %ecx
rp_sidt:
    movl %eax, (%edi) # 将哑中断门描述符存入表中
    movl %edx, 4(%edi)
    addl $8, %edi # edi指向表中下一项
    dec %ecx
    jne rp_sidt
    lidt idt_descr # 加载中断描述符表寄存器值
    ret
# 221 "boot/head.S"
# 加载全局描述符表寄存器(全局描述符表内容已设置好)
setup_gdt:
    lgdt gdt_descr
    ret
# 236 "boot/head.S"
 # 每个页表长为4KB字节(1页内存页面)
.org 0x1000 # 从偏移0x1000处开始存放第1个页表
pg0:

.org 0x2000
pg1:

.org 0x3000
pg2:

.org 0x4000
pg3:

.org 0x5000
# 260 "boot/head.S"
tmp_floppy_area:
    .fill 1024,1,0


# 前面3个入栈0值应该分别表示envp，argv指针和argc的值（main()没有用到）
# pushl $L6 压入返回地址
# pushl $main 压入main函数的入口地址
# 当head.s最后执行ret指令时就会弹出main()的地址
after_page_tables:
    pushl $0 # These are the parameters to main :-)
    pushl $0 # 这些是调用main程序的参数(指init/main.c).
    pushl $0
    pushl $L6 # return address for main, if it decides to.
    pushl $main
    jmp setup_paging # 跳转至setup_paging
L6:
    jmp L6 # main should never return here, but
                                    # just in case, we know what happens.
                                    # main程序绝对不应该返回到这里，不过为了以防万一，所以
                                    # 添加了该语句。这样我们就知道发生什么问题了。



int_msg:
    .asciz "Unknown interrupt\n\r"

.align 4
ignore_int:
    pushl %eax
    pushl %ecx
    pushl %edx
    push %ds
    push %es
    push %fs

    movl $0x10, %eax # 设置段选择符(使ds，es，fs指向gdt表中的数据段)
    mov %ax, %ds
    mov %ax, %es
    mov %ax, %fs
    pushl $int_msg
    call printk # 该函数在kernel/printk.c中
    popl %eax

    pop %fs
    pop %es
    pop %ds
    popl %edx
    popl %ecx
    popl %eax
    iret # 中断返回
# 345 "boot/head.S"
 # 上面英文注释第2段的含义是指在机器物理内存中大于1MB的内存空间主要被用于主内存区。主内存区空间
 # 由mm模块管理，它涉及页面映射操作。内核中所有其它函数就是这里指的"普通"函数。


# 初始化页目录表前4项和4个页表
.align 4
setup_paging:
    ret
    movl $1024 * 5, %ecx
    xorl %eax, %eax
    xorl %edi, %edi
                                        # 页目录从0x0000地址开始
    cld;rep;stosl # eax内容存到es:edi所指内存位置处,且edi增4.

     # 设置页目录表中的前4个页目录项
     # 例如第1个页目录项：
     # 页表所在地址 = 0x00001007 & 0xfffff000 = 0x1000
     # 页表属性标志 = 0x00001007 & 0x00000fff = 0x07 表示该页存在,用户可读写.
    movl $pg0 + 7, pg_dir
    movl $pg1 + 7, pg_dir + 4
    movl $pg2 + 7, pg_dir + 8
    movl $pg3 + 7, pg_dir + 12

    # 设置4个页表中所有项的内容（共4096项），从最后一个页表的最后一项开始按倒退顺序填写
    movl $pg3 + 4092, %edi # edi->最后一页的最后一项.
    movl $0xfff007, %eax
    std # 方向位置位，edi值递减(4字节)
1: stosl
    subl $0x1000, %eax # 每填好一项，物理地址值减0x1000。
    jge 1b # 如果小于0则说明全填写好了
    cld
    # 设置页目录表基地址寄存器cr3（保存页目录表的物理地址）
    xorl %eax, %eax
    movl %eax, %cr3
    # 设置启动使用分页处理(cr0的PG标志，位31)
    movl %cr0, %eax
    orl $0x80000000, %eax # 添上PG标志
    movl %eax, %cr0
    ret

# 在改变分页处理标志后要求使用转移指令刷新预取指令队列，这里用的是返回指令ret。
# 该返回指令ret的另一个作用并跳转到/init/main.c程序去运行。

.align 4

# 前2字节是描述符表的限长，后4字节是描述符表在线性地址空间中的32位基地址。
.word 0
idt_descr:
    .word 256 * 8 - 1 # idt contains 256 entries
    .long idt

.align 4 # 这个对齐貌似多余

.word 0
gdt_descr:
    .word 256 * 8 - 1 # so does gdt (not that that's any
    .long gdt # magic number, but it works for me :^)

.align 8
# 中断描述符表（空表）
idt: .fill 256, 8, 0 # idt is uninitialized

# 全局描述符表
# 前4项分别是空项(不用)、代码段描述符、数据段描述符、系统调用段描述符（没有使用）
# 同时还预留了252项的空间，用于放置所创建任务的局部描述符(LDT)和对应的任务状态段TSS的描述符
# (0-nul, 1-cs, 2-ds, 3-syscall, 4-TSS0, 5-LDT0, 6-TSS1, 7-LDT1, 8-TSS2 etc...)
gdt:
    .quad 0x0000000000000000
    .quad 0x00cf9a000000ffff
    .quad 0x00cf92000000ffff
    .quad 0x0000000000000000
    .quad 0x00cffa000000ffff
    .quad 0x00cff2000000ffff
    .fill 250, 8, 0
