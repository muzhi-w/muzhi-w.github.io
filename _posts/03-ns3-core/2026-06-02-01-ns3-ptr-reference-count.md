---
title: "彻底理解 ns-3 的 Ptr：从引用计数到 RDMA 对象生命周期"
date: 2026-06-02 15:30:00 +0800
permalink: /posts/ns3-ptr-reference-count/
categories: [网络, ns-3]
tags: [ns3, cpp, smart-pointer, ptr, reference-count, object, rdma]
description: "从 C++ 智能指针讲到 ns-3 自己的 Ptr<T>，理解 Create、CreateObject、SimpleRefCount、Object、Dispose，以及它们在 RDMA 代码里的生命周期语义。"
---

<!-- series-nav -->
> **系列位置**：ns-3 源码阅读，第 01 篇 / 共 4 篇
> **总目录**：[学习路线](/roadmap/)
> **下一篇**：[彻底理解 ns-3 对象系统：Object、TypeId 和 Attribute](/posts/ns3-object-typeid-attribute/)


上一篇文章里，我们系统讲了 C++ 标准智能指针：

```cpp
std::unique_ptr
std::shared_ptr
std::weak_ptr
```

但是读 ns-3 代码时，很快会发现另一种指针到处都是：

```cpp
Ptr<Node>
Ptr<Packet>
Ptr<NetDevice>
Ptr<RdmaHw>
Ptr<RdmaQueuePair>
Ptr<QbbNetDevice>
```

这不是 `std::unique_ptr`。

也不是 `std::shared_ptr`。

它是 ns-3 自己实现的一套智能指针：

```cpp
ns3::Ptr<T>
```

这篇文章专门讲它。

先说结论：

> ns-3 的 `Ptr<T>` 是一套侵入式引用计数智能指针。
>
> 它通过对象内部的 `Ref()` / `Unref()` 管理生命周期。

如果上一篇文章的核心是：

```text
标准智能指针用类型表达所有权。
```

那么这篇文章的核心就是：

```text
ns-3 用 Ptr<T> 管理仿真对象的引用关系。
```

理解了 `Ptr<T>`，再看 RDMA 代码里的这些函数就会自然很多：

```cpp
void InitQp(Ptr<RdmaQueuePair> qp,
            Ptr<QbbNetDevice> dev,
            Ptr<RdmaHw> hw);
```

它们不是随便写成指针。

它们是在接入 ns-3 的对象生命周期体系。

本文涉及的源码主要来自我当前使用的 ns-3.19 工作区：

```text
src/core/model/ptr.h
src/core/model/simple-ref-count.h
src/core/model/object.h
src/core/model/object.cc
src/network/model/packet.h
src/point-to-point/model/rdma-hw.h
src/point-to-point/model/rdma-hw.cc
src/point-to-point/model/rdma-queue-pair.h
```

文中有些代码是源码摘录，有些是为了讲清楚机制而写的简化版。遇到简化版时，我会明确说明。

---

## 1. 先看 RDMA 代码里的 Ptr

在你的 `RdmaHw` 里，有很多这样的代码：

代码来源：

```text
src/point-to-point/model/rdma-hw.cc
```

```cpp
Ptr<RdmaQueuePair> qp = CreateObject<RdmaQueuePair>(pg, sip, dip, sport, dport);
```

还有：

```cpp
Ptr<RdmaRxQueuePair> q = CreateObject<RdmaRxQueuePair>();
```

还有 packet：

```cpp
Ptr<Packet> p = Create<Packet>(payload_size);
```

还有函数参数：

```cpp
int ReceiveUdp(Ptr<Packet> p, CustomHeader& ch);

void EnsureSenderCcReady(Ptr<RdmaQueuePair> qp,
                         Ptr<QbbNetDevice> dev);
```

这些 `Ptr<T>` 的共同含义是：

```text
这是一个 ns-3 风格的智能指针。
它指向一个由 ns-3 引用计数机制管理的对象。
当前代码不需要手动 delete。
```

所以在 ns-3 里看到：

```cpp
Ptr<T>
```

第一反应不应该是：

```text
这是裸指针吗？
```

而应该是：

```text
这是 ns-3 引用计数对象的句柄。
```

---

## 2. Ptr<T> 为什么不是裸指针

裸指针写法是：

```cpp
RdmaQueuePair* qp = new RdmaQueuePair(...);
```

