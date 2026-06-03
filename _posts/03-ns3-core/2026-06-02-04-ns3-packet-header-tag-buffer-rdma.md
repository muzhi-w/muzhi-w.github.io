---
title: "彻底理解 ns-3 的 Packet：Header、Tag、Buffer 和 RDMA 报文生命周期"
date: 2026-06-02 18:35:00 +0800
permalink: /posts/ns3-packet-header-tag-buffer-rdma/
categories: [网络, ns-3]
tags: [ns3, packet, header, tag, buffer, rdma, qbb, hpcc]
description: "从 Packet 的 Buffer、Header、Tag 和 Metadata 讲起，理解 AddHeader、RemoveHeader、PeekHeader、PacketTag/ByteTag，以及 RDMA 数据包、ACK/NACK、CNP、PFC 在 ns-3 里的生命周期。"
---

<!-- series-nav -->
> **系列位置**：ns-3 源码阅读，第 04 篇 / 共 4 篇
> **总目录**：[学习路线](/roadmap/)
> **上一篇**：[彻底理解 ns-3 事件系统：Simulator、EventId 和 RDMA 定时器](/posts/ns3-simulator-eventid-rdma-timers/)


前面几篇文章已经讲了：

```text
C++ 模板
C++ 智能指针
ns-3 的 Ptr<T>
ns-3 的 Object / TypeId / Attribute
ns-3 的 Simulator / EventId
```

现在可以开始看真正的网络数据本体：

```text
Packet
```

你在 RDMA 代码里会一直看到：

```cpp
Ptr<Packet> p

p->AddHeader(...)
p->RemoveHeader(...)
p->PeekHeader(...)

p->AddPacketTag(...)
p->PeekPacketTag(...)
p->RemovePacketTag(...)

p->Copy()
p->GetSize()
```

如果不理解 `Packet`，很多 RDMA 代码会显得很乱：

```text
为什么 AddHeader 的顺序是 SeqTs -> UDP -> IPv4 -> PPP？
为什么收到包时可以 PeekHeader(CustomHeader)？
为什么 ACK/NACK/CNP 是重新 Create<Packet>() 出来的？
为什么 FlowIDNUMTag 不在真实 header 里，却能跟着包走？
为什么 switch 可以 RemoveHeader(ipv4)，改 ECN，再 AddHeader(ipv4) 回去？
为什么 HPCC 可以直接 GetBuffer() 后往 INT 字段里 PushHop？
```

这篇文章专门讲清楚：

```text
Packet 内部到底有什么？
Buffer 是什么？
Header 是什么？
Tag 是什么？
Header 和 Tag 有什么区别？
AddHeader / RemoveHeader / PeekHeader 底层做了什么？
PacketTag 和 ByteTag 有什么区别？
RDMA data packet 是怎么构造、传输、解析和反馈的？
```

## 1. Packet 不是只有一段 bytes

直觉上，我们可能会以为一个 packet 就是：

```text
一段连续的字节数组
```

但 ns-3 的 `Packet` 不只是 bytes。

代码来源：

```text
src/network/model/packet.h
```

简化自源码：

```cpp
class Packet : public SimpleRefCount<Packet> {
private:
    Buffer m_buffer;
    ByteTagList m_byteTagList;
    PacketTagList m_packetTagList;
    PacketMetadata m_metadata;
};
```

所以一个 `Packet` 至少可以拆成四部分：

```text
m_buffer         真正的协议字节
m_byteTagList    贴在一段字节范围上的 tag
m_packetTagList  贴在整个 packet 上的 tag
m_metadata       header/trailer 的类型元信息，主要用于打印和检查
```

这四个东西分别解决不同的问题。

`m_buffer` 是最像真实网络包的部分。

它存的是：

```text
PPP header
IPv4 header
UDP header
SeqTsHeader
payload
```

这类真实协议内容。

`m_packetTagList` 和 `m_byteTagList` 是仿真辅助信息。

它们不是正常协议头的一部分。

比如：

```text
这个 packet 属于哪个 flow？
这个 flow 的总大小是多少？
这个 packet 是 flow start 还是 flow end？
这个 packet 从哪个 ingress interface 进来的？
```

这些信息很有用，但真实网络协议头里未必有标准字段可以放。

这时就可以用 `Tag`。

`m_metadata` 主要是 ns-3 为了知道 buffer 里曾经加过哪些 header/trailer。

它不一定默认打开完整打印能力。

## 2. Header 是真实协议字节

`Header` 是 ns-3 里所有协议头的基类。

代码来源：

```text
src/network/model/header.h
```

简化自源码：

```cpp
class Header : public Chunk
{
public:
    virtual uint32_t GetSerializedSize(void) const = 0;
    virtual void Serialize(Buffer::Iterator start) const = 0;
    virtual uint32_t Deserialize(Buffer::Iterator start) = 0;
    virtual void Print(std::ostream &os) const = 0;
};
```

只要一个类想被：

```cpp
p->AddHeader(header);
p->RemoveHeader(header);
p->PeekHeader(header);
```

使用，它就应该继承 `Header`，并实现这些函数。

这几个函数的含义非常直接：

```text
GetSerializedSize()  这个 header 需要多少字节
Serialize()          把这个 header 写进 Packet 的 Buffer
Deserialize()        从 Packet 的 Buffer 读出这个 header
Print()              打印 header 内容
```

所以 `Header` 是真实数据。

只要你：

```cpp
p->AddHeader(ipHeader);
```

这个 IPv4 header 的字节就真的被写进了 packet buffer。

`p->GetSize()` 也会变大。

## 3. Buffer 是 Header 真正写入的地方

`Packet` 里的真实字节存在：

```cpp
Buffer m_buffer;
```

代码来源：

```text
src/network/model/buffer.h
```

`Buffer` 提供了一个内部迭代器：

```cpp
class Buffer {
public:
    class Iterator {
        void Next(void);
        void Prev(void);
        void Next(uint32_t delta);
        void Prev(uint32_t delta);
        ...
    };
};
```

Header 的序列化函数就是拿这个 iterator 写字段。

比如一个 header 里可能会写：

```cpp
i.WriteHtonU32(m_seq);
i.WriteHtonU16(m_pg);
```

这就是真正把数字按网络字节序写进 packet buffer。

`Buffer` 还支持：

```text
在开头加空间
在末尾加空间
从开头删除
从末尾删除
创建 fragment
copy-on-write 复制
```

所以 `Packet::AddHeader` 可以高效地在 packet 前面塞 header。

## 4. AddHeader 做了什么

看源码。

代码来源：

