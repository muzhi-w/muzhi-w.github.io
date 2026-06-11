---
title: "彻底理解 ns-3 的 Tag：PacketTag、ByteTag 和 RDMA 仿真元信息"
date: 2026-06-11 8:45:00 +0800
permalink: /posts/ns3-tag-packettag-bytetag-rdma/
categories: [网络, ns-3]
tags: [ns3, tag, packettag, bytetag, packet, rdma, flowidnumtag, flowstattag]
description: "从 ns-3 的 Tag 基类、TagBuffer、PacketTagList 和 ByteTagList 讲起，理解 Tag 为什么不是协议字段，以及 RDMA 源码里的 FlowIDNUMTag、FlowStatTag 如何服务于 flow id、FCT、PFC 统计和调试。"
---

<!-- series-nav -->
> **系列位置**：ns-3 源码阅读，第 05 篇 / 共 5 篇
> **总目录**：[学习路线](/roadmap/)
> **上一篇**：[彻底理解 ns-3 的 Packet：Header、Tag、Buffer 和 RDMA 报文生命周期](/posts/ns3-packet-header-tag-buffer-rdma/)


上一篇文章讲了 `Packet`、`Header`、`Buffer` 和 `Tag` 的整体关系。

但 `Tag` 这个东西值得单独拎出来再讲一篇。

因为读 RDMA 仿真源码时，很多信息不是放在真实协议 header 里的，而是通过 `Tag` 跟着 `Packet` 走。

比如：

```cpp
FlowIDNUMTag fint;
FlowStatTag fst;

p->AddPacketTag(fint);
p->PeekPacketTag(fst);
oldp->PeekPacketTag(fit);
newp->AddPacketTag(fit);
```

如果没有理解 `Tag`，这些代码很容易被误读成：

```text
这个字段是不是发到链路上的？
它会不会改变 packet size？
为什么 ACK/NACK/CNP 要复制 FlowIDNUMTag？
为什么有些地方先 Peek，再决定要不要 Add？
为什么不能直接 Add 两次同一种 Tag？
为什么 RemovePacketTag 可能导致后面读不到？
```

这篇文章专门讲清楚这些问题。

主线是：

```text
Tag 是什么
-> Tag 和 Header 的区别
-> PacketTag 和 ByteTag 的区别
-> Tag 在 Packet 内部怎么保存
-> Add / Peek / Remove / Replace 各是什么意思
-> RDMA 源码里的 FlowIDNUMTag / FlowStatTag 怎么用
-> 新增一个 Tag 时应该检查什么
```

## 1. 先给 Tag 一个准确定位

`Tag` 不是网络协议头。

它是 ns-3 仿真器给 `Packet` 额外挂的一段元信息。

这句话很重要。

可以先用一个最简单的对比：

```text
Header：这个包真正带到网络上的协议字节。
Tag：仿真器内部跟着 Packet 走的辅助信息。
```

比如真实协议字段：

```text
IPv4 source address
IPv4 destination address
UDP source port
UDP destination port
RDMA seq
ACK/NACK seq
CNP 里的拥塞反馈字段
PFC pause time
```

这些应该放在 `Header` 里。

因为它们是接收端协议逻辑必须解析的真实内容。

而下面这些信息通常不应该放进真实 header：

```text
这个 packet 属于哪个 flow
这个 flow 总大小是多少
这个 packet 是 flow 的第一个包还是最后一个包
这个 packet 第一次发送时的仿真时间
这个包从哪个入端口进入交换机
这个 flow 因为 PFC 被挡住了多久
某个负载均衡算法内部的路径选择标记
```

这些信息更多是为了：

```text
统计
调试
trace
跨层辅助
仿真实验 bookkeeping
```

所以它们更适合做 `Tag`。

一句话记住：

```text
协议要看见的字段，放 Header。
仿真器自己要记的小纸条，放 Tag。
```

## 2. Packet 内部本来就有两套 TagList

先回到 `Packet` 的内部结构。

代码来源：

```text
src/network/model/packet.h
```

简化之后可以这样看：

```cpp
class Packet
{
private:
    Buffer m_buffer;
    ByteTagList m_byteTagList;
    PacketTagList m_packetTagList;
    PacketMetadata m_metadata;
};
```

这里有四个东西：

```text
m_buffer         真实协议字节，Header / Trailer / payload 都在这里
m_byteTagList    挂在某段字节范围上的 tag
m_packetTagList  挂在整个 packet 上的 tag
m_metadata       调试和打印用的元数据
```

上一讲的重点主要是 `m_buffer`。

这一讲的重点是：

```text
m_byteTagList
m_packetTagList
```

这两个列表和真实协议字节是分开的。

所以一般情况下：

```cpp
p->AddHeader(header);
```

会改变 `m_buffer`，也会改变 `p->GetSize()`。

而：

```cpp
p->AddPacketTag(tag);
```

改变的是 `m_packetTagList`，通常不会改变 `m_buffer`，也不会让链路发送时间变长。

## 3. Tag 基类长什么样

`Tag` 自己是一个抽象基类。

代码来源：

```text
src/network/model/tag.h
```

核心接口是：

