---
title: "彻底理解 C++ 模板：从 Ptr<T> 看懂 typename 和尖括号"
date: 2026-06-02 16:15:00 +0800
categories: [C++, 工程实践]
tags: [cpp, template, typename, generic-programming, ns3, ptr]
description: "从为什么需要模板讲起，理解 template <typename T>、类模板、函数模板、多模板参数、模板实例化，以及 ns-3 里的 Ptr<T>、Create<T>() 和 SimpleRefCount<T>。"
---

上一篇写 ns-3 的 `Ptr<T>` 时，我意识到一个问题：

如果没有先理解 C++ 模板，那么下面这些代码会非常难读：

```cpp
template <typename T>
class Ptr {
private:
    T* m_ptr;
};
```

还有：

```cpp
Ptr<Packet>
Ptr<RdmaQueuePair>
Create<Packet>()
CreateObject<RdmaQueuePair>()
SimpleRefCount<Packet>
SimpleRefCount<Object, ObjectBase, ObjectDeleter>
```

看起来到处都是尖括号。

如果不知道模板是什么，这些尖括号就会像一层雾挡在代码前面。

所以这篇文章先不讲复杂模板技巧，只讲读 ns-3 代码真正需要的东西：

```text
template <typename T> 是什么？
Ptr<T> 是什么？
T 到底在哪里变成 Packet？
Create<T>() 为什么能创建不同类型的对象？
SimpleRefCount<Packet> 里的 Packet 是什么意思？
模板和虚函数有什么区别？
```

先说结论：

> 模板不是一个具体类，也不是一个具体函数。
>
> 模板是让编译器根据你给的类型，自动生成具体代码的蓝图。

如果把普通类理解成“已经造好的房子”，那么模板更像“造房子的图纸”。

图纸本身不能住人。

但给它不同材料，它可以造出不同房子。

C++ 模板也是这样。

---

## 1. 为什么需要模板

先从一个非常普通的问题开始。

假设我们想写一个盒子，里面保存一个整数：

```cpp
class IntBox {
public:
    void Set(int value) {
        m_value = value;
    }

    int Get() const {
        return m_value;
    }

private:
    int m_value;
};
```

使用方式：

```cpp
IntBox box;
box.Set(10);
std::cout << box.Get() << std::endl;
```

这很简单。

但是如果我们又想保存 `double` 呢？

可能再写一个：

```cpp
class DoubleBox {
public:
    void Set(double value) {
        m_value = value;
    }

    double Get() const {
        return m_value;
    }

private:
    double m_value;
};
```

如果还要保存 `std::string` 呢？

再写一个：

```cpp
class StringBox {
public:
    void Set(std::string value) {
        m_value = value;
    }

    std::string Get() const {
        return m_value;
    }

private:
    std::string m_value;
};
```

这三个类几乎一模一样。

唯一不同的是类型：

```text
int
double
std::string
```

这就产生了一个问题：

```text
能不能把类型也变成一个参数？
```

模板就是为了解决这个问题。

---

## 2. 类模板是什么

用模板改写上面的 `Box`：

```cpp
template <typename T>
class Box {
public:
    void Set(T value) {
        m_value = value;
    }

    T Get() const {
        return m_value;
    }

private:
    T m_value;
};
```

这里最关键的是这一行：

```cpp
template <typename T>
```

它的意思是：

```text
下面这个 class 不是普通 class。
它是一个模板。
T 是一个类型占位符。
使用这个模板时，T 会被替换成具体类型。
```

所以：

```cpp
Box<int> intBox;
```

表示：

```text
使用 Box 模板，并把 T 替换成 int。
```

编译器可以理解成生成了类似这样的类：

```cpp
class Box_int {
public:
    void Set(int value) {
        m_value = value;
    }

    int Get() const {
        return m_value;
    }

private:
    int m_value;
};
```

而：

```cpp
Box<double> doubleBox;
```

表示：

```text
使用 Box 模板，并把 T 替换成 double。
```

编译器可以理解成生成了类似：

