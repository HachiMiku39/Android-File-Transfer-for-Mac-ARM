#ifndef AFT_BRIDGE_H
#define AFT_BRIDGE_H
#include <stdint.h>
#include <stddef.h>
typedef void AFTSession;
typedef int (*AFTProgress)(uint64_t, uint64_t, const void *);
typedef void (*AFTDeviceVisitor)(int, const char *, uint32_t, uint8_t, int, void *);
typedef void (*AFTStorageVisitor)(uint32_t, const char *, uint64_t, uint64_t, void *);
typedef void (*AFTFileVisitor)(uint32_t, const char *, uint64_t, int, void *);
void aft_init(void);
int aft_devices(AFTDeviceVisitor visitor, void *context);
AFTSession *aft_open(uint32_t bus, uint8_t address);
void aft_close(AFTSession *session);
const char *aft_error(AFTSession *session);
int aft_storages(AFTSession *session, AFTStorageVisitor visitor, void *context);
int aft_list(AFTSession *session, uint32_t storage, uint32_t parent, AFTFileVisitor visitor, void *context);
int aft_download(AFTSession *, uint32_t id, const char *path, AFTProgress, const void *);
int aft_upload(AFTSession *, uint32_t storage, uint32_t parent, const char *path, const char *name, AFTProgress, const void *);
uint32_t aft_mkdir(AFTSession *, uint32_t storage, uint32_t parent, const char *name);
int aft_delete(AFTSession *, uint32_t id);
#endif