这种写法有几个老问题：

```text
谁负责 delete？
什么时候 delete？
如果函数中途 return 怎么办？
如果多个地方都保存这个指针，谁最后释放？
```

ns-3 里仿真对象经常会被很多模块同时引用。

比如一个 `RdmaQueuePair` 可能同时出现在：

```text
RdmaHw 的 m_qpMap 里
RdmaQueuePairGroup 的 m_qps 里
某个函数调用栈里
某个事件回调参数里
拥塞控制逻辑里
```

如果用裸指针，很难说清楚到底谁负责释放。

所以 ns-3 用：

```cpp
Ptr<RdmaQueuePair>
```

来表达：

```text
我引用这个对象。
只要还有 Ptr 引用它，它就应该活着。
最后一个 Ptr 消失时，对象可以被销毁。
```

这和 `std::shared_ptr` 有点像。

但实现方式不一样。

---

## 3. Ptr<T> 更像 intrusive_ptr

ns-3 的 `Ptr<T>` 源码注释里说，它类似：

代码来源：

```text
src/core/model/ptr.h
```

```cpp
boost::intrusive_ptr
```

这里的关键词是：

```text
intrusive
```

意思是“侵入式”。

什么叫侵入式引用计数？

就是引用计数不放在智能指针外部，而是放在对象内部。

普通 `std::shared_ptr` 大概是这样：

```text
shared_ptr
    |
    v
控制块：引用计数
    |
    v
真实对象
```

而 ns-3 的 `Ptr<T>` 更像这样：

```text
Ptr<T>
    |
    v
真实对象 T
    |
    v
对象内部有引用计数
```

所以 `Ptr<T>` 要求 `T` 这个类型本身提供：

```cpp
Ref()
Unref()
```

`Ptr<T>` 拷贝时调用 `Ref()`。

`Ptr<T>` 析构时调用 `Unref()`。

这就是 ns-3 `Ptr<T>` 的底层逻辑。

---

## 4. SimpleRefCount 是什么

ns-3 里很多可以被 `Ptr<T>` 管理的类，会继承：

```cpp
SimpleRefCount
```

比如 `Packet`：

代码来源：

```text
src/network/model/packet.h
```

```cpp
class Packet : public SimpleRefCount<Packet>
{
    ...
};
```

`SimpleRefCount` 会给对象提供引用计数能力。

它里面最核心的东西可以简化理解成：

```cpp
class SimpleRefCountLike {
public:
    void Ref() const {
        m_count++;
    }

    void Unref() const {
        m_count--;
        if (m_count == 0) {
            delete this;
        }
    }

private:
    mutable uint32_t m_count;
};
```

真实源码更复杂一些，因为它用了模板和自定义 deleter。

但核心逻辑就是：

```text
Ref() 增加引用计数。
Unref() 减少引用计数。
引用计数变成 0 时删除对象。
```

注意，`Ref()` 和 `Unref()` 一般不应该由用户代码手动调用。

正常情况下，应该让：

```cpp
Ptr<T>
```

自动调用它们。

---

## 5. Ptr<T> 里面到底有什么

`Ptr<T>` 内部其实很朴素。

可以粗略理解成：

简化自：

```text
src/core/model/ptr.h
```

```cpp
template <typename T>
class Ptr {
private:
    T* m_ptr;
};
```

它保存的仍然是一个裸指针。

但是它在构造、拷贝、析构、赋值时，会自动处理引用计数。

简化之后，大概是这样：

```cpp
template <typename T>
class Ptr {
public:
    Ptr()
        : m_ptr(0) {}

    Ptr(T* ptr)
        : m_ptr(ptr) {
        Acquire();
    }

    Ptr(const Ptr& other)
        : m_ptr(other.m_ptr) {
        Acquire();
    }

    ~Ptr() {
        if (m_ptr != 0) {
            m_ptr->Unref();
        }
    }

private:
    void Acquire() const {
        if (m_ptr != 0) {
            m_ptr->Ref();
        }
    }

    T* m_ptr;
};
```

所以这句话：

```cpp
Ptr<Packet> p2 = p1;
```

不是简单复制一个地址。

它还会让 `Packet` 的引用计数加一。

而当 `p2` 离开作用域时，它会让引用计数减一。

---

## 6. 引用计数变化例子

假设我们写：

```cpp
Ptr<Packet> p1 = Create<Packet>(100);
```

