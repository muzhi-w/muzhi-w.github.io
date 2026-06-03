---
title: "彻底理解 ns-3 事件系统：Simulator、EventId 和 RDMA 定时器"
date: 2026-06-02 17:55:00 +0800
permalink: /posts/ns3-simulator-eventid-rdma-timers/
categories: [网络, ns-3]
tags: [ns3, simulator, eventid, event, timer, rdma, dcqcn]
description: "从 Simulator::Schedule、EventId、EventImpl 和 MakeEvent 讲起，理解 ns-3 离散事件仿真，以及 RDMA 重传定时器、DCQCN 周期事件和 QbbNetDevice 发送事件。"
---

<!-- series-nav -->
> **系列位置**：ns-3 源码阅读，第 03 篇 / 共 4 篇
> **总目录**：[学习路线](/roadmap/)
> **上一篇**：[彻底理解 ns-3 对象系统：Object、TypeId 和 Attribute](/posts/ns3-object-typeid-attribute/)
> **下一篇**：[彻底理解 ns-3 的 Packet：Header、Tag、Buffer 和 RDMA 报文生命周期](/posts/ns3-packet-header-tag-buffer-rdma/)


前面几篇文章已经讲了：

```text
C++ 模板
C++ 智能指针
ns-3 的 Ptr<T>
ns-3 的 Object / TypeId / Attribute
```

现在可以继续补 ns-3 里另一个非常核心的东西：

```text
事件系统
```

也就是这些代码背后的机制：

代码来源：

```text
src/point-to-point/model/rdma-hw.cc
```

```cpp
qp->m_retransmit = Simulator::Schedule(
    rto,
    &RdmaHw::HandleTimeout,
    this,
    qp,
    rto);
```

还有：

代码来源：

```text
src/point-to-point/model/rdma-dcqcn.cc
```

```cpp
qp->mlx.m_eventUpdateAlpha = Simulator::Schedule(
    MicroSeconds(config.alpha_resume_interval_us),
    &RdmaDcqcn::UpdateAlpha,
    qp,
    hw);
```

以及：

代码来源：

```text
src/point-to-point/model/qbb-net-device.cc
```

```cpp
m_nextSend = Simulator::Schedule(
    t - Simulator::Now(),
    &QbbNetDevice::DequeueAndTransmit,
    this);
```

这些代码看起来都像“定时器”。

但在 ns-3 里，它们不是操作系统意义上的真实定时器，也不是线程睡眠，更不是每隔一段真实时间醒一次。

它们本质上是：

```text
把一个函数调用，放进 ns-3 的仿真事件队列里。
等仿真时间走到那个点，Simulator 再把这个函数取出来执行。
```

这篇文章就彻底讲清楚：

```text
Simulator 是什么？
Simulator::Schedule 是什么？
EventId 是什么？
EventImpl 是什么？
Cancel 和 Remove 有什么区别？
ScheduleNow / ScheduleDestroy / ScheduleWithContext 是什么？
RDMA 代码里的重传定时器、DCQCN 定时器、发送定时器到底在干嘛？
```

## 1. 先建立一个最重要的概念：ns-3 是离散事件仿真

ns-3 的时间不是现实世界的时间。

比如你写：

```cpp
Simulator::Schedule(Seconds(10), &Foo::Bar, this);
```

这并不是让真实电脑等待 10 秒。

它的意思是：

```text
在当前仿真时间的 10 秒之后，执行 this->Bar()。
```

如果当前仿真时间是：

```text
Simulator::Now() == 3s
```

那么：

```cpp
Simulator::Schedule(Seconds(10), &Foo::Bar, this);
```

会把 `Foo::Bar` 这个事件放到：

```text
仿真时间 13s
```

的位置。

注意，这里的 `13s` 是仿真时间，不是墙上钟表的真实时间。

如果仿真规模很小，ns-3 可能一瞬间就跑完 100 秒的仿真时间。

如果仿真规模很大，ns-3 也可能用真实机器跑很久，才推进一点点仿真时间。

所以读 ns-3 代码时，要始终分清：

```text
真实时间：你的电脑实际花了多久运行程序
仿真时间：ns-3 模拟出来的网络世界里的时间
```

`Simulator::Now()` 返回的是仿真时间。

## 2. Simulator 像一个按时间排序的任务队列

可以把 `Simulator` 想象成一个时间队列。

假设当前仿真时间是 `0ns`，代码安排了这些事件：

```cpp
Simulator::Schedule(NanoSeconds(30), &A, ...);
Simulator::Schedule(NanoSeconds(10), &B, ...);
Simulator::Schedule(NanoSeconds(20), &C, ...);
```

队列里大概是这样：

```text
10ns  -> B
20ns  -> C
30ns  -> A
```

当你调用：

```cpp
Simulator::Run();
```

ns-3 会不断做这件事：

```text
1. 从事件队列里取出时间最早的事件
2. 把 Simulator::Now() 推进到这个事件的时间
3. 执行这个事件绑定的函数
4. 函数执行过程中可能继续 Schedule 新事件
5. 重复，直到没有事件，或者到达 Stop 时间
```

这就是离散事件仿真的核心。

它不是每一个纳秒都循环一遍。

它是直接从一个事件跳到下一个事件。

比如：

```text
0ns 有事件
10ns 有事件
1000000ns 有事件
```

中间没有事件的时间，ns-3 不需要逐个 tick 过去。

它会直接从 `10ns` 跳到 `1000000ns`。

这就是为什么离散事件仿真可以高效地模拟很长的网络过程。

## 3. ns-3 源码对 Simulator 的说明

代码来源：

```text
src/core/model/simulator.h
```

源码注释里说，ns-3 内部的仿真时间是一个 64 位整数，并且同一时间点的事件按照 FIFO 顺序执行。

简化理解就是：

```text
仿真时间内部用整数表示。
事件按照过期时间排序。
如果几个事件的过期时间一样，先插入的先执行。
```

源码里 `Run()` 的注释也很直接：

代码来源：

```text
src/core/model/simulator.h
```

```cpp
static void Run(void);
```

它会一直运行，直到：

```text
没有事件了；
或者用户调用了 Stop；
或者到达了 Stop 设置的仿真时间。
```

所以，ns-3 程序常见结构是：

```cpp
// 1. 创建节点、链路、应用、RDMA 对象

// 2. 安排初始事件

Simulator::Run();

Simulator::Destroy();
```

真正推动整个仿真的，就是 `Simulator::Run()`。

