---
title: "C++ 系统补课 05：const：从 const int 到 const 成员函数"
date: 2026-06-03 17:04:00 +0800
permalink: /posts/cpp-const-from-variable-to-member-function/
categories: [C++, 系统补课]
tags: [cpp, const, const-reference, const-member-function, pointer, ns3]
description: "系统理解 const 修饰变量、指针、引用和成员函数的含义，并用 ns-3 的 Packet API 解释 const 在源码阅读中的作用。"
---

<!-- series-nav -->
> **系列位置**：C++ 系统补课，第 05 篇 / 共 19 篇
> **总目录**：[学习路线](/roadmap/)
> **上一篇**：[04：函数、返回值和参数传递](/posts/cpp-functions-return-parameters/)
> **下一篇**：[06：class 和 struct：对象到底是什么](/posts/cpp-class-struct-object/)


`const` 是 C++ 源码里出现频率极高的关键字。

它的核心意思是：

```text
不允许修改。
```

但它可以修饰很多不同东西：

```cpp
const int x;
const Header& header;
const Packet* p;
Ptr<const Packet> p;
uint32_t GetSize(void) const;
```

这篇把这些形态放在一起讲清楚。

## 1. const 变量

最简单的形式：

```cpp
const int x = 10;
```

意思是：

```text
x 是 int 类型。
x 初始化为 10。
之后不能修改 x。
```

下面是不允许的：

```cpp
x = 20;
```

`const` 常用于表达：

```text
这个值创建后不应该变。
```

## 2. const 引用

形态：

```cpp
const T& ref
```

含义：

```text
引用一个 T 对象。
通过这个引用不能修改对象。
```

ns-3 例子：

```cpp
void AddHeader(const Header& header);
```

读成：

```text
AddHeader 接收一个 Header 引用。
不复制。
不修改传入的 Header。
```

`const T&` 是非常常见的函数参数写法。

它兼顾：

```text
效率：避免拷贝
安全：不修改对象
```

## 3. const 指针相关形态

指针和 const 组合时，容易混。

### 3.1 指向 const 对象的指针

```cpp
const Packet* p;
```

意思是：

```text
p 指向 Packet。
不能通过 p 修改这个 Packet。
```

但是 `p` 自己可以改指向别处。

### 3.2 const 指针

```cpp
Packet* const p = ...;
```

意思是：

```text
p 这个指针本身不能改指向。
但可以通过 p 修改 Packet。
```

### 3.3 指向 const 对象的 const 指针

```cpp
const Packet* const p = ...;
```

意思是：

```text
p 不能改指向。
也不能通过 p 修改 Packet。
```

读法技巧：

```text
const 靠近谁，就限制谁。
```

## 4. Ptr<const Packet>

ns-3 里还可能看到：

```cpp
Ptr<const Packet> p;
```

意思是：

```text
p 是 ns-3 智能指针。
它指向 const Packet。
不能通过 p 修改 Packet。
```

所以只允许调用 `Packet` 的 const 成员函数。

例如：

```cpp
p->GetSize();
```

如果 `GetSize` 声明为：

```cpp
uint32_t GetSize(void) const;
```

就可以调用。

但非 const 成员函数不能调用。

## 5. const 成员函数

看这个：

```cpp
uint32_t GetSize(void) const;
```

最后的 `const` 表示：

```text
这个成员函数不修改当前对象的逻辑状态。
```

它修饰的是函数里的隐含 `this` 指针。

普通成员函数里，`this` 大致是：

```text
Packet* const this
```

const 成员函数里，`this` 大致变成：

```text
const Packet* const this
```

所以 const 成员函数不能随便修改成员变量。

## 6. Packet API 里的 const

代码来源：

```text
src/network/model/packet.h
```

```cpp
uint32_t GetSize(void) const;
Ptr<Packet> Copy(void) const;
uint32_t PeekHeader(Header& header) const;
```

这些函数末尾都有 `const`。

意思是：

```text
它们不修改当前 Packet 的逻辑内容。
```

`PeekHeader` 比较有意思：

```cpp
uint32_t PeekHeader(Header& header) const;
```

它会修改参数 `header`，因为要把解析结果填进去。

但它不修改当前 `Packet`。

所以末尾可以是 `const`。

这再次说明：

```text
参数的 const 和成员函数末尾的 const 是两回事。
```

## 7. AddPacketTag 为什么是 const

代码来源：

```text
src/network/model/packet.h
```

```cpp
void AddPacketTag(const Tag& tag) const;
```

这个函数末尾也是 `const`。

乍一看很怪：

```text
AddPacketTag 明明添加了 tag，为什么还能是 const？
```

ns-3 的解释是：

```text
Tag 是仿真辅助信息。
它不改变 packet 的协议内容和逻辑行为。
```

所以这个 const 是从“协议内容不变”的角度理解。

这说明 C++ 的 const 有时表达的是：

```text
逻辑不变性。
```

而不一定是“底层每一个字节都完全不动”。

## 8. const 的读源码价值

看到 const，可以立刻得到信息：

```text
这个参数会不会被修改？
这个成员函数会不会修改对象？
这个指针能不能改目标对象？
这个 API 是只读接口还是修改接口？
```

例如：

```cpp
void AddHeader(const Header& header);
```

说明：

```text
传入的 header 不会被修改。
```

例如：

```cpp
uint32_t RemoveHeader(Header& header);
```

没有 const，说明：

```text
header 可能会被修改。
```

例如：

```cpp
uint32_t GetSize(void) const;
```

说明：

```text
GetSize 是只读查询。
```

## 9. 常见错误

### 错误 1：把两个 const 混在一起

```cpp
uint32_t PeekHeader(Header& header) const;
```

末尾的 const 只说明不修改当前对象。

不说明不修改参数。

参数 `Header& header` 仍然可以被修改。

### 错误 2：以为 const 对象什么函数都能调

```cpp
Ptr<const Packet> p;
```

只能调用 const 成员函数。

如果某个函数没有声明成 const，就不能通过 `Ptr<const Packet>` 调用。

### 错误 3：看到 const 就以为绝对不会变

有些类内部可能使用 `mutable` 或逻辑 const。

所以 const 更准确的理解是：

```text
这个接口承诺不修改对象的逻辑状态。
```

## 10. 小结

`const` 的核心含义是：

```text
不允许通过这个入口修改。
```

常见形态：

```text
const T          const 变量
const T&         只读引用
const T*         指向 const 对象的指针
T* const         指针本身 const
Ptr<const T>     指向 const T 的 ns-3 智能指针
func() const     const 成员函数
```

下一篇进入：

```text
C++ 系统补课 06：class 和 struct：对象到底是什么
```
