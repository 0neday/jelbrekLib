
#import "kernel_utils.h"
#import "patchfinder64.h"
#import "offsetof.h"
#import "offsets.h"
#import "kexecute.h"

mach_port_t tfpzero;

void init_kernel_utils(mach_port_t tfp0) {
    tfpzero = tfp0;
}

uint64_t Kernel_alloc(vm_size_t size) {
    mach_vm_address_t address = 0;
    mach_vm_allocate(tfpzero, (mach_vm_address_t *)&address, size, VM_FLAGS_ANYWHERE);
    return address;
}

void Kernel_free(mach_vm_address_t address, vm_size_t size) {
    mach_vm_deallocate(tfpzero, address, size);
}

uint64_t TaskSelfAddr() {
    
    uint64_t selfproc = proc_of_pid(getpid());
    if (selfproc == 0) {
        fprintf(stderr, "failed to find our task addr\n");
        exit(EXIT_FAILURE);
    }
    uint64_t addr = KernelRead_64bits(selfproc + off_task);
    
    uint64_t task_addr = addr;
    uint64_t itk_space = KernelRead_64bits(task_addr + off_itk_space);
    
    uint64_t is_table = KernelRead_64bits(itk_space + off_ipc_space_is_table);
    
    uint32_t port_index = mach_task_self() >> 8;
    const int sizeof_ipc_entry_t = 0x18;
    
    uint64_t port_addr = KernelRead_64bits(is_table + (port_index * sizeof_ipc_entry_t));
    
    return port_addr;
}

uint64_t IPCSpaceKernel() {
    return KernelRead_64bits(TaskSelfAddr() + 0x60);
}

uint64_t FindPortAddress(mach_port_name_t port) {
   
    uint64_t task_port_addr = TaskSelfAddr();
    //uint64_t task_addr = TaskSelfAddr();
    uint64_t task_addr = KernelRead_64bits(task_port_addr + off_ip_kobject);
    uint64_t itk_space = KernelRead_64bits(task_addr + off_itk_space);
    
    uint64_t is_table = KernelRead_64bits(itk_space + off_ipc_space_is_table);
    
    uint32_t port_index = port >> 8;
    const int sizeof_ipc_entry_t = 0x18;

    uint64_t port_addr = KernelRead_64bits(is_table + (port_index * sizeof_ipc_entry_t));

    return port_addr;
}

mach_port_t FakeHostPriv_port = MACH_PORT_NULL;

// build a fake host priv port
mach_port_t FakeHostPriv() {
    if (FakeHostPriv_port != MACH_PORT_NULL) {
        return FakeHostPriv_port;
    }
    // get the address of realhost:
    uint64_t hostport_addr = FindPortAddress(mach_host_self());
    uint64_t realhost = KernelRead_64bits(hostport_addr + off_ip_kobject);
    
    // allocate a port
    mach_port_t port = MACH_PORT_NULL;
    kern_return_t err;
    err = mach_port_allocate(mach_task_self(), MACH_PORT_RIGHT_RECEIVE, &port);
    if (err != KERN_SUCCESS) {
        printf("failed to allocate port\n");
        return MACH_PORT_NULL;
    }
    // get a send right
    mach_port_insert_right(mach_task_self(), port, port, MACH_MSG_TYPE_MAKE_SEND);
    
    // locate the port
    uint64_t port_addr = FindPortAddress(port);
    
    // change the type of the port
#define IKOT_HOST_PRIV 4
#define IO_ACTIVE   0x80000000
    KernelWrite_32bits(port_addr + 0, IO_ACTIVE|IKOT_HOST_PRIV);
    
    // change the space of the port
    KernelWrite_64bits(port_addr + 0x60, IPCSpaceKernel());
    
    // set the kobject
    KernelWrite_64bits(port_addr + off_ip_kobject, realhost);
    
    FakeHostPriv_port = port;
    
    return port;
}

