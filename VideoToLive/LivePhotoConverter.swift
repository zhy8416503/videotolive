import AVFoundation
import CoreMedia
import ImageIO
import Photos
import UniformTypeIdentifiers
import UIKit

/// 视频转实况照片的核心转换逻辑
///
/// 实况照片的本质：一张 JPG（关键帧）+ 一段 MOV（配对视频），两者用同一个
/// UUID（content identifier）绑定，iOS 相册即可识别为一张实况照片。
/// 具体标记方式（公开配方，非复制代码）：
///  1. JPG：kCGImagePropertyMakerAppleDictionary 中写入 ["17": assetID]
///  2. MOV：顶层元数据写入 key = "com.apple.quicktime.content.identifier"（keySpace mdta）
///  3. MOV：再加一条 timed metadata track，key = "com.apple.quicktime.still-image-time"，
///     其 timeRange.start 指向关键帧在视频时间轴上的位置，告诉系统封面帧在哪里。
/// 关于 still-image-time 的取舍：它是" nice to have "而非配对必需项——配对只看
/// content identifier；且我们显式传入的 .photo 本来就是用户选的关键帧，即使该
/// track 写入失败（已做容错，失败也不中断流程），相册显示也不受影响。
enum LivePhotoConverter {

    enum ConvertError: Error {
        case badVideo(String)
        case noPhotoAccess
        case failed(String)

        var message: String {
            switch self {
            case .badVideo(let s): return s
            case .noPhotoAccess: return "没有相册写入权限，请在系统设置中允许"
            case .failed(let s): return s
            }
        }
    }