```cpp
class Box_double {
public:
    void Set(double value) {
        m_value = value;
    }

    double Get() const {
        return m_value;
    }

private:
    double m_value;
};
```

所以模板的作用就是：

```text
把重复代码里的“类型差异”抽出来。
让编译器根据具体类型生成具体代码。
```

---

## 3. typename 是什么意思

再看：

```cpp
template <typename T>
```

这里的 `typename` 可以理解成：

```text
后面的 T 是一个类型名。
```

`T` 只是一个名字。

你也可以写：

```cpp
template <typename Type>
class Box {
private:
    Type m_value;
};
```

甚至写：

```cpp
template <typename Anything>
class Box {
private:
    Anything m_value;
};
```

但习惯上，单个模板类型参数常写成：

```cpp
T
```

因为它代表：

```text
Type
```

所以：

```cpp
template <typename T>
```

不是说真的有一个类型叫 `T`。

而是说：

```text
这里先放一个类型占位符，名字叫 T。
```

等你写：

```cpp
Box<int>
```

`T` 就变成 `int`。

等你写：

```cpp
Box<Packet>
```

`T` 就变成 `Packet`。

---

## 4. typename 和 class 的区别

你可能还会看到：

```cpp
template <class T>
```

这和：

```cpp
template <typename T>
```

在大多数场景下是一样的。

比如：

```cpp
template <class T>
class Box {
private:
    T m_value;
};
```

和：

```cpp
template <typename T>
class Box {
private:
    T m_value;
};
```

这里没有区别。

`class T` 并不是说 `T` 必须是 class。

即使写：

```cpp
template <class T>
```

你仍然可以用：

```cpp
Box<int>
Box<double>
Box<Packet>
```

所以对于初学阶段，可以先记住：

```text
template <typename T>
template <class T>
```

在定义模板参数时基本等价。

我更喜欢写 `typename`，因为它更直观地表达：

```text
T 是一个类型。
```

---

## 5. Ptr<T> 是什么

现在回到 ns-3：

```cpp
template <typename T>
class Ptr {
private:
    T* m_ptr;
};
```

这不是一个具体的类。

这是一个类模板。

`T` 是一个占位符。

当你写：

```cpp
Ptr<Packet> p;
```

编译器把 `T` 替换成 `Packet`。

于是可以粗略理解成：

```cpp
class Ptr_Packet {
private:
    Packet* m_ptr;
};
```

当你写：

```cpp
Ptr<RdmaQueuePair> qp;
```

编译器把 `T` 替换成 `RdmaQueuePair`。

于是可以粗略理解成：

```cpp
class Ptr_RdmaQueuePair {
private:
    RdmaQueuePair* m_ptr;
};
```

所以：

```cpp
Ptr<Packet>
Ptr<RdmaQueuePair>
Ptr<RdmaHw>
Ptr<QbbNetDevice>
```

这些都来自同一个模板：

```cpp
Ptr<T>
```

只是 `T` 不一样。

这就是模板的威力。

ns-3 不需要分别写：

```cpp
PacketPtr
RdmaQueuePairPtr
RdmaHwPtr
QbbNetDevicePtr
```

它只需要写一个：

```cpp
template <typename T>
class Ptr
```

然后让编译器根据不同类型生成对应版本。

---

## 6. T* m_ptr 是什么意思

在：

```cpp
template <typename T>
class Ptr {
private:
    T* m_ptr;
};
```

里面：

```cpp
T* m_ptr;
```

表示：

```text
m_ptr 是一个指针。
它指向 T 类型的对象。
```

如果 `T = Packet`，那就是：

```cpp
Packet* m_ptr;
```

如果 `T = RdmaQueuePair`，那就是：

```cpp
RdmaQueuePair* m_ptr;
```

如果 `T = RdmaHw`，那就是：

```cpp
RdmaHw* m_ptr;
```

所以 `Ptr<T>` 的底层仍然保存了一个裸指针。

模板只是让这个裸指针的类型变得通用：

