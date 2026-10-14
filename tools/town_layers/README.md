# 镇区离线图层与原生空间派生

运行输入是 `content/rooms/town/hearthside.tscn`、同目录的
`hearthside.spatial.json` 和 `layers/`。运行时读取原生节点与离线 PNG；
`TownPresenter` 接收快照，与静态节点共用 `WorldPresenter.SortRoot`。

## 输入与转换参数

| 输入 | 实际尺寸 / SHA256 |
| --- | --- |
| `art/production/p1/hamlet_town/town.png` | 1536 × 1024；`fa5d79265d233d9d013c097df44bc810419a31d41e8b756e1b3daf6c42186ee5` |
| 同目录 `layout.json` | world = 1536 × 960；`8f740098d326fd312a0d6463332c5a7d587ed8ae77af0465ff40dbbbb39e1dd3` |

`bake.py` 用 Pillow `Image.Resampling.NEAREST` 一次性把源图转换至
1536 × 960（X 比例 1，Y 比例 15/16）。UV 点按 `(u × 1536, v × 960)`
映射到该 world。图层 ownership 使用 `foreground` 的作者多边形，按
`(feet_uv.y, id)` 排序；后一个 owner 覆盖交叠部分，每个像素只归一层。

`ground.png` 仅保留 owner=0 的原始像素；每个 native PNG 仅保留自己的
ownership，crop 为该 mask 的包围盒。PNG 使用 RGBA、`compress_level=9`。
feet 保留作者的 world 浮点坐标；原生 Sprite2D 的 position=feet，
offset=`crop.xy - feet`，centered=false。manifest 记录源文件及各产物 SHA、
source/world 尺寸、feet、crop、interaction 和 owned_pixels。

未归属某层的区域为 RGBA `(0,0,0,0)`。`unknown_underplate="transparent"`，
`supports_cutaway=false`，`supports_fade=false`；当前输入没有可证明的
clean plate，静态 native 永久参与渲染。遮挡来自共享 Y 排序。

## 原生玩法坐标规则

`--author-scene` 是一次性的作者数据转换入口：生成静态几何、边界、
插槽与路线节点。转换后 `.tscn` 是玩法作者来源；后续编辑原生 scene
时，直接派生 spatial manifest。再次使用 `--author-scene` 会覆盖原生
scene，应只在明确需要重新转换输入时使用。

`TownSceneRoot.derive_spatial_manifest()` 对静态多边形顶点、圆心及作者
插槽/路线用 `_pair()` 的 `snappedf(component, 1.0 / 64.0)`；圆半径也用
`snappedf(radius, 1.0 / 64.0)`。多边形在原生坐标中三角化，再将输出顶点
snapping，舍弃 snapping 后退化的三角形。spatial manifest 是此规则的派生
产物；装载时不自动修复不一致的 manifest。

外边界由原生 `MovementBoundary` 的 `Rect2(14,14,1508,932)` 直接输出，
四个整数不变。1/64 规则用于作者玩法数据派生；每 tick 的 actor feet
保留 registry 的浮点运动结果。`TownPresenter.camera_world_offset()` 的
`floor()` 仅影响表现，不写回 registry。

2026-10-14 当前文件精度审计：比较 Godot 实际加载的原生 Vector2
（float32）与静态 manifest 坐标；圆半径比较 metadata 的 float64 值。
共检查 226 个静态作者点、22 个圆，派生结果有 162 个碰撞形状。

| 误差 | 当前最大值（px） |
| --- | ---: |
| X 分量 | 0.0018310546875 |
| Y 分量 | 0.00048828125 |
| 任一分量 | 0.0018310546875 |
| 点的欧氏距离 | 0.0018673166632652283 |
| 圆半径 | 0.0003599999999996939 |

理论 rounding 上限为每分量和半径 `1/128 px`、点的欧氏距离
`sqrt(2)/128 px`。这些是几何数据的误差，不是像素重组误差。

## 生成与只读检查

```bash
python3 tools/town_layers/bake.py --check
```

该命令检查 SHA、ownership、逐像素重组和临时目录冷生成。已有前任验证
报告：35 native / 1,474,560 pixels，ownership=once，recomposition=exact，
cold_bytes=identical。本次收口未重复运行此检查。

需要明确再生成图层时：

```bash
python3 tools/town_layers/bake.py
```

需要一次性重做作者输入转换时，使用 `bake.py --author-scene`；之后派生
当前原生空间数据。Godot 必须在容器普通用户下运行：

```bash
source scripts/container_env.sh
mib_godot --headless --path . --script res://tools/town_layers/bake_spatial.gd
```

## 本次收口的检查证据

本次实际运行的负向装载/source 检查与精度数据位于被 git 忽略的
`build/current/town-negative-audit/`：`run.log` 记录命令、结果和验证范围；
`check_negative.gd` 仅在内存中破坏装载输入；`check_sources.py` 只读核对
SHA、尺寸、feet/crop、native 绑定、透明孔洞及权威边界源码，未执行再生成
或重组。25 个负向输入被拒绝，修正后的装载日志无脚本错误。

本次仅对负向门禁作补充，未运行图形穿行、完整构建、导出、发布或 golden
更新。静态遮挡与贴边穿行的实际画面还需后续图形验收；容器 llvmpipe 与
宿主真实 GPU 的证据范围仍须分别记录。
