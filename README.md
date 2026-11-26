# Counter-Strike 1.6 on iOS

开源引擎 [Xash3D FWGS](https://github.com/FWGS/xash3d-fwgs) + [cs16-client](https://github.com/Velaron/cs16-client)，
在 GitHub Actions 的 macOS runner 上交叉编译 arm64，最终打成未签名 IPA。

仓库不含任何 Valve 游戏文件，最后一步需要把你自己的 `cstrike` 目录塞进 IPA。

## 能跑什么

- **CS 1.6 本体**：原生 arm64，触屏摇杆 + 蓝牙键鼠，社区服务器联机（UDP，不走 Steam 认证）
- **不是 CS:GO**：CS:GO 是 Source 引擎（D3D9 / Win32 / x86），要重写渲染后端与平台层，没有可行路径

## 流水线

1. 拉引擎与游戏代码（引擎自带官方 iOS 脚本 `scripts/ios/buildcs16.sh`）
2. 用官方脚本编 cs16-client 成 iOS 动态库
3. CMake + iOS toolchain 编引擎本体（arm64 / iOS 12+）
4. 收集 dylib，下一步套 App 外壳后打 IPA

## 还差什么

- SDL2 的 iOS `UIApplicationMain` 入口（App 主程序）
- 把引擎与游戏 dylib 放进 `.app/Frameworks`
- `cstrike/` 资源目录（自备）

## 装法

TrollStore 直装（永久），或 Sideloadly / AltStore 自签（7 天）。

控制：左下摇杆移动，右半屏滑动瞄准，右下开火/跳/蹲/换弹；蓝牙键鼠由引擎原生支持；
联机 `connect IP:端口`。
