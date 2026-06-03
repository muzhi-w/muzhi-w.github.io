---
title: "C++ 系统补课 08：析构函数、栈对象、堆对象和 RAII"
date: 2026-06-03 17:07:00 +0800
permalink: /posts/cpp-destructor-lifetime-raii/
categories: [C++, 系统补课]
tags: [cpp, destructor, lifetime, stack, heap, raii, ns3]
description: "从对象生命周期、栈对象、堆对象、析构函数和 RAII 讲起，为理解 C++ 智能指针和 ns-3 Ptr<T> 打地基。"
---

<!-- series-nav -->
> **系列位置**：C++ 系统补课，第 08 篇 / 共 19 篇
> **总目录**：[学习路线](/roadmap/)
> **上一篇**：[07：构造函数、初始化列表和 this 指针](/posts/cpp-constructor-initializer-this/)
> **下一篇**：[09：拷贝构造、赋值运算符和对象复制](/posts/cpp-copy-constructor-assignment/)


构造函数负责对象创建。

析构函数负责对象销毁。

C++ 难的地方在于：

```text
对象什么时候创建？
对象什么时候销毁？
谁负责销毁？
资源什么时候释放？
```

这篇讲对象生命周期。

## 1. 析构函数是什么

析构函数是对象销毁时自动调用的特殊函数。

```cpp
class Foo {
public:
    ~Foo() {
        // 清理工作
    }
};
```

析构函数特点：

```text
名字是 ~类名
没有返回值
没有参数
对象销毁时自动调用
```

## 2. 栈对象

局部变量通常是栈对象。

```cpp
void f() {
    Foo foo;
}
```

当执行进入函数 `f` 时，`foo` 被创建。

当函数结束时，`foo` 被销毁。

生命周期很清楚：

```text
进入作用域 -> 构造
离开作用域 -> 析构
```

## 3. 堆对象

用 `new` 创建的对象在堆上。

```cpp
Foo* p = new Foo();
```

这会创建一个 `Foo` 对象，并返回它的地址。

需要手动释放：

```cpp
delete p;
```

如果忘记 `delete`，就会内存泄漏。

如果重复 `delete`，也会出问题。

这就是裸 `new/delete` 危险的原因。

## 4. RAII

RAII 是 C++ 里非常重要的思想。

全称是：

```text
Resource Acquisition Is Initialization
```

可以理解为：

```text
资源的获取和对象生命周期绑定。
对象创建时获取资源。
对象销毁时释放资源。
```

智能指针就是 RAII 的典型例子。

```cpp
std::unique_ptr<Foo> p(new Foo());
```

当 `p` 离开作用域时，它会自动删除 `Foo`。

## 5. ns-3 Ptr<T> 和生命周期

ns-3 不主要使用 `std::shared_ptr`。

它有自己的：

```cpp
Ptr<T>
```

例如：

```cpp
Ptr<Packet> p = Create<Packet>(1000);
```

`Ptr<T>` 和引用计数配合。

当没有 `Ptr` 再引用对象时，对象可以被释放。

这也是一种资源管理思想。

## 6. EventId 和生命周期

事件系统里也有生命周期问题。

例如：

```cpp
Simulator::Schedule(delay, &Foo::Bar, this);
```

如果 `Foo` 对象在事件触发前销毁，就可能访问悬空指针。

所以对象销毁前通常要取消相关事件。

RDMA QP 完成时取消重传事件，就是这种生命周期意识。

## 7. 析构函数和 virtual

如果通过基类指针删除派生类对象，基类析构函数应该是 virtual。

例如：

```cpp
class Base {
public:
    virtual ~Base() {}
};
```

否则：

```cpp
Base* p = new Derived();
delete p;
```

可能只调用 `Base` 析构，不调用 `Derived` 析构。

这会导致资源释放不完整。

后面接口类文章会详细讲。

## 8. 生命周期的源码阅读问题

读 C++ 源码时，要问：

```text
1. 这个对象在哪里创建？
2. 是栈对象、堆对象，还是由智能指针管理？
3. 谁拥有它？
4. 它什么时候销毁？
5. 销毁前有没有需要取消的事件或释放的资源？
6. 如果通过基类指针管理，析构函数是不是 virtual？
```

## 9. 小结

C++ 不只是写对象。

还要知道对象什么时候死。

核心概念：

```text
构造函数：对象创建
析构函数：对象销毁
栈对象：离开作用域自动销毁
堆对象：new 创建，需要释放
RAII：把资源释放绑定到对象生命周期
```

下一篇进入：

```text
C++ 系统补课 09：拷贝构造、赋值运算符和对象复制
```
