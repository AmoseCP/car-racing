# CarRacing

CarRacing 是使用 Godot 4 制作的 3D 赛车游戏原型。可驾驶 GT 赛车、拉力赛车或耐力原型车，在沙漠、城市、隧道、草原和森林进行两圈计时赛。不同赛车拥有各自的加速、极速和操控特性。雨雪会影响车速和抓地力，天黑时前灯会自动亮起。

## 开始游戏

从 [GitHub Releases](https://github.com/AmoseCP/car-racing/releases/latest) 下载 Windows x64 ZIP，解压后运行 `CarRacing.exe`。

| 操作 | 键盘 | 手柄 |
| --- | --- | --- |
| 油门 | W / ↑ | RT |
| 刹车和倒车 | S / ↓ | LT |
| 转向 | A / D 或 ← / → | 左摇杆 |
| 切换车灯 | H | X |
| 重试 | R | Y |
| 暂停 | Esc | 菜单键 |
| 切换全屏 | F11 | 暂停菜单 |

在赛道选择页可调整天气和昼夜设置。支持运动传感器的 Windows 掌机或手柄可在「体感设置」中开启体感转向。

## 从源码运行

用 Godot 4.7.2 打开 `project.godot`，等待素材导入后按 F5。安装同版本的 Godot 导出模板后，可使用项目中的 `Windows x64` 预设导出发行版。

## 素材署名

赛车模型、场景素材和字体的来源与许可见 [美术素材署名](racing_prototype/art/CREDITS.txt) 和 [字体许可](racing_prototype/fonts/OFL.txt)。
