---
title: "C++ 系统补课 04：函数、返回值和参数传递"
date: 2026-06-03 17:03:00 +0800
permalink: /posts/cpp-functions-return-parameters/
categories: [C++, 系统补课]
tags: [cpp, function, parameter, return-value, pass-by-value, ns3]
description: "系统理解 C++ 函数声明、返回值、值传递、指针传递、引用传递，以及 ns-3/RDMA 源码中的函数该怎么读。"
---

<!-- series-nav -->
> **系列位置**：C++ 系统补课，第 04 篇 / 共 19 篇
> **总目录**：[学习路线](/roadmap/)
> **上一篇**：[03：引用、const 引用和函数参数](/posts/cpp-reference-const-reference-parameters/)
> **下一篇**：[05：const：从 const int 到 const 成员函数](/posts/cpp-const-from-variable-to-member-function/)


函数是 C++ 程序里的动作单位。

读源码时，经常第一眼看到的不是变量，而是一堆函数声明：

```cpp
uint32_t GetSize(void) const;
Ptr<Packet> Copy(void) const;
void AddHeader(const Header& header);
uint32_t RemoveHeader(Header& header);
```

这篇专门讲：

```text
函数声明怎么拆？
返回值怎么看？
参数传递有哪些方式？
ns-3/RDMA 源码里的函数为什么这么写？
```

## 1. 函数的基本结构

一个函数大致长这样：

```cpp
返回值类型 函数名(参数列表) {
    函数体
}
```

例如：

```cpp
int add(int a, int b) {
    return a + b;
}
```

可以拆成：

```text
int       返回值类型
add       函数名
int a     第一个参数
int b     第二个参数
return    返回结果
```

调用：

```cpp
int c = add(1, 2);
```

结果：

```text
c 的值是 3。
```

## 2. 返回值类型

返回值类型表示：

```text
函数执行完后，会交回什么类型的结果。
```

例如：

```cpp
uint32_t GetSize(void) const;
```

表示：

```text
GetSize 返回 uint32_t。
```

所以可以写：

```cpp
uint32_t size = p->GetSize();
```

再比如：

```cpp
Ptr<Packet> Copy(void) const;
```

表示：

```text
Copy 返回 Ptr<Packet>。
```

所以可以写：

```cpp
Ptr<Packet> copy = p->Copy();
```

返回值类型是读函数的第一件事。

## 3. void 返回值

如果函数返回：

```cpp
void
```

表示：

```text
这个函数不返回结果。
```

例如：

```cpp
void AddHeader(const Header& header);
```

这表示：

```text
AddHeader 执行动作，但不返回值。
```

调用：

```cpp
p->AddHeader(ipHeader);
```

它改变 packet 的 Buffer，但不返回一个新对象。

## 4. 参数列表

参数列表表示函数需要什么输入。

例如：

```cpp
void SetSize(uint64_t size);
```

这个函数需要一个：

```text
uint64_t 类型的 size 参数。
```

再比如：

```cpp
void SetInitialRate(DataRate rate);
```

这个函数需要一个：

```text
DataRate 类型的 rate 参数。
```

参数是函数的输入。

返回值是函数的输出。

函数体是函数做的事情。

## 5. 值传递

值传递形态：

```cpp
void f(int x);
```

调用时：

```cpp
int a = 10;
f(a);
```

函数里的 `x` 是 `a` 的一份拷贝。

如果函数里改 `x`：

```cpp
void f(int x) {
    x = 20;
}
```

外面的 `a` 不变。

所以值传递适合：

```text
小对象
不需要修改调用者对象
复制成本低的参数
```

例如：

```cpp
void SetWin(uint32_t win);
void SetVarWin(bool v);
```

`uint32_t` 和 `bool` 都很小，值传递很自然。

## 6. 引用传递

引用传递形态：

```cpp
void f(int& x);
```

函数里改 `x`，会影响调用者传入的对象。

例如：

```cpp
void f(int& x) {
    x = 20;
}

int a = 10;
f(a);
```

调用后：

```text
a 变成 20。
```

ns-3 里的例子：

```cpp
uint32_t RemoveHeader(Header& header);
```

`RemoveHeader` 需要把解析结果写进 `header`。

所以用可修改引用。

## 7. const 引用传递

形态：

```cpp
void f(const T& x);
```

含义：

```text
不拷贝对象。
也不修改对象。
```

例如：

```cpp
void AddHeader(const Header& header);
```

`AddHeader` 需要读取 header，但不该修改调用者传入的 header。

所以用 `const Header&`。

这是 C++ 工程里非常常见的参数形式。

## 8. 指针传递

形态：

```cpp
void f(Packet* p);
```

指针传递表示：

```text
传入对象地址。
函数可以通过地址访问对象。
指针可能为空。
```

如果函数允许“没有对象”，指针有时比引用更合适。

例如：

```cpp
void f(Packet* p) {
    if (p == nullptr) {
        return;
    }
    p->GetSize();
}
```

在 ns-3 中，更常见的是：

```cpp
Ptr<Packet> p
```

而不是裸 `Packet*`。

因为 `Ptr<T>` 会参与 ns-3 引用计数。

## 9. ns-3 的 Ptr<T> 参数

例如：

```cpp
void Receive(Ptr<Packet> packet);
```

这里参数类型是：

```text
Ptr<Packet>
```

这不是普通值。

它是 ns-3 智能指针对象。

值传递 `Ptr<Packet>` 时，通常会复制这个智能指针对象，并调整引用计数。

这和复制整个 `Packet` 不一样。

所以：

```cpp
Ptr<Packet> packet
```

常用于：

```text
传递 ns-3 对象引用
保证对象在调用过程中有效
避免复制真正的大对象
```

## 10. 成员函数声明里的 const

看：

```cpp
uint32_t GetSize(void) const;
```

最后这个 `const` 不是修饰返回值，也不是修饰参数。

它修饰的是成员函数。

含义是：

```text
这个函数不会修改当前对象的逻辑状态。
```

所以：

```cpp
Ptr<const Packet> p;
p->GetSize();
```

这种只读场景也能调用 `GetSize`。

后面讲 const 时会详细展开。

## 11. 函数声明和函数定义

头文件里常见函数声明：

```cpp
uint32_t GetSize(void) const;
```

源文件里常见函数定义：

```cpp
uint32_t
Packet::GetSize(void) const
{
    return m_buffer.GetSize();
}
```

声明告诉编译器：

```text
这个函数存在，它的接口长这样。
```

定义告诉编译器：

```text
这个函数具体怎么做。
```

头文件和源文件会在后面的工程篇里详细讲。

## 12. 读函数时的固定顺序

看到函数声明，可以按这个顺序读：

```text
1. 返回值类型是什么？
2. 函数名是什么？
3. 参数有哪些？
4. 参数是值、指针、引用还是 const 引用？
5. 末尾有没有 const？
6. 这个函数可能修改谁？
```

例如：

```cpp
uint32_t PeekHeader(Header& header) const;
```

读成：

```text
返回 uint32_t。
函数名 PeekHeader。
参数 header 是可修改引用。
函数本身是 const 成员函数。
因此它会填充参数 header，但不会修改当前 Packet。
```

## 13. 小结

函数是源码里的动作单位。

读函数时，先看：

```text
返回值
参数
const
```

参数传递有四种常见形态：

```text
T          值传递，复制一份
T&         引用传递，可修改原对象
const T&   只读引用，避免拷贝
T*         指针传递，传地址，可为空
Ptr<T>     ns-3 智能指针传递，参与引用计数
```

下一篇进入：

```text
C++ 系统补课 05：const：从 const int 到 const 成员函数
```
