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

这一篇的主线可以先记成：

```text
class 和 struct 都是在定义类型。
对象是按照某个类型创建出来的具体实体。
成员变量描述对象有什么状态。
成员函数描述对象能做什么操作。
public/private 描述外部能不能直接碰对象内部。
```

## 1. class 和 struct 都是在定义类型

最简单的类：

```cpp
class Point {
public:
    int x;
    int y;
};
```

这不是创建了一个具体的点。

它是在定义：

```text
Point 这种类型长什么样。
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

也就是说：

```text
class Point { ... };  定义 Point 类型
Point p;              创建 Point 类型的对象 p
```

`struct` 也是一样。

例如：

```cpp
struct Point {
    int x;
    int y;
};
```

这同样是在定义 `Point` 类型。

后面写：

```cpp
Point p;
```

才是在创建对象。

所以第一层不要把 `class`、`struct`、对象混在一起。

更准确的关系是：

```text
class / struct：定义类型。
变量声明：创建对象。
对象：某个类型的具体实例。
```

## 2. 对象是什么

对象是按照某个类型创建出来的具体实体。

```cpp
Point p;
```

这里：

```text
Point 是类型。
p 是对象。
```

如果写：

```cpp
Point p1;
Point p2;
```

那么 `p1` 和 `p2` 是两个不同对象。

它们类型相同，都是 `Point`。

但它们在内存中是两份不同的实体。

可以理解成：

```text
p1: [x][y]
p2: [x][y]
```

修改 `p1.x` 不会自动修改 `p2.x`。

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

这里要分清楚两个对象：

```text
p：Ptr<Packet> 类型的对象，也就是一个智能指针对象。
Create<Packet>(1000) 创建出来的对象：真正的 Packet 对象。
```

所以：

```cpp
Ptr<Packet> p = Create<Packet>(1000);
```

不能简单读成“p 就是 Packet 对象”。

更准确地读成：

```text
p 持有一个 Packet 对象。
p 可以通过 -> 访问那个 Packet 对象的成员函数。
```

## 3. 成员变量

类内部保存的数据叫成员变量。

成员变量描述的是：

```text
这种对象内部有哪些状态。
```

例如：

```cpp
class Point {
public:
    int x;
    int y;
};
```

`x` 和 `y` 是 `Point` 的成员变量。

如果创建两个对象：

```cpp
Point a;
Point b;

a.x = 1;
b.x = 2;
```

这里的 `a.x` 和 `b.x` 不是同一个变量。

它们分别属于不同对象。

可以理解成：

```text
a: [x = 1][y]
b: [x = 2][y]
```

所以成员变量不是“类全局共享的一份变量”。

普通成员变量是：

```text
每个对象各有一份。
```

代码来源：

```text
src/network/model/packet.h
```

简化摘录：

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

每一个具体的 `Packet` 对象，都会有自己的 `m_buffer`、`m_byteTagList`、`m_packetTagList` 和 `m_metadata`。

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

这里隐藏着一个重要问题：

```text
成员函数到底在操作哪个对象？
```

答案是：

```text
谁调用它，它就操作谁。
```

例如，用一个简单类示意：

```cpp
class Point {
public:
    void MoveTo(int newX, int newY) {
        x = newX;
        y = newY;
    }

private:
    int x;
    int y;
};
```

如果创建两个对象：

```cpp
Point p1;
Point p2;