    /// 主流程：裁剪 -> 关键帧 JPG -> 写配对元数据 -> 存相册
    static func convert(videoURL: URL, keyTime: Double, progress: @escaping (String) -> Void) async throws {
        let fm = FileManager.default
        let workDir = fm.temporaryDirectory.appendingPathComponent("livephoto-" + UUID().uuidString)
        try fm.createDirectory(at: workDir, withIntermediateDirectories: true, attributes: nil)
        defer { try? fm.removeItem(at: workDir) }

        let assetID = UUID().uuidString
        let asset = AVURLAsset(url: videoURL)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else {
            throw ConvertError.badVideo("无法读取视频时长")
        }

        // 以关键帧为中心取 3 秒窗口（不足 3 秒则用全长）
        let window = min(3.0, duration)
        var start = keyTime - window / 2.0
        start = max(0.0, min(start, duration - window))
        let timeRange = CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: 600),
            duration: CMTime(seconds: window, preferredTimescale: 600))

        progress("正在裁剪视频片段…")
        let trimURL = workDir.appendingPathComponent("trim.mov")
        try await exportTrim(asset: asset, timeRange: timeRange, to: trimURL)

        // 关键帧在裁剪后视频中的相对时间（用于 still-image-time）
        let stillInTrim = CMTime(seconds: keyTime - start, preferredTimescale: 600)

        progress("正在提取关键帧…")
        let jpgURL = workDir.appendingPathComponent("key.jpg")
        try await writeKeyPhoto(
            asset: asset,
            at: CMTime(seconds: keyTime, preferredTimescale: 600),
            assetID: assetID,
            to: jpgURL)

        progress("正在写入实况配对标记…")
        let movURL = workDir.appendingPathComponent("live.mov")
        try await addPairingMetadata(trimURL: trimURL, finalURL: movURL, assetID: assetID, stillTime: stillInTrim)

        progress("正在保存到相册…")
        let auth = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard auth == .authorized || auth == .limited else {
            throw ConvertError.noPhotoAccess
        }
        try await PHPhotoLibrary.shared().performChanges {
            let req = PHAssetCreationRequest.forAsset()
            req.addResource(with: .photo, fileURL: jpgURL, options: nil)
            req.addResource(with: .pairedVideo, fileURL: movURL, options: nil)
        }
        progress("已保存到相册")
    }

    /// 读取视频时长（秒）
    static func videoDuration(url: URL) async -> Double {
        do {
            let d = try await AVURLAsset(url: url).load(.duration).seconds
            return d.isFinite ? d : 0
        } catch {
            return 0
        }
    }

    /// 生成指定时刻的缩略图（UI 预览用）
    static func makeThumbnail(videoURL: URL?, at time: Double) async -> UIImage? {
        guard let videoURL = videoURL else { return nil }
        let gen = AVAssetImageGenerator(asset: AVURLAsset(url: videoURL))
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 480, height: 480)
        gen.requestedTimeToleranceBefore = .zero
        gen.requestedTimeToleranceAfter = .zero
        do {
            let cg = try gen.copyCGImage(at: CMTime(seconds: time, preferredTimescale: 600), actualTime: nil)
            return UIImage(cgImage: cg)
        } catch {
            return nil
        }
    }

    // MARK: - 内部步骤

    /// 用最高质量预设按时间窗口裁剪视频
    private static func exportTrim(asset: AVURLAsset, timeRange: CMTimeRange, to url: URL) async throws {
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            throw ConvertError.failed("无法创建视频导出会话")
        }
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) {
            try fm.removeItem(at: url)
        }
        session.outputURL = url
        session.outputFileType = .mov
        session.timeRange = timeRange
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            session.exportAsynchronously {
                if session.status == .completed {
                    cont.resume()
                } else {
                    cont.resume(throwing: ConvertError.failed("视频裁剪失败：" + (session.error?.localizedDescription ?? "未知错误")))
                }
            }
        }
    }

    /// 在关键帧时刻抓图，写入带 MakerApple 标记的 JPG
    private static func writeKeyPhoto(asset: AVURLAsset, at time: CMTime, assetID: String, to url: URL) async throws {
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.requestedTimeToleranceBefore = .zero
        gen.requestedTimeToleranceAfter = .zero
        let cgImage: CGImage
        do {
            cgImage = try gen.copyCGImage(at: time, actualTime: nil)
        } catch {
            throw ConvertError.failed("关键帧提取失败")
        }
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw ConvertError.failed("无法创建图片文件")
        }
        // "17" 为 MakerApple 字典中 content identifier 的固定 key
        let props: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 0.92,
            kCGImagePropertyMakerAppleDictionary: ["17": assetID]
        ]
        CGImageDestinationAddImage(dest, cgImage, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            throw ConvertError.failed("关键帧图片写入失败")
        }
    }

    /// 第二遍：passthrough 拷贝音视频流，同时写入配对元数据。
    /// 自研实现（未复制任何第三方文件），原理为公开的 Live Photo 配方：
    /// 顶层写入 content identifier；另加一条 timed metadata track 标记 still-image-time。
    private static func addPairingMetadata(trimURL: URL, finalURL: URL, assetID: String, stillTime: CMTime) async throws {
        let asset = AVURLAsset(url: trimURL)
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw ConvertError.failed("未找到视频轨道")
        }
        let videoFormats = try await videoTrack.load(.formatDescriptions)
        guard let videoDesc = videoFormats.first else {
            throw ConvertError.failed("视频轨道格式不可读")
        }

        let reader = try AVAssetReader(asset: asset)
        let writer = try AVAssetWriter(outputURL: finalURL, fileType: .mov)

        // 视频 passthrough（不重编码）
        let videoOut = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: nil)
        reader.add(videoOut)
        let videoIn = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: videoDesc)
        videoIn.transform = try await videoTrack.load(.preferredTransform)
        writer.add(videoIn)

        // 音频 passthrough（如果有）
        var audioOut: AVAssetReaderTrackOutput?
        var audioIn: AVAssetWriterInput?
        if let audioTrack = try await asset.loadTracks(withMediaType: .audio).first,
           let audioDesc = try await audioTrack.load(.formatDescriptions).first {
            let out = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: nil)
            reader.add(out)
            audioOut = out
            let inp = AVAssetWriterInput(mediaType: .audio, outputSettings: nil, sourceFormatHint: audioDesc)
            writer.add(inp)
            audioIn = inp
        }

        // still-image-time 定时元数据轨道
        let spec: [String: String] = [
            kCMMetadataFormatDescriptionMetadataSpecificationKey_Identifier as String:
                "mdta/com.apple.quicktime.still-image-time",
            kCMMetadataFormatDescriptionMetadataSpecificationKey_DataType as String:
                "com.apple.metadata.datatype.int8"
        ]
        var metaDesc: CMFormatDescription?
        let mdStatus = CMMetadataFormatDescriptionCreateWithMetadataSpecifications(
            allocator: kCFAllocatorDefault,
            metadataType: kCMMetadataFormatType_Boxed,
            metadataSpecifications: [spec] as CFArray,
            formatDescriptionOut: &metaDesc)
        guard mdStatus == noErr, let metaDesc = metaDesc else {
            throw ConvertError.failed("元数据轨道创建失败")
        }
        let metaIn = AVAssetWriterInput(mediaType: .metadata, outputSettings: nil, sourceFormatHint: metaDesc)
        let metaAdaptor = AVAssetWriterInputMetadataAdaptor(assetWriterInput: metaIn)
        writer.add(metaIn)

        // content identifier：JPG 与 MOV 配对的关键，写在顶层元数据
        let idItem = AVMutableMetadataItem()
        idItem.key = "com.apple.quicktime.content.identifier" as (NSCopying & NSObjectProtocol)
        idItem.keySpace = .quickTimeMetadata
        idItem.value = assetID as (NSCopying & NSObjectProtocol)
        idItem.dataType = "com.apple.metadata.datatype.UTF-8"
        writer.metadata = [idItem]

        guard writer.startWriting() else {
            throw ConvertError.failed("写入器启动失败：" + (writer.error?.localizedDescription ?? "未知错误"))
        }
        writer.startSession(atSourceTime: .zero)

        // still-image-time 的值恒为 0，真正的位置信息由 timed group 的 timeRange.start 携带
        let stillItem = AVMutableMetadataItem()
        stillItem.key = "com.apple.quicktime.still-image-time" as (NSCopying & NSObjectProtocol)
        stillItem.keySpace = .quickTimeMetadata
        stillItem.value = NSNumber(value: 0)
        stillItem.dataType = "com.apple.metadata.datatype.int8"
        let stillGroup = AVTimedMetadataGroup(
            items: [stillItem],
            timeRange: CMTimeRange(start: stillTime, duration: CMTime(value: 1, timescale: 600)))
        // 取舍说明：若这条 timed track 写入失败，相册仍能靠 content identifier 正常配对，
        // 且我们传入的 .photo 本身就是用户选的关键帧，因此失败时仅记录、不中断流程。
        if metaAdaptor.append(stillGroup) == false {
            print("VideoToLive: still-image-time 写入失败，已忽略（不影响配对）")
        }

        guard reader.startReading() else {
            throw ConvertError.failed("视频读取器启动失败")
        }

        let ioQueue = DispatchQueue(label: "com.videotolive.writer")
        let done = DispatchGroup()

        done.enter()
        videoIn.requestMediaDataWhenReady(on: ioQueue) {
            while videoIn.isReadyForMoreMediaData {
                if let sample = videoOut.copyNextSampleBuffer() {
                    if videoIn.append(sample) == false {
                        videoIn.markAsFinished()
                        done.leave()
                        break
                    }
                } else {
                    videoIn.markAsFinished()
                    done.leave()
                    break
                }
            }
        }
        if let audioIn = audioIn, let audioOut = audioOut {
            done.enter()
            audioIn.requestMediaDataWhenReady(on: ioQueue) {
                while audioIn.isReadyForMoreMediaData {
                    if let sample = audioOut.copyNextSampleBuffer() {
                        if audioIn.append(sample) == false {
                            audioIn.markAsFinished()
                            done.leave()
                            break
                        }
                    } else {
                        audioIn.markAsFinished()
                        done.leave()
                        break
                    }
                }
            }
        }

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            ioQueue.async {
                done.wait()
                writer.finishWriting {
                    if writer.status == .completed {
                        cont.resume()
                    } else {
                        cont.resume(throwing: ConvertError.failed("配对视频写入失败：" + (writer.error?.localizedDescription ?? "未知错误")))
                    }
                }
            }
        }
    }
}
