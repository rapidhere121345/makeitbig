# 发布页与 build 规范

这里保存发布页模板和发布配置。运行产物在被 git 忽略的 build/releases，不会提交到源码仓库。

## 快速使用

完成容器构建和双平台导出后，在项目根目录执行：

    ./scripts/release.sh all
    ./scripts/release.sh verify --deep

子命令为 package、index、prune、site、verify、all。package 读取 build/current/linux/make-it-big.x86_64 与 build/current/windows/make-it-big.exe，生成 build 元数据和 SHA256SUMS；prune 默认保留最近 20 个；site 生成可以直接静态托管的 build/releases。

可用 MIB_RELEASE_ROOT 指定发布根。默认根必须在工作区内；只有明确设置 MIB_RELEASE_ALLOW_OUTSIDE=1 才允许使用工作区外的临时测试目录。

## 目录格式

默认 build ID 是 YYYYMMDD-HHMMSS-<git短SHA>，可用 package --id 指定：

    build/releases/
      index.html
      index.json
      app.js
      style.css
      builds/<build-id>/
        build.json
        SHA256SUMS
        linux/make-it-big.x86_64
        windows/make-it-big.exe

build.json 是单个 build 的元数据事实来源，记录提交、时间、平台路径、大小和 SHA256。缺少的平台会被明确记录；完全没有导出文件时必须显式传 --allow-empty。

prune 只处理 builds 的直接子目录，并且要求目录名匹配 build ID、存在有效 build.json、且不是符号链接。它不会递归清理其他目录。

## 安全边界

release/site 是提交到仓库的页面源文件；build/releases 是生成的站点根。发布脚本只读取 build/current，写入配置的发布根，不运行 Docker、不操作 Tailscale、不重启服务。Windows/Linux 文件未签名，公开分发前由运维决定是否增加签名和 ACL。
