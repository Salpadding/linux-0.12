#ifndef _SCHED_EXTRA_H
#define _SCHED_EXTRA_H

static inline struct task_struct * get_current(void)
{
	struct task_struct *cur;
	__asm__("andl %%esp,%0; ":"=r" (cur) : "0" (~4095UL));
	return cur;
 }


// 内核线程的esp可以看作线程的 mirror, esp 到哪线程就到哪儿
#define _switch_to(prev,next) do {					\
	asm volatile("\
                pushl %%esi\n\t"					\
		     "pushl %%edi\n\t"					\
		     "pushl %%ebp\n\t"					\
		     "movl %%esp,%0\n\t"	/* save ESP */		\
		     "movl %2,%%esp\n\t"	/* restore ESP */	\
		     "movl $1f,%1\n\t"		/* save EIP */		\
		     "pushl %3\n\t"		/* restore EIP */	\
		     "jmp __switch_to\n"				\
		     "1:\n\t"						\
		     "popl %%ebp\n\t"					\
		     "popl %%edi\n\t"					\
		     "popl %%esi\n\t"					\
		     :"=m" (prev->tss.esp),"=m" (prev->tss.eip)	\
		     :"m" (next->tss.esp),"m" (next->tss.eip),	\
		      "a" (prev), "d" (next),				\
		      "b" (prev));					\
} while (0)

extern void __attribute__((regparm(3))) __switch_to   (struct task_struct *prev_p, struct task_struct *next_p);


#define current get_current()
#endif
