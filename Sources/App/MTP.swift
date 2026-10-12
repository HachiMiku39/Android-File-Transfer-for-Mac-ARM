import AppKit
import SwiftUI

struct MTPDevice: Identifiable {
    let name: String, bus: UInt32, address: UInt8, speed: Int32
    var id: String { "\(bus):\(address)" }
}
struct Storage: Identifiable { let id: UInt32, name: String, capacity: UInt64, free: UInt64 }
struct RemoteFile: Identifiable { let id: UInt32, name: String, size: UInt64, folder: Bool }
final class CollectionBox<T> { var items: [T] = [] }
final class TransferProgress {
    private let lock = NSLock()
    private var cancelled = false
    private var last = Date.distantPast
    private let began = Date()
    let update: (Double, String) -> Void
    init(update: @escaping (Double, String) -> Void) { self.update = update }
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func report(_ sent: UInt64, _ total: UInt64) -> Int32 {
        lock.lock(); defer { lock.unlock() }
        if cancelled { return 1 }
        let now = Date()
        if now.timeIntervalSince(last) >= 0.1 || sent == total {
            last = now
            let rate = Double(sent) / max(now.timeIntervalSince(began), 0.001) / 1_000_000
            let percent = total == 0 ? 0 : min(Double(sent) / Double(total), 1)
            let text = String(format: "%.1f MB/s · %@ / %@", rate,
                ByteCountFormatter.string(fromByteCount: Int64(clamping: sent), countStyle: .file),
                ByteCountFormatter.string(fromByteCount: Int64(clamping: total), countStyle: .file))
            DispatchQueue.main.async { self.update(percent, text) }
        }
        return 0
    }
}
private let progressCallback: AFTProgress = { sent, total, context in
    guard let context else { return 0 }
    return Unmanaged<TransferProgress>.fromOpaque(context).takeUnretainedValue().report(sent, total)
}

