/* Standalone AArch64/Linux benchmark. No libc, root, filesystem mount or device
 * access. Its only writable file is the exact existing 1 GiB AFT test file.
 * The measured path is Android's /sdcard FUSE filesystem, not raw UFS hardware. */
typedef unsigned long long U;
typedef long L;
static __attribute__((always_inline)) inline L sc(L n,L a,L b,L c,L d,L e,L f){
 register L x8 __asm__("x8")=n;register L x0 __asm__("x0")=a;
 register L x1 __asm__("x1")=b;register L x2 __asm__("x2")=c;
 register L x3 __asm__("x3")=d;register L x4 __asm__("x4")=e;register L x5 __asm__("x5")=f;
 __asm__ volatile("svc #0":"+r"(x0):"r"(x8),"r"(x1),"r"(x2),"r"(x3),"r"(x4),"r"(x5):"memory");return x0;
}
static U ns(void){L t[2];if(sc(113,1,(L)t,0,0,0,0)<0)return 0;return (U)t[0]*1000000000ULL+t[1];}
static void str(const char*s){L n=0;while(s[n])n++;sc(64,1,(L)s,n,0,0,0);}
static void num(U x){char b[32];L p=31;b[p]='\n';do{b[--p]='0'+x%10;x/=10;}while(x);sc(64,1,(L)(b+p),32-p,0,0,0);}
static void field(const char*s,U x){str(s);num(x);}
static U rnd(U*s){U x=*s;x^=x>>12;x^=x<<25;x^=x>>27;*s=x;return x*2685821657736338717ULL;}
static int bench(void){
 const char*path="/sdcard/Download/AFT-Test-20261017-2150/sequential-1GiB.bin";
 /* O_RDWR | O_DIRECT | O_CLOEXEC | O_NOFOLLOW. Never O_CREAT or O_TRUNC. */
 L open_flags=0x98002;
#ifdef AFT_SYNC_WRITE
 open_flags|=0x1000; /* O_DSYNC on AArch64: completion includes data sync. */
#endif
 L fd=sc(56,-100,(L)path,open_flags,0,0,0);
 if(fd<0){field("open_direct_errno=",(U)-fd);return 3;}
 L flags=sc(25,fd,3,0,0,0,0);
 if(flags<0||!(flags&0x10000)){str("O_DIRECT flag missing\n");return 3;}
 field("open_flags=",flags);
 unsigned char st[128];L r=sc(80,fd,(L)st,0,0,0,0);
 if(r<0||*(U*)(st+48)!=1073741824ULL||(*(unsigned int*)(st+16)&0170000)!=0100000){str("Wrong file size/type\n");return 4;}
 L mem=sc(222,0,1048576,3,0x22,-1,0);if((U)mem>(U)-4096){str("mmap failed\n");return 5;}
 U*buffer=(U*)mem;U seed=0x8abc0123deadbeefULL;
 for(U i=0;i<1048576/8;i++)buffer[i]=rnd(&seed);
 int first_mode=0;
#ifdef AFT_SYNC_WRITE
 first_mode=3;
#endif
 for(int mode=first_mode;mode<4;mode++){
  /* fsync and evict this file's cache only; no global cache drop or root. */
  if(sc(82,fd,0,0,0,0,0)<0){str("pretest fsync failed\n");return 7;}
  L advice=sc(223,fd,0,1073741824,4,0,0);
  field("fadvise_dontneed_errno=",advice<0?(U)-advice:0);
  U ops=0,bytes=0,block=mode<2?1048576:4096,offset=0,start=ns(),end;
  int write=mode&1;L syscall_number=write?68:67;seed=0x1234abcd9876ULL;
  for(;;){
   if(mode<2){if(ops==1024)break;offset=ops*block;}
   else {if(ops>=262144)break;if((ops&63)==0&&ns()-start>=30000000000ULL)break;offset=(rnd(&seed)%262144)*4096;}
   /* Update one aligned word, outside syscall, to avoid identical random writes. */
   if(write)buffer[0]=rnd(&seed);
   r=sc(syscall_number,fd,mem,block,offset,0,0);
   if(r!=(L)block){field("io_error=",r<0?(U)-r:999);sc(57,fd,0,0,0,0,0);return 6;}
   ops++;bytes+=block;
  }
  end=ns();U flush_start=end;
  if(write&&sc(82,fd,0,0,0,0,0)<0){str("fsync failed\n");return 7;}
  U flushed=ns();
  field("mode=",mode);field("bytes=",bytes);field("operations=",ops);
  field("elapsed_ns=",end-start);field("fsync_ns=",write?flushed-flush_start:0);
  field("elapsed_including_fsync_ns=",write?flushed-start:end-start);
 }
 sc(57,fd,0,0,0,0,0);return 0;
}
__attribute__((noreturn)) void _start(void){int result=bench();sc(93,result,0,0,0,0,0);for(;;){}}
