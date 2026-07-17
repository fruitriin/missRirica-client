#!/usr/bin/env swift
/// clip-image.swift
///
/// PNG 画像の指定領域を切り出す。
/// annotate-grid で座標を確認した後、注目領域だけを切り出して LLM に渡す際に使う。
///
/// Usage:
///   clip-image <input-png> <output-png> --rect x y width height
///   clip-image <input-png> <output-png> --grid-cell col row N
///   clip-image <input-png> <output-png> --grid-range col1 row1 col2 row2 N
///
/// Exit codes: 0=成功, 1=引数不正/読み込み失敗/書き出し失敗

import CoreGraphics
import Foundation
import ImageIO

// MARK: - オプション

struct Options {
    var inputPath  = ""
    var outputPath = ""
    var rect:      (Int, Int, Int, Int)? = nil       // x, y, width, height
    var gridCell:  (Int, Int, Int)? = nil             // col, row, N
    var gridRange: (Int, Int, Int, Int, Int)? = nil   // col1, row1, col2, row2, N
}

func parseArgs() -> Options {
    var opts = Options()
    let args = Array(CommandLine.arguments.dropFirst())
    var positional: [String] = []

    var i = 0
    while i < args.count {
        switch args[i] {
        case "--rect":
            guard i + 4 < args.count,
                  let x = Int(args[i + 1]), let y = Int(args[i + 2]),
                  let w = Int(args[i + 3]), let h = Int(args[i + 4]) else {
                fputs("Error: --rect requires x y width height\n", stderr); exit(1)
            }
            guard x >= 0, y >= 0, w > 0, h > 0 else {
                fputs("Error: --rect x, y は >= 0、width, height は > 0 である必要があります\n", stderr)
                exit(1)
            }
            opts.rect = (x, y, w, h)
            i += 4
        case "--grid-cell":
            guard i + 3 < args.count,
                  let col = Int(args[i + 1]), let row = Int(args[i + 2]),
                  let n   = Int(args[i + 3]) else {
                fputs("Error: --grid-cell requires col row N\n", stderr); exit(1)
            }
            opts.gridCell = (col, row, n)
            i += 3
        case "--grid-range":
            guard i + 5 < args.count,
                  let col1 = Int(args[i + 1]), let row1 = Int(args[i + 2]),
                  let col2 = Int(args[i + 3]), let row2 = Int(args[i + 4]),
                  let n    = Int(args[i + 5]) else {
                fputs("Error: --grid-range requires col1 row1 col2 row2 N\n", stderr); exit(1)
            }
            opts.gridRange = (col1, row1, col2, row2, n)
            i += 5
        default:
            positional.append(args[i])
        }
        i += 1
    }

    guard positional.count == 2 else {
        fputs("Usage: clip-image <input-png> <output-png> --rect x y width height\n", stderr)
        fputs("       clip-image <input-png> <output-png> --grid-cell col row N\n", stderr)
        fputs("       clip-image <input-png> <output-png> --grid-range col1 row1 col2 row2 N\n", stderr)
        exit(1)
    }

    opts.inputPath  = positional[0]
    opts.outputPath = positional[1]

    guard opts.rect != nil || opts.gridCell != nil || opts.gridRange != nil else {
        fputs("Error: --rect, --grid-cell, --grid-range のいずれかが必要です\n", stderr)
        exit(1)
    }

    return opts
}

// MARK: - パストラバーサル防止（capture-window.swift L50-58 準拠）

func validatePath(_ path: String, label: String) {
    let resolved = URL(fileURLWithPath: path).standardized.path
    let cwd = FileManager.default.currentDirectoryPath
    guard resolved.hasPrefix(cwd + "/") || resolved == cwd else {
        fputs("Error: \(label) はワーキングディレクトリ配下でなければなりません (\(cwd))\n", stderr)
        fputs("  resolved: \(resolved)\n", stderr)
        exit(1)
    }
}

// MARK: - PNG 書き出し

func writePNG(image: CGImage, path: String) -> Bool {
    let url = URL(fileURLWithPath: path)
    let dir = url.deletingLastPathComponent()
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        fputs("Error: 書き出し先の作成に失敗しました '\(path)'\n", stderr)
        return false
    }

    CGImageDestinationAddImage(dest, image, nil)

    guard CGImageDestinationFinalize(dest) else {
        fputs("Error: PNG 書き出しに失敗しました '\(path)'\n", stderr)
        return false
    }

    return true
}