```cpp
class Tag : public ObjectBase
{
public:
    static TypeId GetTypeId(void);

    virtual uint32_t GetSerializedSize(void) const = 0;
    virtual void Serialize(TagBuffer i) const = 0;
    virtual void Deserialize(TagBuffer i) = 0;
    virtual void Print(std::ostream &os) const = 0;
};
```

这几个函数和 `Header` 很像。

但它们的含义不一样。

### 3.1 GetTypeId

`Tag` 也进入 ns-3 的 `TypeId` 系统。

所以一个具体 Tag 类通常会写：

```cpp
static TypeId GetTypeId(void);
virtual TypeId GetInstanceTypeId(void) const;
```

这样 ns-3 能知道：

```text
这个 tag 的真实类型是什么。
```

`PacketTagList` 查找 tag 时，就是按 `TypeId` 找的。

比如你传进去一个空的 `FlowIDNUMTag fit;`，然后：

```cpp
p->PeekPacketTag(fit);
```

ns-3 会看 `fit.GetInstanceTypeId()`，然后在 packet 的 tag list 里找同类型的 tag。

找到了，就把保存的字节反序列化回 `fit` 这个对象。

### 3.2 GetSerializedSize

`GetSerializedSize()` 返回这个 tag 保存时需要多少字节。

比如一个 tag 里有：

```cpp
uint8_t type;
double initiatedTime;
```

那它大致需要：

```cpp
sizeof(type) + sizeof(initiatedTime)
```

ns-3 会根据这个大小给 `TagBuffer` 分配空间。

### 3.3 Serialize

`Serialize(TagBuffer i)` 把 tag 对象里的字段写进 `TagBuffer`。

注意，这里不是写进 packet 的真实 `Buffer`。

它只是把 tag 自己的数据保存到 `PacketTagList` 或 `ByteTagList` 内部。

### 3.4 Deserialize

`Deserialize(TagBuffer i)` 从 `TagBuffer` 里读出字段，恢复到 tag 对象。

也就是说：

```cpp
FlowIDNUMTag fit;
p->PeekPacketTag(fit);
```

真正发生的是：

```text
1. 根据 fit 的 TypeId 找到 packet 里同类型的 tag 数据
2. 调用 fit.Deserialize(...)
3. 把 tag list 里保存的字节读回 fit 的成员变量
```

### 3.5 Print

`Print(std::ostream &os)` 用于调试打印。

比如：

```cpp
p->PrintPacketTags(std::cout);
```

最终会调用每个 tag 的 `Print`。

## 4. TagBuffer 不是 Packet Buffer

很多人看到 `Serialize / Deserialize` 就会下意识以为：

```text
Tag 也会写进网络包字节里。
```

这个理解是错的。

`Tag` 序列化到的是 `TagBuffer`。

代码来源：

```text
src/network/model/tag-buffer.h
```

它是专门给 tag 使用的小缓冲区。

`TagBuffer` 的注释里有一个非常关键的限制：

```text
不要写超过 GetSerializedSize() 申请的字节。
```

所以写一个 Tag 时，必须保证：

```text
GetSerializedSize() 返回的大小
Serialize() 实际写入的大小
Deserialize() 实际读出的大小
```

三者一致。

这条规则非常实用。

读任何自定义 Tag 时，都应该检查这三件事。

## 5. PacketTag 和 ByteTag 的区别

ns-3 有两种 tag：

```text
PacketTag
ByteTag
```

它们都继承自同一个 `Tag` 基类。

区别在于挂载位置不同。

### 5.1 PacketTag

`PacketTag` 挂在整个 packet 上。

比如：

```cpp
p->AddPacketTag(fint);
```

意思是：

```text
给这个 packet 整体贴一张标签。
```

在 RDMA 源码里，`FlowIDNUMTag` 和 `FlowStatTag` 都是按 `PacketTag` 使用的。

因为它们描述的是：

```text
这个 packet 属于哪个 flow
这个 packet 在 flow 生命周期中的位置
```

这些信息不是某几个字节的属性，而是整个包的属性。

### 5.2 ByteTag

`ByteTag` 挂在 packet 的某段字节范围上。

它更像是在说：

```text
这个 tag 跟着这一段 payload 字节走。
```

如果 packet 被分片、裁剪、拼接，`ByteTag` 会更关心字节范围的变化。

比如 ns-3 自带的 delay/jitter 估计工具会用：

```cpp
packet->AddByteTag(tag);
packet->FindFirstMatchingByteTag(tag);
```

但你现在读 RDMA 主线时，最常见的是 `PacketTag`。

所以本文主要讲 `PacketTag`。

## 6. 为什么 AddPacketTag 是 const 方法

来看 `Packet` 里的 API。

代码来源：

```text
src/network/model/packet.h
```

```cpp
void AddPacketTag(const Tag &tag) const;
bool RemovePacketTag(Tag &tag);
bool ReplacePacketTag(Tag &tag);
bool PeekPacketTag(Tag &tag) const;
void RemoveAllPacketTags(void);
```

最反直觉的是：

```cpp
void AddPacketTag(const Tag &tag) const;
```

为什么给 packet 加 tag，函数却是 `const`？

源码注释给出的理由是：

```text
给 packet 加 tag 不改变 packet 的协议内容和行为。
不知道这个 tag 存在的代码，继续按原来的方式处理 packet。
```

