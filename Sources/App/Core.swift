import Foundation

struct ToolDevice: Identifiable, Equatable {
    let serial: String
    let state: String
    let detail: String
    var id: String { serial }
    var label: String { "\(serial) · \(state) \(detail)" }
}

enum CoreError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let s) = self { return s }; return nil }
}

enum ArgumentParser {
    // Only tokenizes arguments. Never evaluates a host shell, substitutions or pipes.
    static func parse(_ text: String) throws -> [String] {
        var args: [String] = [], current = "", quote: Character?, escaped = false, active = false
        for c in text {
            if escaped { current.append(c); escaped = false; active = true; continue }
            if c == "\\" && quote != "'" { escaped = true; active = true; continue }
            if let q = quote {
                if c == q { quote = nil } else { current.append(c) }
                continue
            }
            if c == "\"" || c == "'" { quote = c; active = true }
            else if c.isWhitespace {
                if active { args.append(current); current = ""; active = false }
            } else { current.append(c); active = true }
        }
        guard quote == nil && !escaped else { throw CoreError.message("引号或转义未闭合。") }
        if active { args.append(current) }
        return args
    }
    static func quote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    static func devices(_ output: String, fastboot: Bool) -> [ToolDevice] {
        output.split(separator: "\n").compactMap { line in
            let parts = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            guard parts.count >= 2, !line.hasPrefix("List of devices"), !line.hasPrefix("*"),
                  ["device", "unauthorized", "offline", "recovery", "sideload", "bootloader", "fastboot"].contains(parts[1]) else { return nil }
            return ToolDevice(serial: parts[0], state: parts[1], detail: parts.dropFirst(2).joined(separator: " "))
        }
    }
    static func targeted(serial: String, arguments: [String]) throws -> [String] {
        guard !serial.isEmpty, !arguments.isEmpty else { throw CoreError.message("先选择目标设备并输入命令。") }
        // Keep advanced commands scoped to the selected device, including option=value forms.
        guard !arguments.contains(where: { $0.hasPrefix("-s") || $0.hasPrefix("--serial") || $0 == "-d" || $0 == "-e" || $0.hasPrefix("-t") || $0.hasPrefix("-H") || $0.hasPrefix("-P") || $0.hasPrefix("-L") || $0.hasPrefix("--transport-id") || $0 == "-a" }) else {
            throw CoreError.message("设备和服务器选项由应用管理，请只输入子命令。")
        }
        return ["-s", serial] + arguments
    }
    static func safeName(_ s: String) throws -> String {
        guard !s.isEmpty, s != ".", s != "..", !s.contains("/"), !s.contains("\0") else { throw CoreError.message("文件名无效。") }
        return s
    }
    static func usbLabel(_ speed: Int32) -> String {
        switch speed {
        case 4: return "USB 3 · SuperSpeed 5 Gbps"
        case 5, 6: return "USB 3 · SuperSpeed Plus ≥10 Gbps"
        case 3: return "USB 2 · High Speed 480 Mbps"
        case 2: return "USB · Full Speed 12 Mbps"
        case 1: return "USB · Low Speed 1.5 Mbps"
        default: return "USB 速度未知"
        }
    }
}