```text
Ptr<Packet> 里面保存 Packet*
Ptr<RdmaQueuePair> 里面保存 RdmaQueuePair*
Ptr<RdmaHw> 里面保存 RdmaHw*
```

---

## 7. 模板不是运行时决定类型

一个很重要的点：

```text
模板是在编译期展开的。
```

也就是说：

```cpp
Ptr<Packet> p;
Ptr<RdmaQueuePair> qp;
```

编译器在编译代码时就知道：

```text
p 是 Ptr<Packet>
qp 是 Ptr<RdmaQueuePair>
```

它不是程序运行到这里才决定 `T` 是什么。

`T` 在编译期就确定了。

所以模板和虚函数不一样。

虚函数解决的是：

```text
运行时根据真实对象类型调用不同实现。
```

模板解决的是：

```text
编译期根据给定类型生成不同代码。
```

这句话后面会很重要。

---

## 8. 函数模板是什么

模板不只能修饰 class，也可以修饰函数。

比如我们想写一个函数，返回两个数中较大的那个。

如果不用模板，可能写：

```cpp
int MaxInt(int a, int b) {
    return a > b ? a : b;
}

double MaxDouble(double a, double b) {
    return a > b ? a : b;
}
```

这两个函数逻辑完全一样，只是类型不同。

可以用函数模板：

```cpp
template <typename T>
T Max(T a, T b) {
    return a > b ? a : b;
}
```

调用：

```cpp
int x = Max<int>(1, 2);
double y = Max<double>(1.5, 2.5);
```

这里：

```cpp
Max<int>
```

表示：

```text
用 T = int 生成一个 Max 函数。
```

而：

```cpp
Max<double>
```

表示：

```text
用 T = double 生成一个 Max 函数。
```

所以函数模板和类模板的思想一样：

```text
把类型变成参数。
让编译器生成具体函数。
```

---

## 9. Create<T>() 为什么也是模板

ns-3 里有：

```cpp
template <typename T>
Ptr<T> Create(void) {
    return Ptr<T>(new T(), false);
}
```

先不管 `false` 是什么意思。

只看模板部分。

这说明：

```cpp
Create<T>()
```

是一个函数模板。

如果你写：

```cpp
Ptr<Packet> p = Create<Packet>();
```

编译器把 `T` 替换成 `Packet`，可以粗略理解成：

```cpp
Ptr<Packet> Create_Packet() {
    return Ptr<Packet>(new Packet(), false);
}
```

如果你写：

```cpp
Ptr<MyClass> p = Create<MyClass>();
```

编译器把 `T` 替换成 `MyClass`，可以粗略理解成：

```cpp
Ptr<MyClass> Create_MyClass() {
    return Ptr<MyClass>(new MyClass(), false);
}
```

所以 `Create<T>()` 的核心是：

```text
创建一个 T 类型对象。
返回 Ptr<T>。
```

`T` 是谁，由调用时的尖括号决定。

---

## 10. 带参数的函数模板

ns-3 的 `Create<T>()` 还有很多重载版本。

比如：

```cpp
template <typename T, typename T1>
Ptr<T> Create(T1 a1) {
    return Ptr<T>(new T(a1), false);
}
```

这里有两个模板参数：

```cpp
T
T1
```

`T` 表示要创建的对象类型。

`T1` 表示构造函数第一个参数的类型。

比如：

```cpp
Ptr<Packet> p = Create<Packet>(100);
```

这里：

```text
T = Packet
T1 = int
```

所以可以粗略展开成：

```cpp
Ptr<Packet> Create_Packet_int(int a1) {
    return Ptr<Packet>(new Packet(a1), false);
}
```

再比如：

```cpp
Ptr<RdmaQueuePair> qp =
    CreateObject<RdmaQueuePair>(pg, sip, dip, sport, dport);
```

这里也是类似思想：

```text
T = RdmaQueuePair
后面的模板参数表示构造函数参数类型
```

在 ns-3.19 这种老代码里，你会看到很多手写的 `T1`、`T2`、`T3`、`T4`。

