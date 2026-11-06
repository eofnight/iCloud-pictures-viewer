import SwiftUI

struct PhotoEditor: View {
    @EnvironmentObject var library: Library
    @State private var cropMode = false
    @State private var crop: CGRect?
    @State private var zoom = 1.0
    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()
            if let image = library.image {
                GeometryReader { geometry in
                    let ratio = min((geometry.size.width-40) / image.size.width, (geometry.size.height-40) / image.size.height)
                    let size = CGSize(width: image.size.width * ratio * zoom, height: image.size.height * ratio * zoom)
                    ScrollView([.horizontal, .vertical]) {
                        ZStack {
                            Image(nsImage: image).resizable().frame(width: size.width, height: size.height)
                            if cropMode { CropOverlay(selection: $crop).frame(width: size.width, height: size.height) }
                        }.frame(width: size.width, height: size.height)
                            .frame(minWidth: geometry.size.width, minHeight: geometry.size.height)
                    }
                }.background(Color.black.opacity(0.88))
                filmstrip
            } else {
                VStack(spacing: 18) {
                    if library.busy { ProgressView("正在讀取／下載圖片…") }
                    else { Label("無法預覽此圖片", systemImage: "photo.badge.exclamationmark") }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }.onChange(of: library.selected) { _, _ in crop = nil; cropMode = false; zoom = 1 }
    }
    private var controls: some View {
        HStack(spacing: 16) {
            Button { library.move(-1) } label: { Image(systemName: "chevron.left") }.keyboardShortcut(.leftArrow, modifiers: [])
            Button { library.move(1) } label: { Image(systemName: "chevron.right") }.keyboardShortcut(.rightArrow, modifiers: [])
            Divider().frame(height: 20)
            Button { if let image = library.image { library.image = ImageEdits.rotate(image); crop = nil } } label: { Label("旋轉", systemImage: "rotate.right") }
            Toggle(isOn: $cropMode) { Label("裁切", systemImage: "crop") }.toggleStyle(.button)
            if cropMode {
                Button("套用裁切") {
                    if let image = library.image, let crop, let result = ImageEdits.crop(image, normalized: crop) { library.image = result }
                    crop = nil; cropMode = false
                }.disabled(crop == nil || (crop?.width ?? 0) < 0.001 || (crop?.height ?? 0) < 0.001)
            }
            Button("還原") { library.image = library.original; crop = nil; zoom = 1 }
            Spacer()
            Slider(value: $zoom, in: 1...4).frame(width: 100).help("放大預覽")
            Button("另存 PNG…") { library.save() }.buttonStyle(.borderedProminent)
        }.buttonStyle(.borderless).padding(.horizontal, 24).padding(.vertical, 12).disabled(library.image == nil || library.busy)
    }
    private var filmstrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 10) {
                    ForEach(library.entries.filter { !$0.isDirectory }) { entry in
                        Button { library.select(entry) } label: {
                            Thumbnail(entry: entry, epoch: library.cacheEpoch).frame(width: 64, height: 64).clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(library.selected == entry.url ? Color.accentColor : .clear, lineWidth: 3))
                        }.buttonStyle(.plain).id(entry.url)
                    }
                }.padding(12)
            }.frame(height: 88).background(.bar)
                .onChange(of: library.selected, initial: true) { _, value in
                    if let value { proxy.scrollTo(value, anchor: .center) }
                }
        }
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
