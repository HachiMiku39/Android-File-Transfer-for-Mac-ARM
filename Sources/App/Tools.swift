import AppKit
import SwiftUI

final class ToolRunner: ObservableObject {
    @Published var output = ""
    @Published var running = false
    @Published var adbDevices: [ToolDevice] = []
    @Published var fastbootDevices: [ToolDevice] = []
    @Published var adbSerial = ""
    @Published var fastbootSerial = ""
    private var process: Process?
    static var directory: URL { Bundle.main.resourceURL!.appendingPathComponent("platform-tools") }
    static func executable(_ name: String) -> URL { directory.appendingPathComponent(name) }

    func run(_ name: String, _ args: [String], completion: ((String, Int32) -> Void)? = nil) {
        guard !running else { return }
        let p = Process(), pipe = Pipe()
        p.executableURL = Self.executable(name); p.arguments = args
        p.standardOutput = pipe; p.standardError = pipe
        // fastboot discovers filesystem helpers in the same directory.
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = Self.directory.path + ":/usr/bin:/bin:/usr/sbin:/sbin"
        p.environment = env
        output = "$ \(name) \(args.map(ArgumentParser.quote).joined(separator: " "))\n"
        do { try p.run() } catch { output += error.localizedDescription; return }
        process = p; running = true
        DispatchQueue.global(qos: .userInitiated).async {
            var captured = Data()
            while true {
                let data = pipe.fileHandleForReading.availableData
                if data.isEmpty { break }
                captured.append(data)
                if captured.count > 1_048_576 { captured.removeFirst(captured.count - 1_048_576) }
                let text = String(decoding: data, as: UTF8.self)
                DispatchQueue.main.async {
                    self.output += text
                    if self.output.count > 1_048_576 { self.output = String(self.output.suffix(1_048_576)) }
                }
            }
            p.waitUntilExit()
            let result = String(decoding: captured, as: UTF8.self), code = p.terminationStatus
            DispatchQueue.main.async {
                self.running = false; self.process = nil
                self.output += "\n[退出码 \(code)]\n"
                completion?(result, code)
            }
        }
    }
    func stop() { if let p = process, p.isRunning { p.terminate() } }
    func refresh() {
        run("adb", ["devices", "-l"]) { text, code in
            self.adbDevices = code == 0 ? ArgumentParser.devices(text, fastboot: false) : []
            if !self.adbDevices.contains(where: { $0.serial == self.adbSerial }) { self.adbSerial = self.adbDevices.first?.serial ?? "" }
            self.run("fastboot", ["devices"]) { text, code in
                self.fastbootDevices = code == 0 ? ArgumentParser.devices(text, fastboot: true) : []
                if !self.fastbootDevices.contains(where: { $0.serial == self.fastbootSerial }) { self.fastbootSerial = self.fastbootDevices.first?.serial ?? "" }
            }
        }
    }
    func interactiveShell() throws {
        guard !adbSerial.isEmpty else { throw CoreError.message("请先选择 ADB 设备。") }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("aft-shell-\(UUID().uuidString).command")
        let script = "#!/bin/zsh\n" + ArgumentParser.quote(Self.executable("adb").path) + " -s " + ArgumentParser.quote(adbSerial) + " shell\nrm -- " + ArgumentParser.quote(file.path) + "\n"
        try script.write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
        NSWorkspace.shared.open(file)
    }
}

