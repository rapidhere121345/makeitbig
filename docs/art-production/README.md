# 当前美术来源与维护

正式资源以运行代码读取的 `art/production/p1/` 为准。这里保留当前素材的原图、实际提示词、来源记录和配方；生成工具为来源记录中的内置 image_gen。源图保持原始字节，配方负责裁切、去底、最近邻缩放和图集排列。

| 当前资源 | 保留来源 |
| --- | --- |
| 小镇环境 | `art/production/p1/hamlet_town/town.png` 原始生成位图；同目录 `SOURCE.json` 保留完整提示词与参考路径 |
| 居民、旧镇兼容素材、炉火、灯笼 | `p1-hamlet-style-r13/`；模板来源 `p1-hamlet-concept-v02/`、`p1-hamlet-life-v01/` |
| 战场 v03 与旧场景兼容素材 | `p1-combat-style-r13/`；`p1-scene-rework-v01/`、`p1-calibration-v01/` |
| 游侠、敌人动作 | `p1-ranger-actions-v01/recipe.final.json`、`p1-enemy-actions-v01/recipe.final.json` 与对应 sources |
| 装备、技能、导航、天赋与律筹 | `p1-early-loop-v01/`、`p1-equipment-readability-v02/`、`p1-hub-navigation-v01/`、`p1-icon-expansion-v01/` |
| UI材质 | `p1-ui-style-r13/` 的原图、提示词和打包映射 |
| 标题、循环与返镇 | `p1-title-concept-v02/`、`p1-title-life-v01/`、`p1-hearth-return-v01/` |
| 五人对话头像 | `p1-story-portraits-r14/`：仅 v03 原图、提示词、当前裁切配方与 FROZEN 导入清单 |
| 地面与视觉参考 | `p1-ground-refine-v01/`；`../art-concepts/` 中保留的生产参考原图和提示词 |

`hamlet_ground_r14` 的 atlas 没有记录原图映射，暂保留 `p1-hamlet-ground-v03/` 原图与配方以及炉边镇构图原图，待确认现行地面的重建链。概念参考图不直接代替运行贴图。字体来源和原许可位于 [PROVENANCE.md](../../art/fonts/PROVENANCE.md) 与 [LICENSE-noto-cjk.txt](../../art/fonts/LICENSE-noto-cjk.txt)；生成图的来源记录不视为第三方授权书。

维护检查：`scripts/test.sh` 与 `scripts/test.ps1` 均调用 `tests/test_scene_atmosphere.gd` 和 `tests/test_workbench_layout.gd`。前者依赖场景光影、镇区、战场、返镇表现脚本及 `ground_refine_v01/ground.png`；后者依赖 `facility_screen.gd` 和 `tests/test_facility_screen.gd`。两份入口及其 UID 保留，生产资源与外部依赖未改。字体重打包脚本 `tools/art_pipeline/repack_ui_font.py` 保留；头像导入检查使用现行 FROZEN 清单。旧截图、GIF、复制项目、候选和验收报告不留在这些目录。