## 4. Simulator::Schedule 的标准语法

最常见的语法是：

```cpp
EventId id = Simulator::Schedule(
    delay,
    &ClassName::MemberFunction,
    object,
    arg1,
    arg2);
```

这里每一部分的含义是：

```text
delay                    多久之后执行，注意是相对当前仿真时间
&ClassName::MemberFunction  要执行的成员函数
object                   对哪个对象调用这个成员函数
arg1, arg2               传给成员函数的参数
返回值 EventId           这个事件的句柄，可以用来取消或检查状态
```

例如：

```cpp
Simulator::Schedule(
    MicroSeconds(10),
    &QbbNetDevice::Resume,
    this,
    qIndex);
```

意思是：

```text
10 微秒仿真时间之后，调用 this->Resume(qIndex)。
```

如果函数没有参数：

```cpp
Simulator::Schedule(
    NanoSeconds(100),
    &QbbNetDevice::DequeueAndTransmit,
    this);
```

意思是：

```text
100 纳秒仿真时间之后，调用 this->DequeueAndTransmit()。
```

如果是普通函数，不是成员函数，也可以调度：

```cpp
void PrintSomething(uint32_t x);

Simulator::Schedule(
    Seconds(1),
    &PrintSomething,
    10);
```

意思是：

```text
1 秒仿真时间之后，调用 PrintSomething(10)。
```

不过你现在 RDMA 代码里最常见的是成员函数版本。

## 5. Schedule 的第一个参数是相对时间，不是绝对时间

这是一个很容易踩坑的地方。

`Simulator::Schedule(delay, ...)` 里的 `delay` 是：

```text
从当前仿真时间开始，还要等多久。
```

不是：

```text
我要安排到仿真时间 delay 这个绝对时刻。
```

比如当前：

```cpp
Simulator::Now() == MicroSeconds(100)
```

如果写：

```cpp
Simulator::Schedule(MicroSeconds(30), &Foo::Bar, this);
```

事件会在：

```text
100us + 30us = 130us
```

执行。

如果你手里有一个绝对时间 `t`，想在 `t` 那一刻执行，就要写：

```cpp
Simulator::Schedule(t - Simulator::Now(), &Foo::Bar, this);
```

你的 `QbbNetDevice` 代码里就有这个模式。

代码来源：

```text
src/point-to-point/model/qbb-net-device.cc
```

```cpp
if (valid && m_nextSend.IsExpired() &&
    t < Simulator::GetMaximumSimulationTime() &&
    t > Simulator::Now()) {
    m_nextSend = Simulator::Schedule(
        t - Simulator::Now(),
        &QbbNetDevice::DequeueAndTransmit,
        this);
}
```

这里的 `t` 表示“某个队列下一次可发送的绝对仿真时间”。

但是 `Schedule` 要的是相对 delay。

所以要写：

```cpp
t - Simulator::Now()
```

也就是：

```text
距离那个绝对时间点，还剩多久。
```

## 6. EventId 是什么

`Simulator::Schedule` 会返回一个 `EventId`。

比如：

```cpp
EventId id = Simulator::Schedule(
    MicroSeconds(10),
    &Foo::Bar,
    this);
```

这个 `id` 不是事件本身。

它更像是：

```text
事件句柄
```

或者说：

```text
你之后还能找到这个事件的一张小票。
```

有了它，你可以：

```cpp
Simulator::Cancel(id);
```

也可以：

```cpp
id.Cancel();
```

还可以：

```cpp
if (id.IsRunning()) {
    id.Cancel();
}
```

代码来源：

```text
src/core/model/event-id.h
```

简化自源码：

```cpp
class EventId {
public:
    EventId();

    void Cancel(void);
    bool IsExpired(void) const;
    bool IsRunning(void) const;

private:
    Ptr<EventImpl> m_eventImpl;
    uint64_t m_ts;
    uint32_t m_context;
    uint32_t m_uid;
};
```

这里有几个关键信息。

第一，`EventId` 里面保存了一个：

```cpp
Ptr<EventImpl> m_eventImpl;
```

也就是说，`EventId` 里面指向了真正的事件实现对象。

第二，它还保存了：

```cpp
uint64_t m_ts;
uint32_t m_context;
uint32_t m_uid;
```

大致可以理解为：

```text
m_ts       事件发生的仿真时间戳
m_context 事件上下文，常用于 node id
m_uid      事件唯一编号
```

第三，`EventId` 的默认构造函数就是合法状态。

代码来源：

```text
src/core/model/event-id.cc
```

```cpp
EventId::EventId()
  : m_eventImpl(0),
    m_ts(0),
    m_context(0),
    m_uid(0)
{
}
```

所以即使一个 `EventId` 还没有接过 `Schedule` 的返回值，也可以安全地调用：

```cpp
id.Cancel();
id.IsRunning();
id.IsExpired();
```

这对写定时器非常方便。

比如你的 RDMA 状态里直接放了几个 `EventId` 字段。

代码来源：

```text
src/point-to-point/model/rdma-cc-state.h
```

```cpp
struct RdmaDcqcnQpState {
    DataRate m_targetRate;
    EventId m_eventUpdateAlpha;
    double m_alpha;
    bool m_alpha_cnp_arrived;
    bool m_first_cnp;
    EventId m_eventDecreaseRate;
    bool m_decrease_cnp_arrived;
    uint32_t m_rpTimeStage;
    EventId m_rpTimer;
};
```

即使这些事件还没被真正 schedule，调用 `Cancel` 也不会炸。

所以你代码里可以直接写：

代码来源：

```text
src/point-to-point/model/rdma-dcqcn.cc
```

```cpp
void RdmaDcqcn::CancelQpEvents(Ptr<RdmaQueuePair> qp) {
    Simulator::Cancel(qp->mlx.m_eventUpdateAlpha);
    Simulator::Cancel(qp->mlx.m_eventDecreaseRate);
    Simulator::Cancel(qp->mlx.m_rpTimer);
}
```

不用先判断这几个事件到底有没有被设置过。

## 7. IsRunning 和 IsExpired 的含义

`EventId::IsRunning()` 的源码非常短。

代码来源：

```text
src/core/model/event-id.cc
```

```cpp
bool
EventId::IsRunning(void) const
{
    return !IsExpired();
}
```

也就是说：

```text
IsRunning() == 事件还没过期
IsExpired() == 事件已经过期，或者已经不再有效地等待执行
```

这里的“过期”不是说对象生命周期过期。

它指的是：