`Create<Packet>(100)` 会创建一个 `Packet`，并返回 `Ptr<Packet>`。

此时可以粗略理解为：

```text
Packet 引用计数 = 1
p1 指向 Packet
```

然后：

```cpp
Ptr<Packet> p2 = p1;
```

`p2` 拷贝了 `p1`。

引用计数变成：

```text
Packet 引用计数 = 2
p1 指向 Packet
p2 指向同一个 Packet
```

如果 `p2` 离开作用域：

```text
Packet 引用计数 = 1
p1 还在
Packet 不能删除
```

如果 `p1` 也离开作用域：

```text
Packet 引用计数 = 0
Packet 被删除
```

这就是 `Ptr<T>` 的基本生命模型。

---

## 7. Create<T>()：给 SimpleRefCount 对象用

ns-3 里创建 `Ptr<T>` 对象时，常见写法不是：

```cpp
Ptr<Packet> p(new Packet(...));
```

而是：

```cpp
Ptr<Packet> p = Create<Packet>(...);
```

比如你的代码里有：

```cpp
Ptr<Packet> newp = Create<Packet>(payload_size);
```

`Create<T>()` 大概做了这样的事情：

简化自：

```text
src/core/model/ptr.h
```

```cpp
return Ptr<T>(new T(args...), false);
```

这里有一个非常重要的细节：

```cpp
false
```

它的意思是：

```text
创建 Ptr 时，不再额外调用 Ref()。
```

为什么？

因为 `SimpleRefCount` 对象刚刚构造出来时，引用计数已经是 1。

如果再调用一次 `Ref()`，引用计数会变成 2。

那就可能导致对象永远删不掉。

所以 ns-3 提供 `Create<T>()`，就是为了把这个细节封装起来。

正常写代码时，应该优先使用：

```cpp
Create<T>()
```

而不是自己手写：

```cpp
new T()
```

---

## 8. 一个容易踩的坑：Ptr<T>(new T())

看起来下面这句好像也可以：

```cpp
Ptr<Packet> p(new Packet());
```

但这在 ns-3 里很容易出问题。

原因是：

```text
new Packet() 创建对象时，引用计数初始为 1。
Ptr<Packet>(raw) 构造时又会调用 Ref()。
引用计数变成 2。
```

如果没有对应地手动 `Unref()` 掉最初那一份引用，对象就可能泄漏。

所以 ns-3 源码里会提供这种写法：

```cpp
Ptr<T>(new T(args...), false)
```

但是普通业务代码里更推荐：

```cpp
Ptr<T> p = Create<T>(args...);
```

可以这样记：

```text
普通 C++ unique_ptr：new 出来立刻交给 unique_ptr。
ns-3 Ptr：不要随手 new，优先用 Create 或 CreateObject。
```

---

## 9. CreateObject<T>()：给 Object 子类用

ns-3 里还有一个非常重要的创建函数：

```cpp
CreateObject<T>()
```

比如你的 RDMA 代码里：

代码来源：

```text
src/point-to-point/model/rdma-hw.cc
```

```cpp
Ptr<RdmaQueuePair> qp =
    CreateObject<RdmaQueuePair>(pg, sip, dip, sport, dport);
```

还有：

```cpp
Ptr<RdmaRxQueuePair> q = CreateObject<RdmaRxQueuePair>();
```

为什么这里不用 `Create<T>()`，而用 `CreateObject<T>()`？

因为：

```cpp
RdmaQueuePair
RdmaRxQueuePair
RdmaHw
```

这些类继承自：

```cpp
ns3::Object
```

比如：

代码来源：

```text
src/point-to-point/model/rdma-queue-pair.h
```

```cpp
class RdmaQueuePair : public Object {
    ...
};
```

`Object` 不只是引用计数。

它还接入了 ns-3 的对象系统：

```text
TypeId
Attribute
ObjectFactory
AggregateObject
Initialize
Dispose / DoDispose
```

所以 `CreateObject<T>()` 不只是 `new T()`。

它还会做对象构造后的 ns-3 初始化工作。

源码里大概是：

代码来源：

```text
src/core/model/object.h
```

```cpp
Ptr<T> CompleteConstruct(T* p) {
    p->SetTypeId(T::GetTypeId());
    p->Object::Construct(AttributeConstructionList());
    return Ptr<T>(p, false);
}
```

所以选择规则是：