```text
src/network/model/packet.cc
```

简化自源码：

```cpp
void
Packet::AddHeader(const Header &header)
{
    uint32_t size = header.GetSerializedSize();
    m_buffer.AddAtStart(size);
    header.Serialize(m_buffer.Begin());
    m_metadata.AddHeader(header, size);
}
```

这段可以翻译成：

```text
1. 问 header：你需要多少字节？
2. 在 packet buffer 的开头腾出这么多字节
3. 调用 header.Serialize，把 header 写进去
4. 更新 packet metadata
```

注意：

```text
AddHeader 是加在 packet 的最前面。
```

所以如果你这样写：

```cpp
p->AddHeader(seqTs);
p->AddHeader(udpHeader);
p->AddHeader(ipHeader);
p->AddHeader(ppp);
```

最终 packet 从外到内是：

```text
PPP | IPv4 | UDP | SeqTs | payload
```

这正是 RDMA data packet 构造时的顺序。

## 5. RemoveHeader 做了什么

代码来源：

```text
src/network/model/packet.cc
```

简化自源码：

```cpp
uint32_t
Packet::RemoveHeader(Header &header)
{
    uint32_t deserialized = header.Deserialize(m_buffer.Begin());
    m_buffer.RemoveAtStart(deserialized);
    m_metadata.RemoveHeader(header, deserialized);
    return deserialized;
}
```

它做的是：

```text
1. 从 packet buffer 开头读出 header
2. 把读出来的字段填进 header 对象
3. 从 packet buffer 开头删除这段 header 字节
4. 返回删除了多少字节
```

所以 `RemoveHeader` 会改变 packet。

如果一个包现在是：

```text
PPP | IPv4 | UDP | SeqTs | payload
```

调用：

```cpp
PppHeader ppp;
p->RemoveHeader(ppp);
```

之后 packet 会变成：

```text
IPv4 | UDP | SeqTs | payload
```

再调用：

```cpp
Ipv4Header ip;
p->RemoveHeader(ip);
```

之后 packet 会变成：

```text
UDP | SeqTs | payload
```

所以 remove 的顺序必须从外到内。

这和 add 的顺序正好相反。

## 6. PeekHeader 做了什么

代码来源：

```text
src/network/model/packet.cc
```

简化自源码：

```cpp
uint32_t
Packet::PeekHeader(Header &header) const
{
    uint32_t deserialized = header.Deserialize(m_buffer.Begin());
    return deserialized;
}
```

`PeekHeader` 和 `RemoveHeader` 最大区别是：

```text
PeekHeader 只读，不删除。
```

也就是说：

```cpp
CustomHeader ch(...);
p->PeekHeader(ch);
```

会从 packet buffer 开头解析 header 字段，把结果放进 `ch`。

但 packet 仍然保持原样。

所以你可以用它做分类：

```text
这是 UDP data？
这是 ACK？
这是 NACK？
这是 CNP？
这是 PFC？
源地址和目的地址是什么？
sport/dport 是什么？
seq 是多少？
ECN bit 是多少？
```

读完以后，包还能继续传下去。

这就是为什么你的 `QbbNetDevice::Receive` 里大量使用 `PeekHeader`。

## 7. AddHeader 顺序：从内到外

这是读 ns-3 Packet 代码时最重要的规律之一。

因为 `AddHeader` 总是加在最前面，所以构造一个完整 packet 时要：

```text
先加最内层 header
再加外层 header
最后加最外层 header
```

你的 RDMA 数据包构造就是标准例子。

代码来源：

```text
src/point-to-point/model/rdma-tx-scheduler.cc
```

简化自源码：

```cpp
Ptr<Packet> RdmaTxScheduler::BuildUdpDataPacket(
    Ptr<RdmaQueuePair> qp,
    uint32_t seq,
    uint32_t payload_size)
{
    Ptr<Packet> p = Create<Packet>(payload_size);

    SeqTsHeader seqTs;
    seqTs.SetSeq(seq);
    seqTs.SetPG(qp->m_pg);
    p->AddHeader(seqTs);

    UdpHeader udpHeader;
    udpHeader.SetDestinationPort(qp->dport);
    udpHeader.SetSourcePort(qp->sport);
    p->AddHeader(udpHeader);

    Ipv4Header ipHeader;
    ipHeader.SetSource(qp->sip);
    ipHeader.SetDestination(qp->dip);
    ipHeader.SetProtocol(RDMA_PROTO_UDP);
    ipHeader.SetPayloadSize(p->GetSize());
    p->AddHeader(ipHeader);

    PppHeader ppp;
    ppp.SetProtocol(RDMA_PPP_IPV4);
    p->AddHeader(ppp);

    return p;
}
```

这段执行完后，packet 的逻辑布局是：

```text
PPP | IPv4 | UDP | SeqTsHeader | payload
```

注意 `Ipv4Header::SetPayloadSize(p->GetSize())` 的位置。

它是在加 IPv4 header 之前调用的。

此时 `p` 里面已经有：

```text
UDP | SeqTsHeader | payload
```

这正好是 IPv4 payload 的大小。

IPv4 payload 不包括 IPv4 header 自己，也不包括 PPP header。

所以这个位置是有讲究的。

## 8. RemoveHeader 顺序：从外到内

如果要真的拆包，就要按相反顺序。

例如当前 packet 是：

```text
PPP | IPv4 | UDP | SeqTsHeader | payload
```

那么拆包应该是：

```cpp
PppHeader ppp;
p->RemoveHeader(ppp);

Ipv4Header ip;
p->RemoveHeader(ip);

UdpHeader udp;
p->RemoveHeader(udp);

SeqTsHeader seqTs;
p->RemoveHeader(seqTs);
```

因为 `RemoveHeader` 永远从 packet 当前开头开始读。

如果顺序错了，比如一上来就：

```cpp
UdpHeader udp;
p->RemoveHeader(udp);
```

那它会把 PPP header 的字节当成 UDP header 去解释。

结果当然会错。

## 9. PeekHeader 和 CustomHeader：你的代码里的快速解析器

你的 RDMA 代码里经常这样写：

代码来源：

```text
src/point-to-point/model/qbb-net-device.cc
```

```cpp
CustomHeader ch(
    CustomHeader::L2_Header |
    CustomHeader::L3_Header |
    CustomHeader::L4_Header);

ch.getInt = 1;
packet->PeekHeader(ch);
```

这里的 `CustomHeader` 是你这个代码库里非常重要的“快速解析器”。

它继承自 `Header`。

代码来源：

```text
src/network/utils/custom-header.h
```

简化自源码：

