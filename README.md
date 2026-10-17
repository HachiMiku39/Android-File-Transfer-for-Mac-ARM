# Android File Transfer for Mac ARM

原生 Apple Silicon Android USB 文件传输工具，集成 **ADB Shell / Fastboot**。
Native arm64 Android USB file transfer for macOS, with bundled ADB and Fastboot.

这是独立开源替代应用，不是 Google 旧版二进制的转换或官方更新；没有复用其
专有程序、图标或界面资源。Google 原版仅提供 Intel 程序，应用包本身不包含
可重新编译的完整源代码。

## 下载与安装

从 [Releases](https://github.com/HachiMiku39/Android-File-Transfer-for-Mac-ARM/releases)
下载 `Android-File-Transfer-Mac-ARM.zip`，解压后将 `.app` 拖入“应用程序”。

- Apple Silicon Mac，macOS 13 或更新版本；整个发布包的 Mach-O 程序均为 arm64。
- Preview 版本使用 ad-hoc 签名，尚未做 Developer ID 公证。若 macOS 拦截首次
  启动，请在“系统设置 → 隐私与安全性”确认来源后选择“仍要打开”。
- **macOS 28 尚未发布，未进行该系统的兼容性测试。** 原生 arm64 不依赖 Rosetta。
  [Apple 已说明普通 Rosetta 支持在 macOS 27 之后结束](https://support.apple.com/en-us/102527)。

## 文件传输

1. 用数据线连接手机，解锁手机并将 USB 用途设为“文件传输 / Android Auto”。
2. 退出旧版 Android File Transfer、OpenMTP 等其他 MTP 客户端及旧版后台 Agent。
3. 点击“刷新设备”，选择手机、存储和目录。
4. 上传或下载文件 / 文件夹；双击目录进入。支持新建文件夹、确认后删除、进度、
   平均 MB/s 和取消传输。文件大小采用 64 位，程序没有旧版的 4 GB 人为限制。

同名项目会停止并提示，不自动覆盖。下载先写入专用临时目录，核对字节数后
才保存最终文件；失败的临时下载会清理。递归操作不是事务，失败时已完成的
文件会保留；取消上传可能留下部分远端文件。符号链接和特殊文件不会被上传。

### USB 3

- 使用 libusb 原生 macOS USB bulk 传输，识别协商速度：High Speed / SuperSpeed /
  SuperSpeed Plus。支持 USB 3，不强制降到 USB 2。
- SuperSpeed 使用 **1 MiB** bulk 请求，减少旧版 libmtp 16 KiB 同步调用的开销。
  USB 2 和已知 iRiver 特例保留上游块大小。
- “兼容模式”恢复 16 KiB，切换时重开连接。遇到手机传输失败可启用它。
- **未声称达到 USB 3 标称速率。** 5 Gbps 是链路速率，不是文件吞吐量；手机 MTP
  服务、存储、USB 端口及线材都会限制速度。USB-C 外形不代表支持 USB 3。
- 已完成下述 Xiaomi 15 Ultra 的 1 GiB 实机吞吐量及 SHA-256 往返验证。
  大块路径仍为预览；其他机型、USB 2 对照及兼容模式吞吐量尚待验证。

### 实机测试（2026-10-17）

Xiaomi 15 Ultra（25019PNF3C），Android 16；经 USB 3 Hub，系统报告协商链路
**10 Gbps**。样本为 **1 GiB（1,073,741,824 字节）**，测试数据位于手机下载目录
的专用子目录。下表 MB/s 均采用十进制单位。

| 测试 | 结果 | 测量范围 |
|---|---:|---|
| USB MTP 上传：Mac → 手机 | **577.27 MB/s** | 单次 1 GiB，1.860 秒 |
| USB MTP 下载：手机 → Mac | **437.72 MB/s** | 单次 1 GiB，2.453 秒 |
| 手机内部顺序读取 | 631.77 MB/s | 1 MiB 块，下载目录文件系统 |
| 手机内部顺序写入 | 259.45 MB/s | 1 MiB 块，包含末尾 fsync |
| 手机内部 4 KiB 随机读取 | 944.95 MB/s，230,701 IOPS | Q1T1，**缓存影响无法排除** |
| 手机内部 4 KiB 随机同步写入 | **79.29 MB/s，19,359 IOPS** | Q1T1，O_DSYNC |

**校验通过：**原始文件、手机文件、下载副本的 SHA-256 完全一致。
应用内 ADB 刷新与 `adb shell getprop ro.product.model` 也已通过，返回型号
`25019PNF3C`，退出码 0。

MTP 数据来自使用发布版同一 C 桥接代码与动态库的测试程序，未覆盖 GUI 的全部
传输交互。这是单设备、单次短样本，不能外推到所有手机或长时间持续吞吐。
手机内部读写与 USB 传输分开测量；下载目录经过 Android emulated storage/FUSE，
即使调用者保留 O_DIRECT，也不能证明底层完全绕过缓存，**不将 4K 读取结果
作为 UFS 裸性能结论**。

[详细报告](docs/benchmarks/2026-10-17/android-device-test-report.txt) ·
[原始数值与计算结果](docs/benchmarks/2026-10-17/android-device-test-results.json) ·
[测量工具源码](docs/benchmarks/2026-10-17/phone-bench.c)

现场发现旧版 Google Android File Transfer 会独占 MTP；退出旧版主程序后传输
成功。libmtp 的设备库将此 USB ID 显示为 Mi-2s，实际机型由 USB/ADB 确认为
Xiaomi 15 Ultra。测试后手机曾回到仅 ADB 模式，此时需要重新选择文件传输才能
使用 MTP。刷机、解锁、擦除、重启均未测试。

## ADB Shell / Fastboot

附带 Google 官方 Android SDK Platform Tools **37.0.1**（arm64）。不需要用户
安装 Homebrew、Android Studio 或配置 PATH；包含 adb、fastboot 和原包的
文件系统辅助程序、配置、libc++ 与完整版权声明。

**macOS 通常不需要另装 ADB USB 驱动。** Windows 的 OEM USB 驱动不适用于
macOS（[Android 官方说明](https://developer.android.com/studio/run/device)）。ADB 必须在手机开启开发者选项 / USB 调试，并允许这台 Mac 的 RSA 授权。
MTP 文件传输本身不需要 USB 调试。

- 刷新显示 ADB 与 Fastboot 设备，包括 unauthorized / offline 状态。
- 单次 Shell 命令及在 macOS Terminal 中打开交互式 `adb shell`。
- 重启系统、Recovery、Bootloader、fastbootd。
- 选择镜像，临时 `fastboot boot` 或 `fastboot flash <partition> <image>`。
- 高级子命令支持引号，例如 `sideload '/path/update.zip'` 或
  `flashing unlock`。输入子命令即可，不要输入 adb/fastboot 程序名。
- 每次执行都用 `-s` 指定用户选择的设备，并显示完整命令供确认。
- 参数直接传给 Process，不通过 Mac shell 解释；ADB Shell 字符串在 Android
  设备上按 shell 语法解释。交互终端临时脚本对工具路径和序列号作单引号转义。
- 命令输出最多保留最近 1 MiB；停止命令会终止主机工具，但不能撤回已提交给
  手机的刷写或擦除操作。

刷机请使用准确适配机型和分区的镜像。解锁通常会清空数据；错误镜像可能
导致无法启动。应用提供工具，不提供自动识别固件适配或一键解锁流程。

## 从源码构建

需要 Apple Silicon macOS、Xcode Command Line Tools、Python 3、pkg-config。

```sh
xcode-select --install
brew install pkg-config
./scripts/build.sh
```

脚本下载固定版本的上游归档并检查 SHA-256；在 `.build/` 内构建动态链接的
libmtp / libusb，不改写系统库或 Google 旧版应用。

输出：`dist/Android File Transfer ARM.app`、`dist/Android-File-Transfer-Mac-ARM.zip`。
依赖缓存可用 `AFT_CACHE=/path/to/cache` 指定；离线构建需先准备三份脚本列出的归档。
脚本设置 macOS 13 deployment target；打包时验证全部可执行程序架构、动态库
路径、代码签名，执行命令参数安全测试和 MTP 无设备探测。

## 验证状态

| 项目 | 0.1.0 Preview |
|---|---|
| 本机 arm64 编译与启动 | macOS 27.2 开发版上通过 |
| 全部捆绑 Mach-O 均为 arm64 | 自动验证 |
| 内置 adb / fastboot 可运行并输出版本 | 自动验证 |
| 参数解析、设备绑定、路径穿越防护、USB 速度标签 | 自动验证 |
| MTP 检测无设备时正常返回 | 自动验证 |
| Xiaomi 15 Ultra 1 GiB MTP 后端上传 / 下载 | 2026-10-17 实机通过；未覆盖全部 GUI 交互 |
| USB 3 吞吐量与 SHA-256 往返一致性 | 单设备 1 GiB 样本通过，见上方结果 |
| ADB 授权、应用内设备刷新及 Shell 型号查询 | 2026-10-17 实机通过 |
| >4 GiB、拔线 / 取消、其他机型及 USB 2 / 兼容模式对照 | 待实机验证 |
| Fastboot 刷机、解锁、擦除和重启 | 按测试范围未执行 |
| macOS 28 | 尚未发布，待验证 |

实机测试建议：记录 Mac/系统、手机、线材和协商速度；分别用 USB 2、USB 3 与
兼容模式上传同一份 ≥1 GB 文件并下载到不同目录，对比 SHA-256 和耗时。
>4 GB 使用手机支持的存储；先备份，只在专用测试目录验证取消和删除。

## 许可与第三方源码

应用代码：MIT。动态库：LGPL-2.1 / LGPL-2.1-or-later；Platform Tools 保留
原包的完整 notices。详见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
发布附带上游库源码归档和构建脚本，可重新构建并替换动态库。

无统计上报、无自动更新网络请求。ADB 使用标准本机 adb server；应用退出
不会主动关闭可能被其他工具使用的 adb server。