```text
如果 T 只是 SimpleRefCount 对象，用 Create<T>()。
如果 T 是 Object 子类，用 CreateObject<T>()。
```

在你的代码里：

```cpp
Packet
```

是 `SimpleRefCount<Packet>`，所以常见：

```cpp
Create<Packet>()
```

而：

```cpp
RdmaQueuePair
RdmaRxQueuePair
RdmaHw
QbbNetDevice
Node
```

都是 ns-3 `Object` 体系里的对象，所以常见：

```cpp
CreateObject<T>()
```

---

## 10. Object 是什么

`ns3::Object` 可以理解成 ns-3 仿真对象体系的基类。

它本身继承了引用计数：

代码来源：

```text
src/core/model/object.h
```

```cpp
class Object : public SimpleRefCount<Object, ObjectBase, ObjectDeleter>
{
    ...
};
```

所以 `Object` 子类天然可以被 `Ptr<T>` 管理。

但 `Object` 还提供了更多功能。

比如：

```cpp
TypeId
```

用于 ns-3 的类型系统。

比如：

```cpp
Attribute
```

用于配置对象属性。

比如：

```cpp
AggregateObject
```

用于把多个 `Object` 聚合到一起。

再比如：

```cpp
Dispose()
DoDispose()
```

用于释放引用关系，打破循环依赖。

所以：

```text
SimpleRefCount 只负责引用计数。
Object 在引用计数之上，加了 ns-3 对象模型。
```

---

## 11. Dispose 和 DoDispose

引用计数有一个经典问题：

```text
循环引用。
```

比如：

```text
A 通过 Ptr 持有 B。
B 又通过 Ptr 持有 A。
```

这时即使外部引用都没了，`A` 和 `B` 仍然互相引用。

引用计数不会变成 0。

对象就不会自动释放。

标准 C++ 里通常用：

```cpp
std::weak_ptr
```

来打破循环。

而 ns-3 的 `Ptr<T>` 没有对应的 `weak_ptr`。

ns-3 的做法是：

```cpp
Dispose()
DoDispose()
```

`Dispose()` 会触发对象的 `DoDispose()`。

子类应该在 `DoDispose()` 里清理自己持有的 `Ptr`、取消事件、释放和其他对象的引用关系。

ns-3 的注释里也强调：很多真正的销毁清理逻辑应该放到 `DoDispose()`，而不是析构函数里。

相关源码：

```text
src/core/model/object.h
src/core/model/object.cc
```

可以粗略理解：

```text
析构函数：对象真正被 delete 时执行。
DoDispose：提前断开 ns-3 对象之间的引用关系。
```

对于普通 RDMA queue pair 这种对象，你可能不一定显式写 `DoDispose()`。

但如果一个对象持有很多 `Ptr`，或者注册了事件回调，或者可能和别的对象互相引用，就要认真考虑 `DoDispose()`。

---

## 12. Ptr<T> 作为函数参数

ns-3 代码里经常直接按值传 `Ptr<T>`：

```cpp
void RdmaHw::EnsureSenderCcReady(Ptr<RdmaQueuePair> qp,
                                 Ptr<QbbNetDevice> dev) {
    ...
}
```

这和裸指针不同。

传 `Ptr<T>` 时，会拷贝一个 `Ptr<T>`。

拷贝时会调用 `Ref()`。

所以函数执行期间，对象引用计数会增加。

函数返回时，参数里的 `Ptr<T>` 析构，又会调用 `Unref()`。

可以理解成：

```text
这个函数临时持有对象的一份引用。
函数执行期间，对象不会因为其他引用消失而被删除。
函数结束后，这份临时引用释放。
```

所以：

```cpp
void Foo(Ptr<Packet> p)
```

不是转移所有权。

它只是共享一份引用。

这点和：

```cpp
void Foo(std::unique_ptr<Packet> p)
```

完全不同。

`unique_ptr` 按值传参通常表示所有权转移。

`Ptr<T>` 按值传参通常表示临时增加一份引用。

---

## 13. Ptr<T> 的访问方式

`Ptr<T>` 用起来很像普通指针。

比如：

```cpp
qp->SetInitialRate(rate);
```

这是因为 `Ptr<T>` 重载了：

```cpp
operator->()
```

也可以解引用：

```cpp
(*qp).SetInitialRate(rate);
```

也可以判断是否为空：

```cpp
if (qp) {
    ...
}
```

或者：