final class MTPModel: ObservableObject {
    @Published var devices: [MTPDevice] = []
    @Published var selectedDevice = ""
    @Published var storages: [Storage] = []
    @Published var selectedStorage: UInt32 = 0
    @Published var files: [RemoteFile] = []
    @Published var path: [(UInt32, String)] = []
    @Published var busy = false
    @Published var status = "连接手机，解锁并选择 USB 文件传输 (MTP)。"
    @Published var error = ""
    @Published var progress: Double = 0
    @Published var throughput = ""
    @Published var compatibility = false
    private let queue = DispatchQueue(label: "io.aft.mtp", qos: .userInitiated)
    private var session: UnsafeMutableRawPointer?
    private var transfer: TransferProgress?
    var folder: UInt32 { path.last?.0 ?? 0 }
    var connected: Bool { !storages.isEmpty }
    var link: String { devices.first(where: { $0.id == selectedDevice }).map { ArgumentParser.usbLabel($0.speed) } ?? "未连接" }
    init() { queue.async { aft_init() } }
    private func work(_ label: String, action: @escaping () throws -> Void, done: (() -> Void)? = nil) {
        guard !busy else { return }
        busy = true; status = label; progress = 0; throughput = ""
        queue.async {
            do {
                try action()
                DispatchQueue.main.async { self.busy = false; self.status = "完成"; self.transfer = nil; done?() }
            } catch {
                let text = error.localizedDescription
                DispatchQueue.main.async { self.busy = false; self.error = text; self.status = "操作未完成"; self.transfer = nil }
            }
        }
    }
    private func failure() -> CoreError { .message(String(cString: aft_error(session))) }
    func scan() {
        work("正在查找 MTP 设备…", action: {
            aft_close(self.session); self.session = nil
            let box = CollectionBox<MTPDevice>()
            let ptr = Unmanaged.passUnretained(box).toOpaque()
            let result = aft_devices({ _, name, bus, address, speed, ctx in
                let box = Unmanaged<CollectionBox<MTPDevice>>.fromOpaque(ctx!).takeUnretainedValue()
                box.items.append(MTPDevice(name: String(cString: name!), bus: bus, address: address, speed: speed))
            }, ptr)
            guard result >= 0 else { throw CoreError.message("USB 检测失败，请退出其他 MTP 应用并重连。") }
            let devices = box.items
            DispatchQueue.main.async {
                self.devices = devices; self.storages = []; self.files = []; self.path = []
                self.selectedStorage = 0
                self.selectedDevice = devices.first?.id ?? ""
            }
        }, done: { if !self.devices.isEmpty { self.connect() } else { self.status = "未找到设备。解锁手机、选择文件传输，再点击刷新设备。" } })
    }
    func connect() {
        guard let device = devices.first(where: { $0.id == selectedDevice }) else { return }
        let compat = compatibility
        storages = []; files = []; path = []; selectedStorage = 0
        work("正在打开 \(device.name)…", action: {
            aft_close(self.session); self.session = nil
            setenv("AFT_USB_COMPAT", compat ? "1" : "0", 1)
            self.session = aft_open(device.bus, device.address)
            guard self.session != nil else { throw self.failure() }
            let box = CollectionBox<Storage>()
            let ret = aft_storages(self.session, { id, name, capacity, free, ctx in
                Unmanaged<CollectionBox<Storage>>.fromOpaque(ctx!).takeUnretainedValue().items.append(
                    Storage(id: id, name: String(cString: name!), capacity: capacity, free: free))
            }, Unmanaged.passUnretained(box).toOpaque())
            guard ret == 0 else { throw self.failure() }
            guard !box.items.isEmpty else { throw CoreError.message("设备没有可访问的存储。请解锁并启用文件传输。") }
            let storage = box.items
            DispatchQueue.main.async { self.storages = storage; self.selectedStorage = storage[0].id; self.path = []; self.files = [] }
        }, done: { self.refresh() })
    }
    private func list(_ storage: UInt32, _ parent: UInt32) throws -> [RemoteFile] {
        let box = CollectionBox<RemoteFile>()
        let ret = aft_list(session, storage, parent, { id, name, size, folder, ctx in
            Unmanaged<CollectionBox<RemoteFile>>.fromOpaque(ctx!).takeUnretainedValue().items.append(
                RemoteFile(id: id, name: String(cString: name!), size: size, folder: folder != 0))
        }, Unmanaged.passUnretained(box).toOpaque())
        guard ret == 0 else { throw failure() }
        return box.items.sorted { $0.folder != $1.folder ? $0.folder : $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    func refresh() {
        guard selectedStorage != 0 else { return }
        let storage = selectedStorage, parent = folder
        work("正在读取目录…", action: {
            let files = try self.list(storage, parent)
            DispatchQueue.main.async { self.files = files }
        })
    }
    func enter(_ file: RemoteFile) { guard file.folder && !busy else { return }; path.append((file.id, file.name)); refresh() }
    func up() { guard !path.isEmpty && !busy else { return }; path.removeLast(); refresh() }
    func cancel() { transfer?.cancel() }
    func mkdir(_ name: String) {
        let storage = selectedStorage, parent = folder
        work("正在新建文件夹…", action: {
            let name = try ArgumentParser.safeName(name)
            guard !((try self.list(storage, parent)).contains { $0.name == name }) else { throw CoreError.message("已存在同名文件或目录。") }
            guard aft_mkdir(self.session, storage, parent, name) != 0 else { throw self.failure() }
        }, done: { self.refresh() })
    }
    func remove(_ file: RemoteFile) {
        work("正在删除 \(file.name)…", action: {
            guard aft_delete(self.session, file.id) == 0 else { throw self.failure() }
        }, done: { self.refresh() })
    }
    private func makeProgress() -> TransferProgress {
        let box = TransferProgress { self.progress = $0; self.throughput = $1 }
        DispatchQueue.main.async { self.transfer = box }
        return box
    }
    func upload(_ urls: [URL]) {
        let storage = selectedStorage, parent = folder
        work("正在上传 \(urls.count) 个项目…", action: {
            for url in urls { try self.uploadTree(url, storage: storage, parent: parent) }
        }, done: { self.refresh() })
    }
    private func uploadTree(_ url: URL, storage: UInt32, parent: UInt32) throws {
        let name = try ArgumentParser.safeName(url.lastPathComponent)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let type = attributes[.type] as? FileAttributeType
        guard type == .typeRegular || type == .typeDirectory else { throw CoreError.message("不上传符号链接或特殊文件：\(name)") }
        guard !((try list(storage, parent)).contains { $0.name == name }) else { throw CoreError.message("设备上已存在 \(name)。为避免覆盖，上传已停止，请重命名后再试。") }
        if type == .typeDirectory {
            let id = aft_mkdir(session, storage, parent, name)
            guard id != 0 else { throw failure() }
            for child in try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) {
                try uploadTree(child, storage: storage, parent: id)
            }
        } else {
            let box = makeProgress()
            let ret = aft_upload(session, storage, parent, url.path, name, progressCallback, Unmanaged.passUnretained(box).toOpaque())
            guard ret == 0 else { throw CoreError.message(box.isCancelled ? "上传已取消；设备上可能留有部分文件，请刷新检查。" : String(cString: aft_error(session))) }
        }
    }
    func download(_ file: RemoteFile, to directory: URL) {
        let storage = selectedStorage
        work("正在下载 \(file.name)…", action: { try self.downloadTree(file, storage: storage, directory: directory) })
    }
    private func downloadTree(_ file: RemoteFile, storage: UInt32, directory: URL) throws {
        let name = try ArgumentParser.safeName(file.name)
        let destination = directory.appendingPathComponent(name)
        guard !FileManager.default.fileExists(atPath: destination.path) else { throw CoreError.message("本地已存在 \(name)，请更换下载目录或重命名。") }
        if file.folder {
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
            for child in try list(storage, file.id) { try downloadTree(child, storage: storage, directory: destination) }
        } else {
            // Use an exclusive, private temporary directory; final files appear only on success.
            let tempDir = directory.appendingPathComponent(".aft-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            defer { try? FileManager.default.removeItem(at: tempDir) }
            let partial = tempDir.appendingPathComponent("download.partial")
            let box = makeProgress()
            guard aft_download(session, file.id, partial.path, progressCallback, Unmanaged.passUnretained(box).toOpaque()) == 0 else {
                throw CoreError.message(box.isCancelled ? "下载已取消。" : String(cString: aft_error(session)))
            }
            let size = (try FileManager.default.attributesOfItem(atPath: partial.path)[.size] as? NSNumber)?.uint64Value
            guard size == file.size else { throw CoreError.message("下载大小不一致，未保存最终文件。") }
            // moveItem fails if another process created destination during transfer.
            try FileManager.default.moveItem(at: partial, to: destination)
        }
    }
}

struct FilesView: View {
    @StateObject private var model = MTPModel()
    @ViewState private var selection: UInt32?
    @ViewState private var newFolder = ""
    @ViewState private var showFolder = false
    @ViewState private var deleting: RemoteFile?
    @ViewState private var confirmDelete = false
    private var selected: RemoteFile? { model.files.first { $0.id == selection } }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("USB 文件传输").font(.title2.bold())
                Spacer()
                Toggle("兼容模式（16 KiB）", isOn: $model.compatibility).toggleStyle(.checkbox)
                    .onChange(of: model.compatibility) { _ in if model.connected { model.connect() } }
                Button("刷新设备") { selection = nil; model.scan() }
            }.disabled(model.busy)
            HStack {
                Picker("手机", selection: $model.selectedDevice) {
                    Text("选择设备").tag("")
                    ForEach(model.devices) { Text("\($0.name) · \($0.id)").tag($0.id) }
                }.frame(maxWidth: 360).onChange(of: model.selectedDevice) { _ in
                    if !model.busy { selection = nil; model.connect() }
                }
                Button("连接") { model.connect() }.disabled(model.selectedDevice.isEmpty)
                Text(model.link).font(.callout).foregroundStyle(.secondary)
                Spacer()
            }.disabled(model.busy)
            HStack {
                Picker("存储", selection: $model.selectedStorage) {
                    Text("选择存储").tag(UInt32(0))
                    ForEach(model.storages) { Text($0.name).tag($0.id) }
                }.frame(width: 250)
                    .onChange(of: model.selectedStorage) { _ in model.path = []; selection = nil; if !model.busy { model.refresh() } }
                if let storage = model.storages.first(where: { $0.id == model.selectedStorage }) {
                    Text("可用 " + ByteCountFormatter.string(fromByteCount: Int64(clamping: storage.free), countStyle: .file)).foregroundStyle(.secondary)
                }
                Spacer()
            }.disabled(model.busy)
            HStack {
                Button { selection = nil; model.up() } label: { Label("上级目录", systemImage: "arrow.up") }.disabled(model.path.isEmpty)
                Text("/" + model.path.map { $0.1 }.joined(separator: "/")).lineLimit(1)
                Spacer()
                Button("打开文件夹") { if let selected { selection = nil; model.enter(selected) } }.disabled(selected?.folder != true)
                Button("刷新") { model.refresh() }
            }.disabled(model.busy || !model.connected)
            Table(model.files, selection: $selection) {
                TableColumn("名称") { file in
                    HStack { Image(systemName: file.folder ? "folder.fill" : "doc").foregroundStyle(file.folder ? .blue : .secondary); Text(file.name) }
                        .onTapGesture(count: 2) { model.enter(file) }
                }
                TableColumn("大小") { file in Text(file.folder ? "—" : ByteCountFormatter.string(fromByteCount: Int64(clamping: file.size), countStyle: .file)) }.width(150)
                TableColumn("类型") { file in Text(file.folder ? "文件夹" : "文件") }.width(90)
            }.disabled(model.busy)
            HStack {
                Button("上传文件 / 文件夹…") {
                    let panel = NSOpenPanel(); panel.canChooseFiles = true; panel.canChooseDirectories = true; panel.allowsMultipleSelection = true
                    if panel.runModal() == .OK { model.upload(panel.urls) }
                }
                Button("下载选中项目…") {
                    guard let selected else { return }
                    let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
                    if panel.runModal() == .OK, let url = panel.url { model.download(selected, to: url) }
                }.disabled(selected == nil)
                Button("新建文件夹…") { newFolder = ""; showFolder = true }
                Button("删除…", role: .destructive) { deleting = selected; confirmDelete = true }.disabled(selected == nil)
                Spacer()
            }.disabled(model.busy || !model.connected)
            HStack {
                Text(model.status).font(.callout)
                Spacer()
                if model.busy { ProgressView().controlSize(.small); Button("取消传输") { model.cancel() } }
            }
            if !model.throughput.isEmpty { ProgressView(value: model.progress); Text(model.throughput).font(.system(.callout, design: .monospaced)) }
            Text("USB 3 需要手机、数据线和端口均支持 SuperSpeed。协商速度不等于文件传输速度；文件传输不需要 USB 调试。")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(20)
        .alert("MTP 操作未完成", isPresented: Binding(get: { !model.error.isEmpty }, set: { if !$0 { model.error = "" } })) {
            Button("好") { model.error = "" }
        } message: { Text(model.error) }
        .alert("新建文件夹", isPresented: $showFolder) {
            TextField("文件夹名称", text: $newFolder)
            Button("取消", role: .cancel) {}
            Button("创建") { model.mkdir(newFolder) }
        }
        .alert("删除设备上的项目？", isPresented: $confirmDelete) {
            Button("取消", role: .cancel) { deleting = nil }
            Button("永久删除", role: .destructive) { if let deleting { model.remove(deleting) }; deleting = nil; selection = nil }
        } message: { Text("\(deleting?.name ?? "")\n删除可能包含文件夹内所有内容，无法通过废纸篓恢复。") }
    }
}
