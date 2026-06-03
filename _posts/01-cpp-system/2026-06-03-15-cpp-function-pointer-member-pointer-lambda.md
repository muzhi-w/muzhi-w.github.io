---
title: "C++ 系统补课 15：函数指针、成员函数指针和 lambda"
date: 2026-06-03 17:14:00 +0800
permalink: /posts/cpp-function-pointer-member-pointer-lambda/
categories: [C++, 系统补课]
tags: [cpp, function-pointer, member-function-pointer, lambda, callback, simulator]
description: "从函数指针、成员函数指针和 lambda 讲起，解释为什么 ns-3 的 Simulator::Schedule 可以传入 &Class::Function。"
---

<!-- series-nav -->
> **系列位置**：C++ 系统补课，第 15 篇 / 共 19 篇
> **总目录**：[学习路线](/roadmap/)
> **上一篇**：[14：STL 入门：string、vector、map 和 iterator](/posts/cpp-stl-string-vector-map-iterator/)
> **下一篇**：[16：模板：template、typename 和泛型](/posts/cpp-template-typename-generic/)


ns-3 事件系统里经常看到：

```cpp
Simulator::Schedule(
    delay,
    &QbbNetDevice::Receive,
    dev,
    packet);
```

最容易卡住的是：

```cpp
&QbbNetDevice::Receive
```

这不是普通变量地址。

它是成员函数指针。

## 1. 普通函数指针

普通函数：

```cpp
void hello() {
}
```

函数指针：

```cpp
void (*fp)() = &hello;
```

调用：

```cpp
fp();
```

函数指针保存的是：

```text
某个普通函数的入口。
```

## 2. 带参数的函数指针

```cpp
int add(int a, int b) {
    return a + b;
}

int (*fp)(int, int) = &add;
int c = fp(1, 2);
```

类型要匹配：

```text
返回值类型
参数类型
```

## 3. 成员函数指针

成员函数属于类。

```cpp
class Foo {
public:
    void Bar(int x);
};
```

成员函数指针：

```cpp
void (Foo::*mp)(int) = &Foo::Bar;
```

它表示：

```text
Foo 类中某个成员函数的位置。
```

但它不能单独调用。

必须有对象：

```cpp
Foo foo;
(foo.*mp)(10);
```

如果是对象指针：

```cpp
Foo* p = &foo;
(p->*mp)(10);
```

## 4. Simulator::Schedule 的含义

```cpp
Simulator::Schedule(
    delay,
    &Foo::Bar,
    fooPtr,
    10);
```

可以理解成：

```text
delay 之后，
在 fooPtr 指向的对象上，
调用 Foo::Bar(10)。
```

`&Foo::Bar` 是成员函数指针。

`fooPtr` 是对象。

`10` 是参数。

## 5. lambda

lambda 是匿名函数对象。

```cpp
auto f = []() {
    // do something
};

f();
```

带参数：

```cpp
auto add = [](int a, int b) {
    return a + b;
};
```

捕获外部变量：

```cpp
int x = 10;
auto f = [x]() {
    return x + 1;
};
```

lambda 在现代 C++ callback 场景很常见。

ns-3 老代码中更常见成员函数指针和 Callback。

## 6. Callback 思想

callback 的核心是：

```text
把“以后要调用的函数”作为参数传出去。
```

事件系统就是 callback 思想。

```cpp
Simulator::Schedule(delay, &Foo::Bar, this);
```

意思是：

```text
现在不调用。
以后由 Simulator 调用。
```

## 7. 读源码时的检查问题

看到 `&Class::Function`，要问：

```text
1. 这是哪个类的成员函数？
2. 后面传入了哪个对象？
3. 函数参数是否匹配？
4. 这个调用是现在执行，还是未来回调？
5. 对象生命周期是否覆盖未来调用时刻？
```

## 8. 小结

函数指针指向普通函数。

成员函数指针指向类的成员函数。

成员函数指针调用时必须有对象。

`Simulator::Schedule` 的核心就是：

```text
时间 + 成员函数指针 + 对象 + 参数
```

下一篇进入：

```text
C++ 系统补课 16：模板：template、typename 和泛型
```
