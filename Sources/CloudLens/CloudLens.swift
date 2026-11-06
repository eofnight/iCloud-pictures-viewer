import SwiftUI

@main struct CloudLensApp: App {
    @StateObject private var library = Library()
    var body: some Scene {
        WindowGroup {
            BrowserView().environmentObject(library)
                .frame(minWidth: 1050, minHeight: 700)
        }.defaultSize(width: 1380, height: 900)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("開啟資料夾…") { library.choose() }.keyboardShortcut("o")
            }
        }
    }
}

struct BrowserView: View {
    @EnvironmentObject var library: Library
    @State private var search = ""
    @State private var cardSize = 220.0
    @State private var showInfo = false
    @State private var descending = false
    private var entries: [Entry] {
        let result = library.entries.filter { search.isEmpty || $0.url.lastPathComponent.localizedCaseInsensitiveContains(search) }
        return descending ? Array(result.reversed()) : result
    }
    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 340)
        } detail: {
            VStack(spacing: 0) {
                header
                Divider()
                if library.selected != nil {
                    PhotoEditor()
                } else if library.folder == nil {
                    ContentUnavailableView {
                        Label("你的相簿，盡在這裡", systemImage: "rectangle.stack")
                    } description: {
                        Text("選擇 iCloud Drive 或本機資料夾，將子資料夾以相簿方式呈現。")
                    } actions: {
                        Button("選擇圖片資料夾…") { library.choose() }.buttonStyle(.borderedProminent)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    gallery
                }
                Divider()
                footer
            }.background(Color(nsColor: .controlBackgroundColor))
        }
        .toolbar {
            ToolbarItemGroup {
                Button { library.choose() } label: { Label("開啟資料夾", systemImage: "folder.badge.plus") }
                Button { if let folder = library.folder { library.browse(folder) } } label: { Label("重新整理", systemImage: "arrow.clockwise") }.disabled(library.folder == nil)
            }
        }
        .inspector(isPresented: $showInfo) { inspector.frame(minWidth: 230, idealWidth: 260) }
        .alert("CloudLens", isPresented: Binding(get: { library.message != nil }, set: { if !$0 { library.message = nil } })) {
            Button("好") { library.message = nil }
        } message: { Text(library.message ?? "") }
    }
    private var sidebar: some View {
        List {
            Section("資料庫") {
                Button { if let root = library.root { library.browse(root) } } label: {
                    Label("所有相簿", systemImage: "rectangle.stack")
                        .fontWeight(library.folder == library.root ? .semibold : .regular)
                }.disabled(library.root == nil)
                Button { library.choose() } label: { Label("開啟資料夾…", systemImage: "icloud") }
            }
            Section("相簿") {
                ForEach(library.albums) { album in
                    SidebarFolder(entry: album)
                }
                if library.albums.isEmpty {
                    Text("子資料夾會顯示在這裡").font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("儲存空間") {
                Button { library.cacheSize() } label: { Label("查看快取大小", systemImage: "externaldrive") }
                Button { library.clearCache() } label: { Label("清除縮圖快取", systemImage: "trash") }
            }
        }.listStyle(.sidebar).buttonStyle(.plain)
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 10) {
                    Image(systemName: "icloud").font(.title2).foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("iCloud Pictures Viewer").font(.caption.bold())
                        Text(library.root?.lastPathComponent ?? "尚未選擇資料夾").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                }.padding(16).background(.bar)
            }
    }
    private var header: some View {
        HStack(spacing: 18) {
            if library.selected != nil {
                Button { library.closePreview() } label: { Image(systemName: "chevron.left") }.help("返回相簿")
            } else if library.canGoUp {
                Button { library.up() } label: { Image(systemName: "chevron.left") }.help("上一層")
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(library.selected?.lastPathComponent ?? (library.folder == library.root ? "相簿" : library.folder?.lastPathComponent) ?? "相簿")
                    .font(.system(size: 21, weight: .semibold)).lineLimit(1)
                Text("\(library.entries.filter(\.isDirectory).count) 個資料夾 · \(library.entries.filter { !$0.isDirectory }.count) 張圖片")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 10)
            if library.selected == nil {
                Menu {
                    Button("名稱：A → Z") { descending = false }
                    Button("名稱：Z → A") { descending = true }
                } label: { Image(systemName: "line.3.horizontal.decrease") }.menuStyle(.borderlessButton).frame(width: 28).help("排序")
                HStack(spacing: 8) {
                    Image(systemName: "minus").font(.caption)
                    Slider(value: $cardSize, in: 160...300).frame(width: 90)
                    Image(systemName: "plus").font(.caption)
                }
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("搜尋此資料夾", text: $search).textFieldStyle(.plain)
                    if !search.isEmpty { Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain) }
                }.padding(.horizontal, 12).padding(.vertical, 9).frame(width: 210)
                    .background(.quaternary.opacity(0.5), in: Capsule())
            }
            Button { showInfo.toggle() } label: { Image(systemName: "info.circle").font(.title3) }.buttonStyle(.plain).help("顯示資訊")
        }.padding(.horizontal, 28).padding(.vertical, 20)
    }
    private var gallery: some View {
        ScrollView {
            if entries.isEmpty {
                ContentUnavailableView(search.isEmpty ? "此資料夾沒有圖片或相簿" : "找不到符合的項目", systemImage: search.isEmpty ? "photo.on.rectangle" : "magnifyingglass")
                    .frame(maxWidth: .infinity).padding(.top, 100)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: cardSize), spacing: 24)], spacing: 26) {
                    ForEach(entries) { entry in
                        Button { library.select(entry) } label: {
                            if entry.isDirectory {
                                AlbumCard(entry: entry, epoch: library.cacheEpoch)
                            } else {
                                PhotoCard(entry: entry, epoch: library.cacheEpoch)
                            }
                        }.buttonStyle(.plain)
                    }
                }.padding(30)
            }
        }.onChange(of: library.folder) { _, _ in search = "" }
    }
    private var footer: some View {
        HStack {
            Image(systemName: "folder").foregroundStyle(.blue)
            Text(library.folder?.path ?? "開啟資料夾開始瀏覽").lineLimit(1).truncationMode(.middle)
            Spacer()
            if library.isPrefetching { ProgressView().controlSize(.small) }
            Text(library.cacheProgress).lineLimit(1)
            if library.isPrefetching {
                Button("停止") { library.stopPrefetch() }.buttonStyle(.borderless)
            }
            Text(library.cacheLabel)
            if library.selected == nil { Text("\(entries.count) 個項目") }
        }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 24).padding(.vertical, 10)
    }
    private var inspector: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("資訊", systemImage: "info.circle").font(.title2.bold())
            Divider()
            Text(library.selected?.lastPathComponent ?? library.folder?.lastPathComponent ?? "尚未選擇項目").font(.headline).textSelection(.enabled)
            if let image = library.image {
                LabeledContent("尺寸", value: "\(Int(image.size.width)) × \(Int(image.size.height))")
            }
            if let url = library.selected ?? library.folder {
                Text(url.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
            Divider()
            Label("本機縮圖快取", systemImage: "externaldrive").font(.headline)
            Text(library.cacheLabel.isEmpty ? "點下方按鈕查看使用量" : library.cacheLabel).foregroundStyle(.secondary)
            Button("查看大小") { library.cacheSize() }
            Button("清除縮圖快取") { library.clearCache() }
            Text("清除後，瀏覽時會重新產生縮圖。").font(.caption).foregroundStyle(.secondary)
            Spacer()
        }.padding(22)
    }
}

struct SidebarFolder: View {
    @EnvironmentObject var library: Library
    let entry: Entry
    @State private var expanded = false
    @State private var children: [Entry] = []
    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            ForEach(children) { child in
                SidebarFolder(entry: child)
            }
        } label: {
            Button { library.browse(entry.url) } label: {
                Label(entry.url.lastPathComponent, systemImage: "folder")
                    .foregroundStyle(library.folder == entry.url ? Color.accentColor : Color.primary)
                    .fontWeight(library.folder == entry.url ? .semibold : .regular)
                    .padding(.vertical, 3)
            }
        }.task(id: expanded) {
            guard expanded else { return }
            let url = entry.url
            children = await Task.detached { ((try? Library.readEntries(url)) ?? []).filter(\.isDirectory) }.value
        }
    }
}