```cpp
class CustomHeader : public Header {
public:
    enum HeaderType {
        L2_Header = 1,
        L3_Header = 2,
        L4_Header = 4
    };

    uint16_t pppProto;

    uint32_t l3Prot : 8;
    uint32_t sip;
    uint32_t dip;

    union {
        struct {
            uint16_t sport;
            uint16_t dport;
            uint16_t payload_size;
            uint16_t pg;
            uint32_t seq;
            IntHeader ih;
        } udp;

        struct {
            uint16_t sport, dport;
            uint16_t flags;
            uint16_t pg;
            uint32_t seq;
            IntHeader ih;
            uint32_t irnNack;
            uint16_t irnNackSize;
        } ack;

        struct {
            uint8_t qIndex;
            uint16_t sport;
            uint16_t dport;
            uint8_t ecnBits;
            uint16_t qfb;
            uint16_t total;
        } cnp;

        struct {
            uint32_t time;
            uint32_t qlen;
            uint8_t qIndex;
        } pfc;
    };
};
```

`CustomHeader` 和普通 header 的使用方式有点不一样。

它不只是代表单个协议头。

它更像是：

```text
从 packet buffer 的开头一次性解析 L2/L3/L4 多层字段，
然后把结果放在一个方便读取的对象里。
```

比如它的 `Deserialize` 会先解析 PPP，再解析 IPv4，再根据 `l3Prot` 解析 UDP、ACK、NACK、CNP 或 PFC。

代码来源：

```text
src/network/utils/custom-header.cc
```

简化自源码：

```cpp
uint32_t CustomHeader::Deserialize(Buffer::Iterator start) {
    if (headerType & L2_Header) {
        pppProto = i.ReadNtohU16();
        i.Next(12);
    }

    if (headerType & L3_Header) {
        // parse IPv4 fields
        m_tos = i.ReadU8();
        ipid = i.ReadNtohU16();
        l3Prot = i.ReadU8();
        sip = i.ReadNtohU32();
        dip = i.ReadNtohU32();
    }

    if (headerType & L4_Header) {
        if (l3Prot == 0x11) {
            // UDP + SeqTsHeader
            udp.sport = i.ReadNtohU16();
            udp.dport = i.ReadNtohU16();
            udp.seq = i.ReadNtohU32();
            udp.pg = i.ReadNtohU16();
            if (getInt) {
                udp.ih.Deserialize(i);
            }
        }
    }
}
```

这就是为什么接收路径里可以直接写：

```cpp
packet->PeekHeader(ch);
```

然后马上判断：

```cpp
if (ch.l3Prot == RDMA_PROTO_UDP) ...
if (ch.l3Prot == RDMA_PROTO_ACK) ...
if (ch.l3Prot == RDMA_PROTO_NACK) ...
if (ch.l3Prot == RDMA_PROTO_CNP) ...
if (ch.l3Prot == RDMA_PROTO_PFC) ...
```

它的好处是：

```text
解析方便
不会破坏 packet
上层可以快速拿到 RDMA 需要的字段
```

它的代价是：

```text
CustomHeader 强依赖你的包格式。
如果真实 header 顺序或大小变了，CustomHeader 的解析逻辑也要同步改。
```

## 10. Tag 是仿真辅助信息

`Tag` 和 `Header` 完全不是一类东西。

代码来源：

```text
src/network/model/tag.h
```

简化自源码：

```cpp
class Tag : public ObjectBase
{
public:
    virtual uint32_t GetSerializedSize(void) const = 0;
    virtual void Serialize(TagBuffer i) const = 0;
    virtual void Deserialize(TagBuffer i) = 0;
    virtual void Print(std::ostream &os) const = 0;
};
```

它看起来也有 `Serialize/Deserialize`。

但要注意：

```text
Tag 序列化到的是 TagBuffer，不是 Packet 的真实协议 Buffer。
```

也就是说：

```text
Header 是网络包内容。
Tag 是 ns-3 仿真器给 packet 挂上的额外信息。
```

一个简单区别：

```text
AddHeader 会改变 packet 的真实字节和 GetSize()
AddPacketTag 一般不改变 packet 的真实协议字节和 GetSize()
```

所以如果某个字段必须被接收端协议解析出来，比如：

```text
IPv4 source/destination
UDP source/destination port
RDMA seq
ACK/NACK seq
CNP 信息
PFC pause time
```

它应该是 Header。

如果某个字段只是为了仿真统计、调试、跨层辅助，比如：

```text
flow id
flow size
flow start/end
入端口编号
某种 routing/负载均衡内部标记
```

它通常适合做 Tag。

## 11. PacketTag 和 ByteTag 的区别

ns-3 有两类 tag：

```text
PacketTag
ByteTag
```

源码注释里说得很清楚。

代码来源：

```text
src/network/model/packet.h
```

可以这样理解：

```text
PacketTag 是贴在整个 packet 上的。
ByteTag 是贴在 packet 的某段字节上的。
```

当 packet 被复制、切片、重组时：

```text
ByteTag 跟着具体字节走。
PacketTag 跟着 packet 这个整体走。
```

在你的 RDMA 代码里最常见的是 `PacketTag`。

例如：

```cpp
p->AddPacketTag(fint);
p->PeekPacketTag(fint);
p->RemovePacketTag(fint);
```

`ByteTag` 在 ns-3 里也很有用，但你现在这条 RDMA 主线主要先理解 `PacketTag` 就够了。

## 12. AddPacketTag / PeekPacketTag / RemovePacketTag

看源码。

代码来源：

```text
src/network/model/packet.cc
```

