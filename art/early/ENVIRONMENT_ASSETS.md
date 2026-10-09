# 前期环境预备资产

状态（2026-09-10）：已接入当前纵向切片。标题页读取启动背景与动效帧带，基地读取全景，契约页和设施页读取四个工作台切图；预览图仍只供评审。

| 素材 | 当前读取端 |
|---|---|
| `boot/title_background.png`、`boot/title_fx_sheet.png` | `src/presentation/title_screen.gd` |
| `base/base_hub.png` | `src/presentation/base_hub_screen.gd` |
| `base/stations/contract_desk.png` | `src/presentation/contract_screen.gd` |
| 其余三个 `base/stations/*.png` | `src/presentation/facility_screen.gd` |

## 启动背景动图

- `boot/title_background.png`：`1280×720` 不透明静态底图；保留大片黑色标题安全区。
- `boot/title_fx_sheet.png`：`2560×448` RGBA 帧带，横向 8 帧，每帧 `320×448`。
- FX 绘制位置：`(480, 96)`；播放速度：`6 fps`；循环。
- 取帧区域：`Rect2(frame_index * 320, 0, 320, 448)`。
- `boot/title_background_preview.gif`：历史 `640×360` 循环预览，已从工作树移除；不作为 Godot 运行时资源。

动效只包含阈门巨像中央门缝的紫色呼吸，不移动背景、游侠或 UI，因此可以随时关闭，也不会影响玩法状态。

## 基地

- `base/base_hub.png`：`1280×720` 完整六功能点基地，无玩家、无 UI。
- 四个开局核心功能点保持明亮可辨：契约台、装备/符文台、命运锻造台、训练木桩与战报。
- 代理舱和不朽祭坛在全景中保持关闭/封印，只作为未来目标，不暗示开局已经解锁。
- 中央区域留空，用于玩家、交互标记或功能卡片。

## 主要工作台

`base/stations/` 内四张文件均为 `128×128` RGBA、真实透明背景：

- `contract_desk.png`
- `equipment_rune_desk.png`
- `destiny_forge.png`
- `training_report.png`

它们可以用于工作台详情页、交互按钮或后续模块化基地。`base/stations_preview.png` 是四件素材的无文字总览，已从工作树移除，不应在运行时加载。

## 生产约束

- 所有运行时 PNG 已降到实际尺寸，并经过 nearest-neighbor 放大或透明底清理。
- 场景图限定到前期十色色板的相关子集；工作台每张最多使用七个实体色。
- 没有文字、公式、数值和可被误读为功能状态的装饰符号。
- 图像仅做表现层；manifest 中所有素材都允许缺失降级，不能进入权威状态或回放哈希。
- 完整元数据见 [`environment_manifest.json`](environment_manifest.json)，内建 ImageGen 提示词见 [`environment_prompts.md`](environment_prompts.md)。
