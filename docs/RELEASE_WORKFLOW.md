# 发布工作流

发布源文件与页面模板放在 `release/`，发布脚本是 `scripts/release.sh`。构建产物放在被 git 忽略的 `build/releases/`，不会进入源码提交。

## 目录和命名

`release.sh package` 从 `build/current/linux/make-it-big.x86_64` 与 `build/current/windows/make-it-big.exe` 读取导出文件，创建一个按时间排序的 build 目录。默认 build ID 是 `YYYYMMDD-HHMMSS-<git短SHA>`，也可以用 `--id` 明确指定。每个 build 至少包含：

- `build.json`：构建 ID、提交、时间、平台文件、大小和 SHA256。
- `linux/make-it-big.x86_64`：Linux x86_64 下载文件。
- `windows/make-it-big.exe`：Windows x86_64 下载文件。
- `SHA256SUMS`：下载文件的校验清单。

`index` 会在 `build/releases/index.json` 生成新到旧的索引；`site` 将页面模板、样式、脚本和索引写入同一发布根，因此 `build/releases/` 可以直接作为静态站点根。缺少某个平台文件时，元数据会明确标记，页面不应把不存在的文件伪装成可下载。

## 固定命令

```bash
./scripts/container_build.sh
./scripts/release.sh all
./scripts/release.sh verify
```

`all` 按 package → prune → index → site → verify 执行。`prune` 默认保留最近 20 个带有效 `build.json` 且名称符合 build ID 规则的目录，只删除 `build/releases/` 的直接子目录；它不会递归清理其他路径。需要测试其他位置时显式设置 `MIB_RELEASE_ROOT`，并先确认该目录内容。

## Tailscale 上线

容器只负责生成和校验文件：

```bash
./deploy/tailscale/stage_release_page.sh
```

该脚本校验 `build/releases/` 这一唯一静态发布根，并要求最新 build 同时包含 Linux 和 Windows 下载。历史 build、索引和页面资源都由 `release.sh all` 写入同一目录，Tailscale 不再使用另一套单 build 页面。因为当前容器没有 Tailscale 客户端/TUN，实际暴露由宿主机执行 `deploy/tailscale/serve_host.sh.example serve` 完成；宿主机必须先确认 bind mount 的路径与发布根可见。默认入口是 tailnet-only `tailscale serve`，监听节点 HTTPS；`funnel` 属于公开互联网暴露，必须单独检查 tailnet policy、ACL 和未签名二进制风险。

若宿主机不能直接看到 bind mount，才考虑容器 HTTP 服务路径：容器服务绑定 8080，宿主机以 `127.0.0.1:8080:8080` 发布后再让 Tailscale serve 代理 `127.0.0.1`。这需要宿主机按 Paseo 的容器生命周期流程重建或更新端口映射；项目脚本不会执行这一步。

上线前至少确认：`./deploy/tailscale/validate.sh` 和 `./deploy/tailscale/stage_release_page.sh --check` 通过、发布根不包含源码、宿主机 `tailscale serve status` 指向 `build/releases/`、tailnet 内能打开 `/` 并下载两个平台文件。发布页只提供下载，不承担账号鉴权；访问控制由 Tailscale tailnet/ACL 负责。
# 当前发布入口

Tailnet-only 发布页：<https://rapidhere-home.tail99c4e8.ts.net:8448>。

静态发布根固定为 `build/releases/`，由宿主机 Tailscale Serve 暴露；容器内不运行 `tailscaled`。