简化自源码：

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
Packet::PeekPacketTag(Tag &tag) const
{
    return m_packetTagList.Peek(tag);
}
```

注意 `AddPacketTag` 是 `const` 方法：

```cpp
void AddPacketTag(const Tag& tag) const;
```

这看起来反直觉。

为什么一个 `const Packet` 还能加 tag？

源码注释里的解释是：

```text
加 tag 不改变 packet 的协议内容和行为。
不关心这个 tag 的代码，看到这个 packet 时行为还是一样。
```

这对 trace 很有用。

一个 trace callback 即使拿到的是 `Ptr<const Packet>`，也可以给 packet 加调试 tag。

## 13. RDMA 里的 FlowIDNUMTag

代码来源：

```text
src/network/model/flow-id-num-tag.h
```

简化自源码：

```cpp
class FlowIDNUMTag : public Tag
{
public:
    void SetId(int32_t ttl);
    int32_t GetId();
    uint32_t GetFlowSize();
    void SetFlowSize(uint32_t fs);

private:
    int32_t flow_stat;
    uint32_t flow_size;
};
```

这个 tag 在发送端被加到 packet 上。

代码来源：

```text
src/point-to-point/model/rdma-tx-scheduler.cc
```

```cpp
FlowIDNUMTag fint;
if (!p->PeekPacketTag(fint)) {
    fint.SetId(qp->m_flow_id);
    fint.SetFlowSize(qp->m_size);
    p->AddPacketTag(fint);
}
```

这段代码的意思是：

```text
如果 packet 上还没有 FlowIDNUMTag，
就把当前 QP 的 flow id 和 flow size 放进 tag，
再挂到 packet 上。
```

这个信息不是网络协议 header。

它是仿真里为了统计、反馈包继承 flow 信息、调试方便而存在的。

比如 ACK/NACK/CNP 构造时，会从原 packet 复制这个 tag。

代码来源：

```text
src/point-to-point/model/rdma-feedback-builder.cc
```

```cpp
FlowIDNUMTag fit;
if (oldp->PeekPacketTag(fit)) {
    newp->AddPacketTag(fit);
}
```

这段的意思是：

```text
如果原 data packet 带了 flow id tag，
那么新生成的 ACK/NACK/CNP packet 也继承这个 flow id tag。
```

这样统计系统可以知道：

```text
这个反馈包对应哪个 flow。
```

## 14. RDMA 里的 FlowStatTag

代码来源：

```text
src/point-to-point/model/flow-stat-tag.h
```

简化自源码：

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

发送端会根据当前 packet 在 flow 中的位置设置它。

代码来源：

```text
src/point-to-point/model/rdma-tx-scheduler.cc
```

简化自源码：

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

这段代码的目标是：

```text
给 packet 打上 flow 生命周期标记：
    是第一个包？
    是最后一个包？
    既是第一个又是最后一个？
    还是中间普通包？

同时记录发起时间，便于后面统计 flow completion time。
```

这些都不应该塞进真实协议头。

所以它们适合做 `PacketTag`。

## 15. Header 和 Tag 的区别总结

可以用一张表记住。

```text
Header:
    属于真实 packet 字节
    AddHeader 会改变 Buffer
    AddHeader 会改变 GetSize()
    接收端协议可以从字节里解析出来
    适合表示 PPP/IPv4/UDP/SeqTs/qbb/CNP/PFC

Tag:
    属于 ns-3 仿真辅助信息
    AddPacketTag 不改变真实协议字节
    通常不改变 GetSize()
    不是真实网络协议的一部分
    适合表示 flow id、flow size、flow start/end、调试和跨层信息
```

一句话：

```text
Header 是包里真正带着走的数据。
Tag 是仿真器给包贴的小纸条。
```

## 16. Packet::Copy 是 COW copy

代码来源：

```text
src/network/model/packet.h
```

源码注释说：

```text
Packet::Copy 返回的是 COW copy。
```

COW 是：

```text
copy-on-write
```

也就是：

```text
复制时不一定立刻深拷贝所有字节。
两个 Packet 可以先共享内部数据。
直到某一方需要修改时，再做必要复制。
```

源码里 `Copy()` 很短。

代码来源：

```text
src/network/model/packet.cc
```

```cpp
Ptr<Packet>
Packet::Copy(void) const
{
    return Ptr<Packet>(new Packet(*this), false);
}
```

而 copy constructor 会复制：

```cpp
m_buffer
m_byteTagList
m_packetTagList
m_metadata
```

这让 `Packet::Copy()` 看起来像独立副本。

但性能上可以借助底层共享结构避免不必要的深拷贝。

你的 `QbbNetDevice` 里有这个用法。

代码来源：

```text
src/point-to-point/model/qbb-net-device.cc
```

```cpp
Ptr<Packet> packet = p->Copy();
packet->RemoveHeader(h);
```

这里复制一份 packet，是为了临时解析或处理 header，而不直接破坏原来的 `p`。

这是很常见的安全做法。

## 17. Create<Packet>(payload_size) 是什么意思

发送端构造 RDMA data packet 时：

代码来源：

```text
src/point-to-point/model/rdma-tx-scheduler.cc
```

```cpp
Ptr<Packet> p = Create<Packet>(payload_size);
```

这行的意思是：

```text
创建一个 Packet，里面先放 payload_size 字节的 payload。
```

这些 payload 在 ns-3 里通常是“占位字节”。

仿真并不一定关心每个 payload byte 的真实内容。

它更关心：

```text
这个包有多大？
序号是多少？
属于哪个 flow？
经过哪个队列？
什么时候发？
什么时候到？
会不会触发 ACK/NACK/CNP？
```

所以 `payload_size` 的意义很大。

它会影响：

```text
Packet::GetSize()
发送时间 txTime
队列占用
链路传输时间
flow 剩余字节
RTO/ACK 逻辑
```

而 payload 的每一个字节具体是什么，很多 RDMA 仿真并不关心。

## 18. RDMA data packet 的生命周期

现在把 `Packet` 放回 RDMA 主流程里。

一个 RDMA data packet 大概经历这些阶段：

```text
1. RdmaTxScheduler 创建 payload packet
2. AddHeader 构造 SeqTs / UDP / IPv4 / PPP
3. AddPacketTag 挂 flow 统计信息
4. QbbNetDevice 计算发送时间并交给 Channel
5. QbbChannel 用 Simulator 安排到达事件
6. 对端 QbbNetDevice::Receive 收到 packet
7. PeekHeader(CustomHeader) 快速解析字段
8. switch 或 NIC 根据 ch.l3Prot 分发
9. receiver RDMA 逻辑处理 seq，生成 ACK/NACK/CNP
```

下面一步一步看。

## 19. 第一步：发送端构造 data packet

代码来源：

```text
src/point-to-point/model/rdma-tx-scheduler.cc
```

核心代码：

```cpp
Ptr<Packet> p = Create<Packet>(payload_size);

SeqTsHeader seqTs;
seqTs.SetSeq(seq);
seqTs.SetPG(qp->m_pg);
p->AddHeader(seqTs);

UdpHeader udpHeader;
udpHeader.SetDestinationPort(qp->dport);
udpHeader.SetSourcePort(qp->sport);
p->AddHeader(udpHeader);

Ipv4Header ipHeader;
ipHeader.SetSource(qp->sip);
ipHeader.SetDestination(qp->dip);
ipHeader.SetProtocol(RDMA_PROTO_UDP);
ipHeader.SetPayloadSize(p->GetSize());
p->AddHeader(ipHeader);

