// Renders Kliq's app icon into an .iconset directory. The artwork lives in
// Sources/Kliq/UI/Components/KliqLogo.swift; build.sh compiles the two together
// and turns the result into AppIcon.icns with iconutil:
//
//   swiftc -parse-as-library -o build/make_icon Tools/make_icon.swift Sources/Kliq/UI/Components/KliqLogo.swift
//   build/make_icon build/AppIcon.iconset
import AppKit

@main
struct MakeIcon {
    static func main() {
        let args = CommandLine.arguments
        guard args.count >= 2 else {
            FileHandle.standardError.write(Data("usage: make_icon <out.iconset>\n".utf8))
            exit(1)
        }
        let outDir = URL(fileURLWithPath: args[1])
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        let variants: [(String, Int)] = [
            ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
            ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
            ("icon_512x512", 512), ("icon_512x512@2x", 1024),
        ]
        for (name, px) in variants {
            guard let png = KliqLogo.appIconBitmap(px: px).representation(using: .png, properties: [:]) else { continue }
            try? png.write(to: outDir.appendingPathComponent("\(name).png"))
        }
        print("wrote \(variants.count) icon sizes to \(outDir.path)")
    }
}