```cpp
if (qp == 0) {
    ...
}
```

你的代码里有：

```cpp
if (m_ccController) {
    ...
}
```

这是 `std::unique_ptr` 的布尔判断。

而 ns-3 里也经常看到：

```cpp
if (qp == NULL) {
    ...
}
```

这是 `Ptr<T>` 和空指针比较。

虽然写法相似，但背后机制不一样。

---

## 14. PeekPointer 和 GetPointer

有时你会看到 ns-3 里有两个函数：

```cpp
PeekPointer(p)
GetPointer(p)
```

它们都会从 `Ptr<T>` 里拿出裸指针。

但语义不同。

`PeekPointer`：

```cpp
T* raw = PeekPointer(p);
```

只是偷看一下内部裸指针。

它不会增加引用计数。

所以调用者不需要 `Unref()`。

但是也不能把这个裸指针长期保存下来，除非你能保证原来的 `Ptr<T>` 活得足够久。

`GetPointer`：

```cpp
T* raw = GetPointer(p);
```

会先增加引用计数。

这意味着调用者拿到的不只是观察指针，而是拿到了一份需要负责释放的引用。

之后调用者应该手动：

```cpp
raw->Unref();
```

所以普通代码里应当尽量少用 `GetPointer`。

可以这样记：

```text
PeekPointer：只看，不加引用计数。
GetPointer：拿一份引用，要负责 Unref。
```

如果只是为了调用成员函数，不需要这两个函数。

直接：

```cpp
p->DoSomething();
```

就好。

---

## 15. Ptr<T> 的类型转换

ns-3 也给 `Ptr<T>` 提供了类似指针转换的工具。

比如：

```cpp
DynamicCast<T>(p)
StaticCast<T>(p)
ConstCast<T>(p)
```

这和 C++ 里的：

```cpp
dynamic_cast
static_cast
const_cast
```

类似，只是返回的仍然是：

```cpp
Ptr<T>
```

例如：

```cpp
Ptr<NetDevice> dev = ...;
Ptr<QbbNetDevice> qbb = DynamicCast<QbbNetDevice>(dev);
```

如果真实对象确实是 `QbbNetDevice`，那么 `qbb` 就非空。

如果不是，`qbb` 就是空指针。

这种写法比先拿裸指针再 cast 更符合 ns-3 风格。

---

## 16. Ptr<T> 和 std::shared_ptr 的区别

`Ptr<T>` 看起来很像 `std::shared_ptr<T>`。

但它们不是一回事。

可以这样对比：

| 类型 | 引用计数放在哪里 | 对象需要配合吗 | 是否标准 C++ | 典型使用场景 |
| --- | --- | --- | --- | --- |
| `std::shared_ptr<T>` | 外部控制块 | 不需要继承特殊基类 | 是 | 普通 C++ 共享所有权 |
| `ns3::Ptr<T>` | 对象内部 | 需要 `Ref()` / `Unref()` | 不是 | ns-3 仿真对象 |

`std::shared_ptr` 可以管理普通 C++ 对象：

```cpp
std::shared_ptr<Dog> p = std::make_shared<Dog>();
```

`Ptr<T>` 不行。

如果 `T` 没有：

```cpp
Ref()
Unref()
```

那么：

```cpp
Ptr<T>
```

就无法正常工作。

所以 `Ptr<T>` 不是一个通用替代品。

它是 ns-3 对象体系的一部分。

---

## 17. Ptr<T> 和 std::unique_ptr 的区别

`std::unique_ptr<T>` 表示：

```text
唯一拥有者。
不能拷贝，只能移动。
```

而 `Ptr<T>` 表示：

```text
共享引用。
可以拷贝。
拷贝时引用计数增加。
```

所以：

```cpp
std::unique_ptr<IRdmaCongestionController> m_ccController;
```

和：

```cpp
Ptr<RdmaQueuePair> qp;
```

表达的是完全不同的设计。

前者表示：

```text
RdmaHw 独占拥有一个拥塞控制器。
```

后者表示：

```text
这是一个 ns-3 queue pair 对象，可能被多个地方引用。
```

所以不能因为它们都叫“智能指针”，就混着用。

---

## 18. 为什么 m_ccController 不用 Ptr<T>

你的 `RdmaHw` 里现在有：

```cpp
std::unique_ptr<IRdmaCongestionController> m_ccController;
```

有人可能会问：

