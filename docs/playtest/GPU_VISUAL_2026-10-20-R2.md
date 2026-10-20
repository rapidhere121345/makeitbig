# 真机 GPU 视觉验收 · 高分辨率加压轮 · 2026-10-20(第二轮)

第一轮验收记录见 [GPU_VISUAL_2026-10-20.md](GPU_VISUAL_2026-10-20.md)。本轮在 1920×1080(Xvfb `:97` + NVIDIA vendor library,engine.log 存证 RTX 4080 SUPER)下由两个视觉模型**串行**各跑一轮交互式验收(同一时刻仅一个游戏实例):glm-5.3-flash#max(`build/current/gpu-visual-r2-glm/`,约 40 分钟)与 deepseek-flash#low(`build/current/gpu-visual-r2-ds/`)。协议同前:play_session 窗口命令 + 逐帧截图读图。

## 结论

- **1.5× 非整数缩放零伪影**:双方独立确认 HUD 文字、精灵边缘、图标在任何放大倍数下无发糊/锯齿不均/闪烁。
- 城镇五设施、双战斗房、结算页、对话、桥栏边界全部走通,无文字截断/面板溢出。

## 交叉验证与修复

| # | 级别 | 发现 | 验证 | 处置 |
|---|---|---|---|---|
| 1 | 严重 | **胜利后控制冻结 + 残敌继续攻击 + 拾取报内部错误键**:猎杀精英胜利后 Manual 移动被 `active()` 切断(战利品窗口要求走近按 F,逻辑自相矛盾),残余扇射游猎者持续输出,`loot_out_of_range` 未本地化 | DeepSeek 复现 | 已修复:`collect_commands` 在"胜利+拾取窗口开启"期间保留移动向量(攻击保持锁定);CombatPhasePort 新增 `room_terminal_locked()`,终局后跳过敌人 AI 相位;拾取错误键本地化(距离过远/已请求/窗口关闭) |
| 2 | 严重 | **前景件开窗在真机不生效**(米拉对话点英雄被覆雪岩堆完全吞没):节点查找从 `mounted_scene` 出发,但挂载后前景件被重挂到 world presenter 层,DFS 落空(`node=false`,诊断日志实锤) | DeepSeek 复现 + flash 像素差分证实 100% 不透明 | 已修复:查找根改为 SceneRuntime 节点(其子树同时包含挂载场景与 presenter 层);修复后 `node=true`,flash 复读确认覆盖区半透明、英雄幽灵剪影透出、识别特征保留。备行架棚区一处因碰撞体不可达未复现,无需处理 |
| 3 | 一般 | **对话/成长册 Esc 失效**:按钮文案宣称 Esc 但无 Shortcut 绑定,焦点持有控件吞键 | 双方复现(DeepSeek 发现范围更大) | 已修复:对话"稍后再聊 Esc"与成长册"返回 Esc"直接绑定 ESC Shortcut |
| 4 | 一般 | **击杀"击破"标签与伤害数字同点叠压** | 双方复现 | 已修复:death 文本通道加宽错位(15→34px) |
| 5 | 中 | 顶部入场提示长句被右侧面板硬裁切(回收环场) | DeepSeek | 已修复:RoomStartLabel 开启 `clip_text + OVERRUN_TRIM_ELLIPSIS` |
| 6 | 打磨 | 敌我贴身叠压辨识度、雪地英雄对比度、版心留白、目标信息陈旧、开场卡淡出残影 | 单方或低危 | 入 backlog |

## 备注

- GLM 报告的"备行架棚区英雄隐身"在 DeepSeek 复验中因碰撞体阻挡不可达原位,判非问题;但由此引出的开窗查找根修复(发现 2)让全部前景件开窗真正生效。
- "回火砧锁定仍可交互"与"训练完成后铭牌仍显示未验证"两项无法判定是否有意,留待设计确认。

## 门禁

完整 `container_test.sh` 全绿(600/600 matrix、历史回放金标不变)、双平台导出与 Linux 空目录 smoke 通过后交付。
