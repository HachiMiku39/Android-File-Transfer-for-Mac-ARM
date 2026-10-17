#include "Bridge.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <time.h>
#include <sys/stat.h>
static uint32_t bus, storage, downloads, found; static uint8_t address; static int speed;
static uint64_t free_bytes;
static void dev(int i,const char*n,uint32_t b,uint8_t a,int sp,void*ctx){if(i==0){bus=b;address=a;speed=sp;}}
static void store(uint32_t id,const char*n,uint64_t cap,uint64_t free,void*ctx){if(!storage){storage=id;free_bytes=free;}}
static void root(uint32_t id,const char*n,uint64_t size,int folder,void*ctx){if(folder&&(!strcmp(n,"Download")||!strcmp(n,"Downloads")))downloads=id;}
static void findfile(uint32_t id,const char*n,uint64_t size,int folder,void*ctx){if(!folder&&!strcmp(n,(const char*)ctx))found=id;}
static double now(void){struct timespec t;clock_gettime(CLOCK_MONOTONIC,&t);return t.tv_sec+t.tv_nsec/1e9;}
static int progress(uint64_t n,uint64_t total,const void*ctx){static double last;double t=now();if(t-last>5||n==total){fprintf(stderr,"%s %.1f%%\n",(const char*)ctx,total?100.*n/total:0);last=t;}return 0;}
int main(int argc,char**argv){
 setbuf(stdout,NULL); if(argc!=4){fprintf(stderr,"usage: mtp-test INPUT OUTPUT TEST_FOLDER\n");return 2;}
 aft_init();int count=aft_devices(dev,NULL);printf("MTP_COUNT=%d USB_SPEED_ENUM=%d\n",count,speed);
 if(count!=1)return 3;
 AFTSession*s=aft_open(bus,address);if(!s){fprintf(stderr,"%s\n",aft_error(s));return 4;}
 int result=1;
 if(aft_storages(s,store,NULL)||!storage)goto done;
 if(free_bytes<((uint64_t)3<<30)){fprintf(stderr,"Insufficient free space\n");goto done;}
 if(aft_list(s,storage,0,root,NULL)||!downloads){fprintf(stderr,"Downloads not found\n");goto done;}
 uint32_t folder=aft_mkdir(s,storage,downloads,argv[3]);if(!folder)goto done;
 struct stat st;if(stat(argv[1],&st))goto done;
 const char*name="sequential-1GiB.bin";
 double t=now();int ret=aft_upload(s,storage,folder,argv[1],name,progress,"UPLOAD");double upload=now()-t;
 if(ret)goto done;
 if(aft_list(s,storage,folder,findfile,(void*)name)||!found)goto done;
 t=now();ret=aft_download(s,found,argv[2],progress,"DOWNLOAD");double download=now()-t;
 if(ret)goto done;
 printf("RESULT_JSON={\"bytes\":%lld,\"usb_speed_enum\":%d,\"upload_seconds\":%.6f,\"upload_MBps\":%.3f,\"download_seconds\":%.6f,\"download_MBps\":%.3f,\"remote_folder\":\"/sdcard/Download/%s\"}\n",(long long)st.st_size,speed,upload,st.st_size/upload/1e6,download,st.st_size/download/1e6,argv[3]);result=0;
 done: if(result)fprintf(stderr,"MTP_ERROR=%s\n",aft_error(s));aft_close(s);return result;
}
