# 羽毛球场地预约助手

这是一个本地运行的预约任务面板，用来配置目标日期、时间、场地偏好，并自动计算平台放号时间。

## 当前功能

- 创建预约任务
- 自动计算放号时间：目标日前一周同星期 24:00，也就是目标日期前 6 天的 00:00:00
- 日期三态显示：已放号可立即预约，未放号标红可用于 24 点守候，过去日期置灰
- 支持选择全天任意开始和结束时间范围
- 支持连续两小时预约策略：优先同一片场地，也可接受两个场地
- 倒计时提醒
- 30 秒待命提醒
- 到 00:00:00 后进入持续刷新抢场状态
- 支持配置刷新检测间隔
- 支持配置最大重试时长，第一次失败后会继续发起
- 白天使用时，如果目标日期已经放号，会立即发起预约
- 本地保存任务队列
- 执行日志
- 当前版本未接入小程序自动化时，“系统已抢票成功，请去微信支付”按钮用于模拟最终成功状态

## 打开方式

可以直接双击 `index.html` 打开。

如果想用本地服务打开，可以在项目目录运行：

```powershell
python -m http.server 4173 --bind 127.0.0.1
```

然后访问：

```text
http://127.0.0.1:4173
```

## 后续自动化方向

下一阶段可以接入手机或模拟器自动化，用于：

- 打开微信小程序
- 点击“场地预定”
- 选择目标日期
- 扫描可预约格子
- 按偏好选择最多两个场次
- 提交订单
- 停在支付确认前，由用户手动支付

## 自动化连接测试

先运行安卓设备连接测试，确认电脑能控制手机：

```powershell
.\automation\connection-test.ps1
```

详细步骤见：

```text
automation/README.md
```

如果使用 PC 微信小程序窗口，先点击小程序窗口让它置顶，然后运行：

```powershell
.\automation\pc-wechat-window-test.ps1 -UseForeground
```

它会保存窗口截图到：

```text
automation/pc-wechat-window.png
```

0 点前目标日期可能还没有出现在页面里。正式抢场时可以传 `-TargetDateIndex`，让脚本在每次刷新后点击顶部第 N 个日期标签，例如：

```powershell
powershell -ExecutionPolicy Bypass -File .\automation\invoke-pc-wechat-booking.ps1 -UseMouseWindow -DelaySeconds 5 -StartAt "2026-06-07 00:00:00" -StartTime "10:00" -EndTime "12:00" -PreferredCourts "3,4,2,5,1" -TargetDateIndex 5 -ClickSlots -SubmitOrder -RetryIntervalMs 500 -MaxRetrySeconds 180
```

## 两种使用场景

自动判断：如果预约日期已经放号，就立即预约；如果还没放号，就等到放号时间再抢：

```powershell
.\automation\run-auto-booking.ps1 -BookingDate "2026-06-12" -StartTime "10:00" -EndTime "12:00" -PreferredCourts "3,4,2,5,1" -DatePageSwipes 1 -TargetDateIndex 5 -SubmitOrder
```

白天立即预约已放号日期：

```powershell
.\automation\run-now-booking.ps1 -StartTime "15:00" -EndTime "18:00" -PreferredCourts "3,4,2,5,1" -SubmitOrder
```

24 点守候抢新放号日期：

```powershell
.\automation\run-midnight-booking.ps1 -StartTime "10:00" -EndTime "12:00" -PreferredCourts "3,4,2,5,1" -DatePageSwipes 1 -TargetDateIndex 5 -SubmitOrder
```