这是因为当时还没有广泛使用现代 C++ 的可变参数模板。

所以 ns-3 手动写了很多版本：

```cpp
Create()
Create(T1 a1)
Create(T1 a1, T2 a2)
Create(T1 a1, T2 a2, T3 a3)
...
```

目的就是支持不同数量的构造参数。

---

## 11. 模板参数可以有多个

再看 ns-3 的：

```cpp
template <typename T,
          typename PARENT = empty,
          typename DELETER = DefaultDeleter<T>>
class SimpleRefCount : public PARENT {
    ...
};
```

这比 `Ptr<T>` 稍微复杂一点。

它有三个模板参数：

```text
T
PARENT
DELETER
```

`T` 表示当前要被引用计数管理的类型。

`PARENT` 表示它要继承的父类。

`DELETER` 表示引用计数归零时怎么删除对象。

后面两个还有默认值：

```cpp
typename PARENT = empty
typename DELETER = DefaultDeleter<T>
```

这意味着如果你只写：

```cpp
SimpleRefCount<Packet>
```

编译器会自动补成：

```cpp
SimpleRefCount<Packet, empty, DefaultDeleter<Packet>>
```

所以：

```cpp
class Packet : public SimpleRefCount<Packet>
```

虽然只写了一个参数，但实际用了默认模板参数。

---

## 12. 默认模板参数是什么

默认模板参数和函数默认参数很像。

函数默认参数：

```cpp
void Print(int x = 10);
```

如果调用：

```cpp
Print();
```

就相当于：

```cpp
Print(10);
```

模板默认参数也是类似。

比如：

```cpp
template <typename T, typename Deleter = DefaultDeleter<T>>
class Owner {
    ...
};
```

如果写：

```cpp
Owner<Dog>
```

就相当于：

```cpp
Owner<Dog, DefaultDeleter<Dog>>
```

如果你想指定自己的删除方式，可以写：

```cpp
Owner<Dog, MyDogDeleter>
```

所以 ns-3 里的：

```cpp
SimpleRefCount<Packet>
```

之所以能只写一个参数，是因为后面的参数有默认值。

---

## 13. SimpleRefCount<Packet> 为什么这么写

看这个代码：

```cpp
class Packet : public SimpleRefCount<Packet>
{
    ...
};
```

第一次看会觉得很怪：

```text
Packet 为什么继承 SimpleRefCount<Packet>？
Packet 还没定义完，怎么就拿来当模板参数了？
```

这是 C++ 里一个常见模板模式：

```text
CRTP：Curiously Recurring Template Pattern
```

名字很吓人，但这里先不用深入。

只要理解它的目的：

```text
让 SimpleRefCount 知道最终被管理的真实类型是 Packet。
```

因为当引用计数归零时，`SimpleRefCount` 需要删除真实对象。

它需要知道：

```text
我要 delete 的到底是什么类型？
```

所以写：

```cpp
SimpleRefCount<Packet>
```

等于是告诉它：

```text
我现在是在给 Packet 增加引用计数能力。
引用计数归零时，按 Packet 来删除。
```

类似地：

```cpp
class Object : public SimpleRefCount<Object, ObjectBase, ObjectDeleter>
```

表示：

```text
给 Object 增加引用计数能力。
同时继承 ObjectBase。
引用计数归零时，用 ObjectDeleter 删除。
```

先理解到这个程度就够了。

---

## 14. 模板实例化是什么

模板本身不是最终代码。

当你真正使用某个模板类型时，编译器会生成具体代码。

这个过程叫：

```text
模板实例化
```

比如模板：

```cpp
template <typename T>
class Box {
private:
    T m_value;
};
```

当你写：

```cpp
Box<int> a;
Box<double> b;
```

编译器会分别生成：

```text
Box<int> 的代码
Box<double> 的代码
```

这两个是不同类型。

所以：

```cpp
Box<int> a;
Box<double> b;
```

里面的 `a` 和 `b` 不是同一个类型。

它们只是来自同一个模板。

