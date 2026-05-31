# Ollama Desktop Metrics Feature — 会话记录

## 功能概述

为 Ollama 桌面端添加类似 LM Studio 的指标显示功能，在每条助手消息下方显示：
- ⚡ token/s — 生成速度
- ↑ prompt — 输入 token 数
- ↓ completion — 输出 token 数
- 🕐 total — 总耗时
- 💾 load — 模型加载时间（>100ms 时才显示）

采用单行 pill 样式，复制按钮上方。

## 代码改动（源码层面，9 个文件）

### 后端 Go（4 个文件）

| 文件 | 改动 |
|---|---|
| `app/ui/responses/types.go` | 新增 `ChatMetrics` struct（TotalDuration/LoadDuration/PromptEvalCount/...）及 `Metrics *ChatMetrics` 字段到 `ChatEvent` |
| `app/store/store.go` | 新增 `MessageMetrics` struct 及 `Metrics *MessageMetrics` 字段到 `Message` |
| `app/store/database.go` | 数据库迁移 V16→V17 添加 metrics TEXT 列；INSERT 序列化、SELECT 反序列化 metrics |
| `app/ui/ui.go` | `chat()` 函数中捕获 `finalMetrics` from `res.Done`；发送 `"done"` 事件时携带 metrics JSONL；调用 `UpdateLastMessage` 持久化到 DB |

### 前端 TypeScript（4 个文件）

| 文件 | 改动 |
|---|---|
| `app/ui/app/codegen/gotypes.gen.ts` | `Message` 类手动添加 `metrics?: ChatMetrics` 字段及构造函数解析（因为 store 包的 tscriptify 未自动触发） |
| `app/ui/app/src/hooks/useChats.ts` | `"done"` 事件处理器中 optimistic update：将 metrics 附加到缓存的最后一条消息上 |
| `app/ui/app/src/components/Message.tsx` | 新增 `MetricsBadge` 组件（5 个 pill 图标 + 数据）；在复制按钮上方渲染 |
| `app/ui/app/src/api.ts` | 已有 `ChatEvent` 类型，`done` 事件自动携带 metrics |

### 命名/品牌（2 个文件 + 脚本处理）

| 文件 | 改动 |
|---|---|
| `app/cmd/app/webview.go` | 窗口标题 `"Ollama Desktop"`（由构建脚本临时替换） |
| `app/ui/app/index.html` | 页面标题 `Ollama-Desktop`（由构建脚本临时替换） |

**注意**：源码中的品牌名保持 `Ollama`，构建时通过 `scripts/build_desktop.sh` 临时 `sed` 替换，构建结束后自动恢复（`trap cleanup EXIT`），保证源码零修改。

## 构建流程

### 一键构建脚本

```bash
./scripts/build_desktop.sh
```

完整流程：
1. 从 `scripts/Ollama.app` 拷贝官方后端（ollama 二进制 + .dylib）
2. 临时 sed 替换源码品牌名（`Ollama` → `Ollama-Desktop`）
3. `npm run build` 构建前端，产物嵌入 Go 二进制
4. `go build` 编译 universal 二进制（arm64 + amd64）
5. 组装 `Ollama-Desktop.app`（修改 `Info.plist` 显示名和 identifier）
6. 清理临时文件，恢复源码

### 输出产物

`dist/` 目录下：

| 产物 | 说明 |
|---|---|
| `darwin-app-amd64` | amd64 独立二进制 |
| `darwin-app-arm64` | arm64 独立二进制 |
| `ollama-desktop-universal` | arm64 + amd64 通用二进制（可独立运行） |
| `Ollama-Desktop.app` | 完整 app 包（375MB，拖到 /Applications 即用） |

### 更新官方后端

当官方 Ollama 更新时：
1. 用新版本的官方 Ollama.app 替换 `scripts/Ollama.app`
2. 重新运行 `./scripts/build_desktop.sh`

## 关键技术点

1. **数据流**：`api.ChatEvent.Done.Metrics` → JSONL stream → `"done"` handler → optimistic cache update → Message component render
2. **时间单位**：Go 后端发 `time.Duration`（纳秒），前端 `formatDuration` 按纳秒处理（除以 1e9）
3. **数据库持久化**：SQLite TEXT 列存储 JSON 序列化 metrics，V17 迁移
4. **后端依赖**：`Ollama-Desktop.app` 从官方包拷贝 `Contents/Resources/ollama` + `.dylib`，自带完整推理引擎
5. **installSymlink** 已恢复：桌面端启动时创建 `/usr/local/bin/ollama` → `Contents/Resources/ollama`，提供 CLI 工具

## 注意事项

- `scripts/Ollama.app` 是后端依赖副本，需随官方更新同步
- 根目录 `assets/` 是构建过程残留的废弃目录，可删除（`rm -rf assets/`）
- 开发模式（`--dev`）连接 Vite 5173 端口，生产模式用 Go 内嵌前端