这对 trace 很重要。

很多 trace callback 会拿到：

```cpp
Ptr<const Packet>
```

如果只是想给包贴一个调试 tag，不应该被 `const` 限制住。

所以 ns-3 把添加 tag 设计成 const 操作。

但要注意：

```text
const 只是说不改变协议内容。
并不是说 tag list 在内存里完全没有变化。
```

底层仍然会修改 `m_packetTagList`。

只是从 ns-3 的设计语义上看，tag 是旁路信息，不属于 packet 的协议内容。

## 7. Add / Peek / Remove / Replace 分别是什么意思

看 `packet.cc`。

代码来源：

```text
src/network/model/packet.cc
```

简化后是：

```cpp
void
Packet::AddPacketTag(const Tag &tag) const
{
    m_packetTagList.Add(tag);
}

bool
Packet::RemovePacketTag(Tag &tag)
{
    return m_packetTagList.Remove(tag);
}

bool
Packet::ReplacePacketTag(Tag &tag)
{
    return m_packetTagList.Replace(tag);
}

bool
Packet::PeekPacketTag(Tag &tag) const
{
    return m_packetTagList.Peek(tag);
}
```

这几个函数的语义要分清楚。

### 7.1 AddPacketTag

```cpp
p->AddPacketTag(tag);
```

意思是：

```text
把 tag 保存到 p 的 PacketTagList 里。
```

但是这里有一个限制：

```text
同一个 packet 上不能 Add 两个同类型 PacketTag。
```

`PacketTagList::Add` 里会检查：

```cpp
NS_ASSERT_MSG(cur->tid != tag.GetInstanceTypeId(),
              "Error: cannot add the same kind of tag twice.");
```

所以这类代码很常见：

```cpp
FlowIDNUMTag fint;
if (!p->PeekPacketTag(fint)) {
    fint.SetId(qp->m_flow_id);
    fint.SetFlowSize(qp->m_size);
    p->AddPacketTag(fint);
}
```

它不是多余的。

它是在避免同一种 tag 被重复添加。

### 7.2 PeekPacketTag

```cpp
FlowIDNUMTag fit;
if (p->PeekPacketTag(fit)) {
    uint32_t flowId = fit.GetId();
}
```

`Peek` 的意思是：

```text
找到了就读出来，但不删除。
```

这是最常用、也最安全的读取方式。

如果后面的模块还要读同一个 tag，就应该用 `Peek`。

### 7.3 RemovePacketTag

```cpp
FlowIDNUMTag fit;
p->RemovePacketTag(fit);
```

`Remove` 的意思是：

```text
找到了就读出来，并且从 packet 上删掉。
```

所以它有副作用。

如果你只是想看一下 flow id，不要随手用 `RemovePacketTag`。

否则后面的模块可能读不到。

### 7.4 ReplacePacketTag

```cpp
p->ReplacePacketTag(tag);
```

`Replace` 的意思是：

```text
如果已经有同类型 tag，就替换旧值。
如果没有，就添加新 tag。
```

当你确实要更新一个 tag 的值时，`Replace` 比先 `Remove` 再 `Add` 更直接。

### 7.5 RemoveAllPacketTags

```cpp
p->RemoveAllPacketTags();
```

这会删掉 packet 上所有 `PacketTag`。

除非你非常确定这个包后面不需要任何仿真元信息，否则不要随便用。

## 8. PacketTagList 使用 copy-on-write

`PacketTagList` 不是一个简单数组。

源码注释里明确说它使用 copy-on-write。

代码来源：

```text
src/network/model/packet-tag-list.h
```

核心思想是：

```text
Packet 被复制时，PacketTagList 先共享底层 TagData。
如果其中一个副本修改 tag list，再复制必要的那段结构。
```

所以：

```cpp
Ptr<Packet> p = Create<Packet>(100);
p->AddPacketTag(tag);

Ptr<Packet> copy = p->Copy();
```

此时 `copy` 也能读到原来的 tag。

ns-3 自带示例也展示了这一点。

代码来源：

```text
src/network/examples/main-packet-tag.cc
```

简化后：

```cpp
MyTag tag;
tag.SetSimpleValue(0x56);

Ptr<Packet> p = Create<Packet>(100);
p->AddPacketTag(tag);

Ptr<Packet> aCopy = p->Copy();

MyTag tagCopy;
p->PeekPacketTag(tagCopy);

NS_ASSERT(tagCopy.GetSimpleValue() == tag.GetSimpleValue());
```

这说明：

```text
Packet::Copy 会保留 PacketTag。
```

但要注意另一种情况：

```cpp
Ptr<Packet> newp = Create<Packet>(...);
```

这是一个全新的 packet。

它不会自动继承旧 packet 的 tag。

所以 ACK/NACK/CNP 这种新创建的反馈包，如果还想保留 flow id，就必须手动复制 tag。

## 9. RDMA 里的 FlowIDNUMTag

现在进入你的 RDMA 源码。

先看 `FlowIDNUMTag`。

代码来源：

```text
src/network/model/flow-id-num-tag.h
src/network/model/flow-id-num-tag.cc
```

简化后的类定义：

