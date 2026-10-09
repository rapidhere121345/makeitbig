# Tailscale 发布页

当前状态是“配置已准备，未实际上线”。2026-10-09 的容器内探测确认：没有 tailscale 或 tailscaled，没有 `/dev/net/tun`，当前用户是 uid 1000；项目目录是宿主机 bind mount，宿主机可在确认路径后读取 `build/releases/`。

## 容器内准备

在既有 `makeitbig-paseo` 容器内执行：

```bash
./scripts/release.sh all
./scripts/release.sh verify --deep
./deploy/tailscale/validate.sh
./deploy/tailscale/stage_release_page.sh --check
```

`release.sh all` 将页面、索引、校验清单和最近 20 个 build 写入 `build/releases/`。`stage_release_page.sh` 只校验这个唯一静态发布根，并确认最新 build 同时有 Linux 与 Windows 下载；它不会复制另一份二进制，也不会修改容器或宿主机网络。`MIB_RELEASE_STAGING_DIR` 如果被设置，必须解析到与 `MIB_RELEASE_ROOT` 相同的目录。

可选的容器 HTTP 服务用于宿主机端口代理：

```bash
./deploy/tailscale/serve_release_page.sh
```

它以非 root 用户在 `0.0.0.0:8080` 提供 `build/releases/`。宿主机必须已经以 `127.0.0.1:8080:8080` 发布容器端口，项目脚本不会重建容器或修改端口。

## 宿主机实际上线

先在宿主机确认 bind mount 的真实路径。默认示例使用 `/paseo-makeitbig/project`；不一致时设置 `MIB_RELEASE_HOST_ROOT`。确认宿主机能看到 `build/releases/index.html` 后，在宿主机执行：

```bash
MIB_RELEASE_HOST_ROOT=/paseo-makeitbig/project ./deploy/tailscale/serve_host.sh.example serve
```

该命令把完整发布页作为静态根暴露，因此首页可以浏览最新 build 和历史 build，并提供两个平台的下载。访问地址由 `tailscale serve status` 显示。关闭配置：

```bash
./deploy/tailscale/serve_host.sh.example off
```

`serve_host.sh.example` 只能在有 Tailscale 客户端的宿主机执行；容器内执行会失败，这是边界设计。

## funnel 与访问控制

`funnel` 会把下载页公开到互联网，页面没有额外鉴权；只有在 tailnet policy、节点证书、ACL 和未签名二进制风险完成审查后，才由宿主机明确执行：

```bash
./deploy/tailscale/serve_host.sh.example funnel
```

默认使用 `serve`。tailnet-only 访问权限由 Tailscale ACL 控制。不要把项目根目录作为 serve 目标，只暴露 `build/releases/`。

## 上线前清单

- `release.sh all`、`release.sh verify --deep`、`deploy/tailscale/validate.sh` 和 `stage_release_page.sh --check` 通过。
- `build/releases/index.json` 的最新 build 同时列出 Linux 与 Windows，且 `SHA256SUMS` 与 metadata 校验通过。
- 宿主机确认发布根路径与 bind mount 一致，`tailscale serve status` 指向 `build/releases/`。
- tailnet 内能打开首页、浏览历史 build，并下载两个平台文件。
- 没有执行容器、宿主机、OCX 或 Jingwei 重启；本目录的容器脚本不会执行这些操作。
# 当前发布地址

Tailnet-only：<https://rapidhere-home.tail99c4e8.ts.net:8448>。

该地址由宿主机 Tailscale Serve 指向项目的 `build/releases/`；容器内不运行 `tailscaled`。
