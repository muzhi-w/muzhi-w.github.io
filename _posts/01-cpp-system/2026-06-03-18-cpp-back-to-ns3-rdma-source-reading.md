---
title: "C++ 系统补课 18：回到 ns-3：Ptr<T>、Object、Simulator、Packet"
date: 2026-06-03 17:17:00 +0800
permalink: /posts/cpp-back-to-ns3-rdma-source-reading/
categories: [C++, 系统补课]
tags: [cpp, ns3, rdma, ptr, object, simulator, packet, source-code-reading]
description: "把前面系统补课的 C++ 概念重新接回 ns-3：Ptr<T>、Object、Simulator、EventId、Packet、Header、Tag 和 RDMA 源码阅读。"
---

<!-- series-nav -->
> **系列位置**：C++ 系统补课，第 18 篇 / 共 19 篇
> **总目录**：[学习路线](/roadmap/)
> **上一篇**：[17：智能指针和资源管理](/posts/cpp-smart-pointer-resource-management/)


前面从 0 开始补了 C++ 的基础地图。

这一篇把这些概念重新接回 ns-3/RDMA 源码。

ns-3 里很多代码看似复杂，其实是多个 C++ 基础概念叠在一起：

```text
类型
指针
引用
const
函数
类
构造和析构
继承和多态
模板
智能指针
回调
```

## 1. Ptr<T>

```cpp
Ptr<Packet> p;
Ptr<RdmaQueuePair> qp;
Ptr<QbbNetDevice> dev;
```

这里涉及：

```text
模板：Ptr<T>
智能指针：引用计数
对象类型：Packet/RdmaQueuePair/QbbNetDevice
成员访问：->
```

读法：

```text
p 是一个 ns-3 智能指针。
它指向 Packet 对象。
可以通过 p-> 调用 Packet 成员函数。
```

## 2. Object

```cpp
class RdmaQueuePair : public Object
```

这里涉及：

```text
class
public 继承
ns-3 对象系统
TypeId
引用计数
```

读法：

```text
RdmaQueuePair 是 ns-3 Object 子类。
它可以参与 ns-3 对象系统。
```

## 3. Simulator::Schedule

```cpp
Simulator::Schedule(
    delay,
    &QbbNetDevice::Receive,
    dev,
    packet);
```

这里涉及：

```text
静态函数
函数模板
成员函数指针
对象参数
Ptr<T>
事件系统
对象生命周期
```

读法：

```text
delay 之后，在 dev 对象上调用 Receive(packet)。
```

## 4. EventId

```cpp
EventId m_retransmit;
```

这里涉及：

```text
类类型
对象状态
事件句柄
取消和检查
```

读法：

```text
m_retransmit 保存一个未来事件的句柄。
可以用来 Cancel 或 IsRunning。
```

## 5. Packet

```cpp
Ptr<Packet> p = Create<Packet>(payload_size);
```

这里涉及：

```text
模板函数 Create<T>
Ptr<T>
对象创建
Packet 类型
payload size
```

读法：

```text
创建一个 Packet 对象，用 Ptr<Packet> 管理。
```

## 6. Header 和多态

```cpp
void AddHeader(const Header& header);
```

这里涉及：

```text
函数参数
const 引用
基类引用
多态
Header 接口
```

读法：

```text
AddHeader 接收任意 Header 派生类对象，只读它，并序列化进 Packet。
```

实际传入：

```text
Ipv4Header
UdpHeader
SeqTsHeader
qbbHeader
CnHeader
PauseHeader
```

## 7. Tag

```cpp
p->AddPacketTag(fit);
p->PeekPacketTag(fit);
```

这里涉及：

```text
对象成员函数
引用参数
Tag 抽象类
仿真辅助信息
```

读法：

```text
给 packet 挂上仿真辅助信息，不改变真实协议字节。
```

## 8. RDMA 发送路径中的组合

```cpp
Ptr<Packet> p = Create<Packet>(payload_size);
p->AddHeader(seqTs);
p->AddHeader(udpHeader);
p->AddHeader(ipHeader);
p->AddHeader(ppp);
p->AddPacketTag(fint);
```

这里同时出现：

```text
智能指针
模板
对象创建
成员函数调用
const 引用
多态
Header/Tag 区分
```

读法：

```text
创建 Packet。
向 Buffer 添加真实协议头。
向 TagList 添加仿真辅助信息。
```

## 9. RDMA 定时器中的组合

```cpp
qp->m_retransmit = Simulator::Schedule(
    rto,
    &RdmaHw::HandleTimeout,
    this,
    qp,
    rto);
```

这里同时出现：

```text
成员变量
EventId
成员函数指针
this 裸指针
Ptr<RdmaQueuePair>
Time
事件系统
```

读法：

```text
rto 之后，调用当前 RdmaHw 对象的 HandleTimeout(qp, rto)。
事件句柄保存到 qp->m_retransmit。
```

## 10. 一套稳定读法

以后读 ns-3/RDMA 源码，可以按这个顺序：

```text
1. 先看类型
2. 再看对象生命周期
3. 再看函数参数传递方式
4. 再看是否有继承和多态
5. 再看是否有模板
6. 再看是否有事件/回调
7. 最后放回模块职责和调用链
```

例如：

```cpp
uint32_t PeekHeader(Header& header) const;
```

读成：

```text
返回 uint32_t。
参数是可修改 Header 引用。
函数不修改当前 Packet。
可能通过多态解析具体 Header。
```

## 11. C++ 基础和 ns-3 的关系

可以把整个关系总结成：

```text
类型和值              帮助读变量和表达式
指针和引用            帮助读参数、this、Ptr<T>
函数                  帮助读 API
class/object          帮助读模块职责
构造/析构/RAII        帮助读生命周期
继承/多态             帮助读 Header/Object/接口
模板                  帮助读 Ptr<T>/Create<T>
智能指针              帮助读对象管理
函数指针/回调         帮助读 Simulator::Schedule
```

## 12. 小结

这一篇把系统补课重新接回 ns-3。

读者已经可以看到：

```text
ns-3 源码不是一团魔法。
它是 C++ 基础概念的组合。
```

后续如果继续写 RDMA 源码路径型博客，就可以站在这套地基上：

```text
RDMA QueuePair
RDMA 发送路径
RDMA 接收路径
DCQCN
PFC/Qbb
SwitchMmu
Trace/Log
```

这时再读源码，就不是被语法推着走。

而是能主动拆解：

```text
这个对象是什么？
谁拥有它？
这个函数修改谁？
这个事件什么时候触发？
这个 packet 里的字段是真实 Header 还是仿真 Tag？
```

这就是 C++ 系统补课的目的。