同理：

```cpp
Ptr<Packet>
Ptr<RdmaQueuePair>
```

也是不同类型。

一个管理 `Packet*`。

一个管理 `RdmaQueuePair*`。

只是它们来自同一个 `Ptr<T>` 模板。

---

## 15. 模板和 auto 的区别

有时候会混淆：

```cpp
template <typename T>
```

和：

```cpp
auto
```

它们都好像在“自动处理类型”。

但含义不同。

模板是定义通用代码：

```cpp
template <typename T>
T Max(T a, T b) {
    return a > b ? a : b;
}
```

`auto` 是让编译器推导变量类型：

```cpp
auto x = Max<int>(1, 2);
```

这里 `auto` 只是让编译器推导：

```text
x 是 int
```

它不是定义模板。

所以：

```text
template 用来写通用蓝图。
auto 用来让编译器推导某个变量的具体类型。
```

---

## 16. 模板和虚函数的区别

这个区别非常重要。

虚函数是运行时多态。

比如：

```cpp
Animal* a = new Dog();
a->Speak();
```

`a` 的静态类型是：

```cpp
Animal*
```

但真实对象是：

```cpp
Dog
```

如果 `Speak()` 是虚函数，程序运行时会调用：

```cpp
Dog::Speak()
```

这叫：

```text
运行时决定调用哪个函数。
```

模板是编译期生成代码。

比如：

```cpp
Ptr<Packet> p;
Ptr<RdmaQueuePair> qp;
```

编译器在编译时就知道：

```text
p 是管理 Packet 的 Ptr。
qp 是管理 RdmaQueuePair 的 Ptr。
```

这叫：

```text
编译期根据类型生成代码。
```

可以简单对比：

| 机制 | 发生时间 | 解决什么问题 |
| --- | --- | --- |
| 虚函数 | 运行时 | 父类指针调用子类实现 |
| 模板 | 编译期 | 同一套代码适配不同类型 |

所以它们不是一回事。

但在真实工程里，它们经常一起出现。

比如你的 RDMA 重构里：

```cpp
std::unique_ptr<IRdmaCongestionController>
```

这里：

```cpp
unique_ptr<T>
```

是模板。

而：

```cpp
IRdmaCongestionController
```

里面的虚函数是运行时多态。

所以这一行代码同时用到了：

```text
模板
虚函数
智能指针
```

这就是 C++ 代码为什么刚开始看起来这么密。

---

## 17. 模板错误为什么难读

C++ 模板错误经常很长。

原因是模板会在编译时展开。

如果模板内部某个地方出错，编译器会把一长串展开路径都打印出来。

比如你写：

```cpp
Ptr<MyClass> p;
```

但 `MyClass` 没有：

```cpp
Ref()
Unref()
```

那么 `Ptr<MyClass>` 在编译时可能报错：

```text
class MyClass has no member named Ref
class MyClass has no member named Unref
```

这不是因为 `Ptr<T>` 模板本身坏了。

而是因为：

```text
你把一个不满足 Ptr 要求的类型传给了 Ptr<T>。
```

所以读模板错误时，要抓住一个问题：

```text
T 到底被替换成了什么类型？
```

比如：

```cpp
Ptr<MyClass>
```

那 `T = MyClass`。

然后再看模板内部用到了哪些 `T` 的能力。

如果模板内部写：

```cpp
m_ptr->Ref();
```

那 `MyClass` 必须有：

```cpp
Ref()
```

否则就会报错。

---

## 18. 模板对类型有隐含要求

模板通常不会直接写：

```text
T 必须有什么函数。
```

但模板代码会隐含要求。

比如：

```cpp
template <typename T>
T Max(T a, T b) {
    return a > b ? a : b;
}
```

这个模板要求：

```text
T 必须支持 operator>
```

所以：

```cpp
Max<int>(1, 2)
```

没问题。

```cpp
Max<std::string>("a", "b")
```

如果 `std::string` 支持比较，也没问题。

但如果某个类型不能比较：

