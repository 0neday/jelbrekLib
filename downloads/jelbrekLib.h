
extern uint32_t KASLR_Slide;
extern uint64_t KernelBase;
extern mach_port_t TFP0;

/*
 Purpose: Initialize jelbrekLib (first thing you have to call)
 Parameters:
    kernel task port (tfp0)
 Return values:
    1: tfp0 port not valid
    2: Something messed up while finding the kernel base
    3: patchfinder didn't initialize properly
    4: kernelSymbolFinder didn't initialize properly
 */
int init_jelbrek(mach_port_t tfpzero);

/*
 Purpose: Free memory used by jelbrekLib & clean up (last thing you have to call)
*/
void term_jelbrek(void);

/*
 Purpose:
    Add a macho binary on the AMFI trustcache
 Parameters:
    A path to single macho or a directory for recursive patching
 Return values:
    -1: path doesn't exist
    -2: Couldn't find valid macho in directory
     2: Binary not an executable
     3: Binary bigger than 0x4000 bytes or something weird happened when running lstat
     4: Permission denied when trying to open file
     5: Something weird happened when reading data from the file
     6: Binary is not a macho
     7: file mmap() failed
*/
int trustbin(const char *path);

/*
 Purpose:
    Unsandboxes a process
 Parameters:
    The process ID
 Return values:
    true: successfully unsandboxed or already unsandboxed
    false: something went wrong
 */
BOOL unsandbox(pid_t pid);

/*
 Purpose:
    Sets special codesigning flags on a process
 Parameters:
    The process ID
 Return values:
    true: successfully patched or already has flags
    false: something went wrong
 */
BOOL setcsflags(pid_t pid);

/*
 Purpose:
    Patches the UID & GID of a process to 0
 Parameters:
    The process ID
 Return values:
    true: successfully patched or already has root
    false: something went wrong
 */
BOOL rootify(pid_t pid);

/*
 Purpose:
    Sets TF_PLATFORM flag on a process & CS_PLATFORM_BINARY csflag
 Parameters:
    The process ID
 Return values:
    true: successfully patched or already has root
    false: something went wrong
 */
void platformize(pid_t pid);

/*
 Purpose:
    Patches entitlements stored on the AMFI slot of the credentials label (not the actual entitlements, so this doesn't work with every entitlement)
 Parameters:
    The process ID
    The entitlement (eg. com.apple.private.skip-library-validation)
    Entitlement value, either true or false
 Return values:
    true: successfully patched or already has entitlement
    false: something went wrong
 */
BOOL entitlePid(pid_t pid, const char *ent, BOOL val);

/*
 Purpose:
    Borrows credentials from another process ID
 Parameters:
    The target's process ID
    The donor's process ID
 Return values:
    Original credentials (use to revert later)
 */
uint64_t borrowCredsFromPid(pid_t target, pid_t donor);

/*
 Purpose:
    Spawns a binary and borrows credentials from it
 Parameters:
    The target's process ID
    The donor binary path & up to 6 arguments (Leave NULL if not using)
 Return values:
    Original credentials (use to revert later)
 */
uint64_t borrowCredsFromDonor(pid_t target, char *binary, char *arg1, char *arg2, char *arg3, char *arg4, char *arg5, char *arg6, char**env);

/*
 Purpose:
    Undoes crenetial dontaion
 Parameters:
    The target's process ID
    The original credentials
 */
void undoCredDonation(pid_t target, uint64_t origcred);

/*
 Purpose:
    Spawn a process as platform binary
 Parameters:
    Binary path
    Up to 6 arguments (Leave NULL if not using)
    environment variables (Leave NULL if not using)
 Return values:
    posix_spawn's return value
 */
int launchAsPlatform(char *binary, char *arg1, char *arg2, char *arg3, char *arg4, char *arg5, char *arg6, char**env);

/*
 Purpose:
    Spawn a process
 Parameters:
    Binary path
    Up to 6 arguments (Leave NULL if not using)
    environment variables (Leave NULL if not using)
 Return values:
    posix_spawn's'return value
 */
int launch(char *binary, char *arg1, char *arg2, char *arg3, char *arg4, char *arg5, char *arg6, char**env);

/*
 Purpose:
    Mount a device as read and write on a specified path
 Parameters:
    Device name
    Path to mount
 Return values:
    mount() return value
 */
int mountDevAtPathAsRW(const char* devpath, const char* path);

/*
 Purpose:
    Mount / as read and write on iOS 10.3-11.4b3
 Return values:
    0: mount succeeded
    -1: mount failed
 */
int remountRootFS(void);

/*
 Purpose:
    Get the kernel vnode pointer for a specified path
 Parameters:
    Target path
 Return values:
    Vnode pointer of path
 */
