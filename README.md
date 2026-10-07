# 视频转实况 (VideoToLive)

把相册里的一段视频转成 iOS 实况照片（Live Photo），保存回相册，长按即可播放动态效果。

## 功能

- 「选择视频」：用系统 PHPicker 挑选一段视频并预览
- 拖动滑块选择关键帧（封面），实时显示该时刻的缩略图
- 「生成实况照片并保存到相册」：以关键帧为中心裁 3 秒视频，生成配对的 JPG + MOV 并写入相册

## 原理

实况照片 = 一张 JPG（关键帧）+ 一段 MOV（配对视频），两者用同一个 UUID
（content identifier）绑定：

1. JPG 的 `MakerApple` 字典写入 `["17": assetID]`
2. MOV 顶层元数据写入 `mdta/com.apple.quicktime.content.identifier = assetID`
3. MOV 再加一条 timed metadata track：`mdta/com.apple.quicktime.still-image-time`，
   其 `timeRange.start` 指向关键帧在视频时间轴上的位置

第 2 步是配对的关键；第 3 步为可选项（失败不影响配对，已在代码中容错）。

## 构建（未签名 IPA）

1. 把本目录推到一个 GitHub 公开仓库
2. 在 Codemagic 手动添加该仓库，选择 `ios-unsigned` workflow 开始构建
3. 下载产物 `VideoToLive-unsigned.ipa`，自行签名后侧载安装

注意：未签名包在免费 Apple ID 下 7 天过期，需重新签名安装。

## 工程结构

- `VideoToLive/VideoToLiveApp.swift` — App 入口
- `VideoToLive/ContentView.swift` — 单页面 UI + PHPicker 封装
- `VideoToLive/LivePhotoConverter.swift` — 转换核心逻辑（裁剪 / 关键帧 / 配对元数据 / 存相册）
- `VideoToLive/Info.plist` — 含相册权限中文说明
- `VideoToLive.xcodeproj/` — 工程文件（含共享 scheme `VideoToLive`）
- `gen_pbxproj.py` — 生成 `project.pbxproj` 的脚本
- `codemagic.yaml` — Codemagic 构建配置

Bundle ID：`com.zhy8416503.videotolive`，最低支持 iOS 17.0。