```text
这个事件是否已经到达它的仿真时间点，或者已经不再处于等待执行的状态。
```

你的 `RdmaHw` 里有一个很典型的写法。

代码来源：

```text
src/point-to-point/model/rdma-hw.cc
```

```cpp
if (qp->m_retransmit.IsRunning()) {
    qp->m_retransmit.Cancel();
}

qp->m_retransmit = Simulator::Schedule(
    rto,
    &RdmaHw::HandleTimeout,
    this,
    qp,
    rto);
```

这段代码的意思是：

```text
如果旧的重传定时器还在等，就先取消它；
然后重新安排一个新的重传定时器。
```

这就是标准的“重启定时器”模式。

## 8. EventImpl 是真正被执行的事件对象

`EventId` 是句柄。

那真正的事件是什么？

答案是：

```cpp
EventImpl
```

代码来源：

```text
src/core/model/event-impl.h
```

简化自源码：

```cpp
class EventImpl : public SimpleRefCount<EventImpl>
{
public:
    void Invoke(void);
    void Cancel(void);
    bool IsCancelled(void);

protected:
    virtual void Notify(void) = 0;

private:
    bool m_cancel;
};
```

这里又出现了前面文章讲过的东西：

```cpp
SimpleRefCount<EventImpl>
```

说明事件对象本身也是引用计数管理的。

`Invoke()` 是仿真器执行事件时调用的函数。

代码来源：

```text
src/core/model/event-impl.cc
```

```cpp
void
EventImpl::Invoke(void)
{
    if (!m_cancel) {
        Notify();
    }
}
```

这段非常关键。

它说明：

```text
事件到时间点之后，Simulator 会调用 EventImpl::Invoke()。
Invoke() 会先检查这个事件有没有被取消。
如果没有取消，就调用 Notify()。
如果已经取消，就什么都不做。
```

所以 `Cancel` 的本质就是：

```text
把 EventImpl 里的 m_cancel 标志设置成 true。
```

代码来源：

```text
src/core/model/event-impl.cc
```

```cpp
void
EventImpl::Cancel(void)
{
    m_cancel = true;
}
```

这也解释了为什么 `Cancel` 很快。

它通常不是把事件从时间队列里挖出来，而是给事件打一个取消标记。

等这个事件原本的时间到了，仿真器发现它被取消了，就不执行它绑定的函数。

## 9. MakeEvent：把函数、对象、参数包装成 EventImpl

现在还有一个问题：

```cpp
Simulator::Schedule(
    MicroSeconds(10),
    &QbbNetDevice::Resume,
    this,
    qIndex);
```

这行代码里明明传的是：

```text
时间
成员函数指针
对象
参数
```

为什么最后会变成 `EventImpl` 呢？

关键在：

```cpp
MakeEvent(...)
```

代码来源：

```text
src/core/model/simulator.h
```

简化自源码：

```cpp
template <typename MEM, typename OBJ, typename T1>
EventId
Simulator::Schedule(Time const &time, MEM mem_ptr, OBJ obj, T1 a1)
{
    return DoSchedule(time, MakeEvent(mem_ptr, obj, a1));
}
```

也就是说，`Schedule` 做了两件事：

```text
1. MakeEvent(mem_ptr, obj, a1)：把函数调用包装成 EventImpl
2. DoSchedule(time, event)：把这个 EventImpl 放进仿真事件队列
```

`MakeEvent` 的源码很有意思。

代码来源：

```text
src/core/model/make-event.h
```

简化自源码：

```cpp
template <typename MEM, typename OBJ, typename T1>
EventImpl*
MakeEvent(MEM mem_ptr, OBJ obj, T1 a1)
{
    class EventMemberImpl1 : public EventImpl
    {
    public:
        EventMemberImpl1(OBJ obj, MEM function, T1 a1)
          : m_obj(obj),
            m_function(function),
            m_a1(a1)
        {
        }

    private:
        virtual void Notify(void)
        {
            (EventMemberImplObjTraits<OBJ>::GetReference(m_obj).*m_function)(m_a1);
        }

        OBJ m_obj;
        MEM m_function;
        typename TypeTraits<T1>::ReferencedType m_a1;
    };

    return new EventMemberImpl1(obj, mem_ptr, a1);
}
```

这段代码很值得慢慢看。

它做的事情是：

```text
创建一个 EventMemberImpl1 对象。
这个对象继承 EventImpl。
它内部保存：
    m_obj       要调用哪个对象
    m_function 要调用哪个成员函数
    m_a1        调用时传入的参数

等事件过期时，Notify() 被调用。
Notify() 里面真正执行：
    m_obj->m_function(m_a1)
```

所以：

```cpp
Simulator::Schedule(
    MicroSeconds(10),
    &QbbNetDevice::Resume,
    this,
    qIndex);
```

最后大概会被包装成：

```text
一个 EventImpl 子类对象
里面存着：
    obj      = this
    function = &QbbNetDevice::Resume
    a1       = qIndex

10us 仿真时间之后，调用：
    this->Resume(qIndex)
```

这就是 `Schedule` 的本质。

## 10. 为什么 Schedule 可以接受 this，也可以接受 Ptr<T>

`MakeEvent` 调用成员函数时用了这一句：

代码来源：

```text
src/core/model/make-event.h
```

```cpp
(EventMemberImplObjTraits<OBJ>::GetReference(m_obj).*m_function)(m_a1);
```

这里的 `OBJ` 可能是：

```text
裸指针，例如 QbbNetDevice*
ns-3 智能指针，例如 Ptr<QbbNetDevice>
```

如果 `OBJ` 是裸指针，`make-event.h` 里有这个特化：

代码来源：

```text
src/core/model/make-event.h
```

```cpp
template <typename T>
struct EventMemberImplObjTraits<T *>
{
    static T &GetReference(T *p)
    {
        return *p;
    }
};
```

它把 `T*` 解引用成 `T&`，于是可以调用成员函数。

如果 `OBJ` 是 `Ptr<T>`，`ptr.h` 里又有另一个特化：

代码来源：

```text
src/core/model/ptr.h
```

```cpp
template <typename T>
struct EventMemberImplObjTraits<Ptr<T> > {
    static T& GetReference(Ptr<T> p) { return *PeekPointer(p); }
};
```

这就是为什么下面两种写法都可以：

```cpp
Simulator::Schedule(delay, &Foo::Bar, this);
```

也可以：

```cpp
Ptr<Foo> foo = CreateObject<Foo>();
Simulator::Schedule(delay, &Foo::Bar, foo);
```