PppHeader ppp;
ppp.SetProtocol(RDMA_PPP_IPV4);
p->AddHeader(ppp);
```

执行后：

```text
PPP | IPv4 | UDP | SeqTsHeader | payload
```

其中：

```text
SeqTsHeader 里放 RDMA data sequence 和 PG
UDP header 里放 sport/dport
IPv4 header 里放 sip/dip/protocol/payload size
PPP header 表示里面承载 IPv4
```

`SeqTsHeader` 在你这个代码库里也带了 `IntHeader`。

代码来源：

```text
src/internet/model/seq-ts-header.h
src/internet/model/seq-ts-header.cc
```

简化自源码：

```cpp
class SeqTsHeader : public Header
{
private:
    uint32_t m_seq;
    uint16_t m_pg;

public:
    IntHeader ih;
};

uint32_t SeqTsHeader::GetHeaderSize(void) {
    return 6 + IntHeader::GetStaticSize();
}

void SeqTsHeader::Serialize(Buffer::Iterator start) const {
    i.WriteHtonU32(m_seq);
    i.WriteHtonU16(m_pg);
    ih.Serialize(i);
}
```

也就是说，data packet 的 L4 payload 前部不仅有 seq/PG，还可能带 HPCC/INT 相关信息。

## 20. 第二步：发送端挂 flow tags

构造完真实 header 后，发送端还会挂 tag。

代码来源：

```text
src/point-to-point/model/rdma-tx-scheduler.cc
```

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

这一步不会改变 packet 的真实协议布局。

真实字节仍然是：

```text
PPP | IPv4 | UDP | SeqTsHeader | payload
```

但 packet 对象旁边多了两张“小纸条”：

```text
FlowIDNUMTag  这个 packet 属于哪个 flow，flow 总大小是多少
FlowStatTag   这个 packet 是 flow start/end/normal，以及发起时间
```

后续统计和反馈包构造会用到它们。

## 21. 第三步：QbbNetDevice 发送 packet

代码来源：

```text
src/point-to-point/model/qbb-net-device.cc
```

简化自源码：

```cpp
bool QbbNetDevice::TransmitStart(Ptr<Packet> p) {
    m_txMachineState = BUSY;
    m_currentPkt = p;

    Time txTime = Seconds(m_bps.CalculateTxTime(p->GetSize()));
    Time txCompleteTime = txTime + m_tInterframeGap;

    Simulator::Schedule(
        txCompleteTime,
        &QbbNetDevice::TransmitComplete,
        this);

    bool result = m_channel->TransmitStart(p, this, txTime);
    return result;
}
```

这里 `p->GetSize()` 很重要。

它包括：

```text
payload
SeqTsHeader
UDP header
IPv4 header
PPP header
```

但是不包括 `PacketTag`。

所以 `FlowIDNUMTag` 和 `FlowStatTag` 不会让链路发送时间变长。

这是合理的。

Tag 是仿真辅助信息，不是真实 wire bytes。

## 22. 第四步：QbbChannel 安排接收事件

代码来源：

```text
src/point-to-point/model/qbb-channel.cc
```

```cpp
bool QbbChannel::TransmitStart(
    Ptr<Packet> p,
    Ptr<QbbNetDevice> src,
    Time txTime)
{
    uint32_t wire = src == m_link[0].m_src ? 0 : 1;

    Simulator::ScheduleWithContext(
        m_link[wire].m_dst->GetNode()->GetId(),
        txTime + m_delay,
        &QbbNetDevice::Receive,
        m_link[wire].m_dst,
        p);

    return true;
}
```

这一步把前一篇事件系统文章也串起来了。

这段代码的意思是：

```text
经过发送时间 txTime 和传播延迟 m_delay 后，
在接收端 node 的上下文里，
调用接收端 QbbNetDevice::Receive(p)。
```

注意这里传的是：

```cpp
Ptr<Packet> p
```

所以事件对象会持有这个 packet 的智能指针。

packet 会至少活到接收事件执行。

## 23. 第五步：接收端用 CustomHeader 解析 packet

代码来源：

```text
src/point-to-point/model/qbb-net-device.cc
```

```cpp
CustomHeader ch(
    CustomHeader::L2_Header |
    CustomHeader::L3_Header |
    CustomHeader::L4_Header);

ch.getInt = 1;
packet->PeekHeader(ch);
```

这一步不会把 header 从 packet 中删掉。

它只是把字段解析到 `ch` 里。

然后代码根据 `ch.l3Prot` 分类。

代码来源：

```text
src/point-to-point/model/qbb-net-device.cc
```

```cpp
if (ch.l3Prot == 0xFE) {
    // PFC
} else {
    if (m_node->GetNodeType() > 0) {
        packet->AddPacketTag(FlowIdTag(m_ifIndex));
        m_node->SwitchReceiveFromDevice(this, packet, ch);
    } else {
        int ret = m_rdmaReceiveCb(packet, ch);
        if (ret == 0) DoMpiReceive(packet);
    }
}
```

这里可以看出两个分支：

```text
如果是 PFC，网卡本地处理 pause/resume。
如果不是 PFC：
    switch 节点交给 SwitchNode
    NIC 节点交给 RDMA receive callback
```

switch 分支里还做了一件事：

```cpp
packet->AddPacketTag(FlowIdTag(m_ifIndex));
```

这表示：

```text
给 packet 贴一个入端口相关的 tag。
```

它是 switch 内部逻辑用的仿真信息，不是网络协议头。

## 24. 第六步：switch 可以修改真实 header

switch 里可能要做 ECN 标记。

代码来源：

```text
src/point-to-point/model/switch-node.cc
```

简化自源码：

```cpp
if (m_ecnEnabled) {
    bool egressCongested = m_mmu->ShouldSendCN(ifIndex, qIndex);
    if (egressCongested) {
        PppHeader ppp;
        Ipv4Header h;

        p->RemoveHeader(ppp);
        p->RemoveHeader(h);

        h.SetEcn((Ipv4Header::EcnType)0x03);

        p->AddHeader(h);
        p->AddHeader(ppp);
    }
}
```

这段非常适合用来理解 `RemoveHeader` 和 `AddHeader`。

当前 packet 是：

```text
PPP | IPv4 | UDP | SeqTsHeader | payload
```

先：

```cpp
p->RemoveHeader(ppp);
```

变成：

```text
IPv4 | UDP | SeqTsHeader | payload
```

再：

```cpp
p->RemoveHeader(h);
```

变成：

```text
UDP | SeqTsHeader | payload
```

现在 `h` 这个 C++ 对象里已经装着原 IPv4 header 的字段。

于是可以：

```cpp
h.SetEcn((Ipv4Header::EcnType)0x03);
```

然后加回去：

```cpp
p->AddHeader(h);
p->AddHeader(ppp);
```

最终又变回：

```text
PPP | IPv4 | UDP | SeqTsHeader | payload
```

只是 IPv4 header 里的 ECN bits 被改了。

这就是：

```text
拆外层 header -> 修改字段 -> 按相反顺序加回去
```

## 25. 第七步：HPCC/INT 直接改 Buffer

你的 switch 代码里还有一段更底层的操作。

代码来源：

```text
src/point-to-point/model/switch-node.cc
```

```cpp
uint8_t *buf = p->GetBuffer();

