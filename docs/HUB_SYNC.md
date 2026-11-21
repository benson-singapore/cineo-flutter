# Cineo Hub 同步（Flutter）

设备通过 Hub API 契约 v1.0.2 发起同步。设备 token 与云端 TMDB Key 保存在 `flutter_secure_storage`；PIN 仅用于绑定请求。错误只展示安全业务消息，不记录凭证、TMDB Key 或完整站点地址。

## 触发矩阵

| 操作 | 请求 | Trigger | 行为 |
| --- | --- | --- | --- |
| 应用冷启动 | 拉取 | `launch_pull` | 增量拉取并应用远端记录、TMDB Key 与偏好；失败不自动重拉 |
| 设置页立即拉取 | 拉取 | `manual_pull` | 仅拉取并应用，不推送 |
| 播放进度自动更新 | 推送 | `auto_progress` | 按本机配置间隔检查，只推当前播放进度单信封；位置无变化不发 |
| 收藏变化 | 推送 | `auto_favorite` | 每媒体键 2 秒防抖合并，只推最后状态；取消收藏推墓碑 |
| 失败退避重试 | 推送 | `retry` | 只重试推送，不拉取；服从 Retry-After 和指数退避 |
| 设置页推送全部 | 分批推送 | `full_push` | 本机站点、历史、收藏和进度入队，逐批推送；冲突以较新的为准 |
| 设置页推送并拉取 | 推送后拉取 | `full_push` / `manual_pull` | 两个独立请求顺序执行 |
| 进入后台 | 尽力推送 | `auto_progress` | 尽力提交 outbox；系统可能暂停或终止请求。该头在后台场景表示自动推送，因为契约没有独立后台 trigger |
| 从后台回前台 | 无 | — | 不自动拉取 |

Push 与 pull 互不触发。推送只发送 outbox；拉取只取回并应用远端数据，TMDB Key 与偏好仍由云端管理，不上传 setting 实体。进度间隔候选为 5/10/15/30/60 秒，默认 10 秒，最小 5 秒；设置保存在本机 `shared_preferences`，不进入同步数据。

## 记录与冲突

实体键遵循 `docs/api-contract/DECISIONS.md` 与 `site-sourcekey-vectors.json`。站点以规范化 API URL 的 SHA-256 sourceKey 为键；不上传 demo 或设备诊断字段。冲突按 `updated_at` 较新优先、删除优先、`device_id` 字典序处理。未知 `site_type` 保留在 `hub_sync_state`，不转换为可用来源。

40900 触发 rebuild；重建前 outbox 暂停，用户确认后才按当前本机记录重建队列。Hub 请求失败时保留待推送记录并按指数退避重试（上限 5 分钟，尊重 Retry-After）。若单条自动推送与另一个推送任务重叠，当前调用明确失败并保留已入队数据；后续自动周期、后台尝试或手动推送会再次处理。Hub 不可用时错误不会中断媒体浏览或播放。

## 手机与电视播放记录约定（本地实现，待双端联机验收）

同一来源使用 API 地址规范化后的 SHA-256 `sourceKey`，来源的影片 ID 使用 `vodId`。键中的组件按 UTF-8 百分号编码。新 `history` 键为 `sourceKey:vodId`；剧集 `progress` 键为 `sourceKey:vodId:lineName:episodeIndex`。`episodeIndex` 从 0 开始，采用来源原始线路中的位置，空条目仍占位置；客户端本地的 `episodeNumber` 从 1 开始。线路重名、来源或集序无法唯一确认时不得猜测。

新载荷携带 `source_api`、`video`，Flutter 同时携带 `source_key`；`video` 包含来源、影片 ID、标题、封面等，另有 `line_name`、`episode_title`、`episode_index`、`cineo_index_base: 0`、`position_ms`、`duration_ms`；可确认的媒体类型使用 `cineo_media_kind`。历史使用同一影片最新且可确认的记录；并列最新的歧义记录不自动选取。Hub 按用户、实体及准确键保存，保留写入时间并执行服务端冲突规则。两端各自独立保存 Orbit 插件历史，不进入默认历史。

接收方只在来源与影片键可确认且载荷身份不冲突时落库；电视端续播时重新从同一来源详情解析唯一线路及集序，不通过 Hub 传播播放地址。旧载荷的索引基准或来源无法确认时保留、不猜测；旧四段历史键和待删除记录不自动合并或清理。旧不可信待发记录可能暂缓推送，须在同步结果中提示。

以上约定与当前未提交代码对应，不表示已验证真实双端传输、关闭重开或设备续播。已知部分 TV 旧载荷缺可靠媒体类型，旧数据、真实设备及重试最终收敛仍需独立验证。

## 本地数据库

数据库版本由 14 升至 15。升级新增 `hub_outbox`（按 entity/key 合并）和 `hub_sync_state`，不清理既有收藏、进度、站点或媒体快照。