差别在生命周期。

如果传的是 `this`：

```text
事件里保存的是裸指针。
事件不会增加这个对象的引用计数。
你必须保证事件执行前，这个对象还活着。
如果对象提前销毁，又没有取消事件，就可能出问题。
```

如果传的是 `Ptr<T>`：

```text
事件里保存的是 Ptr<T>。
事件对象会持有一份 Ptr<T>。
这通常会让对象至少活到事件对象释放。
```

这点在 ns-3 里非常重要。

例如：

代码来源：

```text
src/point-to-point/model/qbb-channel.cc
```

```cpp
Simulator::ScheduleWithContext(
    m_link[wire].m_dst->GetNode()->GetId(),
    txTime + m_delay,
    &QbbNetDevice::Receive,
    m_link[wire].m_dst,
    p);
```

这里 `m_link[wire].m_dst` 是接收端设备指针。

如果它是 `Ptr<QbbNetDevice>`，事件对象会保存一份 `Ptr`。

而 `p` 是 `Ptr<Packet>`，也会作为参数被保存进事件对象里。

所以这个接收事件会携带：

```text
接收端设备
Packet
```

等传播延迟和发送时间过去之后，再调用：

```cpp
dst->Receive(p);
```

## 11. Cancel 和 Remove 的区别

ns-3 里取消事件有两个常见方法：

```cpp
Simulator::Cancel(id);
Simulator::Remove(id);
```

它们的可见效果很像：

```text
都让这个事件最终不会执行绑定的函数。
```

但内部机制不同。

### 11.1 Cancel：打取消标记

代码来源：

```text
src/core/model/simulator.h
```

源码注释说，`Cancel` 会设置事件的 cancel bit，并且复杂度是 `O(1)`。

结合 `EventImpl::Invoke()` 可以理解为：

```text
Cancel 不一定把事件从队列里删除。
Cancel 只是告诉这个事件：即使时间到了，也不要调用 Notify()。
```

所以：

```cpp
Simulator::Cancel(id);
```

通常可以理解成：

```text
这张定时器还在队列里等到原本的时间点，
但是等时间到了以后，它发现自己被取消了，
于是不会执行真正的回调函数。
```

### 11.2 Remove：真的从队列中移除

`Remove` 的目标是直接把事件从调度队列里拿掉。

源码注释里也说，`Remove` 和 `Cancel` 可见效果类似，但复杂度更高。

原因也直观：

```text
Cancel 只是改一个标志位。
Remove 要在事件队列的数据结构里找到这个事件，并把它删掉。
```

所以在很多 ns-3 代码里，更常见的是：

```cpp
Simulator::Cancel(id);
```

尤其是定时器重启场景：

```cpp
if (timer.IsRunning()) {
    timer.Cancel();
}
timer = Simulator::Schedule(delay, &Foo::Timeout, this);
```

### 11.3 Cancel 的一个隐藏影响：Ptr 参数可能被多保活一段时间

这一点对理解对象生命周期很重要。

因为 `Cancel` 通常只是打标记，事件对象可能仍然留在事件队列里，直到原本的仿真时间点才被处理掉。

如果这个事件对象内部保存了 `Ptr<T>` 参数，那么这个 `Ptr<T>` 也会继续存在一段时间。

例如：

```cpp
qp->m_retransmit = Simulator::Schedule(
    rto,
    &RdmaHw::HandleTimeout,
    this,
    qp,
    rto);
```

这里的 `qp` 是 `Ptr<RdmaQueuePair>`。

事件对象会保存一份 `qp`。

如果后来：

```cpp
qp->m_retransmit.Cancel();
```

这个事件不会再执行 `HandleTimeout`。

但是如果底层只是取消而不是移除，那么事件对象可能还在队列里等到原定时间，里面保存的 `Ptr<RdmaQueuePair>` 也可能让 QP 对象多活一段仿真时间。

这通常不是 bug。

但是如果你在排查对象迟迟不析构，或者内存占用峰值，就要知道这个机制。

## 12. ScheduleNow、ScheduleDestroy、ScheduleWithContext

除了普通的 `Schedule`，ns-3 还有几个特殊版本。

### 12.1 ScheduleNow

```cpp
Simulator::ScheduleNow(&Foo::Bar, this);
```

意思是：

```text
把事件安排在当前仿真时间执行。
```

但它不是普通 C++ 的立即函数调用。

也就是说：

```cpp
Foo::Bar();
```

和：

```cpp
Simulator::ScheduleNow(&Foo::Bar, this);
```

不是一回事。

前者是现在立刻执行。

后者是：

```text
把一个事件插入仿真器队列，时间戳是当前仿真时间。
等仿真器继续调度事件时再执行。
```

这在你想打断当前调用栈，或者希望某个动作通过事件系统统一执行时很有用。

### 12.2 ScheduleDestroy

```cpp
Simulator::ScheduleDestroy(&Foo::Cleanup, this);
```

意思是：

```text
在 Simulator::Destroy() 阶段执行清理事件。
```

ns-3 里有些全局列表会这么用。

代码来源：

```text
src/network/model/node-list.cc
src/network/model/channel-list.cc
```

它们会在销毁阶段安排删除全局对象。

要注意：

```text
ScheduleDestroy 安排的事件不能像普通事件一样 Cancel / Remove / IsExpired。
```

这个限制在 `simulator.h` 的注释里写得很明确。

### 12.3 ScheduleWithContext

```cpp
Simulator::ScheduleWithContext(
    nodeId,
    delay,
    &Foo::Bar,
    object,
    arg);
```

它比 `Schedule` 多了一个：

```cpp
context
```

在 ns-3 网络仿真里，这个 context 经常用来表示：

```text
当前事件属于哪个 Node
```

比如链路把包送到对端设备时：

代码来源：

```text
src/point-to-point/model/qbb-channel.cc
```

```cpp
Simulator::ScheduleWithContext(
    m_link[wire].m_dst->GetNode()->GetId(),
    txTime + m_delay,
    &QbbNetDevice::Receive,
    m_link[wire].m_dst,
    p);
```

这里的含义是：

```text
经过发送时间 txTime 和传播延迟 m_delay 之后，
在接收端 node 的上下文里，
调用接收端网卡的 Receive(p)。
```

这样日志、trace、上下文信息就能和正确的节点关联起来。

## 13. RDMA 重传定时器：m_retransmit

现在看你的 RDMA 代码。

代码来源：

```text
src/point-to-point/model/rdma-queue-pair.h
```