```text
ns-3 不是有 Ptr<T> 吗？
为什么这里不用 Ptr<IRdmaCongestionController>？
```

原因有两个。

第一，`IRdmaCongestionController` 不是 ns-3 `Object`。

它只是一个普通 C++ 接口：

```cpp
class IRdmaCongestionController {
public:
    virtual ~IRdmaCongestionController() = default;
    ...
};
```

它没有继承：

```cpp
Object
SimpleRefCount
```

也没有提供：

```cpp
Ref()
Unref()
```

所以它不适合用 `Ptr<T>`。

第二，controller 的所有权语义不是共享引用。

它是：

```text
RdmaHw 独占拥有一个 controller。
```

这正是 `std::unique_ptr` 的语义。

所以：

```cpp
std::unique_ptr<IRdmaCongestionController>
```

比：

```cpp
Ptr<IRdmaCongestionController>
```

更准确。

换句话说：

```text
ns-3 仿真对象，用 Ptr<T>。
普通 C++ 独占策略对象，用 unique_ptr。
```

---

## 19. RDMA 里的 QP 生命周期

看这段代码：

代码来源：

```text
src/point-to-point/model/rdma-hw.cc
```

```cpp
Ptr<RdmaQueuePair> qp =
    CreateObject<RdmaQueuePair>(pg, sip, dip, sport, dport);

m_nic[nic_idx].qpGrp->AddQp(qp);

uint64_t key = GetQpKey(dip.Get(), sport, dport, pg);
m_qpMap[key] = qp;
```

这里 `qp` 至少被几个地方引用：

```text
局部变量 qp
RdmaQueuePairGroup::m_qps
RdmaHw::m_qpMap
```

每多保存一份 `Ptr<RdmaQueuePair>`，引用计数就会增加。

函数结束后，局部变量 `qp` 消失。

但 QP 不会被删除。

因为它还在：

```text
m_qpMap
qpGrp->m_qps
```

里面。

再看删除：

```cpp
void RdmaHw::DeleteQueuePair(Ptr<RdmaQueuePair> qp) {
    uint64_t key = GetQpKey(qp->dip.Get(), qp->sport, qp->dport, qp->m_pg);
    m_qpMap.erase(key);
}
```

`erase` 只是删除了 `m_qpMap` 里的那一份 `Ptr`。

这会让引用计数减一。

但它不一定意味着 QP 立刻被删除。

如果别的地方还有 `Ptr<RdmaQueuePair>`，对象还会继续活着。

所以：

```text
从一个容器里 erase Ptr，不等于马上 delete 对象。
只有最后一个 Ptr 消失，对象才会被释放。
```

这就是引用计数模型。

---

## 20. RDMA 里的 Packet 生命周期

`Packet` 不是 `Object` 子类。

它继承的是：

代码来源：

```text
src/network/model/packet.h
```

```cpp
SimpleRefCount<Packet>
```

所以创建 packet 常见写法是：

```cpp
Ptr<Packet> p = Create<Packet>(payload_size);
```

在 RDMA 反馈包构造代码里，也会看到：

```cpp
Ptr<Packet> newp = Create<Packet>(...);
```

然后这个 `Ptr<Packet>` 会被传来传去：

```cpp
ReceiveUdp(Ptr<Packet> p, CustomHeader& ch)
ReceiveCnp(Ptr<Packet> p, CustomHeader& ch)
ReceiveAck(Ptr<Packet> p, CustomHeader& ch)
```

每次按值传递 `Ptr<Packet>`，都会临时增加引用计数。

函数结束后，临时引用消失。

所以 `Packet` 也不需要手动 `delete`。

这对网络仿真特别重要，因为一个包可能会在协议栈、设备、队列、事件之间流动。

用裸指针管理会非常容易出错。

---

## 21. 传 this 给 Ptr<RdmaHw>

你的 controller 接口里有：

```cpp
virtual void InitQp(Ptr<RdmaQueuePair> qp,
                    Ptr<QbbNetDevice> dev,
                    Ptr<RdmaHw> hw) = 0;
```

而调用处可能写：

```cpp
m_ccController->InitQp(qp, m_nic[nic_idx].dev, this);
```

这里第三个参数需要：

```cpp
Ptr<RdmaHw>
```

但传进去的是：

```cpp
this
```

也就是：

```cpp
RdmaHw*
```

为什么能编译？

