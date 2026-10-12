import AppKit
import SwiftUI

typealias ViewState<Value> = SwiftUI.State<Value>

@main
struct AndroidTransferApp: App {
    init() {
        if CommandLine.arguments.contains("--mtp-probe") {
            aft_init()
            let count = aft_devices({ _, _, _, _, _, _ in }, nil)
            print("MTP devices: \(count)")
            exit(count < 0 ? 1 : 0)
        }
    }
    var body: some Scene {
        WindowGroup("Android File Transfer ARM") {
            TabView {
                FilesView().tabItem { Label("文件传输", systemImage: "arrow.left.arrow.right") }
                ToolsView().tabItem { Label("ADB / Fastboot", systemImage: "terminal") }
                VStack(alignment: .leading, spacing: 16) {
                    Text("Android File Transfer for Mac ARM").font(.title.bold())
                    Text("0.1.0 Preview · Apple Silicon 原生应用 · macOS 13+")
                    Text("独立开源替代应用。基于 libmtp / libusb，附带 Google 官方 Android Platform Tools。与 Google 原版应用无隶属关系。")
                    Text("USB 3 大块传输路径尚需实机吞吐量与完整性验证。可切换兼容模式。macOS 28 尚未发布，因此未进行该系统的兼容性测试。")
                    Link("GitHub 源码和使用说明", destination: URL(string: "https://github.com/HachiMiku39/Android-File-Transfer-for-Mac-ARM")!)
                    Spacer()
                }.padding(30).tabItem { Label("关于", systemImage: "info.circle") }
            }.frame(minWidth: 980, minHeight: 700)
        }
        .commands { CommandGroup(replacing: .newItem) {} }
    }
}
