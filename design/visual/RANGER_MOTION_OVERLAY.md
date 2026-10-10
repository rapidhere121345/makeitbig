# 游侠表现层材质与动作读感（2026-10）

## 现状与做法

src/presentation/ranger_motion_overlay.gd 是游侠唯一的表现层叠加：
首次按姿势从已发布图集像素（combat_style_r13/v03 皮肤，缺省回退
ranger_actions_v01）采样当前朝向/动作/帧的掩码（content/bone/red/leather，
仅取 alpha≥0.55 的实心像素）并缓存，绘制时读取缓存，再决定每个 1px
强调点画在哪。所有强调逐姿势锚定在原图像素上或 1px 邻域内（闪避尾迹
允许 2px），悬空即不画。

本轮三项可见改善：

1. 披风折线明暗：在骨白大色块的下缘与背缘内侧按确定性规则放
   #d3cbb5 阴影阶（下缘最多 14 个、背缘最多 8 个 1px 阴影点），披风最低缘
   加 #111820 落座像素；步行经过帧（1/3）披风尖端向背后踢 1px。
2. 箭袋结构化：红色噪点簇顶部逐帧定位，骨白箭羽 + 旧铜箭尾扣把噪点
   读成背箭；肩甲改放在躯干最宽行（y15..24）的背半侧，死亡低趴自动跳过。
3. 落脚反馈：接触帧（0/2）在打击侧靴顶加 2px #d3cbb5 高光，靴底旁
   1px #91a4b4 踢尘；步行武器手铜点随经过帧上浮 1px。

## 不变量

- 48x48 图集、(24,44) 脚点、射击 socket 与权威/回放全部不动；
  调色板仅使用皮肤已有色 + 认可的冷青（仅运动 accent）。
- west walk 选帧回归：4 帧独立 rect、0-1-2-3 每 15 tick 精确循环
  （tests/unit/test_ranger_motion_overlay.gd）。

## 验证与限制

    source scripts/container_env.sh
    mib_godot --headless --path . --script res://tests/unit/test_ranger_motion_overlay.gd
    mib_godot --headless --path . --script res://tools/art_pipeline/ranger_overlay_report.gd

离屏对比图（原图 vs 叠加后）在 git 忽略的
build/current/overlay-report/，先看 west-walk-compare-4x.png。
限制：强调点跟随的是已发布像素，若重制图集，规则自适应但明暗密度
可能需要复核；未处理红噪点的中间散点（只结构化顶部箭羽区）。