```cpp
class FlowIDNUMTag : public Tag
{
public:
    FlowIDNUMTag();
    static TypeId GetTypeId(void);
    virtual TypeId GetInstanceTypeId(void) const;
    virtual void Print(std::ostream &os) const;
    virtual uint32_t GetSerializedSize(void) const;
    virtual void Serialize(TagBuffer i) const;
    virtual void Deserialize(TagBuffer i);

    void SetId(int32_t ttl);
    int32_t GetId();
    uint16_t Getflowid();
    uint32_t GetFlowSize();
    void SetFlowSize(uint32_t fs);

private:
    int32_t flow_stat;
    uint32_t flow_size;
};
```

这个名字有点绕。

但从字段看，它主要保存两类信息：

```text
flow_stat  这里实际用作 flow id
flow_size  这个 flow 的总大小
```

它不是 RDMA 协议字段。

它是仿真里给 packet 贴上的 flow 身份信息。

### 9.1 TypeId 注册

实现里有：

```cpp
NS_OBJECT_ENSURE_REGISTERED(FlowIDNUMTag);

TypeId
FlowIDNUMTag::GetTypeId(void)
{
    static TypeId tid = TypeId("ns3::FlowIDNUMTag")
        .SetParent<Tag>()
        .AddConstructor<FlowIDNUMTag>();
    return tid;
}
```

这说明：

```text
FlowIDNUMTag 是 ns-3 TypeId 系统里的一个 Tag 类型。
```

`PeekPacketTag` 能按类型找到它，靠的就是这里。

### 9.2 序列化字段

实现里有：

```cpp
uint32_t
FlowIDNUMTag::GetSerializedSize(void) const
{
    return sizeof(flow_stat) + sizeof(flow_size);
}

void
FlowIDNUMTag::Serialize(TagBuffer i) const
{
    i.WriteU16(flow_stat);
    i.WriteU32(flow_size);
}

void
FlowIDNUMTag::Deserialize(TagBuffer i)
{
    flow_stat = i.ReadU16();
    flow_size = i.ReadU32();
}
```

这里要读出两个层次。

第一，意图很清楚：

```text
把 flow id 和 flow size 写进 TagBuffer。
```

第二，严格看这段代码有一个值得注意的细节：

```text
flow_stat 的成员类型是 int32_t。
GetSerializedSize 按 sizeof(flow_stat) 计算。
但 Serialize / Deserialize 用的是 WriteU16 / ReadU16。
```

也就是说：

```text
声明上像 32 bit。
实际序列化时只写 16 bit。
```

如果 flow id 永远很小，这可能暂时不出问题。

但从源码质量角度，最好统一：

```text
要么把 flow_stat 改成 uint16_t。
要么 Serialize / Deserialize 改成 WriteU32 / ReadU32。
要么 GetSerializedSize 按实际写入的 U16 + U32 计算。
```

这就是读 Tag 源码时非常重要的检查方式：

```text
成员变量类型
GetSerializedSize
Serialize
Deserialize
四者必须对齐。
```

## 10. 发送端在哪里给 RDMA data packet 挂 FlowIDNUMTag

发送端构造 RDMA data packet 以后，会给 packet 挂 tag。

代码来源：

```text
src/point-to-point/model/rdma-tx-scheduler.cc
```

核心代码：

```cpp
void
RdmaTxScheduler::AttachTxTags(const RdmaTxSchedulerConfig& config,
                              Ptr<RdmaQueuePair> qp,
                              Ptr<Packet> p,
                              uint32_t payload_size)
{
    FlowIDNUMTag fint;
    if (!p->PeekPacketTag(fint)) {
        fint.SetId(qp->m_flow_id);
        fint.SetFlowSize(qp->m_size);
        p->AddPacketTag(fint);
    }

    ...
}
```

这段代码要按顺序读。

第一步：

```cpp
FlowIDNUMTag fint;
```

先创建一个空 tag 对象。

第二步：

```cpp
if (!p->PeekPacketTag(fint)) {
```

检查当前 packet 上有没有同类型 tag。

如果已经有，就不要再加。

原因是前面说过：

```text
同一个 packet 不能 Add 两个同类型 PacketTag。
```

第三步：

```cpp
fint.SetId(qp->m_flow_id);
fint.SetFlowSize(qp->m_size);
```

从 `RdmaQueuePair` 取出 flow 信息。

这里说明：

```text
QP 是 flow 状态的来源。
PacketTag 是把 QP 上的一部分统计信息挂到具体 packet 上。
```

第四步：

```cpp
p->AddPacketTag(fint);
```

把 flow id 和 flow size 挂到 packet。

之后这个 packet 进入：

```text
QbbNetDevice
-> Queue
-> Channel
-> 对端 QbbNetDevice
-> Receiver
```

这些模块只要拿到 `Ptr<Packet>`，就可以用：

```cpp
FlowIDNUMTag fit;
p->PeekPacketTag(fit);
```

把 flow id 读出来。

## 11. RDMA 里的 FlowStatTag

`FlowIDNUMTag` 解决的是：

```text
这个包属于哪个 flow。
```

`FlowStatTag` 解决的是：

```text
这个包处在 flow 生命周期的哪个位置。
```

代码来源：

```text
src/point-to-point/model/flow-stat-tag.h
src/point-to-point/model/flow-stat-tag.cc
```

