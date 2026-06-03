---
title: "C++ 系统补课 03：引用、const 引用和函数参数"
date: 2026-06-03 17:02:00 +0800
permalink: /posts/cpp-reference-const-reference-parameters/
categories: [C++, 系统补课]
tags: [cpp, reference, const-reference, parameter, ns3, header]
description: "从 T&、const T& 和函数参数讲起，理解为什么 ns-3 里 AddHeader 使用 const Header&，RemoveHeader 使用 Header&。"
---

<!-- series-nav -->
> **系列位置**：C++ 系统补课，第 03 篇 / 共 19 篇
> **总目录**：[学习路线](/roadmap/)
> **上一篇**：[02：内存、地址和指针](/posts/cpp-memory-address-pointer/)
> **下一篇**：[04：函数、返回值和参数传递](/posts/cpp-functions-return-parameters/)


上一篇讲了指针。

这篇讲引用。

引用是 C++ 里非常常见的参数形式：

```cpp
T&
const T&
```

在 ns-3 里尤其常见。

代码来源：

```text
src/network/model/packet.h
```

```cpp
void AddHeader(const Header& header);
uint32_t RemoveHeader(Header& header);
uint32_t PeekHeader(Header& header) const;
```

这三行是理解引用的好例子。

## 1. 引用是什么

引用可以先理解成：

```text
一个对象的别名。
```

例如：

```cpp
int x = 10;
int& r = x;
```

这里：

```text
r 是 x 的引用。
r 是 x 的另一个名字。
```

修改 `r`，就是修改 `x`：

```cpp
r = 20;
```

此时：

```text
x 的值也变成 20。
```

因为 `r` 并不是一个新 int。

它引用的就是 `x`。

## 2. 引用和指针的直观区别

指针写法：

```cpp
int x = 10;
int* p = &x;
*p = 20;
```

引用写法：

```cpp
int x = 10;
int& r = x;
r = 20;
```

两者都能间接操作原对象。

但形式不同：

```text
指针需要保存地址，并通过 *p 解引用。
引用像原对象的别名，直接使用 r。
```

指针可以是 `nullptr`。

引用一般必须绑定到一个有效对象。

所以函数参数里，如果一个对象必须存在，经常使用引用。

## 3. 普通引用参数 T&

看这个函数：

```cpp
void setTo20(int& x) {
    x = 20;
}
```

调用：

```cpp
int a = 10;
setTo20(a);
```

执行后：

```text
a 变成 20。
```

因为 `x` 是 `a` 的引用。

这说明：

```text
T& 参数允许函数修改调用者传入的对象。
```

## 4. const 引用参数 const T&

再看：

```cpp
void printValue(const int& x) {
    // 只能读 x，不能改 x
}
```

`const int&` 的意思是：

```text
引用一个 int 对象。
但这个函数不应该通过这个引用修改它。
```

为什么不直接值传递？

比如：

```cpp
void f(Packet p);
```

这会复制一个 `Packet`。

如果对象很大，复制成本高。

而：

```cpp
void f(const Packet& p);
```

不复制整个对象。

也不允许函数修改它。

这就是 `const T&` 常见的原因：

```text
避免拷贝，同时保证只读。
```

## 5. AddHeader 为什么是 const Header&

代码来源：

```text
src/network/model/packet.h
```

```cpp
void AddHeader(const Header& header);
```

`AddHeader` 的任务是：

```text
把 header 序列化进 Packet 的 Buffer。
```

它需要读取 `header` 的内容。

但不需要修改传进来的 `header` 对象。

所以参数类型是：

```cpp
const Header& header
```

可以读成：

```text
传进来一个 Header 对象的引用。
不拷贝。
不修改。
```

这非常合理。

例如：

```cpp
Ipv4Header ipHeader;
p->AddHeader(ipHeader);
```

`AddHeader` 只需要读取 `ipHeader` 里的字段并序列化。

