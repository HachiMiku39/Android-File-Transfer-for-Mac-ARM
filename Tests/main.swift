import Foundation
func expect(_ condition: @autoclosure () throws -> Bool, _ label: String) rethrows {
    guard try condition() else { fatalError("FAIL: " + label) }
}
func rejects(_ body: () throws -> Void) -> Bool { do { try body(); return false } catch { return true } }
try expect(try ArgumentParser.parse("flash boot '/tmp/my image.img'") == ["flash", "boot", "/tmp/my image.img"], "quoted paths")
try expect(try ArgumentParser.parse("shell \"echo hello\" ''") == ["shell", "echo hello", ""], "empty arguments")
try expect(try ArgumentParser.parse("shell '$(touch /tmp/nope); echo x'") == ["shell", "$(touch /tmp/nope); echo x"], "no host shell evaluation")
expect(rejects { _ = try ArgumentParser.parse("flash 'unterminated") }, "unclosed quote")
expect(rejects { _ = try ArgumentParser.targeted(serial: "", arguments: ["flash"]) }, "no implicit target")
expect(rejects { _ = try ArgumentParser.targeted(serial: "phone", arguments: ["--serial=other", "flash"]) }, "target override rejected")
try expect(try ArgumentParser.targeted(serial: "serial ' with spaces", arguments: ["shell", "id"]) == ["-s", "serial ' with spaces", "shell", "id"], "explicit target")
expect(ArgumentParser.quote("a'b") == "'a'\\''b'", "terminal escaping")
expect(rejects { _ = try ArgumentParser.safeName("../escape") }, "path traversal")
expect(rejects { _ = try ArgumentParser.safeName("..") }, "parent traversal")
expect(rejects { _ = try ArgumentParser.safeName("\0bad") }, "nul rejected")
try expect(try ArgumentParser.safeName("照片 你好.jpg") == "照片 你好.jpg", "unicode names")
let devices = ArgumentParser.devices("List of devices attached\nabc\tdevice product:p model:Pixel\ndef\tunauthorized\nxyz\toffline\n", fastboot: false)
expect(devices.count == 3 && devices[1].state == "unauthorized", "ADB states")
expect(ArgumentParser.devices("fbserial\tfastboot\n", fastboot: true).first?.serial == "fbserial", "fastboot devices")
expect(ArgumentParser.usbLabel(4).contains("5 Gbps"), "libusb SuperSpeed enum")
expect(ArgumentParser.usbLabel(3).contains("480 Mbps"), "libusb HighSpeed enum")
print("PASS: argument parsing, device targeting, path safety, USB speed labels")
