# 07 面试高频 FAQ

## 一、生命周期与基础

**Q:口述一次 BLE 连接的完整生命周期。**
外设广播 → 中心扫描发现(didDiscover,拿广播数据与 RSSI)→ 停扫并发起连接 → 链路建立(didConnect)→ 服务发现(discoverServices/Characteristics,重建 GATT 句柄)→ MTU/连接参数协商 → 业务交互(读/写/订阅通知)→ 断开(主动 cancel 或链路超时,didDisconnect)→ 句柄全部失效,重连必须重新发现、重新订阅。详见 [02](02-CoreBluetooth核心知识.md)。

**Q:Notify 和 Indicate 的区别?**
都是外设推送;Notify 无链路层确认、快;Indicate 每帧要等确认、慢但不丢,医疗设备(血糖仪)常用。订阅本质都是写 CCCD(0x2902)。

**Q:Write Request 和 Write Command 的区别?什么时候用哪个?**
前者有 ATT 确认(可靠、慢、自带流控),后者无确认(快、可能静默丢包,要自查 `canSendWriteWithoutResponse`)。命令类用前者,大流量(OTA、音频)用后者+应用层 ACK。见 [03](03-异常处理手册.md) №6。

**Q:MTU 是什么?iOS 能设置吗?**
ATT 单帧大小,默认 23(净负载 20B)。iOS **自动协商**、App 无法指定,只能读 `maximumWriteValueLength(for:)`。超过单帧的业务数据要分包/组包,见 [04](04-私有二进制协议.md)。

## 二、iOS 特有

**Q:iOS 能拿到设备 MAC 地址吗?怎么持久识别设备?**
拿不到。`peripheral.identifier` 是本机会话级 UUID,换手机会变。持久识别靠:广播厂商数据里的序列号,或连接后读设备信息服务(0x180A)。

**Q:App 杀掉后还能收蓝牙数据吗?**
系统回收的可以:bluetooth-central 后台模式 + State Restoration,系统代持连接、事件拉活(约 10s 窗口)。用户手动上滑杀掉的不行,系统政策。见 [05](05-后台模式与状态恢复.md)。

**Q:iOS 怎么发起配对?怎么解除绑定?**
不能主动发起。访问要求加密的特征收到 `insufficientAuthentication` 时系统自动弹配对框,配对后系统自动重试原操作。解绑只能引导用户去设置里"忽略此设备"。见 [06](06-配对绑定与安全.md)。

**Q:connect 会超时吗?**
永不超时。必须自己实现超时(本项目:超时 Task 竞速),且超时后必须 `cancelPeripheralConnection`,否则会"幽灵连接"。见 [03](03-异常处理手册.md) №3。

## 三、双端差异(Android 对照)

| 维度 | iOS | Android |
|---|---|---|
| 设备标识 | 会话级 UUID,无 MAC | 真 MAC(6.0 后自身地址随机化) |
| 扫描权限 | 只要蓝牙权限 | 12 前要定位权限;12+ BLUETOOTH_SCAN/CONNECT 分层 |
| 后台长连 | 后台模式 + 状态恢复,被杀靠事件拉活 | 前台服务(常驻通知)硬保活 |
| 配对 API | 无,系统按需触发 | createBond 可主动发起 |
| 经典错误 | 各类行为不一致 | GATT 133(资源泄漏/缓存,重试+refresh 民间偏方) |
| GATT 缓存 | 系统管理,偶发需重连刷新 | 问题更重,隐藏 API refresh() |

**Q:Android 12 前扫描为什么要定位权限?**
BLE 广播(iBeacon 等)可用于室内定位,谷歌视扫描结果为位置信息。12+ 可声明 `neverForLocation` 豁免,代价是系统会过滤掉 iBeacon 类结果。

## 四、进阶专题

**Q:OTA 怎么设计?**
私有协议之上的分块传输:查版本 → 元信息握手(大小/总 CRC/块大小)→ 分块下行(免响应写,块号+块 CRC,错块重传)→ 总校验 → 重启激活。工程重点:断点续传、传输中断连恢复(自动重连 + 从断点继续)、低电量拒绝、A/B 双分区防变砖。见 [04](04-私有二进制协议.md)。

**Q:iBeacon 和普通 BLE 广播什么关系?**
iBeacon 是苹果定义的**广播格式**(厂商数据区:UUID+major+minor+txPower),只广播不连接。iOS 上用 CoreLocation(区域监测,可后台唤醒)而非 CoreBluetooth 扫;CoreBluetooth 前台扫得到该厂商数据但被系统部分屏蔽。

**Q:BLE Mesh 了解吗?**
基于广播的多对多组网(泛洪转发),适合照明/楼宇。手机一般作为 Provisioner(配网器)经代理节点(GATT Proxy)接入。与本项目的点对点 GATT 模型是两套体系。

**Q:如何评估/优化 BLE 吞吐?**
理论吞吐 = 每连接间隔的包数 × 净负载 ÷ 间隔。抓手:协商大 MTU、缩短 Connection Interval(iOS 只能由外设发起参数更新请求)、BLE 5 的 2M PHY 与 DLE、免响应写、减少协议层开销。日志时间戳算实际速率。

**Q:怎么让 BLE 模块可测试?**
协议抽象 + 双实现(本项目 `BLECentral` / `MockCentral`,[01](01-架构与并发模型.md));纯逻辑(编解码/解析/退避)与 IO 分离做单元测试(本项目 27 项);Mock 支持故障注入跑异常路径。

**Q:排查"偶发断连"的思路?**
先双通道日志定位断连时刻的 error code 与前后事件时序([03](03-异常处理手册.md) 日志一节)→ 区分:超距/干扰(RSSI 曲线)、外设主动断(固件省电策略)、supervision timeout(连接参数太激进)、iOS 资源回收(后台)→ 对症:重连策略兜底 + 固件参数调整 + 产品侧引导。
