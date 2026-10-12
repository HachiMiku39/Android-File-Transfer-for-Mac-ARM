"""Retain legacy device quirks; use larger bulk transfers on SuperSpeed links.

The unmodified upstream archives and this script are the corresponding source
for the LGPL libraries bundled by this project. Set AFT_USB_COMPAT=1 before
opening a session to restore upstream's 16 KiB bulk buffer.
"""
import pathlib
import sys

p = pathlib.Path(sys.argv[1])
s = p.read_text()
old = '#define CONTEXT_BLOCK_SIZE    (CONTEXT_BLOCK_SIZE_1+CONTEXT_BLOCK_SIZE_2)'
new = '''static unsigned long aft_bulk_block_size(PTP_USB *usb) {
  const char *compat = getenv("AFT_USB_COMPAT");
  uint16_t vendor = usb->rawdevice.device_entry.vendor_id;
  if ((compat && strcmp(compat, "1") == 0) || vendor == 0x4102 || vendor == 0x1006)
    return 0x4000;
  return libusb_get_device_speed(libusb_get_device(usb->handle)) >= LIBUSB_SPEED_SUPER
      ? 0x100000 : 0x4000;
}
#define CONTEXT_BLOCK_SIZE aft_bulk_block_size(ptp_usb)'''
if new in s:
    sys.exit(0)
assert s.count(old) == 1, 'Pinned libmtp source changed; review patch'
p.write_text(s.replace(old, new))
