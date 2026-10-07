import AVFoundation
import AVKit
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var videoURL: URL?
    @State private var player: AVPlayer?
    @State private var duration: Double = 0
    @State private var keyTime: Double = 0
    @State private var thumbnail: UIImage?
    @State private var showPicker = false
    @State private var isWorking = false
    @State private var statusText = "请选择一个视频开始"
    @State private var thumbTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let player = player {
                        VideoPlayer(player: player)
                            .frame(height: 280)
                            .cornerRadius(12)
                    } else {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.secondary.opacity(0.15))
                            .frame(height: 280)
                            .overlay(Text("尚未选择视频").foregroundColor(.secondary))
                    }

                    Button("选择视频") {
                        showPicker = true
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isWorking)

                    if videoURL != nil {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("关键帧：\(fmt(keyTime)) / \(fmt(duration))")
                                .font(.subheadline)
                            if let thumbnail = thumbnail {
                                Image(uiImage: thumbnail)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(height: 120)
                                    .cornerRadius(8)
                            }
                            Slider(value: $keyTime, in: 0 ... max(duration, 0.01))
                                .disabled(duration <= 0 || isWorking)
                            Text("拖动滑块选择实况照片的封面帧")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 4)

                        Button("生成实况照片并保存到相册") {
                            startConvert()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isWorking)
                    }

                    if isWorking {
                        ProgressView()
                            .padding(.top, 4)
                    }
                    Text(statusText)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding()
            }
            .navigationTitle("视频转实况")
        }
        .sheet(isPresented: $showPicker) {
            VideoPicker(isPresented: $showPicker) { url in
                if let url = url {
                    importVideo(url)
                } else {
                    statusText = "未能读取所选视频"
                }
            }
        }
        .onChange(of: keyTime) { _, _ in
            scheduleThumbnail()
        }
    }

    private func fmt(_ s: Double) -> String {
        return String(format: "%.1f 秒", s)
    }

    private func importVideo(_ url: URL) {
        player?.pause()
        player = AVPlayer(url: url)
        videoURL = url
        thumbnail = nil
        statusText = "正在读取视频信息…"
        Task {
            let d = await LivePhotoConverter.videoDuration(url: url)
            await MainActor.run {
                if d > 0 {
                    duration = d
                    keyTime = d / 2.0
                    statusText = "拖动滑块选择关键帧，然后生成实况照片"
                    scheduleThumbnail()
                } else {
                    statusText = "无法读取该视频，请换一个试试"
                }
            }
        }
    }

    private func scheduleThumbnail() {
        thumbTask?.cancel()
        thumbTask = Task {
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard Task.isCancelled == false else { return }
            let t = keyTime
            let u = videoURL
            let img = await LivePhotoConverter.makeThumbnail(videoURL: u, at: t)
            guard Task.isCancelled == false else { return }
            await MainActor.run {
                self.thumbnail = img
            }
        }
    }

    private func startConvert() {
        guard let url = videoURL, isWorking == false else { return }
        let kt = keyTime
        isWorking = true
        statusText = "开始转换…"
        Task {
            do {
                try await LivePhotoConverter.convert(videoURL: url, keyTime: kt) { msg in
                    Task { @MainActor in
                        self.statusText = msg
                    }
                }
                await MainActor.run {
                    isWorking = false
                    statusText = "已保存到相册，去照片 App 里长按查看实况效果"
                }
            } catch let e as LivePhotoConverter.ConvertError {
                await MainActor.run {
                    isWorking = false
                    statusText = "失败：" + e.message
                }
            } catch {
                await MainActor.run {
                    isWorking = false
                    statusText = "失败：" + error.localizedDescription
                }
            }
        }
    }
}

/// PHPicker 视频选择器（SwiftUI 封装）
struct VideoPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    var onPick: (URL?) -> Void

    func makeCoordinator() -> Coordinator {
        return Coordinator(isPresented: $isPresented, onPick: onPick)
    }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .videos
        config.selectionLimit = 1
        let vc = PHPickerViewController(configuration: config)
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        @Binding var isPresented: Bool
        var onPick: (URL?) -> Void

        init(isPresented: Binding<Bool>, onPick: @escaping (URL?) -> Void) {
            self._isPresented = isPresented
            self.onPick = onPick
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            isPresented = false
            guard let provider = results.first?.itemProvider else {
                onPick(nil)
                return
            }
            let typeID: String
            if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                typeID = UTType.movie.identifier
            } else if provider.hasItemConformingToTypeIdentifier(UTType.mpeg4Movie.identifier) {
                typeID = UTType.mpeg4Movie.identifier
            } else {
                onPick(nil)
                return
            }
            provider.loadFileRepresentation(forTypeIdentifier: typeID) { url, error in
                guard let url = url, error == nil else {
                    DispatchQueue.main.async { self.onPick(nil) }
                    return
                }
                let dest = FileManager.default.temporaryDirectory
                    .appendingPathComponent("import-" + UUID().uuidString + ".mov")
                do {
                    if FileManager.default.fileExists(atPath: dest.path) {
                        try FileManager.default.removeItem(at: dest)
                    }
                    // PHPicker 给的是临时 URL，必须先拷贝到自己的目录
                    try FileManager.default.copyItem(at: url, to: dest)
                    DispatchQueue.main.async { self.onPick(dest) }
                } catch {
                    DispatchQueue.main.async { self.onPick(nil) }
                }
            }
        }
    }
}
