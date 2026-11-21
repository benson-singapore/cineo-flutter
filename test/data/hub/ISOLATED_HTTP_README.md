# TV → Hub → Flutter 隔离 HTTP 测试

仅使用新建的本地测试数据库、独立 Android TV 模拟器。命令会删除测试 Hub 中的观看记录，禁止指向真实服务。三个仓库需保持同一待测源码状态。

1. 建立 `/tmp/cineo-e2e-*` 临时目录，在 Hub `server` 目录启动专用服务（下例目录需替换为新建目录）：

```sh
DB_PATH=/tmp/cineo-e2e-EXAMPLE/hub.db LISTEN_ADDR=127.0.0.1:18764 COOKIE_SECURE=false HUB_MASTER_KEY=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA= HUB_ADMIN_USERNAME=isolated HUB_ADMIN_PASSWORD=isolated-test-only go run .
```

2. 在 Flutter 仓库生成仅供此本地服务使用的凭据：

```sh
CINEO_ISOLATED_FIXTURE=/tmp/cineo-e2e-EXAMPLE/fixture.json python3 test/data/hub/prepare_isolated_hub.py
```

3. 用 OpenJDK 17 构建 TV debug 应用及设备测试包；仅安装到独立模拟器。按 `cineo-tv-os/app/src/androidTest/README.md` 的安装方式安装，接着执行：

```sh
adb -s <独立模拟器序列号> shell am instrument -w -r -e testHub http://10.0.2.2:18764 -e testPin "$(python3 -c 'import json;print(json.load(open("/tmp/cineo-e2e-EXAMPLE/fixture.json"))["tv_pin"])')" -e class 'com.nova.tv.WatchSnapshotInstrumentedTest#isolatedHubRealTvPush' com.nova.tv.test/androidx.test.runner.AndroidJUnitRunner
```

4. 确认输出 `OK (1 test)` 后，在 Flutter 仓库运行：

```sh
CINEO_ISOLATED_FIXTURE=/tmp/cineo-e2e-EXAMPLE/fixture.json flutter test --no-pub --reporter expanded test/data/hub/isolated_hub_http_test.dart
```

手机测试使用真实同步引擎及 HTTP，创建四个临时 SQLite 数据库，先拉取 TV 数据，再通过管理接口物理删除 Hub 历史并验证空快照删除及本地保护。每次重跑须使用全新 Hub 数据库、凭据和 TV 测试数据；执行后停止临时 Hub 和独立模拟器。