uint64_t getVnodeAtPath(const char *path);

/*
 Purpose:
    Do a hex dump I guess
 Parameters:
    Address in kernel from where to get data
    Size of data to get
 */
void HexDump(uint64_t addr, size_t size);

/*
 Purpose:
    Execute code within the kernel
 Parameters:
    Slid address of function
    Up to 7 arguments
 Return address:
    Return address of called function (must call ZmFixAddr before using returned pointers)
 */
uint64_t Kernel_Execute(uint64_t addr, uint64_t x0, uint64_t x1, uint64_t x2, uint64_t x3, uint64_t x4, uint64_t x5, uint64_t x6);
uint64_t ZmFixAddr(uint64_t addr);

/*
 Purpose:
    Find a kernel symbol
 Parameters:
    Name of symbol
    Whether to print info or not
 Return value:
    Address of kernel symbol
 */
uint64_t find_symbol(const char *symbol, bool verbose); //powered by kernelSymbolFinder ;)

/*
 Purpose:
    Remap tfp0 as host_special_port 4
 Return value:
    1: Error
    0: Success
*/
int setHGSP4(void);

/*
 Purpose:
    Unlock nvram memory
 */
void unlocknvram(void);

/*
 Purpose:
    Relock nvram memory. unlocknvmram() must have been used beforehand
 Return value:
    -1: Error
     0: Success
 */
int locknvram(void);

/*
 Purpose:
    Find kernel base
 Return value:
    Kernel base?
 */
uint64_t FindKernelBase(void);

/*
 Purpose:
     Internal vnode utilities
 */
int vnode_lookup(const char *path, int flags, uint64_t *vnode, uint64_t vfs_context);
uint64_t get_vfs_context(void);
int vnode_put(uint64_t vnode);

/*
 Purpose:
    Internal snapshot utilities
 */
int list_snapshots(const char *vol);
char *find_system_snapshot(void);
int do_rename(const char *vol, const char *snap, const char *nw);
char *copyBootHash(void);

/*
 Purpose:
    Patchfinding (by xerub & ninjaprawn)
 */
uint64_t Find_allproc(void);
uint64_t Find_add_x0_x0_0x40_ret(void);
uint64_t Find_copyout(void);
uint64_t Find_bzero(void);
uint64_t Find_bcopy(void);
uint64_t Find_rootvnode(void);
uint64_t Find_trustcache(void);
uint64_t Find_amficache(void);
uint64_t Find_OSBoolean_True(void);
uint64_t Find_OSBoolean_False(void);
uint64_t Find_zone_map_ref(void);
uint64_t Find_osunserializexml(void);
uint64_t Find_smalloc(void);

/*
 Purpose:
    Internal utilities
 */
uint64_t TaskSelfAddr(void);
uint64_t IPCSpaceKernel(void);
uint64_t FindPortAddress(mach_port_name_t port);
mach_port_t FakeHostPriv(void);
void convertPortToTaskPort(mach_port_t port, uint64_t space, uint64_t task_kaddr);
void MakePortFakeTaskPort(mach_port_t port, uint64_t task_kaddr);

/*
 Purpose:
    For reading & writing & copying & allocating & freeing kernel memory
 */
size_t KernelRead(uint64_t where, void *p, size_t size);
uint32_t KernelRead_32bits(uint64_t where);
uint64_t KernelRead_64bits(uint64_t where);

size_t kwrite(uint64_t where, const void *p, size_t size);
void KernelWrite_32bits(uint64_t where, uint32_t what);
void KernelWrite_64bits(uint64_t where, uint64_t what);
void Kernel_memcpy(uint64_t dest, uint64_t src, uint32_t length);

void Kernel_free(mach_vm_address_t address, vm_size_t size);
uint64_t Kernel_alloc(vm_size_t size);
uint64_t Kernel_alloc_wired(uint64_t size);

/*
 Purpose:
    Find proc struct on kernel
 Parameters:
    Process ID
 Return values:
    Kernel pointer to proc struct
 */
uint64_t proc_of_pid(pid_t pid);
/*
 Purpose:
    Find proc struct on kernel
 Parameters:
    Process name
 Return values:
    Kernel pointer to proc struct
 */
uint64_t proc_of_procName(char *nm);

/*
 Purpose:
    Find pid of process
 Parameters:
    Process name
 Return values:
    Process ID of process
 */
unsigned int pid_of_procName(char *nm);

/*
 Purpose:
    Inject dylib on process
 Parameters:
    Process ID
    Path to dylib
 Return values:
    -1: Error
     0: Success
 */
int inject_dylib(pid_t pid, char *loaded_dylib);