```cpp
Max<MyClass>(a, b)
```

就可能报错。

ns-3 的 `Ptr<T>` 也是这样。

它要求：

```text
T 必须有 Ref()
T 必须有 Unref()
```

所以：

```cpp
Ptr<Packet>
```

可以。

因为 `Packet` 继承了：

```cpp
SimpleRefCount<Packet>
```

有 `Ref()` 和 `Unref()`。

而普通类：

```cpp
class MyController {};
```

就不适合直接写：

```cpp
Ptr<MyController>
```

因为它没有引用计数能力。

---

## 19. 回到 Ptr<T>

现在再看这段：

```cpp
template <typename T>
class Ptr {
private:
    T* m_ptr;

    void Acquire() const {
        if (m_ptr != 0) {
            m_ptr->Ref();
        }
    }
};
```

如果写：

```cpp
Ptr<Packet> p;
```

那么可以想象成：

```cpp
class Ptr_Packet {
private:
    Packet* m_ptr;

    void Acquire() const {
        if (m_ptr != 0) {
            m_ptr->Ref();
        }
    }
};
```

如果写：

```cpp
Ptr<RdmaQueuePair> qp;
```

那么可以想象成：

```cpp
class Ptr_RdmaQueuePair {
private:
    RdmaQueuePair* m_ptr;

    void Acquire() const {
        if (m_ptr != 0) {
            m_ptr->Ref();
        }
    }
};
```

所以模板帮 ns-3 做了一件事：

```text
同一套 Ptr 逻辑，可以管理不同类型的 ns-3 对象。
```

---

## 20. 回到 CreateObject<T>()

再看：

```cpp
Ptr<RdmaQueuePair> qp =
    CreateObject<RdmaQueuePair>(pg, sip, dip, sport, dport);
```

这里有两个地方用到了模板。

第一个：

```cpp
Ptr<RdmaQueuePair>
```

表示：

```text
一个管理 RdmaQueuePair 对象的 ns-3 智能指针。
```

第二个：

```cpp
CreateObject<RdmaQueuePair>(...)
```

表示：

```text
调用 CreateObject 模板，并让 T = RdmaQueuePair。
创建一个 RdmaQueuePair 对象。
返回 Ptr<RdmaQueuePair>。
```

所以整句可以读成：

```text
创建一个 RdmaQueuePair 对象，
并用 Ptr<RdmaQueuePair> 管理它。
```

这句代码和标准 C++ 里的：

```cpp
std::unique_ptr<Dog> d = std::make_unique<Dog>();
```

有相似的地方：

```text
都是创建对象，并交给智能指针管理。
```

但所有权机制不一样：

```text
make_unique 返回 unique_ptr，表示独占所有权。
CreateObject 返回 Ptr，表示 ns-3 引用计数。
```

---

## 21. 回到 SimpleRefCount<Packet>

再看：

```cpp
class Packet : public SimpleRefCount<Packet>
{
    ...
};
```

现在可以这样读：

```text
Packet 继承了 SimpleRefCount 模板的一个具体版本。
这个具体版本里，T = Packet。
```

也就是说，`SimpleRefCount<Packet>` 是编译器根据模板生成出来的一个基类。

它给 `Packet` 提供：

```cpp
Ref()
Unref()
GetReferenceCount()
```

所以 `Packet` 才能被：

```cpp
Ptr<Packet>
```

管理。

`Ptr<Packet>` 里面调用：

```cpp
m_ptr->Ref();
m_ptr->Unref();
```

时，`Packet` 是有这些函数的。

---

## 22. 回到 unique_ptr<T>

标准智能指针本身也是模板。

比如：

```cpp
std::unique_ptr<IRdmaCongestionController> m_ccController;
```

这里：

```cpp
std::unique_ptr<T>
```

也是一个类模板。

`T` 被替换成：

```cpp
IRdmaCongestionController
```

所以：

```cpp
std::unique_ptr<IRdmaCongestionController>
```

表示：

```text
一个管理 IRdmaCongestionController* 的 unique_ptr。
```