```cpp
// every Send queue is required to implement a Transport Timer
// to time outstanding requests.
EventId m_retransmit;
```

这个 `m_retransmit` 就是 QP 的重传定时器句柄。

真正重启定时器的逻辑在：

代码来源：

```text
src/point-to-point/model/rdma-hw.cc
```

```cpp
void RdmaHw::RestartRetransmitTimer(Ptr<RdmaQueuePair> qp, Time rto) {
    if (qp->m_retransmit.IsRunning()) {
        qp->m_retransmit.Cancel();
    }

    qp->m_retransmit = Simulator::Schedule(
        rto,
        &RdmaHw::HandleTimeout,
        this,
        qp,
        rto);
}
```

这段代码可以翻译成自然语言：

```text
我要为这个 QP 设置一个超时事件。
如果之前已经有一个超时事件还没触发，就先取消旧的。
然后安排一个新的事件：
    rto 仿真时间之后，调用 this->HandleTimeout(qp, rto)。
```

这就是典型的“重启定时器”。

为什么要先取消旧的？

因为如果不取消，可能会出现多个 timeout 事件同时挂在队列里。

比如：

```text
t = 100us 发送包，安排 timeout at 130us
t = 105us 又因为新的发送逻辑重启 timer，安排 timeout at 135us
```

如果不取消旧事件，那么 `130us` 和 `135us` 都可能触发 `HandleTimeout`。

这通常不是你想要的。

所以正确模式是：

```text
一个 QP 同一时间只保留一个有效的重传定时器。
```

### 13.1 包发送后为什么要重启重传定时器

代码来源：

```text
src/point-to-point/model/rdma-hw.cc
```

```cpp
void RdmaHw::PktSent(Ptr<RdmaQueuePair> qp, Ptr<Packet> pkt, Time interframeGap) {
    RdmaTxPostSendResult tx_result =
        RdmaTxScheduler::OnPacketSent(GetTxSchedulerConfig(), qp, pkt, interframeGap);

    if (tx_result.restart_retransmit_timer) {
        RestartRetransmitTimer(
            qp,
            RdmaTxReliability::GetRetransmitTimeout(GetTxReliabilityConfig(), qp));
    }
}
```

这段代码说明：

```text
每次发送一个 packet 后，可靠性逻辑会判断是否需要重启重传定时器。
如果需要，就根据当前 QP 状态计算 RTO，然后 Schedule 一个 HandleTimeout 事件。
```

所以重传定时器不是独立存在的。

它和发送状态、未确认数据、RTO 计算绑定在一起。

### 13.2 QP 完成时要取消重传事件

代码来源：

```text
src/point-to-point/model/rdma-hw.cc
```

```cpp
void RdmaHw::QpComplete(Ptr<RdmaQueuePair> qp) {
    if (m_ccController) {
        m_ccController->CleanupQp(qp, this);
    }

    if (qp->m_retransmit.IsRunning()) {
        qp->m_retransmit.Cancel();
    }

    m_qpCompleteCallback(qp);
    DeleteQueuePair(qp);
}
```

这里的含义很清楚：

```text
QP 已经完成了。
拥塞控制相关事件要清理。
重传定时器也要取消。
然后再走完成回调和删除 QP。
```

如果不取消 `m_retransmit`，可能出现：

```text
QP 已经完成或删除了，
但之前挂着的 timeout 事件后来又触发，
继续访问这个 QP。
```

这就是典型的事件生命周期 bug。

## 14. DCQCN 的定时器：周期更新和自我重调度

DCQCN 里面有三类事件：

代码来源：

```text
src/point-to-point/model/rdma-cc-state.h
```

```cpp
EventId m_eventUpdateAlpha;
EventId m_eventDecreaseRate;
EventId m_rpTimer;
```

它们分别对应：

```text
m_eventUpdateAlpha    周期性更新 alpha
m_eventDecreaseRate   周期性检查是否需要降速
m_rpTimer             rate increase timer，也就是恢复增速相关定时器
```

### 14.1 第一次收到 CNP 时启动 DCQCN 事件

代码来源：

```text
src/point-to-point/model/rdma-dcqcn.cc
```

```cpp
if (qp->mlx.m_first_cnp) {
    qp->mlx.m_alpha = 1;
    qp->mlx.m_alpha_cnp_arrived = false;

    RdmaDcqcn::ScheduleUpdateAlpha(qp, hw);
    RdmaDcqcn::ScheduleDecreaseRate(qp, hw, 1);

    DataRate firstRate(
        static_cast<uint64_t>(
            qp->m_rate.GetBitRate() * config.rate_on_first_cnp));

    qp->mlx.m_targetRate = firstRate;
    qp->m_rate = firstRate;

    qp->mlx.m_first_cnp = false;
}
```

这段代码说明：

```text
第一次收到 CNP 时，DCQCN 才真正启动自己的周期事件。
```

它启动了两个东西：

```text
alpha update
rate decrease check
```

也就是说，CNP 不是只让速率当场变化一次。

它还会启动后续一系列周期性的控制逻辑。

### 14.2 alpha update：周期事件的经典写法

代码来源：

```text
src/point-to-point/model/rdma-dcqcn.cc
```

```cpp
void RdmaDcqcn::ScheduleUpdateAlpha(Ptr<RdmaQueuePair> qp, Ptr<RdmaHw> hw) {
    RdmaDcqcnConfig config = hw->GetDcqcnConfig();

    qp->mlx.m_eventUpdateAlpha = Simulator::Schedule(
        MicroSeconds(config.alpha_resume_interval_us),
        &RdmaDcqcn::UpdateAlpha,
        qp,
        hw);
}
```

它安排的是：

```text
alpha_resume_interval_us 微秒之后，调用 RdmaDcqcn::UpdateAlpha(qp, hw)。
```

再看 `UpdateAlpha`：

代码来源：

```text
src/point-to-point/model/rdma-dcqcn.cc
```

```cpp
void RdmaDcqcn::UpdateAlpha(Ptr<RdmaQueuePair> qp, Ptr<RdmaHw> hw) {
    RdmaDcqcnConfig config = hw->GetDcqcnConfig();

    if (qp->mlx.m_alpha_cnp_arrived) {
        qp->mlx.m_alpha =
            (1 - config.shared.feedback_weight) * qp->mlx.m_alpha +
            config.shared.feedback_weight;
    } else {
        qp->mlx.m_alpha =
            (1 - config.shared.feedback_weight) * qp->mlx.m_alpha;
    }

    qp->mlx.m_alpha_cnp_arrived = false;

    RdmaDcqcn::ScheduleUpdateAlpha(qp, hw);
}
```

