#!/usr/bin/env swift
/// annotate-grid.swift
///
/// PNG 画像にグリッドと座標ラベルを描画する。
/// LLM による画像判定の前処理として、注目領域の座標を確認するために使う。
///
/// Usage:
///   annotate-grid <input-png> <output-png> --divide N
///   annotate-grid <input-png> <output-png> --every N
///
/// Options:
///   --line-color  RRGGBBAA  グリッド線色 (default: FF000080)
///   --label-color RRGGBBAA  ラベル文字色 (default: FFFF00FF)
///   --label-bg    RRGGBBAA  ラベル背景色 (default: 00000080)
///   --font-size   N         フォントサイズ pt (default: 12)
///
/// Exit codes: 0=成功, 1=引数不正/読み込み失敗/書き出し失敗

import CoreGraphics
import CoreText
import Foundation
import ImageIO

// MARK: - カラー

struct RGBA {
    var r, g, b, a: CGFloat
}

func parseRGBA(_ hex: String) -> RGBA? {
    let h = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
    guard h.count == 8, h.allSatisfy({ $0.isHexDigit }),
          let val = UInt64(h, radix: 16) else { return nil }
    return RGBA(
        r: CGFloat((val >> 24) & 0xFF) / 255.0,
        g: CGFloat((val >> 16) & 0xFF) / 255.0,
        b: CGFloat((val >> 8) & 0xFF) / 255.0,
        a: CGFloat(val & 0xFF) / 255.0
    )
}

// MARK: - オプション

struct Options {
    var inputPath = ""
    var outputPath = ""
    var divideN: Int? = nil
    var everyN: Int? = nil
    var lineColor  = RGBA(r: 1.0, g: 0.0, b: 0.0, a: 0.502)  // FF000080
    var labelColor = RGBA(r: 1.0, g: 1.0, b: 0.0, a: 1.0)    // FFFF00FF
    var labelBg    = RGBA(r: 0.0, g: 0.0, b: 0.0, a: 0.502)  // 00000080
    var fontSize: CGFloat = 12
}

