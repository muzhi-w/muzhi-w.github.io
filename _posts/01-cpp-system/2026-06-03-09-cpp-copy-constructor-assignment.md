---
title: "C++ 系统补课 09：拷贝构造、赋值运算符和对象复制"
date: 2026-06-03 17:08:00 +0800
permalink: /posts/cpp-copy-constructor-assignment/
categories: [C++, 系统补课]
tags: [cpp, copy-constructor, assignment, copy, cow, packet, ns3]
description: "理解 C++ 对象复制、拷贝构造、赋值运算符、深拷贝和浅拷贝，并回到 ns-3 Packet::Copy 的 COW copy。"
---

<!-- series-nav -->
> **系列位置**：C++ 系统补课，第 09 篇 / 共 19 篇
> **总目录**：[学习路线](/roadmap/)
> **上一篇**：[08：析构函数、栈对象、堆对象和 RAII](/posts/cpp-destructor-lifetime-raii/)
> **下一篇**：[10：继承、多态、virtual 和 override](/posts/cpp-inheritance-polymorphism-virtual-override/)


对象不仅会创建和销毁。

对象还会被复制。

C++ 里对象复制是一个非常重要的话题。

读者在 ns-3 里会看到：

```cpp
Ptr<Packet> Copy(void) const;
```

也会看到：

```cpp
Packet(const Packet& o);
Packet& operator=(const Packet& o);
```

这篇讲对象复制。

## 1. 什么是拷贝

最简单例子：

```cpp
int a = 10;
int b = a;
```

这里 `b` 得到 `a` 的值。

对基本类型来说，这很简单。

但对对象来说，复制可能很复杂。

```cpp
Packet p1;
Packet p2 = p1;
```

这里要复制的不只是一个整数。

可能涉及：

```text
Buffer
TagList
Metadata
引用计数
内部共享数据
```

## 2. 拷贝构造函数

形态：

```cpp
ClassName(const ClassName& other);
```

例如：

```cpp
Packet(const Packet& o);
```

当用一个已有对象创建新对象时，会调用拷贝构造函数。

```cpp
Packet p2 = p1;
```

这里 `p2` 是新对象。

它从 `p1` 拷贝而来。

## 3. 赋值运算符

形态：

```cpp
ClassName& operator=(const ClassName& other);
```

例如：

```cpp
Packet& operator=(const Packet& o);
```

赋值发生在两个对象都已经存在时：

```cpp
Packet p1;
Packet p2;
p2 = p1;
```

这和拷贝构造不同。

```text
拷贝构造：用旧对象创建新对象。
赋值：两个对象都存在，把一个对象的值赋给另一个。
```

## 4. 浅拷贝和深拷贝

如果对象内部有指针，复制就复杂了。

浅拷贝：

```text
只复制指针地址。
两个对象指向同一块资源。
```

深拷贝：

```text
复制资源内容。
两个对象拥有独立资源。
```

浅拷贝可能导致：

```text
两个对象同时修改同一份数据
重复释放
生命周期混乱
```

深拷贝更独立，但成本更高。

## 5. Copy-on-write

ns-3 Packet 的 Copy 注释里提到：

```text
COW copy
```

COW 是：

```text
copy-on-write
```

意思是：

```text
复制时先共享内部数据。
只有在需要修改时，才复制出独立数据。
```

这样可以兼顾：

```text
逻辑上像独立副本
性能上避免不必要深拷贝
```

## 6. Packet::Copy

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

这里：

```text
new Packet(*this) 调用 Packet 拷贝构造函数。
返回值包进 Ptr<Packet>。
```

所以 `Copy()` 返回一个新的 `Packet` 智能指针。

调用者得到逻辑上的副本。

## 7. 为什么函数参数避免不必要拷贝

如果函数写成：

```cpp
void f(Packet p);
```

调用时可能复制 `Packet`。

如果只是读取，应写成：

```cpp
void f(const Packet& p);
```

或者在 ns-3 中使用：

```cpp
void f(Ptr<Packet> p);
```

这能避免复制整个大对象。

所以理解拷贝后，才能理解为什么 C++ 源码里大量使用引用和指针。

## 8. 读源码时的检查问题

看到对象复制相关代码，可以问：

```text
1. 这里是在拷贝构造，还是赋值？
2. 对象内部有没有资源？
3. 是深拷贝、浅拷贝，还是 COW？
4. 复制成本大不大？
5. 函数参数是否不小心触发了复制？
```

例如：

```cpp
Ptr<Packet> packet = p->Copy();
```

读成：

```text
创建 p 的逻辑副本。
返回 Ptr<Packet>。
底层可能使用 COW 优化。
```

## 9. 小结

对象复制有三件事要分清：

```text
拷贝构造：用旧对象创建新对象
赋值运算符：已有对象之间赋值
Copy 函数：类自己提供的复制接口
```

下一篇进入：

```text
C++ 系统补课 10：继承、多态、virtual 和 override
```