struct ToolsView: View {
    @StateObject private var tools = ToolRunner()
    @ViewState private var shell = "getprop ro.product.model"
    @ViewState private var advanced = "getvar all"
    @ViewState private var useFastboot = true
    @ViewState private var partition = "boot"
    @ViewState private var image: URL?
    @ViewState private var error = ""
    @ViewState private var pending: (String, [String])?
    @ViewState private var confirmation = false
    private func request(_ name: String, _ args: [String]) {
        do {
            let serial = name == "adb" ? tools.adbSerial : tools.fastbootSerial
            pending = (name, try ArgumentParser.targeted(serial: serial, arguments: args))
            confirmation = true
        } catch { self.error = error.localizedDescription }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Android 工具").font(.title2.bold())
                Spacer()
                Button("刷新设备") { tools.refresh() }.disabled(tools.running)
                Button("停止命令") { tools.stop() }.disabled(!tools.running)
            }
            Text("内置官方 ADB / Fastboot 37.0.1 · 原生 arm64 · macOS 无需另装 ADB USB 驱动")
                .font(.callout).foregroundStyle(.secondary)
            GroupBox("ADB Shell") {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("设备", selection: $tools.adbSerial) {
                        Text("选择 ADB 设备").tag("")
                        ForEach(tools.adbDevices) { Text($0.label).tag($0.serial) }
                    }
                    Text("开启开发者选项 → USB 调试，并在手机上允许这台 Mac。unauthorized 表示尚未授权。")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        TextField("Android shell 命令", text: $shell)
                        Button("执行 Shell") { request("adb", ["shell", shell]) }.disabled(shell.isEmpty || tools.adbSerial.isEmpty)
                        Button("交互终端") { do { try tools.interactiveShell() } catch { self.error = error.localizedDescription } }
                            .disabled(tools.adbSerial.isEmpty)
                    }
                    HStack {
                        Button("重启系统") { request("adb", ["reboot"]) }
                        Button("进入 Recovery") { request("adb", ["reboot", "recovery"]) }
                        Button("进入 Bootloader") { request("adb", ["reboot", "bootloader"]) }
                        Button("进入 fastbootd") { request("adb", ["reboot", "fastboot"]) }
                    }.disabled(tools.adbSerial.isEmpty)
                }.padding(6)
            }.disabled(tools.running)
            GroupBox("Fastboot / 刷机") {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("设备", selection: $tools.fastbootSerial) {
                        Text("选择 Fastboot 设备").tag("")
                        ForEach(tools.fastbootDevices) { Text($0.label).tag($0.serial) }
                    }
                    HStack {
                        TextField("分区，例如 boot / init_boot", text: $partition).frame(width: 220)
                        Button("选择镜像…") {
                            let panel = NSOpenPanel(); panel.canChooseDirectories = false
                            if panel.runModal() == .OK { image = panel.url }
                        }
                        Text(image?.lastPathComponent ?? "未选择镜像").lineLimit(1)
                        Spacer()
                    }
                    HStack {
                        Button("读取设备信息") { request("fastboot", ["getvar", "all"]) }
                        Button("临时启动镜像") { if let image { request("fastboot", ["boot", image.path]) } }
                            .disabled(image == nil)
                        Button("刷入分区…") {
                            guard let image else { return }
                            guard !partition.isEmpty, partition.allSatisfy({ $0.isLetter || $0.isNumber || "_:-".contains($0) }), !partition.hasPrefix("-") else {
                                error = "请输入有效分区名。"; return
                            }
                            request("fastboot", ["flash", partition, image.path])
                        }.disabled(image == nil)
                        Button("重启系统") { request("fastboot", ["reboot"]) }
                    }.disabled(tools.fastbootSerial.isEmpty)
                    Text("刷入必须使用适配此机型的镜像；通常需已解锁 bootloader。解锁会清空数据，错误镜像可能导致无法启动。应用不会自动解锁或擦除设备。")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(6)
            }.disabled(tools.running)
            HStack {
                Picker("高级命令", selection: $useFastboot) { Text("fastboot").tag(true); Text("adb").tag(false) }.frame(width: 200)
                TextField("子命令，支持引号，例如 sideload '/path/update.zip'", text: $advanced)
                Button("执行…") {
                    do { request(useFastboot ? "fastboot" : "adb", try ArgumentParser.parse(advanced)) }
                    catch { self.error = error.localizedDescription }
                }.disabled(tools.running)
            }
            ScrollView {
                Text(tools.output.isEmpty ? "命令输出会显示在这里。" : tools.output)
                    .font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(10)
            }.background(Color(nsColor: .textBackgroundColor)).clipShape(RoundedRectangle(cornerRadius: 8))
        }.padding(20)
        .alert("确认执行设备命令", isPresented: $confirmation) {
            Button("取消", role: .cancel) { pending = nil }
            Button("执行", role: .destructive) { if let (name, args) = pending { tools.run(name, args) }; pending = nil }
        } message: {
            if let (name, args) = pending {
                Text("目标和完整命令：\n\(name) \(args.map(ArgumentParser.quote).joined(separator: " "))\n\n命令可能修改设备或清除数据。刷机前请确认机型、分区、镜像和备份。")
            }
        }
        .alert("无法执行", isPresented: Binding(get: { !error.isEmpty }, set: { if !$0 { error = "" } })) {
            Button("好") { error = "" }
        } message: { Text(error) }
    }
}