func parseArgs() -> Options {
    var opts = Options()
    let args = Array(CommandLine.arguments.dropFirst())
    var positional: [String] = []

    var i = 0
    while i < args.count {
        switch args[i] {
        case "--divide":
            i += 1
            guard i < args.count, let n = Int(args[i]) else {
                fputs("Error: --divide requires integer\n", stderr); exit(1)
            }
            guard n >= 1, n <= 65536 else {
                fputs("Error: N は 1..65536 の範囲で指定してください\n", stderr); exit(1)
            }
            opts.divideN = n
        case "--every":
            i += 1
            guard i < args.count, let n = Int(args[i]) else {
                fputs("Error: --every requires integer\n", stderr); exit(1)
            }
            guard n >= 1, n <= 65536 else {
                fputs("Error: N は 1..65536 の範囲で指定してください\n", stderr); exit(1)
            }
            opts.everyN = n
        case "--line-color":
            i += 1
            guard i < args.count, let c = parseRGBA(args[i]) else {
                fputs("Error: --line-color requires RRGGBBAA hex\n", stderr); exit(1)
            }
            opts.lineColor = c
        case "--label-color":
            i += 1
            guard i < args.count, let c = parseRGBA(args[i]) else {
                fputs("Error: --label-color requires RRGGBBAA hex\n", stderr); exit(1)
            }
            opts.labelColor = c
        case "--label-bg":
            i += 1
            guard i < args.count, let c = parseRGBA(args[i]) else {
                fputs("Error: --label-bg requires RRGGBBAA hex\n", stderr); exit(1)
            }
            opts.labelBg = c
        case "--font-size":
            i += 1
            guard i < args.count, let n = Double(args[i]) else {
                fputs("Error: --font-size requires number\n", stderr); exit(1)
            }
            opts.fontSize = CGFloat(n)
        default:
            positional.append(args[i])
        }
        i += 1
    }

    guard positional.count == 2 else {
        fputs("Usage: annotate-grid <input-png> <output-png> --divide N\n", stderr)
        fputs("       annotate-grid <input-png> <output-png> --every N\n", stderr)
        fputs("Options:\n", stderr)
        fputs("  --line-color  RRGGBBAA  グリッド線色 (default: FF000080)\n", stderr)
        fputs("  --label-color RRGGBBAA  ラベル文字色 (default: FFFF00FF)\n", stderr)
        fputs("  --label-bg    RRGGBBAA  ラベル背景色 (default: 00000080)\n", stderr)
        fputs("  --font-size   N         フォントサイズ pt (default: 12)\n", stderr)
        exit(1)
    }

    opts.inputPath  = positional[0]
    opts.outputPath = positional[1]

    guard opts.divideN != nil || opts.everyN != nil else {
        fputs("Error: --divide N または --every N が必要です\n", stderr)
        exit(1)
    }

    if let n = opts.divideN, n < 1 {
        fputs("Error: --divide は 1 以上が必要です\n", stderr); exit(1)
    }
    if let n = opts.everyN, n < 1 {
        fputs("Error: --every は 1 以上が必要です\n", stderr); exit(1)
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

// MARK: - ラベル描画

/// imageX, imageY: 画像座標系（左上原点、Y 下向き）でのラベル左上位置
func drawLabel(
    _ text: String,
    at imageX: CGFloat, imageY: CGFloat,
    in ctx: CGContext, imageHeight: Int,
    opts: Options, ctFont: CTFont
) {
    // 属性付き文字列
    let attrStr = CFAttributedStringCreateMutable(nil, 0)!
    CFAttributedStringReplaceString(attrStr, CFRange(location: 0, length: 0), text as CFString)
    let range = CFRange(location: 0, length: CFAttributedStringGetLength(attrStr))
    CFAttributedStringSetAttribute(attrStr, range, kCTFontAttributeName, ctFont)

    let fgColor = CGColor(red: opts.labelColor.r, green: opts.labelColor.g,
                          blue: opts.labelColor.b, alpha: opts.labelColor.a)
    CFAttributedStringSetAttribute(attrStr, range, kCTForegroundColorAttributeName, fgColor)

    let line = CTLineCreateWithAttributedString(attrStr)
    let bounds = CTLineGetBoundsWithOptions(line, [])
    let ascent  = CTFontGetAscent(ctFont)
    let descent = CTFontGetDescent(ctFont)

    let textWidth  = ceil(bounds.width)
    let textHeight = ceil(ascent + descent)
    let bgPad: CGFloat = 4  // 背景矩形の内側パディング

    // ── 背景矩形（CG座標: 左下原点） ──
    // 画像座標の「上端 imageY - bgPad」→ CG Y の「下端 H - (imageY - bgPad + bgH)」
    let bgW = textWidth + bgPad * 2
    let bgH = textHeight + bgPad * 2
    let bgX = imageX - bgPad
    let bgY = CGFloat(imageHeight) - imageY - textHeight - bgPad  // CG下端

    ctx.setFillColor(red: opts.labelBg.r, green: opts.labelBg.g,
                     blue: opts.labelBg.b, alpha: opts.labelBg.a)
    ctx.fill(CGRect(x: bgX, y: bgY, width: bgW, height: bgH))

    // ── テキスト（render-text.swift の flippedBaselineY パターン準拠） ──
    // 画像座標の「テキスト上端 imageY」→ CG ベースライン = H - imageY - ascent
    let baselineY = CGFloat(imageHeight) - imageY - ascent
    ctx.textPosition = CGPoint(x: imageX, y: baselineY)
    CTLineDraw(line, ctx)
}

// MARK: - divide モード

func drawDivideGrid(ctx: CGContext, image: CGImage, opts: Options) {
    let W = image.width
    let H = image.height
    let n = opts.divideN!

    let cellW = CGFloat(W) / CGFloat(n)
    let cellH = CGFloat(H) / CGFloat(n)

    ctx.setStrokeColor(red: opts.lineColor.r, green: opts.lineColor.g,
                       blue: opts.lineColor.b, alpha: opts.lineColor.a)
    ctx.setLineWidth(1.0)

    // 線分リスト（CG座標）
    var segs: [CGPoint] = []

    // 垂直線（x は画像座標・CG座標で同じ）
    for i in 1..<n {
        let x = CGFloat(i) * cellW
        segs.append(CGPoint(x: x, y: 0))
        segs.append(CGPoint(x: x, y: CGFloat(H)))
    }

    // 水平線（画像 Y = j*cellH → CG Y = H - j*cellH）
    for j in 1..<n {
        let cgY = CGFloat(H) - CGFloat(j) * cellH
        segs.append(CGPoint(x: 0, y: cgY))
        segs.append(CGPoint(x: CGFloat(W), y: cgY))
    }

    if !segs.isEmpty {
        ctx.strokeLineSegments(between: segs)
    }

    // ラベル: 各セル (col, row) の左上 (4px, 4px) に "col,row"
    let ctFont = CTFontCreateWithName("Helvetica-Bold" as CFString, opts.fontSize, nil)
    for row in 0..<n {
        for col in 0..<n {
            let label  = "\(col),\(row)"
            let imgX   = CGFloat(col) * cellW + 4
            let imgY   = CGFloat(row) * cellH + 4
            drawLabel(label, at: imgX, imageY: imgY, in: ctx,
                      imageHeight: H, opts: opts, ctFont: ctFont)
        }
    }
}

// MARK: - every モード

func drawEveryGrid(ctx: CGContext, image: CGImage, opts: Options) {
    let W = image.width
    let H = image.height
    let n = opts.everyN!

    ctx.setStrokeColor(red: opts.lineColor.r, green: opts.lineColor.g,
                       blue: opts.lineColor.b, alpha: opts.lineColor.a)
    ctx.setLineWidth(1.0)

    var segs: [CGPoint] = []

    // 垂直線
    var xi = n
    while xi < W {
        let cx = CGFloat(xi)
        segs.append(CGPoint(x: cx, y: 0))
        segs.append(CGPoint(x: cx, y: CGFloat(H)))
        if xi > Int.max - n { break }
        xi += n
    }

    // 水平線（画像 Y → CG Y）
    var yi = n
    while yi < H {
        let cgY = CGFloat(H) - CGFloat(yi)
        segs.append(CGPoint(x: 0, y: cgY))
        segs.append(CGPoint(x: CGFloat(W), y: cgY))
        if yi > Int.max - n { break }
        yi += n
    }

    if !segs.isEmpty {
        ctx.strokeLineSegments(between: segs)
    }

    let ctFont = CTFontCreateWithName("Helvetica-Bold" as CFString, opts.fontSize, nil)

    // X 線ラベル: 各垂直線の上端に "x=N"
    xi = n
    while xi < W {
        drawLabel("x=\(xi)", at: CGFloat(xi) + 2, imageY: 2,
                  in: ctx, imageHeight: H, opts: opts, ctFont: ctFont)
        if xi > Int.max - n { break }
        xi += n
    }

    // Y 線ラベル: 各水平線の左端に "y=N"
    yi = n
    while yi < H {
        drawLabel("y=\(yi)", at: 2, imageY: CGFloat(yi) + 2,
                  in: ctx, imageHeight: H, opts: opts, ctFont: ctFont)
        if yi > Int.max - n { break }
        yi += n
    }
}

// MARK: - Main

let opts = parseArgs()
validatePath(opts.inputPath,  label: "入力パス")
validatePath(opts.outputPath, label: "出力パス")

// 入力 PNG 読み込み
guard let dataProvider = CGDataProvider(filename: opts.inputPath),
      let inputImage = CGImage(pngDataProviderSource: dataProvider,
                               decode: nil, shouldInterpolate: false,
                               intent: .defaultIntent) else {
    fputs("Error: 画像の読み込みに失敗しました '\(opts.inputPath)'\n", stderr)
    exit(1)
}

let W = inputImage.width
let H = inputImage.height

// CGContext 作成（premultipliedLast）
let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(
    data: nil,
    width: W,
    height: H,
    bitsPerComponent: 8,
    bytesPerRow: W * 4,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fputs("Error: CGContext の作成に失敗しました\n", stderr)
    exit(1)
}

// 元画像をコピー
// CGContext と CGImageDestination はどちらも同じメモリ順（底→上）で動作するため、
// flip CTM は不要。render-text.swift と同じパターン。
ctx.draw(inputImage, in: CGRect(x: 0, y: 0, width: CGFloat(W), height: CGFloat(H)))

// グリッド描画
if opts.divideN != nil {
    drawDivideGrid(ctx: ctx, image: inputImage, opts: opts)
} else {
    drawEveryGrid(ctx: ctx, image: inputImage, opts: opts)
}

// 出力
guard let outputImage = ctx.makeImage() else {
    fputs("Error: 出力画像の生成に失敗しました\n", stderr)
    exit(1)
}

guard writePNG(image: outputImage, path: opts.outputPath) else {
    exit(1)
}

print("Annotated: \(opts.outputPath) (\(W)x\(H)px)")
