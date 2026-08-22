# Zig Switch Controller

一个运行在 **ESP32-WROOM-32D** 上的 Nintendo Switch Pro Controller 模拟器,
由 **Zig 0.16.0 + ESP-IDF + ESP32 + Bluetooth Classic HID** 强力驱动.

## 目录

- [Zig Switch Controller](#zig-switch-controller)
  - [目录](#目录)
  - [状态](#状态)
  - [功能](#功能)
  - [架构](#架构)
  - [构建](#构建)
    - [环境准备](#环境准备)
    - [编译](#编译)
    - [烧录](#烧录)
  - [🌐 HTTP API](#-http-api)
  - [📡 Bluetooth HID](#-bluetooth-hid)
  - [命令脚本](#命令脚本)
    - [基础按键输入](#基础按键输入)
    - [组合按键输入](#组合按键输入)
    - [摇杆输入](#摇杆输入)
    - [重复循环](#重复循环)
    - [重置状态](#重置状态)
    - [时间单位](#时间单位)
  - [致谢](#致谢)
  - [声明](#声明)

## 状态

目前还在处于实验性探索阶段.

## 功能

- 🎮 **Nintendo Switch Pro Controller Emulator**
- 📡 **Bluetooth Classic HID**
- 🕹️ 按键、组合键、摇杆控制
- 🌐 Wi-Fi APSTA
- 🚀 HTTP REST API
- 💾 ESP-IDF NVS 配置

## 架构

```text
                         ┌─────────────────────┐
                         │       ESP32         │
                         │   Zig + ESP-IDF     │
                         └──────────┬──────────┘
                                    │
              ┌─────────────────────┼─────────────────────┐
              │                     │                     │
              ▼                     ▼                     ▼
        ┌───────────┐        ┌────────────┐       ┌─────────────┐
        │   Wi-Fi   │        │ Bluetooth  │       │    NVS      │
        │  AP / STA │        │ Classic HID│       │   Config    │
        └─────┬─────┘        └─────┬──────┘       └─────────────┘
              │                    │
              ▼                    ▼
        ┌─────────────┐      ┌──────────────┐
        │ HTTP Server │      │ ReportQueue  │
        └──────┬──────┘      └──────┬───────┘
               │                    │
               ▼                    ▼
        ┌─────────────────────────────────┐
        │          Controller             │
        │  Button / Stick / Input State  │
        └───────────────┬─────────────────┘
                        │
                        ▼
              ┌──────────────────┐
              │ Switch Protocol  │
              │  HID / Reports   │
              └────────┬─────────┘
                       │
                       ▼
              ┌──────────────────┐
              │ Nintendo Switch  │
              └──────────────────┘
```

## 构建

### 环境准备

- CMake
- Ninja
- ESP-IDF 6.0.2
- [Patched-Zig-Espressif-0.16.0]

### 编译

在激活 ESP-IDF 环境以及导出环境变量 `ZIG_DIR` 为你的 ZIG 工具链路径的命令行终端中, 使用以下指令进行编译:

```shell
idf.py set-target esp32
idf.py build
```

若要指定优化等级, 则可以使用

```shell
idf.py reconfigure -DCMAKE_BUILD_TYPE=ReleaseSmall
idf.py build
```

### 烧录

烧录和正常烧录方法一致, 依旧在相同的环境的命令行终端中, 使用

```shell
idf.py -p <PORT> flash
```

## 🌐 HTTP API

设备启动 HTTP Server 后，可以通过 HTTP API 控制 Controller。

| Method | Endpoint | Description |
|---|---|---|
| `GET` | `/` | API / Web 根入口 |
| `GET` | `/api/config/wifi` | 获取 Wi-Fi 配置 |
| `POST` | `/api?mode=/cfg/wifi` | 更新 Wi-Fi 配置 |
| `POST` | `/api?mode=/cmd/queue` | 将控制器指令字节码推送到执行队列 |
| `POST` | `/api?mode=/cmd/run` | 直接执行指令脚本字节码 |
| `POST` | `/api?mode=/cmd/run/raw` | 直接执行指令脚本 |
| `POST` | `/api?mode=/cmd/test` | 测试指令字节码 |

## 📡 Bluetooth HID

ESP32 通过 Bluetooth Classic HID Device 模拟：

```text
Nintendo Pro Controller
```

默认设备信息：

```text
Name:        Pro Controller
Description: Gamepad
Provider:    Nintendo
```

## 命令脚本

可以使用简单的文本命令控制手柄。

### 基础按键输入

按下 **A** 等待 100 毫秒后弹起.

```text
DOWN A
WAIT 100ms
UP A
```

等价于

```text
TAP 100ms 0ms A
```

### 组合按键输入

按下 **L** 的同时一起按下 **R**, 并等待 100 毫秒后弹起.

```text
DOWN L R
WAIT 100ms
UP L R
WAIT 50ms
```

等价于

```text
TAP 100ms 50ms L R
```

### 摇杆输入

```text
STICK <摇杆> <X轴> <Y轴>
```

- 摇杆类型:
  - 左摇杆: `left_stick`
  - 右摇杆: `right_stick`
- X/Y 轴: [-100, 100] 整数

### 重复循环

循环 5 次按下 **A**

```text
REPEAT 5
    DOWN A
    WAIT 100ms
    UP A
    WAIT 100ms
END
```

### 重置状态

- 重置按键: `RESET_BUTTON`
- 摇杆归位: `RESET_STICK <摇杆>`
- 重置所有: `RESET_ALL`

### 时间单位

支持：

```text
100ms
1s
1.5s
2m
1h
```

如果不指定单位，则默认使用毫秒：

```text
WAIT 100
```

## 致谢

这个项目存在离不开这些仓库的所有贡献者的奉献: 

- [zig-espressif-bootstrap]
- [zig-esp-idf-sample]
- [nxbt]
- [nuxbt]
- [Nintendo_Switch_Reverse_Engineering]

## 声明

本项目仅作为个人学习研究为目的

[Patched-Zig-Espressif-0.16.0]: https://github.com/SmileYik/zig-espressif-bootstrap/releases/tag/0.16.0
[zig-espressif-bootstrap]: https://github.com/kassane/zig-espressif-bootstrap
[zig-esp-idf-sample]: https://github.com/kassane/zig-esp-idf-sample
[nxbt]: https://github.com/Brikwerk/nxbt
[nuxbt]: https://github.com/hannahbee91/nuxbt
[Nintendo_Switch_Reverse_Engineering]: https://github.com/dekuNukem/Nintendo_Switch_Reverse_Engineering