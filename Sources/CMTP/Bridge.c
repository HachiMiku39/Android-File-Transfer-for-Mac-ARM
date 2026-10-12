#include "Bridge.h"
#include <libmtp.h>
#include <libusb.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
void aft_init(void) { LIBMTP_Init(); }
static int speed(uint32_t bus, uint8_t address) {
  libusb_context *ctx = NULL;
  libusb_device **list = NULL;
  int result = 0;
  if (libusb_init(&ctx) != 0) return 0;
  ssize_t n = libusb_get_device_list(ctx, &list);
  for (ssize_t i = 0; i < n; ++i) {
    if (libusb_get_bus_number(list[i]) == bus && libusb_get_device_address(list[i]) == address)
      result = libusb_get_device_speed(list[i]);
  }
  if (list) libusb_free_device_list(list, 1);
  libusb_exit(ctx);
  return result;
}
int aft_devices(AFTDeviceVisitor visitor, void *context) {
  LIBMTP_raw_device_t *raw = NULL;
  int count = 0;
  LIBMTP_error_number_t e = LIBMTP_Detect_Raw_Devices(&raw, &count);
  if (e == LIBMTP_ERROR_NO_DEVICE_ATTACHED) return 0;
  if (e != LIBMTP_ERROR_NONE) { free(raw); return -1; }
  for (int i = 0; i < count; ++i)
    visitor(i, raw[i].device_entry.product ? raw[i].device_entry.product : "Android MTP",
      raw[i].bus_location, raw[i].devnum, speed(raw[i].bus_location, raw[i].devnum), context);
  free(raw);
  return count;
}
AFTSession *aft_open(uint32_t bus, uint8_t address) {
  LIBMTP_raw_device_t *raw = NULL;
  int count = 0;
  LIBMTP_mtpdevice_t *device = NULL;
  if (LIBMTP_Detect_Raw_Devices(&raw, &count) != LIBMTP_ERROR_NONE) { free(raw); return NULL; }
  for (int i = 0; i < count; ++i)
    if (raw[i].bus_location == bus && raw[i].devnum == address) {
      device = LIBMTP_Open_Raw_Device_Uncached(&raw[i]); break;
    }
  free(raw);
  return device;
}
void aft_close(AFTSession *s) { if (s) LIBMTP_Release_Device(s); }
const char *aft_error(AFTSession *s) {
  if (!s) return "无法打开设备。解锁手机、选择 USB 文件传输，并退出其他 MTP 应用。";
  LIBMTP_error_t *e = LIBMTP_Get_Errorstack(s);
  return e && e->error_text ? e->error_text : "MTP 操作失败，请重新连接设备。";
}
int aft_storages(AFTSession *s, AFTStorageVisitor visitor, void *ctx) {
  if (!s) return -1;
  LIBMTP_Clear_Errorstack(s);
  if (LIBMTP_Get_Storage(s, LIBMTP_STORAGE_SORTBY_NOTSORTED) != 0) return -1;
  for (LIBMTP_devicestorage_t *p = ((LIBMTP_mtpdevice_t *)s)->storage; p; p = p->next)
    visitor(p->id, p->StorageDescription ? p->StorageDescription : "Storage", p->MaxCapacity, p->FreeSpaceInBytes, ctx);
  return 0;
}
int aft_list(AFTSession *s, uint32_t storage, uint32_t parent, AFTFileVisitor visitor, void *ctx) {
  if (!s) return -1;
  LIBMTP_Clear_Errorstack(s);
  LIBMTP_file_t *files = LIBMTP_Get_Files_And_Folders(s, storage, parent ? parent : LIBMTP_FILES_AND_FOLDERS_ROOT);
  int failed = LIBMTP_Get_Errorstack(s) != NULL;
  while (files) {
    LIBMTP_file_t *next = files->next;
    visitor(files->item_id, files->filename ? files->filename : "", files->filesize,
      files->filetype == LIBMTP_FILETYPE_FOLDER, ctx);
    LIBMTP_destroy_file_t(files); files = next;
  }
  return failed ? -1 : 0;
}
int aft_download(AFTSession *s, uint32_t id, const char *path, AFTProgress cb, const void *ctx) {
  if (!s) return -1;
  LIBMTP_Clear_Errorstack(s);
  return LIBMTP_Get_File_To_File(s, id, path, cb, ctx);
}
int aft_upload(AFTSession *s, uint32_t storage, uint32_t parent, const char *path, const char *name, AFTProgress cb, const void *ctx) {
  struct stat st;
  if (!s || stat(path, &st) != 0 || !S_ISREG(st.st_mode)) return -1;
  LIBMTP_Clear_Errorstack(s);
  LIBMTP_file_t *f = LIBMTP_new_file_t();
  if (!f) return -1;
  f->filename = strdup(name); f->filesize = (uint64_t)st.st_size;
  f->storage_id = storage; f->parent_id = parent;
  f->filetype = LIBMTP_FILETYPE_UNKNOWN;
  int ret = LIBMTP_Send_File_From_File(s, path, f, cb, ctx);
  LIBMTP_destroy_file_t(f);
  return ret;
}
uint32_t aft_mkdir(AFTSession *s, uint32_t storage, uint32_t parent, const char *name) {
  if (!s) return 0;
  LIBMTP_Clear_Errorstack(s);
  char *copy = strdup(name);
  uint32_t id = LIBMTP_Create_Folder(s, copy, parent, storage);
  free(copy); return id;
}
int aft_delete(AFTSession *s, uint32_t id) {
  if (!s) return -1;
  LIBMTP_Clear_Errorstack(s);
  return LIBMTP_Delete_Object(s, id);
}
