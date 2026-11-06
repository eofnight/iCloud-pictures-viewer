import SwiftUI

struct AlbumCard: View {
    let entry: Entry
    let epoch: UUID
    @State private var covers: [Entry] = []
    @State private var hovered = false
    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            GeometryReader { geometry in
                ZStack {
                    Color.primary.opacity(0.045)
                    if let first = covers.first {
                        Thumbnail(entry: first, epoch: epoch, downloadForCover: true)
                            .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                    } else {
                        Image(systemName: "folder").font(.system(size: 48)).foregroundStyle(.tertiary)
                    }
                }.clipShape(RoundedRectangle(cornerRadius: 13))
            }.aspectRatio(1, contentMode: .fit)
            HStack {
                Text(entry.url.lastPathComponent).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 2)
                Image(systemName: "chevron.right").font(.caption2.bold()).foregroundStyle(.tertiary)
            }.padding(.horizontal, 4)
        }.padding(12).padding(.bottom, 4)
            .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.accentColor.opacity(hovered ? 0.5 : 0), lineWidth: 2))
            .shadow(color: .black.opacity(hovered ? 0.12 : 0.065), radius: hovered ? 18 : 12, y: 7)
            .onHover { hovered = $0 }
            .task(id: "\(entry.id)-\(epoch)") {
                let url = entry.url
                covers = await Task.detached(priority: .utility) {
                    AlbumCovers.find(in: url)
                }.value
            }
            .help("開啟相簿：\(entry.url.lastPathComponent)")
    }
}
struct PhotoCard: View {
    let entry: Entry
    let epoch: UUID
    @State private var hovered = false
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { geometry in
                Thumbnail(entry: entry, epoch: epoch)
                    .frame(width: geometry.size.width, height: geometry.size.height).clipped()
            }.aspectRatio(1, contentMode: .fit).background(Color.primary.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 13))
            Text(entry.url.lastPathComponent).font(.caption).lineLimit(1).padding(.horizontal, 3)
        }.padding(8).padding(.bottom, 4)
            .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 19))
            .overlay(RoundedRectangle(cornerRadius: 19).stroke(Color.accentColor.opacity(hovered ? 0.5 : 0), lineWidth: 2))
            .onHover { hovered = $0 }
    }
}
struct Thumbnail: View {
    @EnvironmentObject var library: Library
    let entry: Entry
    let epoch: UUID
    var downloadForCover = false
    @State private var image: NSImage?
    var body: some View {
        Group {
            if let image { Image(nsImage: image).resizable().scaledToFill() }
            else { Image(systemName: "icloud.and.arrow.down").font(.title2).foregroundStyle(.tertiary) }
        }.task(id: "\(entry.id)-\(epoch)-\(library.cachedURLs.contains(entry.url))") {
            if downloadForCover {
                _ = try? await ThumbnailCache.shared.prepare(entry.url, includePreview: false)
            }
            guard !Task.isCancelled else { return }
            image = await ThumbnailCache.shared.thumbnail(entry.url)
        }
    }
}

// Bounded traversal finds covers for folders organized into several album levels.
// Only the first cover is downloaded, never every image in unopened albums.
enum AlbumCovers {
    static func find(in folder: URL) -> [Entry] {
        var queue: [(URL, Int)] = [(folder, 0)]
        var result: [Entry] = []
        var visited = 0
        while !queue.isEmpty && visited < 24 && result.count < 1 {
            let (url, depth) = queue.removeFirst()
            visited += 1
            let entries = (try? Library.readEntries(url)) ?? []
            result.append(contentsOf: entries.filter { !$0.isDirectory }.prefix(1 - result.count))
            if depth < 3 {
                queue.append(contentsOf: entries.filter { $0.isDirectory }.prefix(24).map { ($0.url, depth + 1) })
            }
        }
        return result
    }
}
