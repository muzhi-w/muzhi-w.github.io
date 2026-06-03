---
title: "C++ 系统补课 17：智能指针和资源管理"
date: 2026-06-03 17:16:00 +0800
permalink: /posts/cpp-smart-pointer-resource-management/
categories: [C++, 系统补课]
tags: [cpp, smart-pointer, unique_ptr, shared_ptr, weak_ptr, raii, ns3-ptr]
description: "系统补课版智能指针入门：从所有权、RAII、unique_ptr、shared_ptr、weak_ptr 到 ns-3 Ptr<T> 的阅读方式。"
---

<!-- series-nav -->
> **系列位置**：C++ 系统补课，第 17 篇 / 共 19 篇
> **总目录**：[学习路线](/roadmap/)
> **上一篇**：[16：模板：template、typename 和泛型](/posts/cpp-template-typename-generic/)
> **下一篇**：[18：回到 ns-3：Ptr<T>、Object、Simulator、Packet](/posts/cpp-back-to-ns3-rdma-source-reading/)


裸指针只保存地址。

它不自动说明：

```text
谁拥有对象？
谁负责释放？
对象什么时候销毁？
```

智能指针就是为了解决资源管理问题。

## 1. 所有权

所有权表示：

```text
谁负责销毁这个对象。
```

裸指针：

```cpp
Foo* p = new Foo();
```

看不出谁负责 `delete`。

这容易造成：

```text
内存泄漏
重复释放
悬空指针
```

## 2. unique_ptr

```cpp
std::unique_ptr<Foo> p(new Foo());
```

`unique_ptr` 表示独占所有权。

```text
同一时刻只有一个 unique_ptr 拥有对象。
离开作用域自动 delete。
```

适合：

```text
对象只有一个明确拥有者。
```

RDMA 拥塞控制器成员就适合这种模式：

```cpp
std::unique_ptr<IRdmaCongestionController> m_ccController;
```

表示：

```text
RdmaHw 独占拥有这个控制器对象。
```

## 3. shared_ptr

```cpp
std::shared_ptr<Foo> p;
```

`shared_ptr` 表示共享所有权。

多个 `shared_ptr` 可以指向同一个对象。

最后一个 `shared_ptr` 销毁时，对象才销毁。

适合：

```text
多个对象共同拥有一个资源。
```

## 4. weak_ptr

`weak_ptr` 是弱引用。

它观察 `shared_ptr` 管理的对象，但不增加强引用计数。

主要用于避免循环引用。

例如：

```text
A shared_ptr 指向 B
B shared_ptr 又指向 A
```

可能导致双方都无法释放。

`weak_ptr` 可以打破这个循环。

## 5. ns-3 Ptr<T>

ns-3 有自己的智能指针：

```cpp
Ptr<T>
```

例如：

```cpp
Ptr<Packet> p = Create<Packet>(1000);
Ptr<RdmaQueuePair> qp;
Ptr<QbbNetDevice> dev;
```

它和 ns-3 的引用计数对象配合。

`Packet`、`Object` 等类型可以被 `Ptr<T>` 管理。

## 6. Ptr<T> 和 unique_ptr 的区别

```text
unique_ptr 表示独占所有权。
Ptr<T> 是 ns-3 引用计数智能指针。
```

`Ptr<T>` 更像：

```text
多个地方可以持有同一个 ns-3 对象的引用。
引用数归零后对象释放。
```

但它不是标准库的 `shared_ptr`。

它是 ns-3 自己的机制。

## 7. 智能指针和裸 this

即使工程里大量使用智能指针，仍然会看到：

```cpp
this
```

例如：

```cpp
Simulator::Schedule(delay, &Foo::Bar, this);
```

`this` 是裸指针。

它不延长对象生命周期。

所以事件系统里传 `this` 时，仍然要考虑对象是否还活着。

## 8. 读源码时的问题

看到指针，要问：

```text
1. 是裸指针还是智能指针？
2. 如果是智能指针，是 unique_ptr、shared_ptr 还是 ns-3 Ptr<T>？
3. 它表达独占所有权、共享所有权，还是普通引用？
4. 对象什么时候销毁？
5. 有没有循环引用或事件延迟调用风险？
```

## 9. 小结

智能指针的核心是资源管理。

```text
unique_ptr  独占所有权
shared_ptr  共享所有权
weak_ptr    弱引用
Ptr<T>      ns-3 引用计数智能指针
```

下一篇进入：

```text
C++ 系统补课 18：回到 ns-3：Ptr<T>、Object、Simulator、Packet
```
