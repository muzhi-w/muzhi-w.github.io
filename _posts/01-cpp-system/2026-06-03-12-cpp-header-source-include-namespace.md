---
title: "C++ 系统补课 12：头文件、源文件、include 和 namespace"
date: 2026-06-03 17:11:00 +0800
permalink: /posts/cpp-header-source-include-namespace/
categories: [C++, 系统补课]
tags: [cpp, header, source-file, include, namespace, include-guard]
description: "理解 .h、.cc、#include、include guard 和 namespace，建立阅读 C++ 工程文件结构的基本能力。"
---

<!-- series-nav -->
> **系列位置**：C++ 系统补课，第 12 篇 / 共 19 篇
> **总目录**：[学习路线](/roadmap/)
> **上一篇**：[11：纯虚函数、接口类和虚析构函数](/posts/cpp-pure-virtual-interface-virtual-destructor/)
> **下一篇**：[13：编译、链接、库和构建系统](/posts/cpp-compile-link-library-build/)


C++ 工程不是一个文件。

它通常由大量头文件和源文件组成：

```text
.h
.cc
```

读 ns-3/RDMA 源码时，必须知道这些文件之间怎么配合。

## 1. 头文件是什么

头文件通常放声明。

例如：

```cpp
class Packet;

class Packet {
public:
    uint32_t GetSize(void) const;
};
```

头文件告诉别的文件：

```text
有哪些类、函数、类型可以使用。
```

常见扩展名：

```text
.h
.hpp
```

ns-3 里主要是 `.h`。

## 2. 源文件是什么

源文件通常放实现。

例如：

```cpp
uint32_t
Packet::GetSize(void) const
{
    return m_buffer.GetSize();
}
```

源文件告诉编译器：

```text
函数具体怎么执行。
```

常见扩展名：

```text
.cc
.cpp
```

ns-3 里主要是 `.cc`。

## 3. #include 是什么

```cpp
#include "packet.h"
```

意思是：

```text
把 packet.h 的内容引入当前文件。
```

如果当前文件要使用 `Packet` 的完整定义，就需要 include 对应头文件。

例如：

```cpp
#include "ns3/packet.h"
```

## 4. include guard

头文件通常有：

```cpp
#ifndef PACKET_H
#define PACKET_H

// 内容

#endif
```

这叫 include guard。

它防止同一个头文件被重复包含导致重复定义。

现代 C++ 也常见：

```cpp
#pragma once
```

ns-3 老代码里更多是 include guard。

## 5. 前向声明

有时不需要完整定义，只需要知道某个类存在。

可以写：

```cpp
class Packet;
```

这叫前向声明。

适合用于：

```text
指针
引用
函数参数声明
```

但如果要访问成员函数或创建对象，就需要完整定义。

## 6. namespace 是什么

命名空间用来避免名字冲突。

ns-3 里的代码通常在：

```cpp
namespace ns3 {

// classes and functions

}
```

所以完整名字其实是：

```text
ns3::Packet
ns3::Time
ns3::Simulator
```

在 `namespace ns3` 内部，可以直接写：

```cpp
Packet
Time
Simulator
```

## 7. .h 和 .cc 怎么读

读一个类时，建议先读 `.h`。

因为头文件告诉读者：

```text
这个类有哪些成员变量？
有哪些 public 接口？
继承谁？
和哪些类型有关？
```

再读 `.cc`。

因为源文件告诉读者：

```text
这些函数具体怎么实现？
状态怎么变化？
调用了哪些其他模块？
```

## 8. 小结

头文件负责声明。

源文件负责实现。

`#include` 引入声明。

include guard 防止重复包含。

namespace 管理名字空间。

下一篇进入：

```text
C++ 系统补课 13：编译、链接、库和构建系统
```
