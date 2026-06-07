# 自动化连接测试

第一步先验证电脑能控制安卓手机，不直接做预约。

## 手机准备

1. 用 USB 连接安卓手机和电脑。
2. 手机打开开发者选项。
3. 开启 USB 调试。
4. 第一次连接时，手机会弹出“允许 USB 调试”，请选择允许。
5. 确认手机已安装并登录微信。

## 电脑准备

安装 Android Platform Tools，确保能使用 `adb.exe`。

常见安装后路径：

```text
%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe
```

如果 `adb` 已加入 PATH，可以直接运行：

```powershell
.\automation\connection-test.ps1
```

如果没有加入 PATH，可以指定 adb 路径：

```powershell
.\automation\connection-test.ps1 -AdbPath "C:\Users\你的用户名\AppData\Local\Android\Sdk\platform-tools\adb.exe"
```

## 通过标准

脚本会检查：

- 是否找到 `adb`
- 是否发现已授权安卓设备
- 设备品牌、型号、Android 版本
- 屏幕尺寸和密度
- 是否安装微信 `com.tencent.mm`
- 是否能截图
- 是否能启动微信

全部通过后，说明可以进入下一步：Appium 自动化控制微信小程序。

## 下一步

连接测试通过后，再做 Appium 脚本：

1. 打开微信。
2. 进入“羽波跃动体育”小程序。
3. 点击“场地预定”。
4. 识别日期、场地、时间格子。
5. 高频刷新并提交订单。
6. 停在支付页，提示手动支付。