当你写：

```cpp
std::unique_ptr<Dog>
```

`T = Dog`。

当你写：

```cpp
std::unique_ptr<Animal>
```

`T = Animal`。

所以标准智能指针和 ns-3 `Ptr` 一样，都用了模板。

区别在于：

```text
unique_ptr<T> 表达独占所有权。
Ptr<T> 表达 ns-3 引用计数。
```

---

## 23. 为什么模板代码经常写在 .h 文件里

你会发现：

```cpp
Ptr<T>
Create<T>()
SimpleRefCount<T>
```

很多模板代码都写在头文件里。

这是因为模板需要在使用时让编译器看到完整定义。

比如你在某个 `.cc` 文件里写：

```cpp
Ptr<Packet> p;
```

编译器需要知道 `Ptr<T>` 的完整代码，才能生成 `Ptr<Packet>`。

如果只有声明，没有实现，编译器没法实例化模板。

所以模板类和模板函数经常直接写在 `.h` 文件里。

这也是为什么 ns-3 的：

```text
src/core/model/ptr.h
src/core/model/simple-ref-count.h
```

里面有大量实现代码。

它们不是普通 `.h` 只放声明的风格。

模板代码放头文件，是 C++ 里很常见的现象。

---

## 24. 读模板代码的办法

读模板代码时，不要一开始就把所有东西都抽象地想。

最实用的方法是：

```text
先选一个具体类型，把 T 替换掉。
```

比如看到：

```cpp
template <typename T>
class Ptr {
private:
    T* m_ptr;
};
```

如果你正在看 packet 代码，就把 `T` 换成 `Packet`：

```cpp
class Ptr_Packet {
private:
    Packet* m_ptr;
};
```

如果你正在看 RDMA QP，就把 `T` 换成 `RdmaQueuePair`：

```cpp
class Ptr_RdmaQueuePair {
private:
    RdmaQueuePair* m_ptr;
};
```

这样模板马上就不抽象了。

读函数模板也是一样。

看到：

```cpp
template <typename T>
Ptr<T> Create() {
    return Ptr<T>(new T(), false);
}
```

如果调用是：

```cpp
Create<Packet>()
```

就把 `T` 换成 `Packet`：

```cpp
Ptr<Packet> Create_Packet() {
    return Ptr<Packet>(new Packet(), false);
}
```

这是理解模板最有效的办法。

---

## 25. 总结

模板的核心不是复杂语法。

模板的核心是：

```text
把类型变成参数。
让编译器根据具体类型生成具体代码。
```

`template <typename T>` 的意思是：

```text
这里定义的是一个模板。
T 是一个类型占位符。
```

`Ptr<T>` 的意思是：

```text
一个通用的 Ptr 模板。
具体管理什么类型，由 T 决定。
```

`Ptr<Packet>` 中：

```text
T = Packet
```

`Ptr<RdmaQueuePair>` 中：

```text
T = RdmaQueuePair
```

`Create<T>()` 是函数模板。

`Create<Packet>()` 表示创建 `Packet`。

`CreateObject<RdmaQueuePair>()` 表示创建 `RdmaQueuePair` 这种 ns-3 `Object`。

`SimpleRefCount<Packet>` 表示给 `Packet` 增加引用计数能力。

理解模板之后，再回头看：

```cpp
template <typename T>
class Ptr {
private:
    T* m_ptr;
};
```

它就不神秘了。

它只是说：

```text
定义一个通用的智能指针模板。
如果 T 是 Packet，它里面保存 Packet*。
如果 T 是 RdmaQueuePair，它里面保存 RdmaQueuePair*。
如果 T 是 RdmaHw，它里面保存 RdmaHw*。
```

ns-3 之所以能用一套 `Ptr<T>` 管理各种对象，靠的就是 C++ 模板。

等这块地基稳了，再读 ns-3 的 `Ptr<T>`、`Create<T>()`、`CreateObject<T>()`、`SimpleRefCount<T>`，就会顺很多。