if (buf[PppHeader::GetStaticSize() + 9] == 0x11) {
    IntHeader *ih =
        (IntHeader *)&buf[
            PppHeader::GetStaticSize() + 20 + 8 + 6
        ];

    if (m_ccMode == 3) {
        ih->PushHop(
            Simulator::Now().GetTimeStep(),
            m_txBytes[ifIndex],
            dev->GetQueue()->GetNBytesTotal(),
            dev->GetDataRate().GetBitRate());
    }
}
```

这里没有用：

```cpp
RemoveHeader
AddHeader
PeekHeader
```

而是直接拿到 packet buffer 的原始指针：

```cpp
p->GetBuffer()
```

然后根据偏移量找到 `IntHeader` 的位置，直接调用：

```cpp
ih->PushHop(...)
```

这很强，也很危险。

强在：

```text
它能直接修改 packet 里的 INT 字段，不需要拆包再组包。
```

危险在：

```text
它强依赖 header 大小和排列顺序。
```

这里的偏移：

```text
PppHeader::GetStaticSize() + 20 + 8 + 6
```

含义大致是：

```text
PPP header size
+ IPv4 header size
+ UDP header size
+ SeqTsHeader 中 seq/pg 的大小
= INT header 开始位置
```

如果以后你改变了：

```text
PPP header 大小
IPv4 header 是否有 options
UDP 前面的字段
SeqTsHeader 的格式
IntHeader::mode
```

这个偏移就可能不对。

所以这种代码要写注释，而且修改 packet 格式时要重点检查。

## 26. 第八步：Receiver 生成 ACK/NACK/CNP

当 receiver 处理 data packet 后，可能会生成反馈包：

```text
ACK
NACK
CNP
```

代码来源：

```text
src/point-to-point/model/rdma-feedback-builder.cc
```

```cpp
if (ShouldSendAckNack(rx_check_result)) {
    feedback.ack_nack =
        BuildAckNackPacket(
            config,
            oldp,
            ch,
            rxQp,
            payload_size,
            rx_check_result);
}

if (ShouldSendCnp(ch, ooo_congestion_hint)) {
    feedback.cnp = BuildCnpPacket(oldp, ch, rxQp);
}
```

这里的 `oldp` 是收到的 data packet。

`ch` 是从 oldp 里 `PeekHeader` 解析出来的字段。

反馈包不是在 oldp 上直接改出来的。

它是重新：

```cpp
Create<Packet>(...)
```

构造出来的。

## 27. ACK/NACK packet 怎么构造

代码来源：

```text
src/point-to-point/model/rdma-feedback-builder.cc
```

简化自源码：

```cpp
qbbHeader seqh;
seqh.SetSeq(rxQp->ReceiverNextExpectedSeq);
seqh.SetPG(ch.udp.pg);
seqh.SetSport(ch.udp.dport);
seqh.SetDport(ch.udp.sport);
seqh.SetIntHeader(ch.udp.ih);

Ptr<Packet> newp = Create<Packet>(
    std::max(60 - 14 - 20 - (int)seqh.GetSerializedSize(), 0));

newp->AddHeader(seqh);

Ipv4Header head;
head.SetDestination(Ipv4Address(ch.sip));
head.SetSource(Ipv4Address(ch.dip));
head.SetProtocol(rx_check_result == RX_SEQ_ACK ? RDMA_PROTO_ACK : RDMA_PROTO_NACK);
head.SetPayloadSize(newp->GetSize());

FlowIDNUMTag fit;
if (oldp->PeekPacketTag(fit)) {
    newp->AddPacketTag(fit);
}

newp->AddHeader(head);
AddIpv4PppHeader(newp);
```

最后 ACK/NACK packet 的布局是：

```text
PPP | IPv4 | qbbHeader | padding payload
```

这里有几个细节。

第一，sport/dport 反过来了：

```cpp
seqh.SetSport(ch.udp.dport);
seqh.SetDport(ch.udp.sport);
```

因为反馈包要从 receiver 发回 sender。

第二，IP 地址也反过来了：

```cpp
head.SetDestination(Ipv4Address(ch.sip));
head.SetSource(Ipv4Address(ch.dip));
```

第三，反馈包继承了 oldp 的 `FlowIDNUMTag`：

```cpp
if (oldp->PeekPacketTag(fit)) {
    newp->AddPacketTag(fit);
}
```

这让 ACK/NACK 也能被统计系统归到同一个 flow。

## 28. qbbHeader 是 ACK/NACK 的 RDMA header

代码来源：

```text
src/point-to-point/model/qbb-header.h
src/point-to-point/model/qbb-header.cc
```

简化自源码：

```cpp
class qbbHeader : public Header
{
public:
    void SetPG(uint16_t pg);
    void SetSeq(uint32_t seq);
    void SetSport(uint32_t sport);
    void SetDport(uint32_t dport);
    void SetIntHeader(const IntHeader &ih);
    void SetIrnNack(uint32_t seq);
    void SetIrnNackSize(size_t sz);

    virtual uint32_t GetSerializedSize(void) const;
    virtual void Serialize(Buffer::Iterator start) const;
    virtual uint32_t Deserialize(Buffer::Iterator start);

private:
    uint16_t sport, dport;
    uint16_t flags;
    uint16_t m_pg;
    uint32_t m_seq;
    IntHeader ih;
    uint32_t m_irn_nack;
    uint16_t m_irn_nack_size;
};
```

它的序列化逻辑是：

代码来源：

```text
src/point-to-point/model/qbb-header.cc
```

```cpp
void qbbHeader::Serialize(Buffer::Iterator start) const
{
    i.WriteU16(sport);
    i.WriteU16(dport);
    i.WriteU16(flags);
    i.WriteU16(m_pg);
    i.WriteU32(m_seq);
    i.WriteU32(m_irn_nack);
    i.WriteU16(m_irn_nack_size);
    ih.Serialize(i);
}
```

所以 ACK/NACK 的关键字段都是真实 header 字节：

```text
sport
dport
flags
pg
ack seq
IRN NACK seq
IRN NACK size
INT information
```

这些不是 tag。

因为 sender 收到 ACK/NACK 后必须从 packet 字节里解析这些控制信息。

## 29. CNP packet 怎么构造

代码来源：

```text
src/point-to-point/model/rdma-feedback-builder.cc
```

简化自源码：

```cpp
CnHeader cnh;
cnh.SetQindex((uint8_t)rxQp->m_ecn_source.qIndex);
cnh.SetSport(ch.udp.sport);
cnh.SetDport(ch.udp.dport);
cnh.SetECNBits(rxQp->m_ecn_source.ecnbits);
cnh.SetQfb(rxQp->m_ecn_source.qfb);
cnh.SetTotal(rxQp->m_ecn_source.total);