核心定义：

```cpp
class FlowStatTag : public Tag {
public:
    enum FlowEnd_t {
        FLOW_END = 0x01,
        FLOW_NOTEND = 0x00,
        FLOW_START = 0x02,
        FLOW_START_AND_END = 0x03,
        FLOW_FIN = 0x04,
    };

    void SetType(uint8_t ttl);
    uint8_t GetType();
    void setInitiatedTime(double t);
    double getInitiatedTime();

private:
    uint8_t flow_stat;
    double initiatedTime;
};
```

字段含义是：

```text
flow_stat       这个 packet 是 flow start / end / normal
initiatedTime   发送端给这个 packet 打 tag 时的仿真时间
```

### 11.1 FlowStatTag 的类型

枚举值可以这样理解：

```text
FLOW_NOTEND          普通中间包
FLOW_START           flow 的第一个包
FLOW_END             flow 的最后一个包
FLOW_START_AND_END   这个 flow 只有一个包，既是开始也是结束
FLOW_FIN             额外的结束标记，具体是否使用要看项目逻辑
```

这里不是 RDMA 协议里的状态机。

它是仿真统计用的 flow 生命周期标记。

### 11.2 FlowStatTag 的序列化

实现代码：

```cpp
uint32_t
FlowStatTag::GetSerializedSize(void) const
{
    return sizeof(flow_stat) + sizeof(initiatedTime);
}

void
FlowStatTag::Serialize(TagBuffer i) const
{
    i.WriteU8(flow_stat);
    i.WriteDouble(initiatedTime);
}

void
FlowStatTag::Deserialize(TagBuffer i)
{
    uint8_t t = i.ReadU8();
    NS_ASSERT(t == FLOW_END ||
              t == FLOW_NOTEND ||
              t == FLOW_START ||
              t == FLOW_START_AND_END);
    flow_stat = t;

    double t2 = i.ReadDouble();
    initiatedTime = t2;
}
```

这段代码整体比较清楚：

```text
1 byte 保存 flow_stat。
8 byte 左右保存 double 时间。
```

但也有一个源码阅读时要注意的点。

`SetType` 里允许：

```cpp
ttl == FLOW_FIN
```

但 `Deserialize` 的断言里没有接受 `FLOW_FIN`。

也就是说：

```text
如果某个 packet 的 FlowStatTag 被设置成 FLOW_FIN，
再经过 Serialize / Deserialize，
可能触发断言。
```

这不一定说明当前路径一定会出错。

但它说明读源码时要检查：

```text
SetType 允许的值
Serialize 写出的值
Deserialize 接受的值
后续逻辑判断的值
```

是否完全一致。

## 12. 发送端如何设置 FlowStatTag

回到发送端。

代码来源：

```text
src/point-to-point/model/rdma-tx-scheduler.cc
```

核心代码：

```cpp
FlowStatTag fst;
uint64_t size = qp->m_size;

if (!p->PeekPacketTag(fst)) {
    if (size < config.mtu &&
        qp->snd_nxt + payload_size >= qp->m_size) {
        fst.SetType(FlowStatTag::FLOW_START_AND_END);
    } else if (qp->snd_nxt + payload_size >= qp->m_size) {
        fst.SetType(FlowStatTag::FLOW_END);
    } else if (qp->snd_nxt == 0) {
        fst.SetType(FlowStatTag::FLOW_START);
    } else {
        fst.SetType(FlowStatTag::FLOW_NOTEND);
    }

    fst.setInitiatedTime(Simulator::Now().GetSeconds());
    p->AddPacketTag(fst);
}
```

这段代码在回答一个问题：

```text
当前要发的这个 packet，是 flow 的哪个阶段？
```

逐个看条件。

### 12.1 FLOW_START_AND_END

```cpp
if (size < config.mtu &&
    qp->snd_nxt + payload_size >= qp->m_size)
```

如果整个 flow 比 MTU 还小，并且这个 packet 发完就覆盖了整个 flow：

```text
这个 packet 既是第一个包，也是最后一个包。
```

所以设置：

```cpp
fst.SetType(FlowStatTag::FLOW_START_AND_END);
```

### 12.2 FLOW_END

```cpp
else if (qp->snd_nxt + payload_size >= qp->m_size)
```

如果发完当前 packet 后，发送进度到达 flow 总大小：

```text
这是最后一个包。
```

所以设置：

```cpp
fst.SetType(FlowStatTag::FLOW_END);
```

### 12.3 FLOW_START

```cpp
else if (qp->snd_nxt == 0)
```

如果当前发送进度还是 0：

```text
这是第一个包。
```

所以设置：

```cpp
fst.SetType(FlowStatTag::FLOW_START);
```

### 12.4 FLOW_NOTEND

其余情况就是中间包：

```cpp
fst.SetType(FlowStatTag::FLOW_NOTEND);
```

### 12.5 记录发送起始时间

最后这一句很关键：

```cpp
fst.setInitiatedTime(Simulator::Now().GetSeconds());
```

它把发送端当前仿真时间写进 tag。

后面接收端拿到这个 tag，就可以用它计算 flow 的开始时间、结束时间和完成时间。

## 13. ACK/NACK/CNP 为什么要复制 FlowIDNUMTag

