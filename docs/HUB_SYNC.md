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

## 本地数据库

数据库版本由 14 升至 15。升级新增 `hub_outbox`（按 entity/key 合并）和 `hub_sync_state`，不清理既有收藏、进度、站点或媒体快照。