Ptr<Packet> newp = Create<Packet>(
    std::max(60 - 14 - 20 - (int)cnh.GetSerializedSize(), 0));

newp->AddHeader(cnh);

Ipv4Header head;
head.SetDestination(Ipv4Address(ch.sip));
head.SetSource(Ipv4Address(ch.dip));
head.SetProtocol(RDMA_PROTO_CNP);
head.SetPayloadSize(newp->GetSize());

FlowIDNUMTag fit;
if (oldp->PeekPacketTag(fit)) {
    newp->AddPacketTag(fit);
}

newp->AddHeader(head);
AddIpv4PppHeader(newp);
```

最后 CNP packet 的布局是：

```text
PPP | IPv4 | CnHeader | padding payload
```

CNP 的拥塞信息在 `CnHeader` 里。

`FlowIDNUMTag` 只是辅助统计。

这又体现了：

```text
协议语义字段放 Header。
仿真统计字段放 Tag。
```

## 30. PFC packet 怎么构造

PFC 是另一类控制包。

代码来源：

```text
src/point-to-point/model/qbb-net-device.cc
```

简化自源码：

```cpp
Ptr<Packet> p = Create<Packet>(0);

PauseHeader pauseh(
    (type == 0 ? m_pausetime : 0),
    m_queue->GetNBytes(qIndex),
    qIndex);

p->AddHeader(pauseh);

Ipv4Header ipv4h;
ipv4h.SetProtocol(0xFE);
ipv4h.SetSource(...);
ipv4h.SetDestination(Ipv4Address("255.255.255.255"));
ipv4h.SetPayloadSize(p->GetSize());
ipv4h.SetTtl(1);

p->AddHeader(ipv4h);
AddHeader(p, 0x800);

CustomHeader ch(...);
p->PeekHeader(ch);
SwitchSend(0, p, ch);
```

PFC packet 的布局是：

```text
PPP | IPv4 | PauseHeader
```

接收端解析后：

代码来源：

```text
src/point-to-point/model/qbb-net-device.cc
```

```cpp
if (ch.l3Prot == 0xFE) {
    unsigned qIndex = ch.pfc.qIndex;
    if (ch.pfc.time > 0) {
        m_paused[qIndex] = true;
        Simulator::Cancel(m_resumeEvt[qIndex]);
        m_resumeEvt[qIndex] =
            Simulator::Schedule(
                MicroSeconds(ch.pfc.time),
                &QbbNetDevice::Resume,
                this,
                qIndex);
    } else {
        Simulator::Cancel(m_resumeEvt[qIndex]);
        Resume(qIndex);
    }
}
```

这里就把三篇文章串起来了：

```text
Packet/Header 负责携带 PFC pause time 和 queue index
CustomHeader 负责 PeekHeader 解析 PFC 字段
Simulator/EventId 负责安排 resume timer
```

## 31. PacketMetadata 是干什么的

`Packet` 里还有：

```cpp
PacketMetadata m_metadata;
```

它记录 header/trailer 的类型和大小信息。

代码来源：

```text
src/network/model/packet.h
```

源码注释说，metadata 用来描述 buffer 中序列化过的 headers/trailers。

它的维护是可选的。

常见用途是：

```text
Packet::Print()
检查 AddHeader / RemoveHeader 是否匹配
调试 packet 中有哪些 header
```

这也是为什么 `AddHeader` 里有：

```cpp
m_metadata.AddHeader(header, size);
```

`RemoveHeader` 里有：

```cpp
m_metadata.RemoveHeader(header, deserialized);
```

不过正常仿真逻辑通常不直接依赖 metadata。

真正影响协议行为的是：

```text
m_buffer 里的字节
m_packetTagList / m_byteTagList 里的 tag
```

## 32. Packet UID 不是 flow id

`Packet` 有自己的 UID。

你会看到：

```cpp
p->GetUid()
```

这个 UID 是 `Packet` 对象内部的标识。

它不是：

```text
flow id
sequence number
真实包编号
发送端全局包数
```

源码注释里也提醒，packet uid 不适合作为“某个协议真正发送了多少包”的精确计数。

原因包括：

```text
packet copy
fragmentation
broadcast
重传
新建反馈包
```

如果要统计 RDMA flow，应该更多依赖：

```text
QP 状态
RDMA seq
FlowIDNUMTag
FlowStatTag
协议层自己的 packet counter
```

而不是单纯看 `Packet::GetUid()`。

## 33. Header / Tag / Event / Ptr 怎么串起来

现在可以把前几篇的知识连成一条链。

一个 data packet 从发送到接收，大概是：

```text
Ptr<Packet> p = Create<Packet>(payload_size)
    |
    v
Packet 内部有 Buffer / TagList / Metadata
    |
    v
AddHeader 把 SeqTs/UDP/IP/PPP 写进 Buffer
    |
    v
AddPacketTag 把 flow id / flow stat 挂到 TagList
    |
    v
QbbNetDevice::TransmitStart 根据 p->GetSize() 算 txTime
    |
    v
QbbChannel::TransmitStart 用 Simulator::ScheduleWithContext 安排 Receive(p)
    |
    v
事件对象保存 Ptr<Packet>，让 packet 活到接收事件
    |
    v
接收端 QbbNetDevice::Receive 用 PeekHeader(CustomHeader) 解析
    |
    v