RDMA data packet 是原始数据包。

ACK/NACK/CNP 是接收端或拥塞反馈逻辑新创建的包。

新包通常是这样来的：

```cpp
Ptr<Packet> newp = Create<Packet>(...);
```

这意味着：

```text
newp 不是 oldp 的 Copy。
newp 不会自动带 oldp 的 PacketTag。
```

所以反馈包构造时要手动复制必要 tag。

代码来源：

```text
src/point-to-point/model/rdma-feedback-builder.cc
```

ACK/NACK 里有：

```cpp
FlowIDNUMTag fit;
if (oldp->PeekPacketTag(fit)) {
    newp->AddPacketTag(fit);
}
```

CNP 里也有：

```cpp
FlowIDNUMTag fit;
if (oldp->PeekPacketTag(fit)) {
    newp->AddPacketTag(fit);
}
```

这段代码的意思是：

```text
如果原始 data packet 带着 flow id，
那么新生成的反馈包也继承这个 flow id。
```

为什么有必要？

因为统计和调试时，我们希望知道：

```text
这个 ACK 属于哪个 flow。
这个 NACK 属于哪个 flow。
这个 CNP 是哪个 flow 触发的。
```

但这些信息不应该写进 ACK/NACK/CNP 的真实协议 header。

所以复制 `FlowIDNUMTag` 是一个合理设计。

## 14. 接收端如何用 FlowStatTag 统计 FCT

Tag 的价值在接收端会更明显。

代码来源：

```text
src/applications/model/udp-server.cc
```

核心逻辑：

```cpp
FlowStatTag fst;
FlowIDNUMTag fit;

if (packet->PeekPacketTag(fst) && packet->PeekPacketTag(fit)) {
    if (firstUsed.GetSeconds() == 0 &&
        fst.GetType() == FlowStatTag::FLOW_START_AND_END) {
        firstUsed = Seconds(fst.getInitiatedTime());
        flow_end_time = Simulator::Now();
        lastUsed = Simulator::Now();
    } else if (firstUsed.GetSeconds() == 0 &&
               fst.GetType() == FlowStatTag::FLOW_START) {
        firstUsed = Seconds(fst.getInitiatedTime());
    } else if (firstUsed.GetSeconds() != 0 &&
               flow_end_time == 0 &&
               fst.GetType() == FlowStatTag::FLOW_END &&
               m_app_recv_buffer.isComplete(expected_flow_size)) {
        flow_end_time = Simulator::Now();
        lastUsed = Simulator::Now();
    }

    incoming_flow_id = fit.GetId();
}
```

这段代码说明了 `FlowStatTag` 和 `FlowIDNUMTag` 的分工：

```text
FlowStatTag   判断 flow 开始和结束
FlowIDNUMTag  知道当前是哪条 flow
```

接收端不是通过真实 RDMA header 得到这些统计信息的。

它是通过 tag 读出来的。

这正是 tag 的用途：

```text
不影响协议逻辑，但帮助仿真统计。
```

## 15. PFC 统计里也会用 FlowIDNUMTag

`FlowIDNUMTag` 不只用于 FCT。

在队列和 PFC 相关逻辑里，它也能帮助统计某条 flow 被 pause 影响了多久。

代码来源：

```text
src/network/utils/broadcom-egress-queue.cc
```

简化逻辑：

```cpp
FlowIDNUMTag fit;
Ptr<Packet> p = ConstCast<Packet, const Packet>(m_queues[q]->Peek());

if (p->PeekPacketTag(fit)) {
    unsigned flowid = static_cast<unsigned>(fit.GetId());
    if (!MAP_KEY_EXISTS(current_pause_time, flowid)) {
        current_pause_time[flowid] = Simulator::Now();
    }
}
```

后面真正 dequeue 时，还会读同一个 tag：

```cpp
FlowIDNUMTag fit;
if (p->PeekPacketTag(fit)) {
    unsigned flowid = static_cast<unsigned>(fit.GetId());
    if (MAP_KEY_EXISTS(current_pause_time, flowid)) {
        Time tdiff = Simulator::Now() - current_pause_time[flowid];
        acc_pause_time[flowid] = acc_pause_time[flowid] + tdiff;
    }
}
```

这里的语义是：

```text
如果某个队列因为 PFC 暂停而不能发包，
就用 packet 上的 flow id 记录是哪条 flow 被挡住。

等这个 flow 的包后来能出队，
再计算被挡住的时间。
```

注意，这完全是仿真统计逻辑。

真实交换机不会在 packet 上携带 `FlowIDNUMTag`。

## 16. FlowIdTag 和 FlowIDNUMTag 不要混淆

ns-3 里还有一个自带或通用的：

```cpp
FlowIdTag
```

代码来源：

```text
src/network/utils/flow-id-tag.h
src/network/utils/flow-id-tag.cc
```

你的 Qbb/PointToPoint 代码里也有：

```cpp
packet->AddPacketTag(FlowIdTag(m_ifIndex));
```

以及：

```cpp
FlowIdTag t;
packet->PeekPacketTag(t);
uint32_t inDev = t.GetFlowId();
```

这个 `FlowIdTag` 在一些路径里被用来记录：

```text
packet 从哪个 ingress device / port 进来。
```

