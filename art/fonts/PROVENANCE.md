# 中文字体与许可

## 2026-10-08：标题、阅读与数值分层

当前 `ShellTheme` 使用 **Noto Serif CJK SC Medium** 显示标题、叙事和普通正文，
**Noto Sans CJK SC Medium** 显示按钮、选项、输入、数字卡片。正文仍为 22px、辅助文字最低 18px；
统一行距与单像素阴影。两款均为官方完整 SC OTF，没有子集化、轮廓修改或合成加粗。
旧 Regular 文件保留供既有资源/历史打包工具使用，不再作为共享主题默认字体。

官方来源：[Noto CJK](https://github.com/notofonts/noto-cjk)，固定提交
`f8d157532fbfaeda587e826d4cd5b21a49186f7c`。下载路径：

- `Serif/OTF/SimplifiedChinese/NotoSerifCJKsc-Medium.otf`
- `Sans/OTF/SimplifiedChinese/NotoSansCJKsc-Medium.otf`
- 同目录树的 `Serif/LICENSE`、`Sans/LICENSE` 原样保存为 `LICENSE-noto-serif.txt`、`LICENSE-noto-sans.txt`。

| 文件 | 大小 | SHA-256 |
| --- | --- | --- |
| `NotoSerifCJKsc-Medium.otf` | 24,805,308 B | `19322be2ecf5dd2abd546db7a86cc83c286026cbd28593583bfcfd721e48c9fe` |
| `NotoSansCJKsc-Medium.otf` | 16,523,632 B | `ca094f6b0001fb048ca39ddd797a0cdb0179e1e55c6561e111c49c3e6a61d7b7` |

字体内置版权信息：Serif 为 “© 2017-2024 Adobe (http://www.adobe.com/).”；
Sans 为 “© 2014-2021 Adobe (http://www.adobe.com/).”。
许可为 SIL OFL 1.1，允许随游戏再分发；完整许可和字体内版权元数据一起保留。
两平台导出均包含 `LICENSE-noto-*.txt`。Godot 导入关闭系统字体回退，避免开发机字体掩盖缺字；
`tests/unit/test_ui_style_r13.gd` 检查正式源码与内容中的汉字覆盖及常用交互符号。

## 原 Regular 字体的历史来源


2026-09-14。本目录是正式非战斗界面共享主题的唯一字体来源。ShellTheme.create() 只从这里加载字体，
不依赖开发机字体，也不使用 SystemFont。

## 随包文件

| 文件 | 大小 | SHA-256 |
| --- | --- | --- |
| NotoSansCJKsc-Regular.mib-repack.otf | 16,212,088 B | b115de38dda5236658f168bb8ef522f9fbc5262f401eb68b45847445728d83af |
| NotoSansCJKsc-Regular.mib-repack.otf.import | Godot导入配置；主线程关闭系统回退 | 指向 res://.godot/imported/...-24f5e26e539ee27fe6a7a9e4ec57478b.fontdata |
| LICENSE-noto-cjk.txt | 14,712 B | 849f4ea9c214fa4ac3593b770c699f387534b11ce671264c1b10d85bdcb5997b |

## 上游来源

- 本机安装文件：/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc
- 大小 19,484,784 B，SHA-256 b76b0433203017ca80401b2ee0dd69350349871c4b19d504c34dbdd80541690a
- Debian 包：fonts-noto-cjk 1:20240730+repack1-1build1
- 上游项目：https://github.com/notofonts/noto-cjk

该文件是 TrueType 集合，含 10 个字面（fc-scan 实测）：

| index | 字面 |
| --- | --- |
| 0 | Noto Sans CJK JP |
| 1 | Noto Sans CJK KR |
| 2 | Noto Sans CJK SC（本次打包的字面） |
| 3 / 4 | Noto Sans CJK TC / HK |
| 5-9 | Noto Sans Mono CJK JP/KR/SC/TC/HK |

## 字面选择

从源集合提取 index 2（Noto Sans CJK SC）为独立单面 OTF，避免字体集合默认选到 JP 字面。可维护的重打包及字节比对入口见下方命令。

## 许可（本地原文，未凭记忆推断）

LICENSE-noto-cjk.txt 是 /usr/share/doc/fonts-noto-cjk/copyright 的逐字节副本（cmp 通过，SHA-256 相同）。
适用条款：

```
第 213 行  Files: *
第 214 行  Copyright: 2010-2012, Google Corporation
第 215 行  License: SIL-1.1
```

SIL Open Font License 1.1 全文在该文件第 223-313 行。OFL 允许再分发与修改（含子集化），要求版权声明与
许可随字体一同分发：本目录已同时包含两者。Debian 版权文件中未声明 Reserved Font Name；本次仍把派生文件
明确标注为 mib-repack，不冒用上游发行文件名。

## 重打包方式

```bash
python3 tools/art_pipeline/repack_ui_font.py          # 生成
python3 tools/art_pipeline/repack_ui_font.py --check  # 只比对，不写盘
```

- 子集工具：本机已装的 libharfbuzz-subset0 12.3.2-2（ctypes 调用 hb_subset_or_fail）。本机没有
  fontTools / hb-subset CLI / fontforge，也没有下载任何东西。
- flags = 8（HB_SUBSET_FLAGS_NAME_LEGACY），保留原始 name 表条目。
- 字符集保留依据：源字面 2 的整张 cmap 全集，不是人工挑选的常用字表。脚本用 hb_face_collect_unicodes
  读出源字面全部码位后原样请求，因此没有砍掉任何该字面本可绘制的字。
- 实测：源字面 65,535 字形 / 44,810 码位；打包含 64,568 字形 / 44,810 码位。字形数少 967 是因为
  harfbuzz 去掉了 cmap 与排版闭包之外的不可达字形，码位覆盖完全一致。
- 若要改小体积：--charset-file <UTF-8 文本> 可只保留该文本覆盖的字符（脚本已支持，未用于本次交付）。

## 已知风险与缺口

- 正式导入参数为`allow_system_fallback=false`，杜绝系统字体掩盖缺字问题。随包字面保留上游SC字面的44,810个码位，不能概括为Unicode全部CJK；以后出现该cmap之外的新字符必须补合规fallback字体或替换符号，并重跑字形检查。
- 不随包字重：只打包 Regular。此包只提供 Regular 字面，不声明包含独立 Bold 字面。
- 体积：16.2 MB 未压缩源文件（导入后 14.2 MB）。这是完整 SC 字面这一取向的直接代价；若日后接受子集，
  可用上面的 --charset-file 缩小，并须重新验收缺字风险。