p1.MoveTo(1, 1);
p2.MoveTo(2, 2);
```

第一次调用时，`MoveTo` 操作的是 `p1` 内部的 `x` 和 `y`。

第二次调用时，`MoveTo` 操作的是 `p2` 内部的 `x` 和 `y`。

`Packet` 也是同样的道理。

某个 `Packet` 对象调用 `AddHeader`，被修改的是那个对象自己的 `m_buffer`。

成员函数内部之所以知道“当前对象是谁”，是因为 C++ 会隐含传入一个 `this` 指针。

这一点下一篇会专门讲。

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

这就是 `class` 经常被用来表达“有职责的对象”的原因。

例如 `Packet` 不希望外部随便直接改 `m_buffer`。

外部应该通过：

```cpp
AddHeader()
RemoveHeader()
PeekHeader()
GetSize()
```

这些接口操作它。

这样 `Packet` 可以保证自己的内部状态始终是合法的。

所以 `private` 的意义不是“藏起来不让看”。

更准确地说：

```text
private 是对象给自己划出的内部边界。
public 是对象愿意暴露给外部使用的接口。
```

## 6. struct 和 class

C++ 里 `struct` 和 `class` 的能力几乎一样。

这句话很重要。

`struct` 不是只能放变量。

`struct` 也可以有：

```text
成员变量
成员函数
构造函数
析构函数
public/private/protected
继承
虚函数
```

`class` 也不是一定要把所有东西都藏起来。

`class` 里也可以有 public 成员变量。

所以在 C++ 里：

```text
struct 和 class 都是在定义类型。
```

它们真正的语法区别主要有两个。

### 6.1 默认访问权限不同

主要默认访问权限不同：

```text
struct 默认 public
class 默认 private
```

例如：

```cpp
struct A {
    int x;
};
```

等价于：

```cpp
struct A {
public:
    int x;
};
```

外部可以直接访问：

```cpp
A a;
a.x = 10;
```

而：

```cpp
class B {
    int x;
};
```

等价于：

```cpp
class B {
private:
    int x;
};
```

外部不能直接访问：

```cpp
B b;
b.x = 10;  // 错误：x 是 private
```

如果想让外部访问，就要显式写：

```cpp
class B {
public:
    int x;
};
```

所以：

```text
struct 里不写 public/private，默认就是 public。
class 里不写 public/private，默认就是 private。
```

### 6.2 默认继承权限不同

还有一个区别是默认继承权限。

例如：

```cpp
struct Child : Parent {
};
```

默认是：

```cpp
struct Child : public Parent {
};
```

而：

```cpp
class Child : Parent {
};
```

默认是：

```cpp
class Child : private Parent {
};
```

这个点初学时不一定马上用到。

但读源码时看到：

```cpp
class Packet : public SimpleRefCount<Packet>
```

就要注意这里显式写了 `public`。

代码来源：

```text
src/network/model/packet.h
```

简化摘录：

```cpp
class Packet : public SimpleRefCount<Packet> {
public:
    Packet();
    Ptr<Packet> CreateFragment(uint32_t start, uint32_t length) const;
    uint32_t GetSize(void) const;
    void AddHeader(const Header& header);
    uint32_t RemoveHeader(Header& header);
    uint32_t PeekHeader(Header& header) const;

private:
    Buffer m_buffer;
    ByteTagList m_byteTagList;
    PacketTagList m_packetTagList;
    PacketMetadata m_metadata;
};
```

这段代码可以这样读：

```text
Packet 是一个类。
Packet 公开继承 SimpleRefCount<Packet>。
public 区域是外部可以使用的接口。
private 区域是 Packet 自己管理的内部状态。
```

### 6.3 工程习惯：struct 偏数据，class 偏职责

既然 `struct` 和 `class` 能力几乎一样，为什么源码里还要区分？

因为工程代码通常会形成一种约定：

```text
struct 常用来表示一组简单数据。
class 常用来表示有职责、有接口、有内部状态保护的对象。
```

这不是 C++ 语法强制的。

这是工程习惯。

例如：

```cpp
struct Config {
    uint32_t win;
    bool enabled;
};
```

常用来表示一组简单数据。

RDMA 里有很多这种状态结构。

代码来源：

```text
src/point-to-point/model/rdma-cc-state.h
```

简化摘录：

```cpp
struct RdmaDcqcnQpState {
    DataRate m_targetRate;
    EventId m_eventUpdateAlpha;
    double m_alpha;
    bool m_alpha_cnp_arrived;
};
```

这种 `struct` 主要是把相关状态放在一起。

它表达的重点是：

```text
这里有一组 DCQCN 相关状态。
这些状态经常作为一个整体被某个 QP 或控制器持有。
```

再看 `Packet`。

`Packet` 不只是“一组字段”。

它有明确职责：

```text
表示网络包。
维护内部 Buffer。
提供 AddHeader、RemoveHeader、PeekHeader 等操作。
控制外部怎样修改内部状态。
```

所以它更适合写成 `class`。

这一点可以先记成：

```text
struct：更像“数据摆在这里”。
class：更像“对象有自己的规则和操作”。
```

但不要把这句话理解成语法规定。

更准确地说：

```text
这是 C++ 工程里的常见风格，不是编译器强制规则。
```

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

`class` 和 `struct` 都用来定义类型。

它们创建出来的具体实体叫对象。

对象内部有：

```text
成员变量：保存状态
成员函数：执行操作
```

`struct` 和 `class` 的主要语法区别是：

```text
struct 默认 public。
class 默认 private。
struct 默认 public 继承。
class 默认 private 继承。
```

但工程上更常见的使用习惯是：

```text
struct 偏向表达一组简单数据。
class 偏向表达有职责、有接口、有内部状态保护的对象。
```

`public/private` 用来控制访问边界。

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
