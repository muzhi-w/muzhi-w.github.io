---
title: "C++ 系统补课 16：模板：template、typename 和泛型"
date: 2026-06-03 17:15:00 +0800
permalink: /posts/cpp-template-typename-generic/
categories: [C++, 系统补课]
tags: [cpp, template, typename, generic, ptr, ns3]
description: "系统补课版模板入门：理解 template、typename、类模板、函数模板，以及 ns-3 Ptr<T> 和 Create<T>() 的基本读法。"
---

<!-- series-nav -->
> **系列位置**：C++ 系统补课，第 16 篇 / 共 19 篇
> **总目录**：[学习路线](/roadmap/)
> **上一篇**：[15：函数指针、成员函数指针和 lambda](/posts/cpp-function-pointer-member-pointer-lambda/)
> **下一篇**：[17：智能指针和资源管理](/posts/cpp-smart-pointer-resource-management/)


模板让 C++ 可以写“适用于多种类型”的代码。

ns-3 里到处都是模板：

```cpp
Ptr<Packet>
Ptr<RdmaQueuePair>
Create<Packet>()
SimpleRefCount<Packet>
```

## 1. 为什么需要模板

如果要写两个函数：

```cpp
int maxInt(int a, int b);
double maxDouble(double a, double b);
```

逻辑一样，只是类型不同。

模板可以写成：

```cpp
template <typename T>
T maxValue(T a, T b) {
    return a > b ? a : b;
}
```

调用：

```cpp
int x = maxValue<int>(1, 2);
double y = maxValue<double>(1.0, 2.0);
```

## 2. template <typename T>

```cpp
template <typename T>
```

表示：

```text
下面的代码里，T 是一个类型参数。
具体 T 是什么，使用时再决定。
```

`T` 可以是：

```text
int
Packet
RdmaQueuePair
QbbNetDevice
```

## 3. 类模板

```cpp
template <typename T>
class Box {
public:
    T value;
};
```

使用：

```cpp
Box<int> a;
Box<double> b;
```

`Box<int>` 和 `Box<double>` 是不同的具体类型。

## 4. Ptr<T>

ns-3 的 `Ptr<T>` 是类模板。

简化形态：

```cpp
template <typename T>
class Ptr {
private:
    T* m_ptr;
};
```

所以：

```cpp
Ptr<Packet>
```

表示：

```text
T = Packet 的 Ptr。
```

```cpp
Ptr<RdmaQueuePair>
```

表示：

```text
T = RdmaQueuePair 的 Ptr。
```

## 5. 函数模板

```cpp
template <typename T>
Ptr<T> Create();
```

表示：

```text
Create 是函数模板。
返回 Ptr<T>。
T 由调用时决定。
```

调用：

```cpp
Ptr<Packet> p = Create<Packet>(1000);
```

这里：

```text
T = Packet。
返回 Ptr<Packet>。
```

## 6. 模板实例化

模板本身像模具。

真正使用时，编译器会根据类型生成具体代码。

例如：

```cpp
Ptr<Packet>
Ptr<RdmaQueuePair>
```

会形成不同的具体类型。

这叫模板实例化。

## 7. typename 和 class

模板参数里：

```cpp
template <typename T>
```

也可以写：

```cpp
template <class T>
```

在这种场景里两者大致等价。

`typename` 更明确表达：

```text
T 是一个类型参数。
```

## 8. 读模板代码的问题

看到模板，先问：

```text
1. 类型参数是谁？
2. 使用时 T 被替换成什么？
3. 返回类型里有没有 T？
4. 参数类型里有没有 T？
5. 这是类模板还是函数模板？
```

例如：

```cpp
Ptr<Packet> p;
```

读成：

```text
Ptr<T> 中 T = Packet。
p 是指向 Packet 的 ns-3 智能指针。
```

## 9. 小结

模板解决：

```text
同一套代码适用于不同类型。
```

核心读法：

```text
template <typename T>  引入类型参数 T
Ptr<T>                 类模板
Create<T>()            函数模板
Ptr<Packet>            T 被替换成 Packet
```

下一篇进入：

```text
C++ 系统补课 17：智能指针和资源管理
```