RDMA/Switch 根据 ch.l3Prot 和 tags 决定后续逻辑
```

所以：

```text
Ptr<T> 解决对象生命周期
Packet 解决网络数据表达
Header 解决真实协议字节
Tag 解决仿真辅助信息
Simulator 解决 packet 在仿真时间里的到达
```

这几块不是分散的。

它们一起构成了 ns-3 的网络仿真模型。

## 34. 读 Packet 代码时的检查清单

以后看到一段 `Packet` 相关代码，可以按这个顺序看。

第一，看这是 Header 还是 Tag：

```text
AddHeader/RemoveHeader/PeekHeader 影响真实 packet 字节。
AddPacketTag/PeekPacketTag/RemovePacketTag 是仿真辅助信息。
```

第二，看 AddHeader 顺序：

```text
AddHeader 是从内到外加。
最后 Add 的 header 会出现在最外层。
```

第三，看 RemoveHeader 顺序：

```text
RemoveHeader 是从外到内拆。
顺序错了，就会把错误字节解释成错误 header。
```

第四，看 PeekHeader 是否会破坏 packet：

```text
PeekHeader 不删除 header。
RemoveHeader 会删除 header。
```

第五，看 `GetSize()` 用在哪里：

```text
链路发送时间
队列字节数
IPv4 payload size
统计 packet size
```

第六，看 tag 是否被复制到反馈包：

```text
ACK/NACK/CNP 如果要保留 flow 统计信息，需要从 oldp PeekPacketTag 再 AddPacketTag。
```

第七，看有没有直接操作 raw buffer：

```text
GetBuffer() + 偏移量通常很脆弱。
改 header 格式时必须检查。
```

## 35. 常见错误

### 错误 1：AddHeader 顺序写反

错误写法：

```cpp
p->AddHeader(ppp);
p->AddHeader(ip);
p->AddHeader(udp);
```

你以为最终是：

```text
PPP | IP | UDP | payload
```

但实际上会变成：

```text
UDP | IP | PPP | payload
```

因为每次 `AddHeader` 都加在最前面。

正确做法是：

```cpp
p->AddHeader(inner);
p->AddHeader(middle);
p->AddHeader(outer);
```

### 错误 2：RemoveHeader 顺序写反

当前 packet 是：

```text
PPP | IPv4 | UDP | payload
```

就必须先：

```cpp
p->RemoveHeader(ppp);
```

再：

```cpp
p->RemoveHeader(ip);
```

不能一上来 remove UDP。

### 错误 3：把 Tag 当成真实协议字段

如果一个字段必须跨节点、跨协议解析，而且真实协议逻辑依赖它，就不要只放 Tag。

比如 RDMA seq 应该在 `SeqTsHeader/qbbHeader` 里。

不能只放：

```cpp
p->AddPacketTag(seqTag);
```

因为 tag 不是 wire format 的一部分。

### 错误 4：以为 AddPacketTag 会改变 GetSize

`AddPacketTag` 一般不会改变真实 packet size。

所以它不会影响：

```text
链路传输时间
队列字节占用
IPv4 payload size
```

如果你需要改变这些，就应该改变 packet 的 buffer，也就是 header/payload/trailer。

### 错误 5：忘记反馈包继承 flow tag

如果 ACK/NACK/CNP 没有复制 `FlowIDNUMTag`，统计系统可能不知道这个反馈包属于哪个 flow。

你的代码里已经做了：

```cpp
FlowIDNUMTag fit;
if (oldp->PeekPacketTag(fit)) {
    newp->AddPacketTag(fit);
}
```

这就是一个很好的习惯。

### 错误 6：直接 GetBuffer 后忘记偏移依赖

像这类代码：

```cpp
uint8_t *buf = p->GetBuffer();
IntHeader *ih = (IntHeader *)&buf[offset];
```

一定要记住：

```text
offset 是写死的协议布局假设。
```

如果 header 结构变化，offset 就要重新检查。

### 错误 7：把 Packet UID 当成 flow id

`p->GetUid()` 是 packet 内部标识。

flow id 应该看：

```text
QP 的 m_flow_id
FlowIDNUMTag
协议或应用层自己的 flow 标识
```

## 36. 回到你最常见的一行代码

现在再看：

```cpp
Ptr<Packet> p = Create<Packet>(payload_size);
```

它不是“创建一个空 C++ 对象”这么简单。

它意味着：

```text
创建一个由 ns-3 引用计数管理的 Packet。
Packet 里有 payload_size 字节的仿真 payload。
后续可以往它的 Buffer 前面 AddHeader。
也可以给它挂 PacketTag/ByteTag。
它可以通过 Ptr<Packet> 在事件系统中传递。
```

再看：

```cpp
p->AddHeader(seqTs);
p->AddHeader(udpHeader);
p->AddHeader(ipHeader);
p->AddHeader(ppp);
```

它意味着：

```text
把真实协议字节写进 Packet::m_buffer。
最终形成：
PPP | IPv4 | UDP | SeqTsHeader | payload
```

再看：

```cpp
p->AddPacketTag(fint);
```

它意味着：

```text
给这个 packet 挂一份仿真辅助信息。
不改变真实协议字节。
不改变链路上的 packet size。
```

再看：

```cpp
packet->PeekHeader(ch);
```

它意味着：

```text
从 packet buffer 开头解析多层 header。
把解析结果放进 ch。
但是不删除 packet 里的 header。
```

这些理解打通后，RDMA 的包路径就会清晰很多。

## 37. 总结

`Packet` 是 ns-3 网络仿真的数据核心。

它内部不是只有 bytes，而是：

```text
Buffer
ByteTagList
PacketTagList
PacketMetadata
```

`Header` 是真实协议字节。

```text
AddHeader 写入 Buffer
RemoveHeader 从 Buffer 删除
PeekHeader 从 Buffer 读取但不删除
```

`Tag` 是仿真辅助信息。

```text
PacketTag 贴在整个 packet 上
ByteTag 贴在一段字节上
```

在你的 RDMA 代码里：

```text
SeqTsHeader / qbbHeader / CnHeader / PauseHeader / IPv4 / UDP / PPP
属于 Header

FlowIDNUMTag / FlowStatTag / FlowIdTag
属于 Tag
```

一个 RDMA data packet 大概是：

```text
PPP | IPv4 | UDP | SeqTsHeader | payload
```

一个 ACK/NACK packet 大概是：

```text
PPP | IPv4 | qbbHeader | padding
```

一个 CNP packet 大概是：

```text
PPP | IPv4 | CnHeader | padding
```

一个 PFC packet 大概是：

```text
PPP | IPv4 | PauseHeader
```

最后，把这句话记住就够用了：

```text
Header 是包的骨架和血肉，Tag 是仿真器贴在包上的便签。
Buffer 负责真实字节，Ptr<Packet> 负责生命周期，Simulator 负责让这个包在仿真时间里到达下一个对象。
```

到这里，再去读 RDMA 发送路径和接收路径，就不会像在看一团线了。
