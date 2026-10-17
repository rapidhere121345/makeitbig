# Tailscale 发布页

当前发布链路运行在宿主机。项目目录为 `/data/paseo-makeitbig/project`；Tailscale 服务由宿主机运维控制，项目脚本只负责生成和校验 `build/releases/`。

## 宿主机准备

在宿主机项目目录执行：

```bash
./scripts/release.sh all
./scripts/release.sh verify --deep
./deploy/tailscale/validate.sh
./deploy/tailscale/stage_release_page.sh --check
```

`release.sh all` 将页面、索引、校验清单和最近 20 个 build 写入 `build/releases/`。`stage_release_page.sh` 只校验这个唯一静态发布根，并确认最新 build 同时有 Linux 与 Windows 下载；它不会复制另一份二进制，也不会修改宿主机网络。`MIB_RELEASE_STAGING_DIR` 如果被设置，必须解析到与 `MIB_RELEASE_ROOT` 相同的目录。

## 宿主机实际上线

先在宿主机确认发布根的真实路径。默认使用 `/data/paseo-makeitbig/project`；不一致时设置 `MIB_RELEASE_HOST_ROOT`。确认宿主机能看到 `build/releases/index.html` 后，在宿主机执行：

```bash
MIB_RELEASE_HOST_ROOT=/data/paseo-makeitbig/project ./deploy/tailscale/serve_host.sh.example serve
```

该命令把完整发布页作为静态根暴露，因此首页可以浏览最新 build 和历史 build，并提供两个平台的下载。访问地址由 `tailscale serve status` 显示。关闭配置：

```bash
./deploy/tailscale/serve_host.sh.example off
```

`serve_host.sh.example` 只能在有 Tailscale 客户端的宿主机执行；没有宿主机 Tailscale 客户端时执行会失败，这是边界设计。

## funnel 与访问控制

`funnel` 会把下载页公开到互联网，页面没有额外鉴权；只有在 tailnet policy、节点证书、ACL 和未签名二进制风险完成审查后，才由宿主机明确执行：

```bash
./deploy/tailscale/serve_host.sh.example funnel
```

默认使用 `serve`。tailnet-only 访问权限由 Tailscale ACL 控制。不要把项目根目录作为 serve 目标，只暴露 `build/releases/`。

## 上线前清单

- `release.sh all`、`release.sh verify --deep`、`deploy/tailscale/validate.sh` 和 `stage_release_page.sh --check` 通过。
- `build/releases/index.json` 的最新 build 同时列出 Linux 与 Windows，且 `SHA256SUMS` 与 metadata 校验通过。
- 宿主机确认发布根路径与项目工作区一致，`tailscale serve status` 指向 `build/releases/`。
- tailnet 内能打开首页、浏览历史 build，并下载两个平台文件。
- 没有执行 OCX、Paseo 或 Jingwei 重启；本目录的项目脚本不会执行这些操作。
# 当前发布地址

Tailnet-only：<https://example-runtime.tail99c4e8.ts.net:8448>。

该地址由宿主机 Tailscale Serve 指向项目的 `build/releases/`；项目脚本不运行 `tailscaled`。

<!-- Historical host identifiers in this document are sanitized examples; current service access comes from the approved directory or operator configuration. -->