// MARK: - Main

let opts = parseArgs()
validatePath(opts.inputPath,  label: "入力パス")
validatePath(opts.outputPath, label: "出力パス")

// PNG 読み込み（ocr-region.swift 参照実装準拠）
guard let dataProvider = CGDataProvider(filename: opts.inputPath),
      let inputImage = CGImage(pngDataProviderSource: dataProvider,
                               decode: nil, shouldInterpolate: false,
                               intent: .defaultIntent) else {
    fputs("Error: 画像の読み込みに失敗しました '\(opts.inputPath)'\n", stderr)
    exit(1)
}

let imgW = inputImage.width
let imgH = inputImage.height

// クリップ矩形の計算
let clipX: Int
let clipY: Int
let clipW: Int
let clipH: Int

if let (x, y, w, h) = opts.rect {
    clipX = x
    clipY = y
    clipW = w
    clipH = h
} else if let (col, row, n) = opts.gridCell {
    guard n >= 1 else {
        fputs("Error: N は 1 以上が必要です\n", stderr); exit(1)
    }
    guard col >= 0, col < n else {
        fputs("Error: col (\(col)) は 0 以上 N (\(n)) 未満でなければなりません\n", stderr); exit(1)
    }
    guard row >= 0, row < n else {
        fputs("Error: row (\(row)) は 0 以上 N (\(n)) 未満でなければなりません\n", stderr); exit(1)
    }

    let cellW = imgW / n
    let cellH = imgH / n
    clipX = col * cellW
    clipY = row * cellH
    // 最終列・行は余りピクセルを吸収（整数除算の丸め誤差を補正）
    clipW = (col == n - 1) ? (imgW - col * cellW) : cellW
    clipH = (row == n - 1) ? (imgH - row * cellH) : cellH
} else if let (col1, row1, col2, row2, n) = opts.gridRange {
    guard n >= 1 else {
        fputs("Error: N は 1 以上が必要です\n", stderr); exit(1)
    }
    guard col1 >= 0, col1 < n, col2 >= 0, col2 < n else {
        fputs("Error: col1 (\(col1)), col2 (\(col2)) は 0 以上 N (\(n)) 未満でなければなりません\n", stderr); exit(1)
    }
    guard row1 >= 0, row1 < n, row2 >= 0, row2 < n else {
        fputs("Error: row1 (\(row1)), row2 (\(row2)) は 0 以上 N (\(n)) 未満でなければなりません\n", stderr); exit(1)
    }
    guard col1 <= col2, row1 <= row2 else {
        fputs("Error: col1 <= col2, row1 <= row2 でなければなりません\n", stderr); exit(1)
    }

    let cellW = imgW / n
    let cellH = imgH / n
    clipX = col1 * cellW
    clipY = row1 * cellH
    // 終端セルは余りピクセルを吸収
    clipW = (col2 == n - 1) ? (imgW - col1 * cellW) : ((col2 + 1) * cellW - col1 * cellW)
    clipH = (row2 == n - 1) ? (imgH - row1 * cellH) : ((row2 + 1) * cellH - row1 * cellH)
} else {
    fputs("Error: --rect, --grid-cell, --grid-range のいずれかが必要です\n", stderr)
    exit(1)
}

// クロップ矩形の範囲外チェック
guard clipX >= 0, clipY >= 0,
      clipX + clipW <= imgW, clipY + clipH <= imgH else {
    fputs("Error: クロップ矩形が画像サイズを超えています\n", stderr)
    fputs("  矩形: x=\(clipX) y=\(clipY) w=\(clipW) h=\(clipH)\n", stderr)
    fputs("  画像: \(imgW)x\(imgH)\n", stderr)
    exit(1)
}

// 矩形クロップ（ocr-region.swift L51-58 参照実装準拠）
let cropRect = CGRect(x: clipX, y: clipY, width: clipW, height: clipH)
guard let croppedImage = inputImage.cropping(to: cropRect) else {
    fputs("Error: 画像のクロップに失敗しました \(cropRect)\n", stderr)
    exit(1)
}

guard writePNG(image: croppedImage, path: opts.outputPath) else {
    exit(1)
}

print("Clipped: \(opts.outputPath) (\(croppedImage.width)x\(croppedImage.height)px)")
