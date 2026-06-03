---
title: "C++ 系统补课 11：纯虚函数、接口类和虚析构函数"
date: 2026-06-03 17:10:00 +0800
permalink: /posts/cpp-pure-virtual-interface-virtual-destructor/
categories: [C++, 系统补课]
tags: [cpp, pure-virtual, interface, virtual-destructor, abstract-class, rdma]
description: "理解纯虚函数、抽象类、接口类和虚析构函数，解释为什么 RDMA 拥塞控制接口需要 virtual 析构函数。"
---

<!-- series-nav -->
> **系列位置**：C++ 系统补课，第 11 篇 / 共 19 篇
> **总目录**：[学习路线](/roadmap/)
> **上一篇**：[10：继承、多态、virtual 和 override](/posts/cpp-inheritance-polymorphism-virtual-override/)
> **下一篇**：[12：头文件、源文件、include 和 namespace](/posts/cpp-header-source-include-namespace/)


上一篇讲了继承和多态。

这篇继续讲接口类。

接口类常用于表达：

```text
这里需要一个能力。
至于具体怎么实现，由派生类决定。
```

## 1. 纯虚函数

纯虚函数形态：

```cpp
virtual void Run() = 0;
```

`= 0` 表示：

```text
这个函数没有默认实现。
派生类必须实现。
```

含有纯虚函数的类叫抽象类。

抽象类不能直接创建对象。

## 2. 接口类

接口类通常只有虚函数，没有太多数据。

例如：

```cpp
class IRdmaCongestionController {
public:
    virtual void OnAck(...) = 0;
    virtual void OnCongestionFeedback(...) = 0;
};
```

它表达：

```text
一个 RDMA 拥塞控制器应该具备哪些回调能力。
```

但不规定具体算法。

## 3. 派生类实现接口

```cpp
class DcqcnCongestionController
    : public IRdmaCongestionController {
public:
    void OnAck(...) override;
    void OnCongestionFeedback(...) override;
};
```

这里：

```text
DCQCN 实现了拥塞控制接口。
```

其他算法也可以实现同一接口。

上层代码不需要关心具体算法类型。

## 4. 为什么需要虚析构函数

如果基类指针指向派生类对象：

```cpp
IRdmaCongestionController* p =
    new DcqcnCongestionController();
```

后面通过基类指针删除：

```cpp
delete p;
```

为了正确调用派生类析构函数，基类析构函数应该是 virtual：

```cpp
class IRdmaCongestionController {
public:
    virtual ~IRdmaCongestionController() {}
};
```

否则可能只析构基类部分。

这会造成资源释放不完整。

## 5. unique_ptr 也需要虚析构函数

即使用：

```cpp
std::unique_ptr<IRdmaCongestionController> controller;
```

也仍然需要基类虚析构函数。

因为 `unique_ptr` 销毁时最终也是通过基类指针删除对象。

所以规则是：

```text
只要类要被当作多态基类使用，就应该有 virtual 析构函数。
```

## 6. 接口类的价值

接口类能把上层和具体实现解耦。

例如：

```cpp
m_ccController->OnCongestionFeedback(...);
```

上层只知道：

```text
m_ccController 是一个拥塞控制器。
```

不需要知道它是：

```text
DCQCN
HPCC
TIMELY
DCTCP
```

这让新增算法更容易。

## 7. 读源码时的检查问题

看到接口类，要问：

```text
1. 它有哪些纯虚函数？
2. 它表达什么能力？
3. 哪些类实现了它？
4. 是否通过基类指针/引用调用？
5. 析构函数是不是 virtual？
```

## 8. 小结

纯虚函数定义接口。

抽象类不能直接实例化。

接口类让不同实现共享同一调用入口。

虚析构函数保证通过基类指针销毁对象时行为正确。

下一篇进入：

```text
C++ 系统补课 12：头文件、源文件、include 和 namespace
```