最后一行非常重要：

```cpp
RdmaDcqcn::ScheduleUpdateAlpha(qp, hw);
```

这叫：

```text
事件自我重调度
```

也就是说：

```text
UpdateAlpha 执行一次。
执行完以后，它自己再安排下一次 UpdateAlpha。
```

这就是 ns-3 里实现周期定时器的常见方式。

它不是：

```text
开一个 while 循环
开一个线程
sleep 一段时间
再执行
```

而是：

```text
每次事件触发时，自己 Schedule 下一次事件。
```

可以画成：

```text
t = 100us   UpdateAlpha()
            -> Schedule next UpdateAlpha at 100us + interval

t = 150us   UpdateAlpha()
            -> Schedule next UpdateAlpha at 150us + interval

t = 200us   UpdateAlpha()
            -> Schedule next UpdateAlpha at 200us + interval
```

只要不取消，它就会一直滚下去。

### 14.3 rate decrease：检查窗口内有没有 CNP

代码来源：

```text
src/point-to-point/model/rdma-dcqcn.cc
```

```cpp
void RdmaDcqcn::ScheduleDecreaseRate(
    Ptr<RdmaQueuePair> qp,
    Ptr<RdmaHw> hw,
    uint32_t delta)
{
    RdmaDcqcnConfig config = hw->GetDcqcnConfig();

    qp->mlx.m_eventDecreaseRate =
        Simulator::Schedule(
            MicroSeconds(config.rate_decrease_interval_us) + NanoSeconds(delta),
            &RdmaDcqcn::CheckRateDecrease,
            qp,
            hw);
}
```

这个定时器的作用是：

```text
每隔 rate_decrease_interval_us 检查一次：
这个时间窗口里有没有收到 CNP？
如果收到了，就执行降速逻辑。
```

`delta` 也值得注意。

第一次启动时：

```cpp
RdmaDcqcn::ScheduleDecreaseRate(qp, hw, 1);
```

这里传了 `1`，然后函数里加了：

```cpp
NanoSeconds(delta)
```

也就是把第一次 rate decrease check 偏移了 `1ns`。

为什么要偏移？

一个合理理解是：

```text
避免某些事件和 alpha update 精确落在同一个时间点；
让事件顺序更明确。
```

ns-3 对同一时间点事件按 FIFO 执行，但显式加 `1ns` 能让时间顺序更直观。

### 14.4 rpTimer：恢复增速的周期事件

代码来源：

```text
src/point-to-point/model/rdma-dcqcn.cc
```

```cpp
if (qp->mlx.m_decrease_cnp_arrived) {
    qp->mlx.m_rpTimeStage = 0;
    qp->mlx.m_decrease_cnp_arrived = false;

    Simulator::Cancel(qp->mlx.m_rpTimer);
    qp->mlx.m_rpTimer = Simulator::Schedule(
        MicroSeconds(config.rp_timer_us),
        &RdmaDcqcn::RateIncEventTimer,
        qp,
        hw);
}
```

这里的逻辑是：

```text
如果本窗口里收到了 CNP，说明发生拥塞反馈。
降速之后，要重新启动恢复增速的 rpTimer。
旧的 rpTimer 先取消。
新的 rpTimer 重新安排。
```

再看 `RateIncEventTimer`：

代码来源：

```text
src/point-to-point/model/rdma-dcqcn.cc
```

```cpp
void RdmaDcqcn::RateIncEventTimer(Ptr<RdmaQueuePair> qp, Ptr<RdmaHw> hw) {
    RdmaDcqcnConfig config = hw->GetDcqcnConfig();

    qp->mlx.m_rpTimer = Simulator::Schedule(
        MicroSeconds(config.rp_timer_us),
        &RdmaDcqcn::RateIncEventTimer,
        qp,
        hw);

    RdmaDcqcn::RateIncEvent(qp, hw);
    qp->mlx.m_rpTimeStage++;
}
```

这也是一个自我重调度周期事件。

它做三件事：

```text
1. 先安排下一次 RateIncEventTimer
2. 执行本次 RateIncEvent
3. 增加恢复阶段 m_rpTimeStage
```

所以 DCQCN 里的 `rpTimer` 不是一次性的“恢复事件”。

它是：

```text
周期性地触发恢复增速逻辑。
```

直到某个拥塞反馈再次取消并重启它，或者 QP 被清理。

### 14.5 QP 清理时取消 DCQCN 事件

代码来源：

```text
src/point-to-point/model/rdma-dcqcn.cc
```

```cpp
void RdmaDcqcn::CancelQpEvents(Ptr<RdmaQueuePair> qp) {
    Simulator::Cancel(qp->mlx.m_eventUpdateAlpha);
    Simulator::Cancel(qp->mlx.m_eventDecreaseRate);
    Simulator::Cancel(qp->mlx.m_rpTimer);
}
```

这段在概念上非常重要。

因为 DCQCN 的几个事件都是周期性的。

如果 QP 完成了，但是这些事件还在继续自我重调度，就会出现：

```text
已经结束的 QP 继续更新 alpha
已经结束的 QP 继续检查 rate decrease
已经结束的 QP 继续做 rate increase
```

所以 QP 生命周期结束时必须取消这些事件。

这也是为什么你的 `RdmaHw::QpComplete` 里先调用：

代码来源：

```text
src/point-to-point/model/rdma-hw.cc
```

```cpp
if (m_ccController) {
    m_ccController->CleanupQp(qp, this);
}
```

再取消重传事件。

拥塞控制器自己的定时器，应该由拥塞控制器自己清理。

RDMA 硬件层的重传定时器，由 RDMA 硬件层清理。

这个边界是合理的。

## 15. QbbNetDevice 的 m_nextSend：不要重复安排发送事件

`QbbNetDevice` 里还有一个很典型的事件：

代码来源：

```text
src/point-to-point/model/qbb-net-device.h
```

```cpp
EventId m_nextSend;  //< The next send event
```

它的作用是：

```text
记录下一次 DequeueAndTransmit 事件。
```

看这段：

代码来源：

```text
src/point-to-point/model/qbb-net-device.cc
```

```cpp
if (valid && m_nextSend.IsExpired() &&
    t < Simulator::GetMaximumSimulationTime() &&
    t > Simulator::Now()) {
    m_nextSend = Simulator::Schedule(
        t - Simulator::Now(),
        &QbbNetDevice::DequeueAndTransmit,
        this);
}
```