而 `FlowIDNUMTag` 在 RDMA flow 统计里通常表示：

```text
业务 flow id 和 flow size。
```

两者名字很像，但不是同一个类型。

所以读源码时不能只看名字里的 `FlowId`。

要看：

```text
具体类名是什么
它的 TypeId 是什么
它在哪里 Add
它在哪里 Peek
它的字段是什么
```

## 17. Header、PacketTag、ByteTag 怎么选择

可以用这张表判断。

| 需求 | 应该用什么 |
|---|---|
| 接收端协议必须解析这个字段 | Header |
| 字段会影响 packet 的真实长度和发送时间 | Header |
| 字段只是仿真统计或调试 | PacketTag |
| 字段描述整个 packet，例如 flow id | PacketTag |
| 字段描述 payload 的某段字节 | ByteTag |
| 新建反馈包也要知道原 flow id | 手动从 oldp Peek，再 Add 到 newp |
| 修改 IPv4 ECN 位 | Header |
| 记录 flow 第一个包和最后一个包 | PacketTag |
| 记录某段数据的 delay/jitter | ByteTag |

这张表在 RDMA 源码里尤其有用。

比如：

```text
CNP 里的 qfb、ecn bits、total
```

这些是协议反馈内容，应该在 `CnHeader`。

而：

```text
这个 CNP 属于哪个 flow
```

适合继承 `FlowIDNUMTag`。

## 18. 新增一个 Tag 应该怎么写

假设你以后要新增一个 tag，用来记录：

```text
这个 packet 选择了哪条 path
这个 path 是第几轮 probe 选出来的
```

大致应该按这个步骤写。

### 18.1 定义类

```cpp
class MyPathTag : public Tag
{
public:
    MyPathTag();
    static TypeId GetTypeId(void);
    virtual TypeId GetInstanceTypeId(void) const;

    virtual uint32_t GetSerializedSize(void) const;
    virtual void Serialize(TagBuffer i) const;
    virtual void Deserialize(TagBuffer i);
    virtual void Print(std::ostream &os) const;

    void SetPath(uint32_t path);
    uint32_t GetPath() const;

private:
    uint32_t m_path;
};
```

### 18.2 注册 TypeId

```cpp
NS_OBJECT_ENSURE_REGISTERED(MyPathTag);

TypeId
MyPathTag::GetTypeId(void)
{
    static TypeId tid = TypeId("ns3::MyPathTag")
        .SetParent<Tag>()
        .AddConstructor<MyPathTag>();
    return tid;
}

TypeId
MyPathTag::GetInstanceTypeId(void) const
{
    return GetTypeId();
}
```

### 18.3 写序列化函数

```cpp
uint32_t
MyPathTag::GetSerializedSize(void) const
{
    return sizeof(m_path);
}

void
MyPathTag::Serialize(TagBuffer i) const
{
    i.WriteU32(m_path);
}

void
MyPathTag::Deserialize(TagBuffer i)
{
    m_path = i.ReadU32();
}
```

这里要检查：

```text
sizeof(m_path) 对应 WriteU32 / ReadU32。
```

不要出现：

```text
成员是 uint32_t
GetSerializedSize 按 4 字节算
Serialize 却只 WriteU16
```

除非你非常明确就是要截断。

### 18.4 Add 前先 Peek

如果这个 tag 对一个 packet 只应该存在一份，推荐写：

```cpp
MyPathTag tag;
if (!p->PeekPacketTag(tag)) {
    tag.SetPath(path);
    p->AddPacketTag(tag);
}
```

如果是更新已有 tag，推荐写：

```cpp
MyPathTag tag;
tag.SetPath(newPath);
p->ReplacePacketTag(tag);
```

不要不检查就连续：

```cpp
p->AddPacketTag(tag);
p->AddPacketTag(tag);
```

同类型 tag 重复添加会触发断言。

## 19. 读 Tag 调用链时的检查清单

以后看到一个 tag，可以按这个顺序读。

```text
1. 这个 Tag 类在哪里定义？
2. 它继承的是不是 ns3::Tag？
3. GetTypeId 里注册的 TypeId 名字是什么？
4. 成员变量有哪些？
5. GetSerializedSize / Serialize / Deserialize 是否一致？
6. 它在哪里 AddPacketTag？
7. Add 前有没有先 Peek，避免重复添加？
8. 它在哪里 PeekPacketTag？
9. 有没有地方 RemovePacketTag，导致后续读不到？
10. 新创建的 packet 是否需要复制旧 packet 的 tag？
11. 这个信息到底应该是 Header，还是 Tag？
12. 这个 tag 服务的是协议逻辑，还是统计调试？
```

这个检查清单比死记 API 更有用。

因为 Tag 的错误经常不是语法错误，而是语义错误。

比如：

```text
把真实协议字段放进 Tag，导致接收端协议解析不到。
把统计字段放进 Header，导致 packet size 和链路时间被污染。
忘记复制 FlowIDNUMTag，导致反馈包无法归属到 flow。
用 RemovePacketTag 读 flow id，导致后续模块读不到。
重复 Add 同类型 Tag，触发 PacketTagList 断言。
Serialize / Deserialize 字节数不一致，导致读出的值不可靠。
```

## 20. 常见错误

