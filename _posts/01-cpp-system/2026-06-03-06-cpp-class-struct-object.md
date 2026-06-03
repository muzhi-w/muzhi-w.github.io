---
title: "C++ 系统补课 06：class 和 struct：对象到底是什么"
date: 2026-06-03 17:05:00 +0800
permalink: /posts/cpp-class-struct-object/
categories: [C++, 系统补课]
tags: [cpp, class, struct, object, member, ns3, rdma]
description: "从 class、struct、成员变量、成员函数和访问控制讲起，理解 C++ 对象在 ns-3/RDMA 源码中的基本形态。"
---

<!-- series-nav -->
> **系列位置**：C++ 系统补课，第 06 篇 / 共 19 篇
> **总目录**：[学习路线](/roadmap/)
> **上一篇**：[05：const：从 const int 到 const 成员函数](/posts/cpp-const-from-variable-to-member-function/)
> **下一篇**：[07：构造函数、初始化列表和 this 指针](/posts/cpp-constructor-initializer-this/)


C++ 工程代码主要由类和对象组成。

在 ns-3/RDMA 源码里，到处都是：

```cpp
class Packet
class RdmaQueuePair
class QbbNetDevice
struct RdmaDcqcnQpState
```

这篇讲清楚：

```text
class 是什么？
struct 是什么？
对象是什么？
成员变量是什么？
成员函数是什么？
public/private 有什么用？
```

## 1. class 是在定义一种对象

最简单的类：

```cpp
class Point {
public:
    int x;
    int y;
};
```

这不是创建了一个具体点。

它是在定义：

```text
Point 这种对象长什么样。
```

后面写：

```cpp
Point p;
```

才是创建一个具体对象。

这个对象里有：

```text
p.x
p.y
```

## 2. 对象是什么

对象是某个类的具体实例。

```cpp
Point p;
```

这里：

```text
Point 是类型。
p 是对象。
```

再看 ns-3：

```cpp
Packet packet;
```

如果这样写，`packet` 就是一个 `Packet` 对象。

但 ns-3 更常见：

```cpp
Ptr<Packet> p = Create<Packet>(1000);
```

这里真正的 `Packet` 对象由 `Create<Packet>` 创建。

`p` 是指向它的 ns-3 智能指针。

## 3. 成员变量

类内部保存的数据叫成员变量。

代码来源：

```text
src/network/model/packet.h
```

```cpp
class Packet : public SimpleRefCount<Packet> {
private:
    Buffer m_buffer;
    ByteTagList m_byteTagList;
    PacketTagList m_packetTagList;
    PacketMetadata m_metadata;
};
```

这些都是 `Packet` 的成员变量：

```text
m_buffer
m_byteTagList
m_packetTagList
m_metadata
```

它们描述了一个 Packet 对象内部拥有什么状态。

## 4. 成员函数

类内部定义的函数叫成员函数。

例如：

```cpp
class Packet {
public:
    uint32_t GetSize(void) const;
    void AddHeader(const Header& header);
};
```

这些函数属于 `Packet`。

调用时要通过对象：

```cpp
p->GetSize();
p->AddHeader(ipHeader);
```

成员函数通常会访问或修改对象的成员变量。

比如 `AddHeader` 会修改 `Packet` 内部的 `m_buffer`。

## 5. public 和 private

`public` 表示外部可以访问。

`private` 表示只有类内部能访问。

例如：

```cpp
class Packet {
public:
    uint32_t GetSize(void) const;

private:
    Buffer m_buffer;
};
```

外部可以写：

```cpp
p->GetSize();
```

但不能直接写：

```cpp
p->m_buffer;
```

因为 `m_buffer` 是 private。

这叫封装。

它的目的不是故意藏东西，而是：

```text
让对象内部状态只能通过规定接口被访问和修改。
```

## 6. struct 和 class

C++ 里 `struct` 和 `class` 很像。

主要默认访问权限不同：

```text
struct 默认 public
class 默认 private
```

例如：

```cpp
struct Config {
    uint32_t win;
    bool enabled;
};
```

常用来表示一组简单数据。

RDMA 里有很多这种状态结构：

```cpp
struct RdmaDcqcnQpState {
    DataRate m_targetRate;
    EventId m_eventUpdateAlpha;
    double m_alpha;
    bool m_alpha_cnp_arrived;
};
```

这种 `struct` 主要是把相关状态放在一起。

## 7. 类负责表达职责

读类时，不要只看语法。

要问：

```text
这个类负责什么？
它保存什么状态？
它提供什么操作？
谁创建它？
谁使用它？
```

例如 `Packet`：

```text
负责表示网络包。
保存 Buffer 和 TagList。
提供 AddHeader、RemoveHeader、PeekHeader。
```

例如 `RdmaQueuePair`：

```text
负责表示 RDMA sender 侧 QP 状态。
保存序号、窗口、速率、定时器等状态。
```

例如 `QbbNetDevice`：

```text
负责网卡收发、队列、PFC、channel 交互。
```

## 8. 成员访问：. 和 ->

对象直接访问成员：

```cpp
Point p;
p.x = 10;
```

指针访问成员：

```cpp
Point* ptr = &p;
ptr->x = 20;
```

ns-3 智能指针也使用 `->`：

```cpp
Ptr<Packet> p = Create<Packet>(1000);
p->GetSize();
```

所以读代码时：

```text
.  表示对象本身访问成员
-> 表示通过指针访问成员
```

## 9. 小结

`class` 和 `struct` 用来定义对象类型。

对象内部有：

```text
成员变量：保存状态
成员函数：执行操作
```

`public/private` 用来控制访问。

读类时，要从工程角度问：

```text
这个类代表什么对象？
它保存什么状态？
它暴露什么接口？
```

下一篇进入：

```text
C++ 系统补课 07：构造函数、初始化列表和 this 指针
```