uint64_t Kernel_alloc_wired(uint64_t size) {
    if (tfpzero == MACH_PORT_NULL) {
        printf("attempt to allocate kernel memory before any kernel memory write primitives available\n");
        sleep(3);
        return 0;
    }
    
    kern_return_t err;
    mach_vm_address_t addr = 0;
    mach_vm_size_t ksize = round_page_kernel(size);
    
    printf("vm_kernel_page_size: %lx\n", vm_kernel_page_size);
    
    err = mach_vm_allocate(tfpzero, &addr, ksize+0x4000, VM_FLAGS_ANYWHERE);
    if (err != KERN_SUCCESS) {
        printf("unable to allocate kernel memory via tfp0: %s %x\n", mach_error_string(err), err);
        sleep(3);
        return 0;
    }
    
    printf("allocated address: %llx\n", addr);
    
    addr += 0x3fff;
    addr &= ~0x3fffull;
    
    printf("address to wire: %llx\n", addr);
    
    err = mach_vm_wire(FakeHostPriv(), tfpzero, addr, ksize, VM_PROT_READ|VM_PROT_WRITE);
    if (err != KERN_SUCCESS) {
        printf("unable to wire kernel memory via tfp0: %s %x\n", mach_error_string(err), err);
        sleep(3);
        return 0;
    }
    return addr;
}


size_t KernelRead(uint64_t where, void *p, size_t size) {
    int rv;
    size_t offset = 0;
    while (offset < size) {
        mach_vm_size_t sz, chunk = 2048;
        if (chunk > size - offset) {
            chunk = size - offset;
        }
        rv = mach_vm_read_overwrite(tfpzero, where + offset, chunk, (mach_vm_address_t)p + offset, &sz);
        if (rv || sz == 0) {
            printf("[*] error on KernelRead(0x%016llx)\n", where);
            break;
        }
        offset += sz;
    }
    return offset;
}

uint32_t KernelRead_32bits(uint64_t where) {
    uint32_t out;
    KernelRead(where, &out, sizeof(uint32_t));
    return out;
}

uint64_t KernelRead_64bits(uint64_t where) {
    uint64_t out;
    KernelRead(where, &out, sizeof(uint64_t));
    return out;
}

size_t KernelWrite(uint64_t where, const void *p, size_t size) {
    int rv;
    size_t offset = 0;
    while (offset < size) {
        size_t chunk = 2048;
        if (chunk > size - offset) {
            chunk = size - offset;
        }
        rv = mach_vm_write(tfpzero, where + offset, (mach_vm_offset_t)p + offset, chunk);
        if (rv) {
            printf("[*] error on KernelWrite(0x%016llx)\n", where);
            break;
        }
        offset += chunk;
    }
    return offset;
}

void KernelWrite_32bits(uint64_t where, uint32_t what) {
    uint32_t _what = what;
    KernelWrite(where, &_what, sizeof(uint32_t));
}


void KernelWrite_64bits(uint64_t where, uint64_t what) {
    uint64_t _what = what;
    KernelWrite(where, &_what, sizeof(uint64_t));
}

const uint64_t kernel_address_space_base = 0xffff000000000000;
void Kernel_memcpy(uint64_t dest, uint64_t src, uint32_t length) {
    if (dest >= kernel_address_space_base) {
        // copy to kernel:
        KernelWrite(dest, (void*) src, length);
    } else {
        // copy from kernel
        KernelRead(src, (void*)dest, length);
    }
}