因为 `Ptr<T>` 有从裸指针构造的构造函数：

```cpp
Ptr(T* ptr)
```

所以编译器可以把：

```cpp
this
```

临时转换成：

```cpp
Ptr<RdmaHw>
```

这个临时 `Ptr<RdmaHw>` 会在函数调用期间增加一次引用计数。

函数调用结束后，临时对象析构，再减少一次引用计数。

这在短调用里通常没问题。

但如果要长期保存 `RdmaHw`，最好明确地保存一个已有的 `Ptr<RdmaHw>`，而不是到处从裸指针临时构造。

这也是为什么理解 `Ptr<T>` 的隐式构造很重要。

---

## 22. Ptr<T> 不等于所有权转移

在标准 C++ 里，如果函数这样写：

```cpp
void Take(std::unique_ptr<Dog> dog);
```

通常表示：

```text
函数接管 dog 的所有权。
调用者失去 dog。
```

但 ns-3 里：

```cpp
void Foo(Ptr<Packet> p);
```

不是这个意思。

它表示：

```text
函数拿到一份共享引用。
调用者手里的 Ptr 仍然有效。
```

调用后：

```cpp
Ptr<Packet> p = Create<Packet>(100);
Foo(p);
p->GetSize();  // 仍然可以继续使用
```

所以 `Ptr<T>` 更接近共享引用。

它不是移动语义。

也不是独占所有权。

---

## 23. 常见错误一：手动 delete Ptr 里的对象

错误写法：

```cpp
Ptr<Packet> p = Create<Packet>(100);
delete PeekPointer(p);  // 错误
```

不要这样做。

对象是由引用计数管理的。

如果你手动 `delete`，其他 `Ptr` 还以为对象活着，后面再访问就会出问题。

正确做法是：

```text
让 Ptr 自己析构。
让引用计数自然归零。
```

---

## 24. 常见错误二：随便调用 Ref 和 Unref

`Ref()` / `Unref()` 是底层机制。

普通业务代码不应该手动写：

```cpp
p->Ref();
p->Unref();
```

否则很容易打乱引用计数。

比如多调用一次 `Ref()`，对象可能泄漏。

多调用一次 `Unref()`，对象可能提前删除。

一般规则是：

```text
用 Ptr<T> 表达引用。
不要手动管理引用计数。
```

只有在很底层、明确知道自己在做什么的代码里，才考虑直接碰 `Ref()` / `Unref()`。

---

## 25. 常见错误三：把 Ptr<T> 当 weak_ptr

`Ptr<T>` 是强引用。

只要你保存一份 `Ptr<T>`，对象引用计数就会增加。

所以如果两个对象互相保存 `Ptr`：

```text
A 保存 Ptr<B>
B 保存 Ptr<A>
```

就可能形成循环引用。

引用计数不会自动识别这种循环。

ns-3 也没有：

```cpp
WeakPtr<T>
```

这种标准设施。

所以这种场景要靠设计来避免，或者通过：

```cpp
Dispose()
DoDispose()
```

显式断开引用关系。

---

## 26. 常见错误四：用 Ptr<T> 管普通类

假设你写：

```cpp
class MyController {
public:
    void Run();
};
```

然后尝试：

```cpp
Ptr<MyController> p;
```

这通常不是对的。

因为 `MyController` 没有：

```cpp
Ref()
Unref()
```

`Ptr<T>` 不知道怎么增加和减少引用计数。

如果你确实想让它成为 ns-3 引用计数对象，可以考虑继承：

```cpp
SimpleRefCount<MyController>
```

或者如果它应该进入 ns-3 对象系统，可以继承：

```cpp
Object
```

但不要为了“能用 Ptr”就随便继承 `Object`。

如果它只是一个普通 C++ 策略对象，像你的：

```cpp
IRdmaCongestionController
```

那用：

```cpp
std::unique_ptr
```

反而更清晰。

---

## 27. 常见错误五：混用 std::shared_ptr 和 Ptr

不要让同一个对象同时被：

```cpp
std::shared_ptr<T>
```

和：

```cpp
Ptr<T>
```

管理。

它们的引用计数体系完全不同。

`shared_ptr` 的引用计数在外部控制块。

`Ptr<T>` 的引用计数在对象内部。

如果混用，很容易出现：

```text
一边认为对象还活着。
另一边已经把对象删除了。
```

在 ns-3 对象上，优先遵循 ns-3 风格：

