import SwiftUI
import ImageIO

@main struct CloudLensApp: App {
    @StateObject private var library = Library()
    var body: some Scene {
        WindowGroup { BrowserView().environmentObject(library).frame(minWidth: 1000, minHeight: 650) }
        .commands {
            CommandGroup(replacing: .newItem) { Button("開啟資料夾…") { library.choose() }.keyboardShortcut("o") }
        }
    }
}
struct BrowserView: View {
    @EnvironmentObject var library: Library
    @State private var cropMode = false
    @State private var crop: CGRect?
    @State private var zoom = 1.0
    var body: some View {
        HSplitView {
            VStack(alignment: .leading) {
                Text("CLOUDLENS").font(.title2.bold()).padding(.horizontal)
                Text(library.folder?.lastPathComponent ?? "你的圖片資料庫").foregroundStyle(.secondary).padding(.horizontal)
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 110))], spacing: 16) {
                        ForEach(library.entries) { entry in
                            Button { library.select(entry) } label: {
                                VStack {
                                    Thumbnail(entry: entry, epoch: library.cacheEpoch).frame(height: 90)
                                    Text(entry.url.lastPathComponent).font(.caption).lineLimit(2).frame(height: 30)
                                }.padding(6).frame(maxWidth: .infinity).background(library.selected == entry.url ? Color.accentColor.opacity(0.22) : Color.clear).clipShape(RoundedRectangle(cornerRadius: 8))
                            }.buttonStyle(.plain)
                        }
                    }.padding()
                }
                HStack { Text("\(library.entries.filter { !$0.isDirectory }.count) 張圖片"); Spacer(); Text(library.cacheLabel) }.font(.caption).foregroundStyle(.secondary).padding()
            }.frame(minWidth: 260, idealWidth: 330, maxWidth: 440)
            VStack(spacing: 0) {
                if let image = library.image {
                    GeometryReader { geometry in
                        let ratio = min(geometry.size.width / image.size.width, geometry.size.height / image.size.height)
                        let size = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
                        ScrollView([.horizontal, .vertical]) {
                            ZStack(alignment: .topLeading) {
                                Image(nsImage: image).resizable().frame(width: size.width * zoom, height: size.height * zoom)
                                if cropMode {
                                    CropOverlay(selection: $crop).frame(width: size.width * zoom, height: size.height * zoom)
                                }
                            }.frame(minWidth: geometry.size.width, minHeight: geometry.size.height)
                        }
                    }.padding(20)
                    HStack {
                        Text(library.selected?.lastPathComponent ?? "").lineLimit(1)
                        Spacer()
                        Text("\(Int(image.size.width)) × \(Int(image.size.height))").foregroundStyle(.secondary)
                        Slider(value: $zoom, in: 1...4).frame(width: 100)
                    }.font(.caption).padding()
                } else if library.busy {
                    Spacer(); ProgressView("正在讀取／下載圖片…"); Spacer()
                } else {
                    Spacer(); Image(systemName: "photo.on.rectangle.angled").font(.system(size: 64)).foregroundStyle(.secondary)
                    Text("開啟 iCloud Drive 或本機資料夾").font(.title2).padding(.top)
                    Text("選取圖片以預覽；使用 ← → 快速切換").foregroundStyle(.secondary)
                    Button("選擇資料夾…") { library.choose() }.padding(); Spacer()
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.black.opacity(0.12))
        }
        .toolbar {
            Button { library.choose() } label: { Label("開啟", systemImage: "folder") }
            Button { library.up() } label: { Label("上一層", systemImage: "arrow.up") }.disabled(!library.canGoUp)
            Button { if let folder = library.folder { library.browse(folder) } } label: { Label("重新整理", systemImage: "arrow.clockwise") }
            Spacer()
            Button { library.move(-1) } label: { Image(systemName: "chevron.left") }.keyboardShortcut(.leftArrow, modifiers: []).disabled(library.selected == nil)
            Button { library.move(1) } label: { Image(systemName: "chevron.right") }.keyboardShortcut(.rightArrow, modifiers: []).disabled(library.selected == nil)
            Button { if let image = library.image { library.image = ImageEdits.rotate(image); crop = nil } } label: { Label("旋轉", systemImage: "rotate.right") }.disabled(library.image == nil)
            Toggle(isOn: $cropMode) { Label("裁切", systemImage: "crop") }.disabled(library.image == nil)
            if cropMode { Button("套用裁切") { if let image = library.image, let crop { library.image = ImageEdits.crop(image, normalized: crop) }; crop = nil; cropMode = false }.disabled(crop == nil) }
            Button("還原") { library.image = library.original; crop = nil; zoom = 1 }.disabled(library.image == nil)
            Button("另存 PNG…") { library.save() }.disabled(library.image == nil)
            Menu { Button("查看快取大小") { library.cacheSize() }; Button("清除縮圖快取") { library.clearCache() } } label: { Label("快取", systemImage: "externaldrive") }
        }
        .onChange(of: library.selected) { _, _ in crop = nil; cropMode = false; zoom = 1 }
        .alert("CloudLens", isPresented: Binding(get: { library.message != nil }, set: { if !$0 { library.message = nil } })) { Button("好") { library.message = nil } } message: { Text(library.message ?? "") }
    }
}
struct Thumbnail: View {
    let entry: Entry
    let epoch: UUID
    @State private var image: NSImage?
    var body: some View {
        Group {
            if entry.isDirectory { Image(systemName: "folder.fill").font(.system(size: 44)).foregroundStyle(.blue) }
            else if let image { Image(nsImage: image).resizable().scaledToFit() }
            else { Image(systemName: "icloud.and.arrow.down").font(.largeTitle).foregroundStyle(.secondary) }
        }.task(id: "\(entry.id)-\(epoch)") { if !entry.isDirectory { image = await ThumbnailCache.shared.thumbnail(entry.url) } }
    }
}
struct CropOverlay: View {
    @Binding var selection: CGRect?
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                Color.black.opacity(0.15)
                if let selection {
                    Rectangle().stroke(.white, style: StrokeStyle(lineWidth: 2, dash: [6])).background(Color.accentColor.opacity(0.15)).frame(width: selection.width * geometry.size.width, height: selection.height * geometry.size.height).offset(x: selection.minX * geometry.size.width, y: selection.minY * geometry.size.height)
                }
            }.contentShape(Rectangle()).gesture(DragGesture(minimumDistance: 2).onChanged { value in
                let x1 = max(0, min(1, value.startLocation.x / geometry.size.width))
                let y1 = max(0, min(1, value.startLocation.y / geometry.size.height))
                let x2 = max(0, min(1, value.location.x / geometry.size.width))
                let y2 = max(0, min(1, value.location.y / geometry.size.height))
                selection = CGRect(x: min(x1,x2), y: min(y1,y2), width: abs(x2-x1), height: abs(y2-y1))
            })
        }
    }
}