void convertPortToTaskPort(mach_port_t port, uint64_t space, uint64_t task_kaddr) {
    // now make the changes to the port object to make it a task port:
    uint64_t port_kaddr = FindPortAddress(port);
    
    KernelWrite_32bits(port_kaddr + koffset(KSTRUCT_OFFSET_IPC_PORT_IO_BITS), 0x80000000 | 2);
    KernelWrite_32bits(port_kaddr + koffset(KSTRUCT_OFFSET_IPC_PORT_IO_REFERENCES), 0xf00d);
    KernelWrite_32bits(port_kaddr + koffset(KSTRUCT_OFFSET_IPC_PORT_IP_SRIGHTS), 0xf00d);
    KernelWrite_64bits(port_kaddr + koffset(KSTRUCT_OFFSET_IPC_PORT_IP_RECEIVER), space);
    KernelWrite_64bits(port_kaddr + koffset(KSTRUCT_OFFSET_IPC_PORT_IP_KOBJECT),  task_kaddr);
    
    // swap our receive right for a send right:
    uint64_t task_port_addr = TaskSelfAddr();
    uint64_t task_addr = KernelRead_64bits(task_port_addr + koffset(KSTRUCT_OFFSET_IPC_PORT_IP_KOBJECT));
    uint64_t itk_space = KernelRead_64bits(task_addr + koffset(KSTRUCT_OFFSET_TASK_ITK_SPACE));
    uint64_t is_table = KernelRead_64bits(itk_space + koffset(KSTRUCT_OFFSET_IPC_SPACE_IS_TABLE));
    
    uint32_t port_index = port >> 8;
    const int sizeof_ipc_entry_t = 0x18;
    uint32_t bits = KernelRead_32bits(is_table + (port_index * sizeof_ipc_entry_t) + 8); // 8 = offset of ie_bits in struct ipc_entry
    
#define IE_BITS_SEND (1<<16)
#define IE_BITS_RECEIVE (1<<17)
    
    bits &= (~IE_BITS_RECEIVE);
    bits |= IE_BITS_SEND;
    
    KernelWrite_32bits(is_table + (port_index * sizeof_ipc_entry_t) + 8, bits);
}

void MakePortFakeTaskPort(mach_port_t port, uint64_t task_kaddr) {
    convertPortToTaskPort(port, IPCSpaceKernel(), task_kaddr);
}

uint64_t proc_of_pid(pid_t pid) {
    uint64_t proc = KernelRead_64bits(Find_allproc()), pd;
    while (proc) { //iterate over all processes till we find the one we're looking for
        pd = KernelRead_32bits(proc + off_p_pid);
        if (pd == pid) return proc;
        proc = KernelRead_64bits(proc);
    }
    
    return 0;
}
uint64_t proc_of_procName(char *nm) {
    uint64_t proc = KernelRead_64bits(Find_allproc());
    char name[40] = {0};
    while (proc) {
        KernelRead(proc + 0x268, name, 20); //read 20 bytes off the process's name and compare
        if (strstr(name, nm)) return proc;
        proc = KernelRead_64bits(proc);
    }
    return 0;
}


unsigned int pid_of_procName(char *nm) {
    uint64_t proc = KernelRead_64bits(Find_allproc());
    char name[40] = {0};
    while (proc) {
        KernelRead(proc + 0x268, name, 20);
        if (strstr(name, nm)) return KernelRead_32bits(proc + off_p_pid);
        proc = KernelRead_64bits(proc);
    }
    return 0;
}


uint64_t ZmFixAddr(uint64_t addr) {
    static kmap_hdr_t zm_hdr = {0, 0, 0, 0};
    
    if (zm_hdr.start == 0) {
        // xxx rk64(0) ?!
        uint64_t zone_map = KernelRead_64bits(Find_zone_map_ref());
        // hdr is at offset 0x10, mutexes at start
        size_t r = KernelRead(zone_map + 0x10, &zm_hdr, sizeof(zm_hdr));
        //printf("zm_range: 0x%llx - 0x%llx (read 0x%zx, exp 0x%zx)\n", zm_hdr.start, zm_hdr.end, r, sizeof(zm_hdr));
        
        if (r != sizeof(zm_hdr) || zm_hdr.start == 0 || zm_hdr.end == 0) {
            printf("KernelRead of zone_map failed!\n");
            exit(1);
        }
        
        if (zm_hdr.end - zm_hdr.start > 0x100000000) {
            printf("zone_map is too big, sorry.\n");
            exit(1);
        }
    }
    
    uint64_t zm_tmp = (zm_hdr.start & 0xffffffff00000000) | ((addr) & 0xffffffff);
    
    return zm_tmp < zm_hdr.start ? zm_tmp + 0x100000000 : zm_tmp;
}