这里为什么要判断：

```cpp
m_nextSend.IsExpired()
```

因为它想表达：

```text
如果当前没有正在等待的 next send 事件，
才安排一个新的 DequeueAndTransmit。
```

否则可能会重复安排多个发送事件。

例如：

```text
t = 100us 发现下一次可发送时间是 110us，安排 DequeueAndTransmit
t = 101us 又检查一次，还是 110us，如果不判断，就又安排一个
t = 102us 再安排一个
```

到了 `110us`，可能会有多个 `DequeueAndTransmit` 连续执行。

这显然不合适。

所以 `m_nextSend` 的作用就是：

```text
保证同一时间只挂一个 next send 事件。
```

## 16. UpdateNextAvail：如果更早能发送，就替换旧事件

`QbbNetDevice` 里还有一个很漂亮的逻辑：

代码来源：

```text
src/point-to-point/model/qbb-net-device.cc
```

```cpp
void QbbNetDevice::UpdateNextAvail(Time t) {
    if (!m_nextSend.IsExpired() && t < m_nextSend.GetTs()) {
        Simulator::Cancel(m_nextSend);
        Time delta = t < Simulator::Now() ? Time(0) : t - Simulator::Now();
        m_nextSend = Simulator::Schedule(
            delta,
            &QbbNetDevice::DequeueAndTransmit,
            this);
    }
}
```

这段代码表达的是：

```text
当前已经有一个 next send 事件。
但是现在发现某个更早的时间 t 就可以发送。
那就取消旧事件，安排一个更早的新事件。
```

这里有两个细节。

第一个：

```cpp
t < m_nextSend.GetTs()
```

说明它只在“新时间更早”时替换旧事件。

第二个：

```cpp
Time delta = t < Simulator::Now() ? Time(0) : t - Simulator::Now();
```

如果 `t` 已经小于当前仿真时间，说明这个发送机会已经“应该发生了”。

那么就用：

```cpp
Time(0)
```

也就是安排在当前仿真时间执行。

如果 `t` 还在未来，就用：

```cpp
t - Simulator::Now()
```

转换成相对 delay。

这段代码把绝对时间、相对时间、事件替换三个概念都串起来了。

## 17. PFC resume timer：暂停多久之后恢复

PFC 里也有一个很典型的定时器：

代码来源：

```text
src/point-to-point/model/qbb-net-device.h
```

```cpp
EventId m_resumeEvt[qCnt];
```

当收到 PFC pause 时：

代码来源：

```text
src/point-to-point/model/qbb-net-device.cc
```

```cpp
if (ch.pfc.time > 0) {
    m_tracePfc(1);
    m_paused[qIndex] = true;

    Simulator::Cancel(m_resumeEvt[qIndex]);
    m_resumeEvt[qIndex] = Simulator::Schedule(
        MicroSeconds(ch.pfc.time),
        &QbbNetDevice::Resume,
        this,
        qIndex);
} else {
    m_tracePfc(0);
    Simulator::Cancel(m_resumeEvt[qIndex]);
    Resume(qIndex);
}
```

自然语言翻译：

```text
如果 pause time > 0：
    标记这个队列暂停
    取消旧的 resume 事件
    安排一个新的 resume 事件
    pause time 微秒之后恢复这个队列

如果 pause time == 0：
    取消旧的 resume 事件
    立刻恢复这个队列
```

为什么收到新的 PFC pause 要先取消旧的 resume？

因为新的 pause 可能延长暂停时间。

例如：

```text
t = 100us 收到 pause 50us，原本 150us 恢复
t = 120us 又收到 pause 50us，应该 170us 恢复
```

如果不取消旧的 resume，`150us` 的旧事件会提前恢复队列。

所以正确模式是：

```text
每次收到新的 pause，都取消旧 resume，再安排新 resume。
```

这和重传定时器的模式很像。

## 18. RDMA 事件系统里最常见的三种模式

你现在的 RDMA/ns-3 代码里，事件系统基本有三种模式。

### 18.1 一次性事件

比如包经过链路，到达对端：

代码来源：

```text
src/point-to-point/model/qbb-channel.cc
```

```cpp
Simulator::ScheduleWithContext(
    dstNodeId,
    txTime + delay,
    &QbbNetDevice::Receive,
    dst,
    packet);
```

这类事件执行一次就结束。

```text
包发送出去。
经过发送时间和传播延迟。
到达接收端。
调用 Receive。
```

### 18.2 可重启定时器

比如重传定时器、PFC resume 定时器：

```cpp
if (timer.IsRunning()) {
    timer.Cancel();
}

timer = Simulator::Schedule(delay, &Foo::Timeout, this, arg);
```

特点是：

```text
同一逻辑上只允许一个有效定时器。
新定时器出现时，旧定时器要取消。
```

### 18.3 周期性自我重调度事件

比如 DCQCN 的 alpha update、rpTimer：

```cpp
void Foo::PeriodicEvent(...) {
    // 做本次工作

    eventId = Simulator::Schedule(interval, &Foo::PeriodicEvent, ...);
}
```

特点是：

```text
事件函数执行完后，自己安排下一次。
```

这种模式要特别小心清理。

因为如果生命周期结束时不取消，它会一直继续调度。

## 19. 读 ns-3 定时器代码时的检查清单

以后看到一段 `Simulator::Schedule`，可以按这个顺序读。

第一，看时间参数：

```text
这个 delay 是相对时间吗？
如果代码里有 t - Simulator::Now()，说明 t 多半是绝对时间。
```

第二，看回调函数：

```text
它最终会调用哪个函数？
是成员函数，还是普通函数？
```

第三，看 object 参数：

```text
传的是 this 还是 Ptr<T>？
如果是 this，对象生命周期由谁保证？
如果是 Ptr<T>，事件会不会让对象多活一段时间？
```

第四，看返回的 EventId 保存在哪里：

```text
有没有保存 EventId？
如果没保存，以后就很难取消它。
```

第五，看有没有取消逻辑：

```text
对象结束时有没有 Cancel？
重启定时器前有没有 Cancel？
周期性事件有没有生命周期边界？
```

第六，看是不是会重复 schedule：

```text
有没有用 IsRunning / IsExpired 避免重复事件？
```

第七，看事件函数内部有没有自我重调度：

```text
如果函数最后又 Schedule 自己，那就是周期事件。
这种事件必须有清理出口。
```

## 20. 常见错误

