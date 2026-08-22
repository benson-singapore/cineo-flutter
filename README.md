# Cineo

Cineo 是一个以本地数据为中心的 Flutter 影视发现与播放客户端。它支持配置多个视频源，从兼容 MacCMS 的 JSON API 获取影视目录、分类和播放地址，并提供搜索、详情、播放、收藏、观看进度、搜索历史、TMDB 数据增强和应用锁等功能。

> 当前应用入口默认使用内置演示媒体库启动。要加载真实站点，需要在应用的“视频源”页面添加或导入 API 视频源，并将其设为默认来源。

## 功能特性

- 首页影视内容分区、分类浏览和横向媒体列表
- 影视搜索、详情页、剧集与单集信息展示
- HLS（`.m3u8`）和 MP4 播放
- 多视频源管理：添加、编辑、启用/禁用、收藏、删除和连通性测试
- MacCMS 兼容 API：目录、分页、分类、详情和播放地址解析
- 粘贴导入 `api_site` 格式的 MacCMS 资源站 JSON 配置
- 默认视频源和同名影视的来源偏好记忆
- 收藏、观看进度、继续观看和搜索历史本地持久化
- TMDB 数据增强：海报、背景图、详情、演员、季和单集简介
- TMDB 元数据与图片磁盘缓存，可查看统计、清理过期缓存或清空缓存
- 应用锁 PIN、失败尝试退避锁定和后台返回宽限期
- 成人标记视频源单独管理，并由应用锁保护显示开关
- Android 画中画播放

## 技术栈

- Flutter / Dart
- Material 3
- `sqflite`：本地媒体状态、视频源、收藏和观看记录
- `shared_preferences`：非敏感的偏好设置
- `flutter_secure_storage`：应用锁验证信息和 TMDB Token
- `video_player`：视频播放
- `path_provider`：TMDB 缓存目录
- `url_launcher`：外部链接打开

## 环境要求

- Flutter SDK
- Dart SDK `>=3.1.5 <4.0.0`
- Android 项目使用 compile SDK 34
- iOS、Android 和 Web 工程已包含在仓库中

建议先确认本机环境：

```bash
flutter doctor
flutter --version
```

## 快速开始

安装依赖并运行开发版本：

```bash
flutter pub get
flutter run
```

指定设备运行：

```bash
flutter devices
flutter run -d <device-id>
```

常用构建命令：

```bash
# Android APK
flutter build apk

# Android App Bundle
flutter build appbundle

# iOS（需要 macOS 和 Xcode）
flutter build ios

# Web
flutter build web
```

## 配置视频源

打开应用的“视频源”页面，可以手动添加来源，也可以导入 MacCMS 兼容的 JSON 配置。

### 手动添加

支持以下来源类型：

| 类型 | 地址要求 | 用途 |
| --- | --- | --- |
| 直链 HLS / MP4 | 必须是以 `.m3u8` 或 `.mp4` 结尾的 HTTP(S) 地址 | 播放单个直链视频 |
| MacCMS 兼容 API | HTTP(S) API 地址 | 获取目录、分类、详情和播放地址 |
| JSON API | HTTP(S) API 地址 | 当前数据访问层按 API 来源处理，实际响应需满足已实现的 MacCMS JSON 结构 |

API 来源经过连通性测试后，才可以设置为默认视频源。默认来源负责首页、搜索和分类浏览；没有配置默认 API 来源时，应用会使用内置演示目录作为回退内容。

### 导入资源站配置

导入功能接受包含 `api_site` 的 JSON 对象，例如：

```json
{
  "cache_time": 7200,
  "api_site": {
    "example": {
      "name": "示例资源站",
      "api": "https://example.com/api.php/provide/vod/",
      "detail": "https://example.com",
      "is_adult": false
    }
  }
}
```

字段说明：

- `cache_time`：可选的正整数缓存时间，单位为秒。
- `api_site`：必填对象，键名会作为来源 ID。
- `name`：来源显示名称。
- `api`：来源 API 地址，必须包含主机名。
- `detail`：可选的站点详情地址。
- `is_adult`：可选布尔值，标记成人来源。

导入只解析和保存本地配置，不会在导入时访问站点。默认情况下建议使用 HTTPS；只有在确认站点可信且确实需要时，才在导入对话框中开启“允许 HTTP 站点”。视频源地址、播放地址和站点内容应仅用于你有权访问的服务。

## 配置 TMDB 数据增强

1. 在 TMDB 账户中创建 API Read Access Token。
2. 打开应用“设置”中的“TMDB 数据增强”。
3. 粘贴 Token 并保存。
4. 打开影视详情时，Cineo 会按标题、类型和年份匹配 TMDB 内容。

TMDB Token 通过 `flutter_secure_storage` 保存在本机，不会写入 URL，也不会在异常信息中输出。TMDB 详情、图片和人工匹配结果会写入应用支持目录下的 `cineo_tmdb_cache` 缓存目录，默认元数据缓存时间为 30 天；缓存内容可以在 TMDB 设置页管理。

## 本地数据

应用使用 SQLite 数据库保存本地状态，默认数据库文件名为 `cineo_local_media.db`。数据包括：

- 视频源配置及启用状态
- 默认来源、收藏来源和来源健康检查结果
- 收藏媒体与媒体展示快照
- 观看进度和继续观看记录
- 搜索历史
- 同一影视的来源选择偏好

应用锁不会保存明文 PIN，而是保存带随机盐的 PBKDF2 验证信息。连续输入错误会触发逐步延长的临时锁定。

## 项目结构

