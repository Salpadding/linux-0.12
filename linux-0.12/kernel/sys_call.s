# 1 "sys_call.S"
# 1 "<built-in>"
# 1 "<command-line>"
# 1 "sys_call.S"
# 58 "sys_call.S"
# 1 "../include/linux/head.h" 1
# 59 "sys_call.S" 2
SIG_CHLD = 17 # 定义SIG_CHLD信号（子进程停止或结束

EAX = 0x00 # 各寄存器的偏移
EBX = 0x04
ECX = 0x08
EDX = 0x0C
ORIG_EAX = 0x10
FS = 0x14
ES = 0x18
DS = 0x1C
EIP = 0x20
CS = 0x24
EFLAGS = 0x28
OLDESP = 0x2C
OLDSS = 0x30

state = 0 # these are offsets into the task-struct.
counter = 4
priority = 8
signal = 12
sigaction = 16 # MUST be 16 (=len of sigaction)
blocked = (33*16)

# offsets within sigaction
sa_handler = 0
sa_mask = 4
sa_flags = 8
sa_restorer = 12

nr_system_calls = 82

ENOSYS = 38





.globl system_call, sys_fork, timer_interrupt, sys_execve, system_call_2
.globl hd_interrupt, floppy_interrupt, parallel_interrupt
.globl device_not_available, coprocessor_error

.align 4
bad_sys_call:
 pushl $-ENOSYS
 jmp ret_from_sys_call
.align 4
reschedule:
 pushl $ret_from_sys_call
 jmp schedule
.align 4
system_call:
 push %ds
 push %es
 push %fs
 pushl %eax # save the orig_eax
 pushl %edx
 pushl %ecx # push %ebx,%ecx,%edx as parameters
 pushl %ebx # to the system call
 movl $0x10,%edx # set up ds,es to kernel space
 mov %dx,%ds
 mov %dx,%es

 mov %dx,%fs
 cmpl NR_syscalls,%eax
 jae bad_sys_call
 call *sys_call_table(,%eax,4)
 pushl %eax
2:
 movl %esp,%eax
    andl $((~((4095)))), %eax
 cmpl $0,state(%eax) # state
 jne reschedule
 cmpl $0,counter(%eax) # counter
 je reschedule
ret_from_sys_call:
 movl %esp,%eax
    andl $((~((4095)))), %eax
 cmpl task,%eax # task[0] cannot have signals
 je 3f
 cmpw $0x0f,CS(%esp) # was old code segment supervisor ?
 jne 3f
 cmpw $0x17,OLDSS(%esp) # was stack segment = 0x17 ?
 jne 3f
 movl signal(%eax),%ebx
 movl blocked(%eax),%ecx
 notl %ecx
 andl %ebx,%ecx
 bsfl %ecx,%ecx
 je 3f
 btrl %ecx,%ebx
 movl %ebx,signal(%eax)
 incl %ecx
 pushl %ecx
 call do_signal
 popl %ecx
 testl %eax, %eax
 jne 2b # see if we need to switch tasks, or do more signals
3: popl %eax
 popl %ebx
 popl %ecx
 popl %edx
 addl $4, %esp # skip orig_eax
 pop %fs
 pop %es
 pop %ds
 iret
system_call_2:
 popl %ebx
 popl %ecx
 popl %edx
 popl %eax # skip orig_eax
 pop %fs
 pop %es
 pop %ds
 iret

.align 4
coprocessor_error:
 push %ds
 push %es
 push %fs
 pushl $-1 # fill in -1 for orig_eax
 pushl %edx
 pushl %ecx
 pushl %ebx
 pushl %eax
 movl $0x10,%eax
 mov %ax,%ds
 mov %ax,%es
 movl $0x17,%eax
 mov %ax,%fs
 pushl $ret_from_sys_call
 jmp math_error

.align 4
device_not_available:
 push %ds
 push %es
 push %fs
 pushl $-1 # fill in -1 for orig_eax
 pushl %edx
 pushl %ecx
 pushl %ebx
 pushl %eax
 movl $0x10,%eax
 mov %ax,%ds
 mov %ax,%es
 movl $0x17,%eax
 mov %ax,%fs
 pushl $ret_from_sys_call
 clts # clear TS so that we can use math
 movl %cr0,%eax
 testl $0x4,%eax # EM (math emulation bit)
 je math_state_restore
 pushl %ebp
 pushl %esi
 pushl %edi
 pushl $0 # temporary storage for ORIG_EIP
 call math_emulate
 addl $4,%esp
 popl %edi
 popl %esi
 popl %ebp
 ret

.align 4
timer_interrupt:
 push %ds # save ds,es and put kernel data space
 push %es # into them. %fs is used by _system_call
 push %fs
 pushl $-1 # fill in -1 for orig_eax
 pushl %edx # we save %eax,%ecx,%edx as gcc doesn't
 pushl %ecx # save those across function calls. %ebx
 pushl %ebx # is saved as we use that in ret_sys_call
 pushl %eax
 movl $0x10,%eax
 mov %ax,%ds
 mov %ax,%es
 #movl $0x17,%eax
 mov %ax,%fs
 incl jiffies
 movb $0x20,%al # EOI to interrupt controller #1
 outb %al,$0x20
 movl CS(%esp),%eax
 andl $3,%eax # %eax is CPL (0 or 3, 0=supervisor)
 pushl %eax
 call do_timer # 'do_timer(long CPL)' does everything from
 addl $4,%esp # task switching to accounting ...
 jmp ret_from_sys_call

.align 4
sys_execve:
 lea EIP(%esp),%eax
 pushl %eax
 call do_execve
 addl $4,%esp
 ret

.align 4
sys_fork:
 call find_empty_process
 testl %eax,%eax
 js 1f
 push %gs
 pushl %esi
 pushl %edi
 pushl %ebp
 pushl %eax
 call copy_process
 addl $20,%esp
1: ret


hd_interrupt:
 pushl %eax
 pushl %ecx
 pushl %edx
 push %ds
 push %es
 push %fs
 movl $0x10,%eax
 mov %ax,%ds
 mov %ax,%es


 movb $0x20,%al
 outb %al,$0xA0 # EOI to interrupt controller #1
 jmp 1f # give port chance to breathe
1: jmp 1f
1: xorl %edx,%edx
 movl %edx,hd_timeout
 xchgl do_hd,%edx
 testl %edx,%edx
 jne 1f
 movl $unexpected_hd_interrupt,%edx
1: outb %al,$0x20
 call *%edx # "interesting" way of handling intr.
 pop %fs
 pop %es
 pop %ds
 popl %edx
 popl %ecx
 popl %eax
 iret

floppy_interrupt:
 pushl %eax
 pushl %ecx
 pushl %edx
 push %ds
 push %es
 push %fs
 movl $0x10,%eax
 mov %ax,%ds
 mov %ax,%es
 movl $0x17,%eax
 mov %ax,%fs
 movb $0x20,%al
 outb %al,$0x20 # EOI to interrupt controller #1
 xorl %eax,%eax
 xchgl do_floppy,%eax
 testl %eax,%eax
 jne 1f
 movl $unexpected_floppy_interrupt,%eax
1: call *%eax # "interesting" way of handling intr.
 pop %fs
 pop %es
 pop %ds
 popl %edx
 popl %ecx
 popl %eax
 iret

parallel_interrupt:
 pushl %eax
 movb $0x20,%al
 outb %al,$0x20
 popl %eax
 iret
