# iCloud Pictures Viewer（CloudLens）

原生 macOS 圖片瀏覽器第一版，使用 SwiftUI、AppKit、Foundation 與 Image I/O，不需要第三方套件。支援 macOS 14 以上。

## 相簿介面

- 左側資料夾樹狀導覽，支援展開子資料夾與返回所有相簿。
- 右側相簿以第一張照片作為單張封面、圓角卡片呈現，支援調整卡片大小。
- 搜尋目前資料夾內的名稱，並以名稱正序／倒序排列。
- 圖片預覽有底部縮圖列、方向鍵切換、旋轉、裁切、縮放與另存功能。
- 資訊側欄可查看路徑、圖片尺寸與快取管理。
- 相簿封面依檔名自然排序選取第一張照片；無直接圖片時，最多搜尋 24 個子資料夾、深度 3 層，並下載該張封面。
- 進入資料夾後依序預載該層所有圖片，顯示完成／失敗張數；切換資料夾、按停止或清除快取會停止後續預載。

## 使用

執行 `./scripts/build-app.sh`，完成後開啟 `dist/CloudLens.app`。也可以以 Xcode 開啟 `Package.swift` 進行開發。

1. 按「開啟」，在系統選擇器中選擇 iCloud Drive 或本機資料夾。
2. 點資料夾進入下一層，按「上一層」返回；點圖片預覽，左右方向鍵切換。
3. 按旋轉，或啟用裁切後拖曳選取範圍、按「套用裁切」。可用「還原」重設所有編輯。
4. 按「另存 PNG…」選擇輸出位置。切換圖片會放棄尚未另存的編輯。
5. 「快取」選單可查看大小與清除縮圖；之後瀏覽會重新產生所需縮圖。

## iCloud 與隱私

使用 Mac 已登入的 iCloud 帳號，不收集 Apple ID、密碼或權杖，也不使用非公開 API。

- `NSOpenPanel`：使用者授權選取資料夾。
- Security-scoped bookmarks：記住上次開啟的資料夾，並在下次啟動恢復授權。
- `FileManager.startDownloadingUbiquitousItem(at:)`：載入封面、進入資料夾預載或選取雲端檔案時要求下載，畫面顯示等待狀態。
- `NSFileCoordinator`：協調圖片讀取與輸出檔案寫入。
- Image I/O：產生 320 像素縮圖與 2048 像素預覽快取，依路徑、修改日期、大小建立快取鍵。

此功能瀏覽 **iCloud Drive 檔案**，不包含 iCloud 照片圖庫。照片圖庫存取需另行整合 PhotoKit 與照片授權。

縮圖存於系統 Caches 下的 `CloudLens/Thumbnails`（沙盒版位於應用程式容器內）。進入資料夾會要求下載該層所有圖片並建立磁碟預覽快取，不將整個資料夾的完整影像同時載入記憶體。預覽載入後，編輯會等待較高解析度影像讀取完成。清除快取會刪除縮圖與預覽檔，不會刪除原圖，也不會移除 macOS 自己保存的 iCloud 本機檔案。

Apple 文件：[檔案授權](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox)、[iCloud 下載](https://developer.apple.com/documentation/foundation/filemanager/startdownloadingubiquitousitem(at:))、[資料夾選擇器](https://developer.apple.com/documentation/appkit/nsopenpanel)。

## 目前限制

- 這是 MVP，尚未實測真實 iCloud 帳號、離線及衝突情境；資料夾變動需按重新整理。
- 影像預覽／編輯最長邊上限為 16,000 像素；超過此尺寸會縮小，另存也是該尺寸。
- 輸出 PNG 不保留 EXIF、GPS 或其他中繼資料，動畫只處理第一格；RAW 支援依系統解碼器而定。
- 編輯目前只有全部還原，尚無逐步復原、原尺寸像素捲動模式、快取容量上限或全螢幕模式。
- 本機建置使用 ad-hoc 簽章與 App Sandbox；正式發布需要自己的 Apple 簽章、Developer ID 及公證流程。
- GitHub 專案：[eofnight/iCloud-pictures-viewer](https://github.com/eofnight/iCloud-pictures-viewer)。原始碼不含照片、快取、個人帳號資料或憑證。

## 驗證

```sh
./scripts/test.sh
```

測試涵蓋旋轉、裁切、預覽快取產生、清除後保留原圖、損壞檔案與取消預載。快取測試使用本機暫存圖片，不經檔案協調服務；正式應用程式仍使用 NSFileCoordinator，實際使用仍需驗證雲端下載與沙盒權限。