它不应该把调用者手里的 `ipHeader` 改掉。

## 6. RemoveHeader 为什么是 Header&

代码来源：

```text
src/network/model/packet.h
```

```cpp
uint32_t RemoveHeader(Header& header);
```

`RemoveHeader` 的任务是：

```text
从 Packet 的 Buffer 开头解析 header 字节。
把解析结果填进调用者传入的 header 对象。
然后从 Packet 中删除这段 header。
```

所以它必须修改 `header`。

例如：

```cpp
Ipv4Header h;
p->RemoveHeader(h);
```

调用前：

```text
h 是一个空的 Ipv4Header 对象。
```

调用后：

```text
h 里被填入 packet 中解析出来的 IPv4 字段。
```

所以参数不能是 `const Header&`。

它必须是：

```cpp
Header& header
```

也就是：

```text
可以修改的引用。
```

## 7. PeekHeader 为什么也是 Header&

```cpp
uint32_t PeekHeader(Header& header) const;
```

`PeekHeader` 不删除 packet 里的 header。

但它仍然需要把解析结果填进 `header` 对象。

所以参数仍然是：

```cpp
Header& header
```

而函数末尾的 `const`：

```cpp
... const;
```

表示：

```text
PeekHeader 不修改当前 Packet 对象。
```

所以这行要分开读：

```cpp
uint32_t PeekHeader(Header& header) const;
```

含义是：

```text
会修改参数 header。
不会修改当前 Packet 对象。
返回读取的字节数。
```

## 8. const T& 和多态

`AddHeader` 的参数是：

```cpp
const Header& header
```

但实际传进去的可能是：

```text
Ipv4Header
UdpHeader
SeqTsHeader
qbbHeader
CnHeader
PauseHeader
```

这是因为这些类都继承自 `Header`。

基类引用可以绑定到派生类对象。

例如：

```cpp
Ipv4Header ip;
const Header& h = ip;
```

这就是多态的入口。

后面讲继承和 virtual 时，会继续深入。

当前先记住：

```text
const Header& 可以接住各种具体 Header 对象。
```

## 9. 引用不是所有权

引用只是别名。

它不表示拥有对象。

比如：

```cpp
void AddHeader(const Header& header);
```

`Packet` 并没有拥有这个 `header` 对象。

它只是临时读取它，把它序列化进 Buffer。

函数返回后，`header` 仍然归调用者管理。

这和智能指针不同。

```cpp
Ptr<Packet> p
```

可能参与引用计数生命周期。

但：

```cpp
Header& header
```

只是引用，不负责生命周期。

## 10. 读源码时的检查问题

看到引用参数，可以问：

```text
1. 是 T& 还是 const T&？
2. 函数会不会修改这个参数？
3. 是否为了避免拷贝？
4. 这个引用有没有绑定到派生类对象？
5. 函数末尾有没有 const？那表示是否修改当前对象。
```

例如：

```cpp
void AddHeader(const Header& header);
```

读成：

```text
只读传入 header。
不复制。
允许传入 Header 的派生类对象。
```

例如：

```cpp
uint32_t RemoveHeader(Header& header);
```

读成：

```text
会把解析结果写进 header。
因此 header 必须是可修改引用。
```

## 11. 小结

这一篇的核心是：

```text
T& 是可修改引用。
const T& 是只读引用。
引用不是对象所有权。
引用参数常用于避免拷贝。
```

ns-3 里的 `Packet` API 非常适合理解引用：

```cpp
void AddHeader(const Header& header);        // 读取 header，不修改 header；会修改 Packet
uint32_t RemoveHeader(Header& header);       // 解析并填充 header；会修改 Packet
uint32_t PeekHeader(Header& header) const;   // 解析并填充 header；不修改 Packet
```

下一篇进入：

```text
C++ 系统补课 04：函数、返回值和参数传递
```

那一篇会把值传递、指针传递、引用传递放在一起比较。