### 错误 1：把 Tag 当成真实协议字段

如果一个字段必须被对端协议解析出来，就不要放 Tag。

比如：

```text
RDMA seq
ACK seq
CNP qfb
PFC pause time
```

这些应该在 Header。

Tag 适合保存：

```text
flow id
flow size
flow start/end
统计时间戳
内部路径标记
```

### 错误 2：以为 AddPacketTag 会改变 GetSize

`AddPacketTag` 不会像 `AddHeader` 那样改变真实 packet bytes。

所以：

```cpp
Time txTime = Seconds(m_bps.CalculateTxTime(p->GetSize()));
```

这里的 `GetSize()` 不会因为 `FlowIDNUMTag` 或 `FlowStatTag` 变大。

这也是为什么 flow 统计信息适合放 Tag。

它不会污染链路传输时间。

### 错误 3：重复 Add 同一种 PacketTag

`PacketTagList::Add` 会断言：

```text
不能添加两个同类型 PacketTag。
```

所以要写：

```cpp
FlowIDNUMTag tag;
if (!p->PeekPacketTag(tag)) {
    p->AddPacketTag(tag);
}
```

或者明确更新：

```cpp
p->ReplacePacketTag(tag);
```

### 错误 4：用 RemovePacketTag 代替 PeekPacketTag

如果只是读取，就用：

```cpp
p->PeekPacketTag(tag);
```

不要随手：

```cpp
p->RemovePacketTag(tag);
```

`Remove` 会把 tag 删除。

这可能导致后续模块无法继续读取 flow id、flow size、flow start/end。

### 错误 5：新建反馈包时忘记复制 tag

如果反馈包是：

```cpp
Ptr<Packet> newp = Create<Packet>(...);
```

那它不会自动继承 `oldp` 的 tag。

所以需要：

```cpp
FlowIDNUMTag fit;
if (oldp->PeekPacketTag(fit)) {
    newp->AddPacketTag(fit);
}
```

否则 ACK/NACK/CNP 可能就无法被统计系统归到原来的 flow。

### 错误 6：Serialize 和 GetSerializedSize 不一致

写自定义 Tag 时，一定检查：

```text
GetSerializedSize 返回多少字节
Serialize 实际写多少字节
Deserialize 实际读多少字节
```

比如 `FlowIDNUMTag` 里有一个值得注意的地方：

```text
flow_stat 是 int32_t
GetSerializedSize 按 sizeof(flow_stat) 计算
Serialize 用 WriteU16 写
Deserialize 用 ReadU16 读
```

这类不一致要么是历史遗留，要么是 bug 隐患。

读源码时不能忽略。

### 错误 7：只看 tag 名字，不看具体 TypeId

`FlowIdTag` 和 `FlowIDNUMTag` 名字很像。

但它们不是一个类。

一个常用于端口/设备相关标记。

一个用于 RDMA flow id / flow size。

读代码时要看：

```cpp
FlowIdTag
FlowIDNUMTag
```

到底是哪一个。

## 21. 回到最常见的一段 RDMA 代码

现在再看这段发送端代码：

```cpp
FlowIDNUMTag fint;
if (!p->PeekPacketTag(fint)) {
    fint.SetId(qp->m_flow_id);
    fint.SetFlowSize(qp->m_size);
    p->AddPacketTag(fint);
}

FlowStatTag fst;
if (!p->PeekPacketTag(fst)) {
    ...
    fst.setInitiatedTime(Simulator::Now().GetSeconds());
    p->AddPacketTag(fst);
}
```

它的意思已经很清楚了：

```text
这个 packet 的真实协议内容已经由 Header 构造好了。

现在额外给它贴两张仿真标签：

FlowIDNUMTag：
    这个包属于哪个 flow
    flow 总大小是多少

FlowStatTag：
    这个包是 flow 的开始、结束，还是中间包
    打 tag 时的仿真时间是多少
```

这些 tag 会跟着 packet 在仿真器里流动。

后面接收端、反馈包构造、队列统计、PFC 统计都可以读它们。

但它们不会变成真实链路上的字节。

这就是 ns-3 `Tag` 最核心的设计价值。

## 22. 总结

这一篇可以压缩成几句话：

```text
Tag 是 ns-3 给 Packet 挂的仿真元信息。

Header 改变真实协议字节。
Tag 不应该被当成真实协议字段。

PacketTag 挂在整个 packet 上。
ByteTag 挂在某段字节范围上。

AddPacketTag 是 const，因为它不改变 packet 的协议内容。
但同一个 packet 不能重复 Add 同类型 PacketTag。

PeekPacketTag 只读不删。
RemovePacketTag 读取并删除。
ReplacePacketTag 用来更新已有 tag。

Packet::Copy 会保留 tag。
Create<Packet>() 新建的包不会自动继承旧包 tag。

RDMA 源码里的 FlowIDNUMTag 用于 flow id / flow size。
FlowStatTag 用于 flow start / end / initiated time。

这些 tag 服务于 FCT、PFC、反馈包归属、调试和统计。
它们不是 RDMA 协议本身。
```

理解了 `Tag`，后面继续读 RDMA 发送路径、接收路径、ACK/NACK/CNP、PFC 和 trace 统计时，会少很多困惑。
