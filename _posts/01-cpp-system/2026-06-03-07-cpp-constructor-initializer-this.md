---
title: "C++ 系统补课 07：构造函数、初始化列表和 this 指针"
date: 2026-06-03 17:06:00 +0800
permalink: /posts/cpp-constructor-initializer-this/
categories: [C++, 系统补课]
tags: [cpp, constructor, initializer-list, this, object-lifetime, ns3]
description: "理解对象创建时构造函数如何执行，初始化列表为什么重要，以及 this 指针在成员函数和 ns-3 事件系统中的含义。"
---

<!-- series-nav -->
> **系列位置**：C++ 系统补课，第 07 篇 / 共 19 篇
> **总目录**：[学习路线](/roadmap/)
> **上一篇**：[06：class 和 struct：对象到底是什么](/posts/cpp-class-struct-object/)
> **下一篇**：[08：析构函数、栈对象、堆对象和 RAII](/posts/cpp-destructor-lifetime-raii/)


类定义了对象长什么样。

构造函数负责：

```text
对象创建时，把对象初始化好。
```

这篇讲：

```text
构造函数
默认构造函数
带参数构造函数
初始化列表
this 指针
```

## 1. 构造函数是什么

构造函数是对象创建时自动调用的特殊函数。

```cpp
class Point {
public:
    Point() {
        x = 0;
        y = 0;
    }

    int x;
    int y;
};
```

创建对象：

```cpp
Point p;
```

会自动调用：

```cpp
Point()
```

于是 `p.x` 和 `p.y` 被设置为 0。

## 2. 构造函数没有返回值

构造函数名字和类名一样。

它没有返回值类型。

```cpp
Point();
```

不是：

```cpp
void Point();
```

这是构造函数的语法特点。

## 3. 带参数构造函数

```cpp
class Point {
public:
    Point(int xValue, int yValue) {
        x = xValue;
        y = yValue;
    }

    int x;
    int y;
};
```

创建：

```cpp
Point p(10, 20);
```

调用带参数构造函数。

对象创建后：

```text
p.x == 10
p.y == 20
```

## 4. 初始化列表

更常见的写法：

```cpp
Point(int xValue, int yValue)
    : x(xValue),
      y(yValue)
{
}
```

冒号后面这一段叫初始化列表。

它表示：

```text
对象成员在创建时直接初始化。
```

和在函数体里赋值不同：

```cpp
Point() {
    x = 0;
}
```

初始化列表发生得更早。

很多成员必须用初始化列表，例如：

```text
const 成员
引用成员
没有默认构造函数的对象成员
基类部分
```

## 5. RDMA 配置结构里的初始化列表

代码来源：

```text
src/point-to-point/model/rdma-queue-pair.h
```

```cpp
struct RdmaSenderQueuePairConfig {
    uint64_t size;
    uint32_t win;
    uint64_t base_rtt;
    bool var_win;
    int32_t flow_id;
    Time timeout;

    RdmaSenderQueuePairConfig()
        : size(0),
          win(0),
          base_rtt(0),
          var_win(false),
          flow_id(-1),
          timeout(Time(0)) {}
};
```

这段表示：

```text
创建 RdmaSenderQueuePairConfig 对象时，
size 初始化为 0，
win 初始化为 0，
var_win 初始化为 false，
flow_id 初始化为 -1，
timeout 初始化为 Time(0)。
```

这比先创建再赋值更清楚。

## 6. 成员初始化顺序

一个容易忽略的点：

```text
成员变量的初始化顺序由它们在类里声明的顺序决定。
不是由初始化列表书写顺序决定。
```

所以最好让初始化列表顺序和成员声明顺序一致。

这能减少误解和编译器警告。

## 7. this 指针

在成员函数里，`this` 表示当前对象的地址。

```cpp
class Point {
public:
    void SetX(int x) {
        this->x = x;
    }

    int x;
};
```

这里：

```text
this->x 是成员变量。
右边的 x 是参数。
```

`this` 的类型大致是：

```text
Point*
```

在 const 成员函数里，大致是：

```text
const Point*
```

## 8. ns-3 事件里的 this

代码形态：

```cpp
Simulator::Schedule(
    delay,
    &QbbNetDevice::TransmitComplete,
    this);
```

这里的 `this` 是当前 `QbbNetDevice` 对象地址。

它被事件系统保存下来。

未来仿真时间到了，事件系统会通过这个地址调用成员函数。

所以 `this` 不只是语法。

它牵涉对象生命周期。

## 9. 构造函数和对象有效状态

构造函数的目标是：

```text
让对象一创建出来，就处于有效状态。
```

如果一个对象创建后还要调用一堆额外函数才能安全使用，就容易出错。

例如配置结构默认构造函数把字段都设置为明确值，就是好习惯。

```cpp
flow_id(-1)
timeout(Time(0))
```

这种默认值让对象状态更可控。

## 10. 小结

构造函数负责对象创建。

初始化列表负责成员初始化。

`this` 表示当前对象地址。

读构造函数时要问：

```text
对象创建时哪些成员被初始化？
默认值是什么？
对象创建后是否处于有效状态？
this 有没有被传给未来执行的回调或事件？
```

下一篇进入：

```text
C++ 系统补课 08：析构函数、栈对象、堆对象和 RAII
```
