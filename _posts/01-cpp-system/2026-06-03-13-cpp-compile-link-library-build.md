---
title: "C++ 系统补课 13：编译、链接、库和构建系统"
date: 2026-06-03 17:12:00 +0800
permalink: /posts/cpp-compile-link-library-build/
categories: [C++, 系统补课]
tags: [cpp, compile, link, library, build-system, waf, ns3]
description: "理解 C++ 从源文件到可执行程序的基本过程：预处理、编译、链接、库和构建系统，为读 ns-3 工程打地基。"
---

<!-- series-nav -->
> **系列位置**：C++ 系统补课，第 13 篇 / 共 19 篇
> **总目录**：[学习路线](/roadmap/)
> **上一篇**：[12：头文件、源文件、include 和 namespace](/posts/cpp-header-source-include-namespace/)
> **下一篇**：[14：STL 入门：string、vector、map 和 iterator](/posts/cpp-stl-string-vector-map-iterator/)


C++ 代码不是直接运行的。

它要经过构建过程。

大致是：

```text
预处理 -> 编译 -> 链接 -> 可执行程序
```

读大型工程时，理解这条链很重要。

## 1. 预处理

预处理处理：

```text
#include
#define
#if/#ifdef
```

例如：

```cpp
#include "packet.h"
```

预处理会把头文件内容展开到当前文件中。

## 2. 编译

编译器把 `.cc` 源文件编译成目标文件。

```text
packet.cc -> packet.o
rdma-hw.cc -> rdma-hw.o
```

编译阶段需要知道：

```text
类型声明
函数声明
类定义
模板定义
```

如果头文件没 include 对，就可能编译失败。

## 3. 链接

链接器把多个目标文件和库合在一起。

例如：

```text
packet.o
simulator.o
rdma-hw.o
qbb-net-device.o
```

链接成最终可执行程序或库。

如果函数声明了但没有定义，可能编译通过，但链接失败。

典型错误是：

```text
undefined reference
```

## 4. 库是什么

库是一组已经编译好的代码。

可以被其他程序链接使用。

ns-3 的不同模块可以理解成不同库或组件：

```text
core
network
internet
point-to-point
applications
```

代码之间通过 include 和链接关系组合起来。

## 5. 构建系统

大型工程不会手动一个文件一个文件编译。

会使用构建系统。

ns-3 早期版本使用 waf。

构建系统负责：

```text
找到源文件
设置 include 路径
设置编译选项
决定链接哪些库
增量构建
```

所以新增 `.cc/.h` 文件后，有时还需要修改构建脚本。

## 6. 编译错误和链接错误的区别

编译错误通常是：

```text
这个类型不存在
函数参数不匹配
语法错
没有声明
```

链接错误通常是：

```text
函数声明找到了，但实现找不到
某个库没有链接
符号重复定义
```

读错误信息时，要先判断它属于哪一类。

## 7. 读工程时的检查问题

```text
1. 这个类声明在哪个 .h？
2. 这个函数实现在哪个 .cc？
3. 当前文件 include 了什么？
4. 是否只需要前向声明？
5. 新增文件是否加入构建系统？
6. 错误是编译阶段还是链接阶段？
```

## 8. 小结

C++ 工程构建可以粗略理解为：

```text
头文件提供声明
源文件提供实现
编译生成目标文件
链接组合成程序或库
构建系统自动管理这个过程
```

下一篇进入：

```text
C++ 系统补课 14：STL 入门：string、vector、map 和 iterator
```