```text
lib/
├── core/
│   ├── demo/          内置演示媒体
│   ├── models/        媒体、视频源、TMDB 和分页模型
│   ├── platform/      平台能力，例如 Android 画中画
│   └── theme/         Cineo Material 3 主题
├── data/
│   ├── cache/         TMDB 文件缓存
│   ├── remote/        MacCMS、TMDB 和分类适配器
│   └── repositories/  本地状态与远程媒体仓库
├── features/
│   ├── app_lock/      应用锁和 PIN
│   ├── home/          首页
│   ├── library/       收藏与观看记录
│   ├── media_details/ 影视详情、剧集和单集
│   ├── player/        视频播放
│   ├── profile/       个人页
│   ├── search/        搜索与分类浏览
│   ├── settings/      通用、TMDB 和缓存设置
│   └── sources/       视频源管理与配置导入
└── shared/widgets/    公共媒体卡片、图片和内容状态组件
```

测试代码位于 `test/`，覆盖数据解析、缓存、视频源导入、仓库、应用锁和主要页面组件。

## 测试与静态检查

运行全部测试和代码分析：

```bash
flutter test
flutter analyze
```

运行单个测试文件：

```bash
flutter test test/mac_cms_client_test.dart
flutter test test/features/home/home_screen_test.dart
```

格式化 Dart 代码：

```bash
dart format lib test
```

## 平台说明

- Android 声明了网络访问权限，并通过原生 `MethodChannel` 提供画中画能力。
- iOS 当前包含基础 Flutter Runner 配置；画中画能力的实现主要位于 Android 原生入口。
- Web 工程可构建，但 `sqflite`、安全存储和部分平台能力是否可用取决于所使用的 Flutter 插件实现与运行环境。
- Android 本地构建会自动生成自签名 keystore；iOS 构建默认生成未签名 IPA，企业签名在下载后进行。

## 自动版本与 GitHub Actions 构建

仓库提供 `Makefile` 和 `.github/workflows/cineo-build.yml`，用于统一版本号、本地构建和 GitHub Actions 构建。

最简单的发布方式：

```bash
make help
```

先打开 `Makefile` 顶部，维护公开版本和内部构建号：

```make
VERSION := 1.0.3
BUILD_NUMBER := 4
```

以后每次只执行一条命令：

```bash
make publish
```

`VERSION` 是公开版本号，格式为 `主版本.次版本.修订版本`，例如 `1.0.3`；`BUILD_NUMBER` 是 Android/iOS 内部构建号，必须为正整数。

`make publish` 会自动拉取远程 `main` 的最新提交，将版本同步到 `pubspec.yaml`，提交并推送 `main`，然后创建 `v1.0.3` 这样的 tag。GitHub Actions 监听 `v*` tag，收到 tag 推送后自动构建并发布到对应的 GitHub Release。

如果要沿用当前公开版本重新打包，必须明确执行 `make publish REBUILD=1`；此时会移动同名 tag 并更新 Release 附件。新版本发布不会覆盖已有 tag。

历史上的 `v1.0.0+1`、`v1.0.0+2`、`v1.0.0+3` tag 保留不变；从 `v1.0.3` 开始，公开版本 tag 不再包含 `+构建号`。Flutter 内部仍使用 `pubspec.yaml` 中的 `1.0.3+4`，其中 `+4` 仅作为 Android/iOS 构建号。

如果当前工作区有除 `Makefile` 和目标更新说明以外的未提交文件，命令会停止，避免把未完成的修改发布出去。

`make android` 首次运行会在 `android/app/release/cineo-release.keystore` 生成一个本地 Android 自签名证书，并在 `android/key.properties` 保存构建配置。这两个文件已加入 `.gitignore`，不会提交到仓库。请务必备份 keystore 和密码；以后更新 Android 应用必须继续使用同一个 keystore，否则系统会把它识别为不同的应用，无法覆盖升级。

GitHub Actions 由版本 tag 推送自动触发，不需要 `GH_TOKEN`、GitHub API 或额外的 Actions 权限配置：

```bash
make publish
```

Actions 会上传两个构建产物：

- Android：`app-release.apk`。如果 GitHub Secrets 中没有 Android 签名信息，工作流会为本次构建生成临时自签名 APK；这种 APK 只适合测试，后续版本不能依赖这个临时证书覆盖升级。
- iOS：`Cineo-unsigned.ipa`。这是未经过 Apple 签名的 IPA，适合下载后使用企业账号或其他合法 Apple 签名流程重新签名。没有 Apple Developer 账号时，无法生成可直接安装或可发布的 Apple 签名 IPA。

如果希望 GitHub Actions 使用固定的 Android 发布证书，可在仓库 Settings → Secrets and variables → Actions 中配置：

| Secret | 内容 |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | `cineo-release.keystore` 的 Base64 内容 |
| `ANDROID_KEYSTORE_PASSWORD` | keystore 密码 |
| `ANDROID_KEY_PASSWORD` | key 密码 |
| `ANDROID_KEY_ALIAS` | key alias，默认本地脚本使用 `cineo` |

在 macOS 本地构建无签名 IPA：

```bash
make ios
```

输出路径为 `build/ios/unsigned-ipa/Cineo.ipa`。GitHub Actions 的输出可从对应 workflow run 的 Artifacts 下载。iOS 的 bundle identifier 当前是 `com.benson.cineo.cineoFlutter`，使用企业账号签名时需要使用与你账号和分发配置匹配的 App ID/profile。

## 版本信息

当前应用版本定义在 `pubspec.yaml`，格式为 `公开版本+内部构建号`，例如 `1.0.3+4`。发布前请同步更新版本号、应用签名、包名以及对应平台的商店配置。

## 许可证

当前仓库未声明开源许可证。除非项目维护者另行授权，请不要将本项目或其附带的媒体源配置、图片和第三方内容用于未经许可的分发。
