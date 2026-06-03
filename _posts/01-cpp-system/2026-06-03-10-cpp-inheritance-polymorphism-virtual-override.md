---
title: "C++ 系统补课 10：继承、多态、virtual 和 override"
date: 2026-06-03 17:09:00 +0800
permalink: /posts/cpp-inheritance-polymorphism-virtual-override/
categories: [C++, 系统补课]
tags: [cpp, inheritance, polymorphism, virtual, override, ns3]
description: "从 public 继承、基类引用、virtual 函数和 override 讲起，理解 ns-3 Header、Object 和 RDMA 控制器接口中的多态。"
---

<!-- series-nav -->
> **系列位置**：C++ 系统补课，第 10 篇 / 共 19 篇
> **总目录**：[学习路线](/roadmap/)
> **上一篇**：[09：拷贝构造、赋值运算符和对象复制](/posts/cpp-copy-constructor-assignment/)
> **下一篇**：[11：纯虚函数、接口类和虚析构函数](/posts/cpp-pure-virtual-interface-virtual-destructor/)


C++ 源码里经常看到：

```cpp
class Packet : public SimpleRefCount<Packet>
class Header : public Chunk
class RdmaQueuePair : public Object
```

这就是继承。

继承和多态让代码可以通过基类接口操作不同派生类对象。

## 1. 继承是什么

简单例子：

```cpp
class Animal {
public:
    void Eat();
};

class Dog : public Animal {
public:
    void Bark();
};
```

`Dog : public Animal` 表示：

```text
Dog 是一种 Animal。
Dog 继承 Animal 的 public 接口。
```

## 2. 基类和派生类

在：

```cpp
class Header : public Chunk
```

中：

```text
Chunk 是基类。
Header 是派生类。
```

在：

```cpp
class Ipv4Header : public Header
```

中：

```text
Header 是基类。
Ipv4Header 是派生类。
```

继承形成一种层次关系。

## 3. 基类引用可以绑定派生类对象

例如：

```cpp
Ipv4Header ip;
const Header& h = ip;
```

`ip` 是 `Ipv4Header`。

但它也是一种 `Header`。

所以 `Header&` 可以引用它。

这就是 `Packet::AddHeader` 的基础。

```cpp
void AddHeader(const Header& header);
```

它可以接收各种具体 header：

```text
Ipv4Header
UdpHeader
SeqTsHeader
qbbHeader
CnHeader
PauseHeader
```

## 4. virtual 是什么

基类中可以声明虚函数：

```cpp
class Header {
public:
    virtual uint32_t GetSerializedSize(void) const = 0;
    virtual void Serialize(Buffer::Iterator start) const = 0;
};
```

`virtual` 表示：

```text
这个函数可以在派生类中重写。
通过基类引用或指针调用时，运行时决定调用哪个版本。
```

这就是多态。

## 5. 纯虚函数

末尾的：

```cpp
= 0
```

表示纯虚函数。

```cpp
virtual void Serialize(...) const = 0;
```

意思是：

```text
Header 只规定接口。
具体怎么 Serialize，由派生类实现。
```

所以 `Header` 是抽象基类。

不能直接创建普通 `Header` 对象。

## 6. override

现代 C++ 推荐派生类重写虚函数时写：

```cpp
uint32_t GetSerializedSize(void) const override;
```

`override` 表示：

```text
这个函数明确要重写基类虚函数。
```

好处是：

```text
如果函数签名写错，编译器会报错。
```

ns-3 老代码不一定处处写 `override`，但阅读现代 C++ 时要认识它。

## 7. Packet::AddHeader 里的多态

```cpp
void AddHeader(const Header& header);
```

函数内部会调用：

```cpp
header.GetSerializedSize();
header.Serialize(...);
```

如果传入的是 `Ipv4Header`，调用的是 `Ipv4Header` 的实现。

如果传入的是 `UdpHeader`，调用的是 `UdpHeader` 的实现。

这就是多态。

同一个接口，不同对象表现不同。

## 8. RDMA 控制器接口里的多态

拥塞控制重构中，接口类通常会长这样：

```cpp
class IRdmaCongestionController {
public:
    virtual void OnCongestionFeedback(...) = 0;
};
```

不同算法实现：

```text
DcqcnCongestionController
HpccCongestionController
TimelyCongestionController
```

上层代码只持有：

```cpp
IRdmaCongestionController*
```

或：

```cpp
std::unique_ptr<IRdmaCongestionController>
```

实际调用哪个算法，由对象真实类型决定。

## 9. 读源码时的检查问题

看到继承和 virtual，可以问：

```text
1. 谁是基类？
2. 谁是派生类？
3. 基类定义了哪些虚函数？
4. 派生类重写了哪些函数？
5. 调用发生在基类指针/引用上吗？
6. 运行时实际对象类型是什么？
```

## 10. 小结

继承表达：

```text
派生类是一种基类。
```

多态表达：

```text
通过同一个基类接口，调用不同派生类实现。
```

`virtual` 是多态的关键。

`override` 是重写虚函数时的安全标记。

下一篇进入：

```text
C++ 系统补课 11：纯虚函数、接口类和虚析构函数
```