### 错误 1：把 Schedule 的时间当成绝对时间

错误理解：

```cpp
Simulator::Schedule(MicroSeconds(100), &Foo::Bar, this);
```

以为它是在：

```text
仿真时间 100us
```

执行。

正确理解：

```text
当前仿真时间 + 100us
```

如果要安排到绝对时间 `t`，要写：

```cpp
Simulator::Schedule(t - Simulator::Now(), &Foo::Bar, this);
```

### 错误 2：忘记保存 EventId

如果写：

```cpp
Simulator::Schedule(delay, &Foo::Timeout, this);
```

但没有保存返回值。

那以后就很难：

```text
取消它
判断它是否还在运行
替换它
```

定时器类事件通常应该保存 `EventId`。

### 错误 3：周期事件没有取消出口

比如：

```cpp
void Foo::Tick() {
    DoSomething();
    m_tick = Simulator::Schedule(interval, &Foo::Tick, this);
}
```

这类事件必须在对象结束时：

```cpp
m_tick.Cancel();
```

否则它会继续调度自己。

DCQCN 的 `CancelQpEvents` 就是在处理这个问题。

### 错误 4：以为 Cancel 会立刻释放所有东西

`Cancel` 通常只是标记事件不执行。

它不一定马上释放事件对象里保存的参数。

如果事件保存了 `Ptr<T>`，这个 `Ptr<T>` 可能仍然存在到事件原本的时间点。

如果确实非常在意立刻从队列删除事件，可以考虑 `Remove`，但要知道它成本更高，而且不是所有事件都能 remove。

### 错误 5：用 this 调度事件，但对象提前销毁

例如：

```cpp
Simulator::Schedule(delay, &Foo::Bar, this);
```

事件里保存的是裸指针。

如果 `this` 对象在事件触发前被销毁，而事件没有取消，后面执行时就会访问悬空指针。

所以用 `this` 调度事件时要明确：

```text
谁保证 this 活到事件执行？
对象销毁前是否取消了事件？
```

### 错误 6：同一个逻辑定时器重复 schedule

比如每次收到包都：

```cpp
timer = Simulator::Schedule(delay, &Foo::Timeout, this);
```

但不取消旧事件。

这样会挂出一堆 timeout。

正确模式通常是：

```cpp
if (timer.IsRunning()) {
    timer.Cancel();
}

timer = Simulator::Schedule(delay, &Foo::Timeout, this);
```

## 21. 回到开头那句 RDMA 代码

现在重新看：

代码来源：

```text
src/point-to-point/model/rdma-hw.cc
```

```cpp
qp->m_retransmit = Simulator::Schedule(
    rto,
    &RdmaHw::HandleTimeout,
    this,
    qp,
    rto);
```

它就不神秘了。

这句话完整翻译是：

```text
创建一个事件。
这个事件会在当前仿真时间 + rto 之后触发。
触发时调用：
    this->HandleTimeout(qp, rto)

把这个事件的句柄保存到：
    qp->m_retransmit

以后可以通过 qp->m_retransmit 取消、检查、替换这个事件。
```

再看：

代码来源：

```text
src/point-to-point/model/rdma-dcqcn.cc
```

```cpp
qp->mlx.m_eventUpdateAlpha = Simulator::Schedule(
    MicroSeconds(config.alpha_resume_interval_us),
    &RdmaDcqcn::UpdateAlpha,
    qp,
    hw);
```

它的意思是：

```text
alpha_resume_interval_us 微秒后，
调用：
    RdmaDcqcn::UpdateAlpha(qp, hw)

并把事件句柄保存到：
    qp->mlx.m_eventUpdateAlpha
```

而且 `UpdateAlpha` 自己最后又会调用：

```cpp
RdmaDcqcn::ScheduleUpdateAlpha(qp, hw);
```

所以它变成了一个周期性事件。

再看：

代码来源：

```text
src/point-to-point/model/qbb-net-device.cc
```

```cpp
m_nextSend = Simulator::Schedule(
    t - Simulator::Now(),
    &QbbNetDevice::DequeueAndTransmit,
    this);
```

它的意思是：

```text
在绝对仿真时间 t 到来时，
执行：
    this->DequeueAndTransmit()

因为 Schedule 要的是相对时间，
所以传入：
    t - Simulator::Now()
```

## 22. 这一套和“智能指针”的关系

事件系统和前面几篇文章其实连在一起。

`EventId` 里面保存：

```cpp
Ptr<EventImpl> m_eventImpl;
```

`EventImpl` 继承：

```cpp
SimpleRefCount<EventImpl>
```

`MakeEvent` 会把函数参数保存进事件对象。

如果参数是：

```cpp
Ptr<RdmaQueuePair>
Ptr<RdmaHw>
Ptr<Packet>
```

那么事件对象内部就会保存这些 `Ptr`。

也就是说：

```text
ns-3 的事件系统不是孤立的。
它和 Ptr<T>、引用计数、对象生命周期紧紧绑在一起。
```

这也是为什么理解 ns-3 时，推荐顺序是：

```text
1. C++ 模板
2. C++ 智能指针
3. ns-3 Ptr<T>
4. ns-3 Object / TypeId / Attribute
5. ns-3 Simulator / EventId
```

到了这一步，很多以前看起来像魔法的代码就会慢慢变成普通工程逻辑。

## 23. 总结

这篇文章可以浓缩成几句话。

`Simulator` 是 ns-3 的仿真时间调度器。

`Simulator::Schedule(delay, func, obj, args...)` 的意思是：

```text
当前仿真时间 + delay 之后，调用 obj->func(args...)。
```

`EventId` 是这个事件的句柄，可以用来：

```text
Cancel
Remove
IsRunning
IsExpired
```

`EventImpl` 是真正被执行的事件对象。

`MakeEvent` 负责把：

```text
成员函数指针
对象
参数
```

包装成一个 `EventImpl`。

`Cancel` 通常是打取消标记，不一定马上从队列中删除事件。

RDMA 里的定时器本质上都是事件：

```text
m_retransmit          QP 重传超时事件
m_eventUpdateAlpha    DCQCN alpha 周期更新事件
m_eventDecreaseRate   DCQCN 降速检查事件
m_rpTimer             DCQCN 恢复增速周期事件
m_nextSend            下一次发送事件
m_resumeEvt           PFC 暂停后的恢复事件
```

看懂这些，RDMA 代码里的“定时器”就不再是黑盒。

它们只是 ns-3 事件队列里一张张写着时间、函数、对象和参数的小票。
