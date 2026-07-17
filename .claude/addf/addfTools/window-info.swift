#!/usr/bin/env swift
/// window-info.swift
///
/// AXUIElement API を使って指定プロセスのウィンドウ属性を JSON 出力する。
///
/// Usage: window-info <process-name>
///        window-info --pid <pid>
/// Exit codes:
///   0 — 成功（JSON を stdout に出力）
///   1 — ウィンドウが見つからない、または引数不正

import ApplicationServices
import Foundation

// MARK: - GUI テスト有効チェック
do {
    let scriptDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().path
    let configPath = scriptDir + "/../Behavior.toml"
    if let contents = try? String(contentsOfFile: configPath, encoding: .utf8) {
        for line in contents.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("enable") && trimmed.contains("=") && trimmed.contains("false") {
                print("{\"disabled\": true, \"reason\": \"gui-test.enable = false in .claude/addf/Behavior.toml\"}")
                exit(0)
            }
        }
    }
}

// MARK: - 引数チェック

// --pid <pid> または <process-name>
let targetName: String?
let directPid: pid_t?

if CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--pid" {
    guard let p = pid_t(CommandLine.arguments[2]) else {
        fputs("Error: invalid PID '\(CommandLine.arguments[2])'\n", stderr)
        exit(1)
    }
    directPid = p
    targetName = nil
} else if CommandLine.arguments.count == 2 {
    targetName = CommandLine.arguments[1]
    directPid = nil
} else {
    fputs("Usage: window-info <process-name>\n", stderr)
    fputs("       window-info --pid <pid>\n", stderr)
    exit(1)
}

// MARK: - プロセス検索

/// 実行中プロセスから名前が一致するものを探す
func findPid(named name: String) -> pid_t? {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/bin/ps")
    task.arguments = ["-eo", "pid,comm"]

    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = Pipe()

    do {
        try task.run()
    } catch {
        return nil
    }
    task.waitUntilExit()

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    guard let output = String(data: data, encoding: .utf8) else { return nil }

    for line in output.split(separator: "\n") {
        let parts = line.trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 1)
        guard parts.count == 2 else { continue }
        let comm = parts[1].trimmingCharacters(in: .whitespaces)
        // comm は "/path/to/binary" の場合もあるので lastPathComponent で比較
        let basename = URL(fileURLWithPath: String(comm)).lastPathComponent
        if basename == name {
            if let pid = pid_t(parts[0]) {
                return pid
            }
        }
    }
    return nil
}

let pid: pid_t
if let dp = directPid {
    pid = dp
} else if let foundPid = findPid(named: targetName!) {
    pid = foundPid
} else {
    fputs("Error: process '\(targetName!)' not found\n", stderr)
    exit(1)
}

// MARK: - AXUIElement でウィンドウ属性取得

let app = AXUIElementCreateApplication(pid)

var windowsRef: CFTypeRef?
let result = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsRef)

guard result == .success,
      let windows = windowsRef as? [AXUIElement],
      let window = windows.first
else {
    fputs("Error: no windows found for '\(targetName ?? "pid:\(pid)")' (pid=\(pid))\n", stderr)
    exit(1)
}

// タイトル
var titleRef: CFTypeRef?
var title = ""
if AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef) == .success {
    title = (titleRef as? String) ?? ""
}

// 位置
var posRef: CFTypeRef?
var posX: Double = 0
var posY: Double = 0
if AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posRef) == .success,
   let posValue = posRef {
    var point = CGPoint.zero
    // swiftlint:disable:next force_cast
    AXValueGetValue(posValue as! AXValue, .cgPoint, &point)
    posX = Double(point.x)
    posY = Double(point.y)
}

// サイズ
var sizeRef: CFTypeRef?
var sizeW: Double = 0
var sizeH: Double = 0
if AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success,
   let sizeValue = sizeRef {
    var cgSize = CGSize.zero
    // swiftlint:disable:next force_cast
    AXValueGetValue(sizeValue as! AXValue, .cgSize, &cgSize)
    sizeW = Double(cgSize.width)
    sizeH = Double(cgSize.height)
}

// フォーカス状態（メインウィンドウか）
var focusedRef: CFTypeRef?
var focused = false
if AXUIElementCopyAttributeValue(window, kAXMainAttribute as CFString, &focusedRef) == .success {
    focused = (focusedRef as? Bool) ?? false
}

// MARK: - JSON 出力

let json: [String: Any] = [
    "title": title,
    "position": ["x": posX, "y": posY],
    "size": ["width": sizeW, "height": sizeH],
    "focused": focused,
    "pid": Int(pid),
]

let jsonData = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
print(String(data: jsonData, encoding: .utf8)!)