```cpp
Ptr<T>
Create<T>()
CreateObject<T>()
```

在普通 C++ 对象上，使用标准智能指针：

```cpp
std::unique_ptr
std::shared_ptr
```

---

## 28. 选择规则

最后总结一套实用选择规则。

第一，如果对象是 ns-3 `Object` 子类：

```cpp
class RdmaQueuePair : public Object
```

用：

```cpp
Ptr<RdmaQueuePair> qp = CreateObject<RdmaQueuePair>(...);
```

第二，如果对象只是 `SimpleRefCount` 子类，不是 `Object`：

```cpp
class Packet : public SimpleRefCount<Packet>
```

用：

```cpp
Ptr<Packet> p = Create<Packet>(...);
```

第三，如果对象是普通 C++ 类，并且只有一个拥有者：

```cpp
std::unique_ptr<T>
```

比如：

```cpp
std::unique_ptr<IRdmaCongestionController> m_ccController;
```

第四，如果对象是普通 C++ 类，并且确实需要共享所有权：

```cpp
std::shared_ptr<T>
```

第五，如果只是临时访问，不负责生命周期：

```cpp
T*
T&
Ptr<T>
```

具体选哪个取决于对象属于哪套生命周期体系。

如果它是 ns-3 对象，按 ns-3 风格传 `Ptr<T>` 很常见。

如果它是普通 C++ 对象，按标准 C++ 的所有权语义选择。

---

## 29. 回到 RDMA 重构

现在再看你的统一接口：

```cpp
class IRdmaCongestionController {
public:
    virtual ~IRdmaCongestionController() = default;

    virtual void InitQp(Ptr<RdmaQueuePair> qp,
                        Ptr<QbbNetDevice> dev,
                        Ptr<RdmaHw> hw) = 0;

    virtual void OnAck(Ptr<RdmaQueuePair> qp,
                       Ptr<Packet> p,
                       CustomHeader& ch,
                       Ptr<RdmaHw> hw) {}
};
```

这里其实同时出现了两套生命周期模型。

第一套是 ns-3 对象模型：

```cpp
Ptr<RdmaQueuePair>
Ptr<QbbNetDevice>
Ptr<Packet>
Ptr<RdmaHw>
```

这些对象由 ns-3 的 `Ptr<T>` 引用计数体系管理。

第二套是普通 C++ 策略对象模型：

```cpp
std::unique_ptr<IRdmaCongestionController> m_ccController;
```

controller 本身由 `RdmaHw` 独占拥有。

所以这套设计其实很清楚：

```text
RdmaHw 用 unique_ptr 拥有一个 controller。
controller 通过 Ptr<T> 操作 ns-3 仿真对象。
```

这就是为什么接口里是：

```cpp
Ptr<RdmaQueuePair> qp
```

而成员变量是：

```cpp
std::unique_ptr<IRdmaCongestionController> m_ccController
```

它们不是矛盾的。

它们分别属于两套对象生命周期。

---

## 30. 总结

ns-3 的 `Ptr<T>` 是 ns-3 自己的智能指针。

它的核心机制是：

```text
Ptr<T> 保存 T*
T 内部有引用计数
Ptr 拷贝时调用 Ref()
Ptr 析构时调用 Unref()
引用计数为 0 时对象被删除
```

它适合管理：

```text
ns-3 Object 子类
SimpleRefCount 子类
ns-3 仿真系统里的共享对象
```

它不适合随便管理普通 C++ 类。

`Create<T>()` 适合 `SimpleRefCount` 对象。

`CreateObject<T>()` 适合 `Object` 子类。

`Dispose()` / `DoDispose()` 用来处理 ns-3 对象之间复杂引用关系，尤其是循环引用和聚合对象清理。

回到 RDMA 代码：

```cpp
Ptr<RdmaQueuePair> qp
Ptr<Packet> p
Ptr<QbbNetDevice> dev
Ptr<RdmaHw> hw
```

这些表示 ns-3 仿真对象引用。

而：

```cpp
std::unique_ptr<IRdmaCongestionController> m_ccController
```

表示普通 C++ 对象的独占所有权。

理解这一点之后，ns-3 里的指针就不再混乱。

它们其实在回答同一个问题：

```text
这个对象属于哪套生命周期体系？
谁负责让它活着？
谁负责让它销毁？
```

`Ptr<T>` 是 ns-3 给出的答案。
