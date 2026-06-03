---
title: "彻底理解 ns-3 对象系统：Object、TypeId 和 Attribute"
date: 2026-06-02 17:45:00 +0800
permalink: /posts/ns3-object-typeid-attribute/
categories: [网络, ns-3]
tags: [ns3, object, typeid, attribute, object-factory, rdma, cpp]
description: "从 ns-3 的 Object 基类讲起，理解 TypeId、GetTypeId、Attribute、Accessor、Checker、ObjectFactory，以及它们在 RDMA 模块中的作用。"
---

<!-- series-nav -->
> **系列位置**：ns-3 源码阅读，第 02 篇 / 共 4 篇
> **总目录**：[学习路线](/roadmap/)
> **上一篇**：[彻底理解 ns-3 的 Ptr：从引用计数到 RDMA 对象生命周期](/posts/ns3-ptr-reference-count/)
> **下一篇**：[彻底理解 ns-3 事件系统：Simulator、EventId 和 RDMA 定时器](/posts/ns3-simulator-eventid-rdma-timers/)


前面几篇文章已经讲了：

```text
C++ 模板
C++ 智能指针
ns-3 的 Ptr<T>
```

现在可以继续往 ns-3 内核里走一步。

读 ns-3 代码时，除了 `Ptr<T>`，还会经常看到这些东西：

```cpp
class RdmaHw : public Object

static TypeId GetTypeId(void);

TypeId("ns3::RdmaHw")
    .SetParent<Object>()
    .AddAttribute(...)

CreateObject<RdmaQueuePair>(...)

ObjectFactory
```

这就是 ns-3 的对象系统。

这篇文章专门讲：

```text
Object 是什么？
TypeId 是什么？
GetTypeId() 为什么几乎每个 Object 子类都有？
Attribute 是什么？
MakeUintegerAccessor / MakeBooleanChecker 这些东西在干嘛？
ObjectFactory 为什么能根据 TypeId 创建对象？
这些东西和 RDMA 代码有什么关系？
```

先说结论：

> `Object` 让一个 C++ 类进入 ns-3 对象系统。
>
> `TypeId` 描述这个类是谁、继承谁、有哪些属性、能不能被工厂创建。
>
> `Attribute` 让成员变量可以通过 ns-3 配置系统统一设置和读取。

如果说 `Ptr<T>` 解决的是：

```text
对象怎么活着，什么时候释放？
```

那么 `Object / TypeId / Attribute` 解决的是：

```text
这个对象在 ns-3 里叫什么？
它属于哪个类型体系？
它有哪些可配置参数？
它能不能被统一创建、配置、查找和追踪？
```

本文涉及的源码主要来自我当前使用的 ns-3.19 工作区：

```text
src/core/model/object.h
src/core/model/object.cc
src/core/model/object-base.h
src/core/model/type-id.h
src/core/model/type-id.cc
src/core/model/attribute.h
src/core/model/object-factory.h
src/core/model/object-factory.cc
src/point-to-point/model/rdma-hw.h
src/point-to-point/model/rdma-hw.cc
src/point-to-point/model/rdma-queue-pair.h
src/point-to-point/model/rdma-queue-pair.cc
src/point-to-point/model/qbb-net-device.cc
```

文中有些代码是源码摘录，有些是为了讲清楚机制而写的简化版。涉及源码时会标出来源。

---

## 1. 为什么需要 ns-3 对象系统

普通 C++ 里，我们可以这样定义一个类：

```cpp
class Dog {
public:
    void Speak();
};
```

这只是一个普通 C++ 类。

它当然能创建对象，也能调用成员函数。

但 ns-3 作为仿真器，需要的东西更多。

它希望很多模型对象都能支持：

```text
引用计数生命周期管理
统一的类型名字
运行时查找类型
统一配置参数
从配置文件或 helper 设置属性
对象工厂动态创建对象
TraceSource 追踪事件
对象聚合
Dispose / DoDispose 清理引用关系
```

如果每个模块都自己写一套，代码会非常乱。

所以 ns-3 提供了一个统一基类：

```cpp
ns3::Object
```

当一个类继承 `Object`，它就进入了 ns-3 的对象系统。

比如你的 RDMA 代码里：

代码来源：

```text
src/point-to-point/model/rdma-hw.h
src/point-to-point/model/rdma-queue-pair.h
```

```cpp
class RdmaHw : public Object {
    ...
};

class RdmaQueuePair : public Object {
    ...
};

class RdmaRxQueuePair : public Object {
    ...
};
```

这意味着它们不只是普通 C++ 对象。

它们也是 ns-3 对象。

---

## 2. Object 提供了什么

`Object` 的源码注释说，它是提供 memory management 和 object aggregation 的基类。

代码来源：

```text
src/core/model/object.h
```

```cpp
class Object : public SimpleRefCount<Object, ObjectBase, ObjectDeleter>
{
public:
    static TypeId GetTypeId(void);
    virtual TypeId GetInstanceTypeId(void) const;

    template <typename T>
    Ptr<T> GetObject(void) const;

    void Dispose(void);
    void AggregateObject(Ptr<Object> other);
    void Initialize(void);

protected:
    virtual void DoInitialize(void);
    virtual void DoDispose(void);
};
```

这段代码可以分成几块理解。

第一，`Object` 继承了引用计数：

```cpp
SimpleRefCount<Object, ObjectBase, ObjectDeleter>
```

所以 `Object` 子类可以被：

```cpp
Ptr<T>
```

管理。

第二，`Object` 接入了类型系统：

```cpp
GetTypeId()
GetInstanceTypeId()
```

第三，`Object` 支持对象聚合：

```cpp
AggregateObject()
GetObject<T>()
```

第四，`Object` 支持生命周期清理：

```cpp
Dispose()
DoDispose()
```

所以可以粗略理解：

```text
SimpleRefCount 只给引用计数。
ObjectBase 给 TypeId / Attribute 基础能力。
Object 在它们之上，形成 ns-3 仿真对象模型。
```

---

## 3. ObjectBase 是什么

`ObjectBase` 是 `Object` 的父系能力之一。

代码来源：

```text
src/core/model/object-base.h
```

```cpp
class ObjectBase
{
public:
    static TypeId GetTypeId(void);
    virtual TypeId GetInstanceTypeId(void) const = 0;

    void SetAttribute(std::string name, const AttributeValue &value);
    bool SetAttributeFailSafe(std::string name, const AttributeValue &value);

    void GetAttribute(std::string name, AttributeValue &value) const;
    bool GetAttributeFailSafe(std::string name, AttributeValue &attribute) const;

protected:
    void ConstructSelf(const AttributeConstructionList &attributes);
};
```

它负责的重点是：

```text
把一个对象实例和 TypeId / Attribute 系统连接起来。
```

比如：

```cpp
object->SetAttribute("Mtu", UintegerValue(1000));
```

这种能力不是普通 C++ 类天生有的。

它来自 ns-3 的 `ObjectBase` / `Object` 系统。

---

## 4. TypeId 是什么

`TypeId` 可以理解成：

```text
ns-3 里的类型身份证。
```

普通 C++ 类型有名字，比如：

```cpp
RdmaHw
RdmaQueuePair
QbbNetDevice
```

但这些名字主要是编译期概念。

ns-3 还需要在运行时知道：

```text
这个类型在 ns-3 里叫什么？
它的父类是谁？
它有哪些 Attribute？
它有没有默认构造函数？
它有哪些 TraceSource？
```

这些信息就记录在 `TypeId` 里。

代码来源：

```text
src/core/model/type-id.h
```

```cpp
class TypeId
{
public:
    explicit TypeId(const char *name);

    TypeId SetParent(TypeId tid);

    template <typename T>
    TypeId SetParent(void);

    template <typename T>
    TypeId AddConstructor(void);

    TypeId AddAttribute(std::string name,
                        std::string help,
                        const AttributeValue &initialValue,
                        Ptr<const AttributeAccessor> accessor,
                        Ptr<const AttributeChecker> checker);
};
```

所以一个 `TypeId` 里记录的不是对象数据本身。

它记录的是类型元信息。

可以这样理解：

```text
Object 是对象本身。
TypeId 是对象类型的说明书。
Attribute 是说明书里列出的可配置字段。
```

---

## 5. GetTypeId() 是什么

在 ns-3 里，`Object` 子类通常都有：

```cpp
static TypeId GetTypeId(void);
```

比如你的 `RdmaQueuePair`：

代码来源：

```text
src/point-to-point/model/rdma-queue-pair.cc
```

```cpp
TypeId RdmaQueuePair::GetTypeId(void) {
    static TypeId tid = TypeId("ns3::RdmaQueuePair").SetParent<Object>();
    return tid;
}
```

这段代码非常短，但很重要。

它的意思是：

```text
RdmaQueuePair 在 ns-3 类型系统里的名字是 ns3::RdmaQueuePair。
它的父类是 Object。
```

这里用了：

```cpp
static TypeId tid
```

表示这个 `TypeId` 只需要创建一次。

后面每次调用 `GetTypeId()`，都返回同一个类型信息对象。

所以：

```cpp
GetTypeId()
```

不是在创建一个新的 `RdmaQueuePair`。

它是在返回：

```text
RdmaQueuePair 这个类型的元信息。
```

---

## 6. 一个最小 Object 子类

如果写一个最小的 ns-3 `Object` 子类，大概会是：

```cpp
class MyObject : public Object {
public:
    static TypeId GetTypeId(void);
};

TypeId MyObject::GetTypeId(void) {
    static TypeId tid = TypeId("ns3::MyObject")
        .SetParent<Object>();
    return tid;
}
```

这样它就进入了 ns-3 类型系统。

它可以被：

```cpp
Ptr<MyObject> obj = CreateObject<MyObject>();
```

创建和引用计数管理。

不过如果想让 `ObjectFactory` 默认创建它，还需要：

```cpp
.AddConstructor<MyObject>()
```

这个后面会讲。

---

## 7. RdmaHw 的 GetTypeId()

你的 `RdmaHw` 的 `GetTypeId()` 就更完整。

代码来源：

```text
src/point-to-point/model/rdma-hw.cc
```

```cpp
TypeId RdmaHw::GetTypeId(void) {
    static TypeId tid =
        TypeId("ns3::RdmaHw")
            .SetParent<Object>()
            .AddAttribute("MinRate", "Minimum rate of a throttled flow",
                          DataRateValue(DataRate("100Mb/s")),
                          MakeDataRateAccessor(&RdmaHw::m_minRate),
                          MakeDataRateChecker())
            .AddAttribute("Mtu", "Mtu.",
                          UintegerValue(1000),
                          MakeUintegerAccessor(&RdmaHw::m_mtu),
                          MakeUintegerChecker<uint32_t>())
            .AddAttribute("CcMode", "which mode of DCQCN is running",
                          UintegerValue(0),
                          MakeUintegerAccessor(&RdmaHw::m_cc_mode),
                          MakeUintegerChecker<uint32_t>());
    return tid;
}
```

这里我只截取了前几个 `AddAttribute`。

真实代码里还有很多 RDMA 参数。

这段代码表达的是：

```text
RdmaHw 是一个 ns-3 Object。
它在 ns-3 里的类型名是 ns3::RdmaHw。
它的父类是 Object。
它有 MinRate、Mtu、CcMode 等可配置属性。
```

所以 `GetTypeId()` 是一个类向 ns-3 系统“登记自己”的地方。

---

## 8. Attribute 是什么

`Attribute` 可以理解成：

```text
ns-3 对成员变量的统一配置接口。
```

比如 `RdmaHw` 里有一个成员变量：

```cpp
uint32_t m_mtu;
```

普通 C++ 里，你可能写 setter：

```cpp
void SetMtu(uint32_t mtu) {
    m_mtu = mtu;
}
```

但 ns-3 希望可以通过统一方式设置：

```cpp
Config::SetDefault("ns3::RdmaHw::Mtu", UintegerValue(1000));
```

或者 helper / factory 在创建对象时设置。

所以 `RdmaHw::GetTypeId()` 里注册了：

```cpp
.AddAttribute("Mtu", "Mtu.",
              UintegerValue(1000),
              MakeUintegerAccessor(&RdmaHw::m_mtu),
              MakeUintegerChecker<uint32_t>())
```

这表示：

```text
属性名叫 Mtu。
帮助说明是 "Mtu."。
默认值是 1000。
它对应成员变量 RdmaHw::m_mtu。
它的类型检查器是 uint32_t。
```

---

## 9. AddAttribute 拆开看

以 `Mtu` 为例：

代码来源：

```text
src/point-to-point/model/rdma-hw.cc
```

```cpp
.AddAttribute("Mtu", "Mtu.",
              UintegerValue(1000),
              MakeUintegerAccessor(&RdmaHw::m_mtu),
              MakeUintegerChecker<uint32_t>())
```

可以拆成五部分。

第一部分：

```cpp
"Mtu"
```

这是 Attribute 名字。

第二部分：

```cpp
"Mtu."
```

这是说明文本。

第三部分：

```cpp
UintegerValue(1000)
```

这是默认值。

因为 `m_mtu` 是整数，所以用 `UintegerValue` 包起来。

第四部分：

```cpp
MakeUintegerAccessor(&RdmaHw::m_mtu)
```

这是 accessor。

它告诉 ns-3：

```text
这个属性实际对应 RdmaHw 里的 m_mtu 成员变量。
```

第五部分：

```cpp
MakeUintegerChecker<uint32_t>()
```

这是 checker。

它告诉 ns-3：

```text
这个属性应该是 uint32_t 类型的无符号整数。
```

所以一条 `AddAttribute` 的结构可以理解成：

```text
名字
说明
默认值
怎么访问对象里的成员变量
怎么检查值是否合法
```

---

## 10. AttributeValue 是什么

ns-3 里的属性值不是直接用普通 C++ 类型传来传去。

它会用一层 `AttributeValue` 包装。

代码来源：

```text
src/core/model/attribute.h
```

```cpp
class AttributeValue : public SimpleRefCount<AttributeValue>
{
public:
    virtual Ptr<AttributeValue> Copy(void) const = 0;
    virtual std::string SerializeToString(Ptr<const AttributeChecker> checker) const = 0;
    virtual bool DeserializeFromString(std::string value,
                                       Ptr<const AttributeChecker> checker) = 0;
};
```

比如：

```cpp
UintegerValue(1000)
BooleanValue(false)
DoubleValue(4.0)
DataRateValue(DataRate("100Mb/s"))
TimeValue(MilliSeconds(4))
```

这些都是具体的 `AttributeValue` 风格对象。

它们把普通 C++ 值包装成 ns-3 Attribute 系统能统一处理的形式。

所以：

```cpp
uint32_t
```

对应：

```cpp
UintegerValue
```

```cpp
bool
```

对应：

```cpp
BooleanValue
```

```cpp
double
```

对应：

```cpp
DoubleValue
```

---

## 11. AttributeAccessor 是什么

`AttributeAccessor` 负责：

```text
怎么把 AttributeValue 写进对象成员变量？
怎么从对象成员变量读出 AttributeValue？
```

代码来源：

```text
src/core/model/attribute.h
```

```cpp
class AttributeAccessor : public SimpleRefCount<AttributeAccessor>
{
public:
    virtual bool Set(ObjectBase *object,
                     const AttributeValue &value) const = 0;

    virtual bool Get(const ObjectBase *object,
                     AttributeValue &attribute) const = 0;

    virtual bool HasGetter(void) const = 0;
    virtual bool HasSetter(void) const = 0;
};
```

你平时不会直接手写 `AttributeAccessor`。

通常用 helper 函数：

```cpp
MakeUintegerAccessor(&RdmaHw::m_mtu)
MakeBooleanAccessor(&RdmaHw::m_irn)
MakeDoubleAccessor(&RdmaHw::m_g)
MakeDataRateAccessor(&RdmaHw::m_minRate)
MakeTimeAccessor(&RdmaHw::m_waitAckTimeout)
```

这些 helper 会帮你生成合适的 accessor。

可以粗略理解：

```text
Accessor 负责找到成员变量。
Value 负责包装具体值。
Checker 负责检查类型和值是否合法。
```

---

## 12. AttributeChecker 是什么

`AttributeChecker` 负责检查属性值是否合法。

代码来源：

```text
src/core/model/attribute.h
```

```cpp
class AttributeChecker : public SimpleRefCount<AttributeChecker>
{
public:
    virtual bool Check(const AttributeValue &value) const = 0;
    virtual std::string GetValueTypeName(void) const = 0;
    virtual Ptr<AttributeValue> Create(void) const = 0;
};
```

比如：

```cpp
MakeUintegerChecker<uint32_t>()
```

表示：

```text
这个属性应该是 uint32_t 类型的无符号整数。
```

```cpp
MakeBooleanChecker()
```

表示：

```text
这个属性应该是 bool。
```

```cpp
MakeDataRateChecker()
```

表示：

```text
这个属性应该是 DataRate。
```

所以如果你给属性设置了错误类型，ns-3 就可以在配置阶段发现问题。

---

## 13. 用一张表理解 Attribute 三件套

以：

```cpp
.AddAttribute("CcMode", "which mode of DCQCN is running",
              UintegerValue(0),
              MakeUintegerAccessor(&RdmaHw::m_cc_mode),
              MakeUintegerChecker<uint32_t>())
```

为例：

| 部分 | 作用 |
| --- | --- |
| `"CcMode"` | 属性名 |
| `"which mode of DCQCN is running"` | 属性说明 |
| `UintegerValue(0)` | 默认值 |
| `MakeUintegerAccessor(&RdmaHw::m_cc_mode)` | 绑定到成员变量 |
| `MakeUintegerChecker<uint32_t>()` | 检查类型和值 |

这条注册完成后，ns-3 就知道：

```text
RdmaHw 有一个可配置属性 CcMode。
默认是 0。
它实际对应 m_cc_mode。
它应该是 uint32_t 类型。
```

于是你的仿真脚本、helper、配置系统都可以用统一方式配置它。

---

## 14. SetParent 是什么

`TypeId` 里经常有：

```cpp
.SetParent<Object>()
```

比如：

```cpp
TypeId("ns3::RdmaQueuePair").SetParent<Object>();
```

这表示：

```text
RdmaQueuePair 在 ns-3 类型系统里的父类是 Object。
```

注意，这不是 C++ 继承本身。

C++ 继承已经写在类定义里：

```cpp
class RdmaQueuePair : public Object
```

`.SetParent<Object>()` 是把这个继承关系登记到 ns-3 的 `TypeId` 系统里。

也就是说：

```text
C++ 编译器知道 RdmaQueuePair 继承 Object。
ns-3 TypeId 系统也需要知道这件事。
```

这样 ns-3 才能做运行时类型查询、文档生成、属性继承等事情。

---

## 15. AddConstructor 是什么

有些 `GetTypeId()` 里会写：

```cpp
.AddConstructor<QbbNetDevice>()
```

代码来源：

```text
src/point-to-point/model/qbb-net-device.cc
```

```cpp
TypeId QbbNetDevice::GetTypeId(void) {
    static TypeId tid =
        TypeId("ns3::QbbNetDevice")
            .SetParent<PointToPointNetDevice>()
            .AddConstructor<QbbNetDevice>()
            .AddAttribute(...);
    return tid;
}
```

`AddConstructor<T>()` 的作用是：

```text
告诉 ns-3：这个类型可以通过 TypeId / ObjectFactory 默认构造出来。
```

`TypeId` 里对应源码是：

代码来源：

```text
src/core/model/type-id.h
```

```cpp
template <typename T>
TypeId TypeId::AddConstructor(void)
{
    struct Maker {
        static ObjectBase* Create() {
            ObjectBase* base = new T();
            return base;
        }
    };
    Callback<ObjectBase*> cb = MakeCallback(&Maker::Create);
    DoAddConstructor(cb);
    return *this;
}
```

这段可以简化理解成：

```text
把 new T() 这个创建方法登记到 TypeId 里。
以后 ObjectFactory 可以通过 TypeId 调用它。
```

所以如果某个类没有默认构造函数，或者不希望被工厂默认创建，它可能不会写 `AddConstructor<T>()`。

比如你的 `RdmaQueuePair` 构造函数需要参数：

```cpp
RdmaQueuePair(uint16_t pg, Ipv4Address sip, Ipv4Address dip,
              uint16_t sport, uint16_t dport);
```

所以它的 `GetTypeId()` 里只是：

```cpp
TypeId("ns3::RdmaQueuePair").SetParent<Object>();
```

没有：

```cpp
.AddConstructor<RdmaQueuePair>()
```

这很合理。

---

## 16. CreateObject<T>() 和 TypeId 的关系

之前讲 `Ptr<T>` 时，我们看过：

```cpp
Ptr<RdmaQueuePair> qp =
    CreateObject<RdmaQueuePair>(pg, sip, dip, sport, dport);
```

`CreateObject<T>()` 会做几件事。

代码来源：

```text
src/core/model/object.h
```

```cpp
template <typename T>
Ptr<T> CompleteConstruct(T* p)
{
    p->SetTypeId(T::GetTypeId());
    p->Object::Construct(AttributeConstructionList());
    return Ptr<T>(p, false);
}

template <typename T>
Ptr<T> CreateObject(void)
{
    return CompleteConstruct(new T());
}
```

这说明 `CreateObject<T>()` 不只是：

```cpp
new T()
```

它还会：

```text
设置对象实例的 TypeId。
执行 Object 的构造流程。
让 Attribute 系统有机会初始化对象。
返回 Ptr<T>。
```

所以如果一个类继承了 `Object`，通常应该使用：

```cpp
CreateObject<T>()
```

而不是直接：

```cpp
new T()
```

---

## 17. ObjectFactory 是什么

`ObjectFactory` 是 ns-3 里根据 `TypeId` 创建对象的工具。

代码来源：

```text
src/core/model/object-factory.h
```

```cpp
class ObjectFactory
{
public:
    void SetTypeId(TypeId tid);
    void Set(std::string name, const AttributeValue &value);
    Ptr<Object> Create(void) const;

    template <typename T>
    Ptr<T> Create(void) const;
};
```

它可以保存：

```text
要创建什么类型
创建时要设置哪些 Attribute
```

源码里创建对象的核心逻辑是：

代码来源：

```text
src/core/model/object-factory.cc
```

```cpp
Ptr<Object> ObjectFactory::Create(void) const
{
    Callback<ObjectBase*> cb = m_tid.GetConstructor();
    ObjectBase* base = cb();
    Object* derived = dynamic_cast<Object*>(base);
    derived->SetTypeId(m_tid);
    derived->Construct(m_parameters);
    Ptr<Object> object = Ptr<Object>(derived, false);
    return object;
}
```

可以粗略理解：

```text
ObjectFactory 根据 TypeId 找到构造函数。
调用构造函数创建对象。
把提前设置好的 Attribute 应用到对象上。
返回 Ptr<Object>。
```

这就是为什么 `TypeId` 里要记录 constructor 和 attributes。

它们不是只为了好看。

它们真的会参与对象创建。

---

## 18. Attribute 什么时候生效

Attribute 通常在几个时机生效。

第一，默认值。

在 `GetTypeId()` 里注册：

```cpp
UintegerValue(1000)
```

这就是默认值。

第二，创建对象时设置。

比如 `ObjectFactory` 可以先：

```cpp
factory.Set("Mtu", UintegerValue(1500));
```

再创建对象。

第三，对象创建后设置。

因为 `ObjectBase` 提供：

```cpp
SetAttribute()
GetAttribute()
```

所以可以对已有对象设置属性。

第四，全局默认配置。

ns-3 的配置系统可以对某类对象的属性设置默认值。

这也是为什么属性名需要是字符串：

```text
ns3::RdmaHw::Mtu
ns3::RdmaHw::CcMode
```

这样脚本和配置系统可以通过名字找到它们。

---

## 19. 为什么 AddAttribute 适合仿真参数

RDMA 模块里有很多参数：

```text
Mtu
CcMode
NACKGenerationInterval
L2ChunkSize
L2AckInterval
FastReact
IrnEnable
IrnRtoLow
IrnRtoHigh
```

这些参数很适合注册成 Attribute。

原因是：

```text
它们是模型配置，不是临时局部状态。
它们经常需要从仿真脚本调整。
它们需要默认值。
它们需要类型检查。
它们最好能被文档和配置系统看到。
```

如果这些参数只靠普通 setter，使用者就必须知道具体对象、具体函数、具体调用时机。

而 Attribute 系统提供了更统一的入口。

所以：

```cpp
.AddAttribute("IrnEnable", "Enable IRN",
              BooleanValue(false),
              MakeBooleanAccessor(&RdmaHw::m_irn),
              MakeBooleanChecker())
```

比单纯写：

```cpp
void SetIrnEnable(bool enable);
```

更符合 ns-3 的模型配置风格。

---

## 20. TypeId 和文档

`TypeId` 不只是给程序运行用。

它也能帮助生成文档。

因为 `TypeId` 里有：

```text
类型名
父类
Attribute 名字
Attribute 说明
默认值
TraceSource 信息
```

所以 ns-3 可以把模型有哪些可配置属性展示出来。

这也是为什么 `AddAttribute` 里有 help 字符串：

```cpp
.AddAttribute("Mtu", "Mtu.", ...)
```

这个说明文字不只是注释。

它是 `TypeId` 元信息的一部分。

所以写 Attribute 时，help 字符串应该认真写。

尤其是模型参数很多时，说明文字会直接影响别人能不能用懂这个模型。

---

## 21. TraceSource 简单提一下

虽然这篇主要讲 Attribute，但 `TypeId` 里还有：

```cpp
AddTraceSource()
```

比如 `QbbNetDevice` 里有：

代码来源：

```text
src/point-to-point/model/qbb-net-device.cc
```

```cpp
.AddTraceSource("Enqueue", "Enqueue a packet in the queue.",
                MakeTraceSourceAccessor(&QbbNetDevice::m_traceEnqueue))
```

`TraceSource` 是 ns-3 的追踪系统入口。

它可以让外部代码连接 callback，观察某些事件。

比如：

```text
入队
出队
丢包
PFC
QP dequeue
```

它和 Attribute 一样，也是通过 `TypeId` 注册到 ns-3 类型系统里的。

可以简单理解：

```text
Attribute 注册可配置参数。
TraceSource 注册可观察事件。
```

---

## 22. AggregateObject 是什么

`Object` 还有一个很 ns-3 的功能：

```cpp
AggregateObject()
```

它允许把多个 `Object` 聚合在一起。

聚合之后，可以从一个对象上：

```cpp
GetObject<T>()
```

找到另一个被聚合的对象。

这和普通 C++ 成员变量不完全一样。

普通成员变量是：

```text
A 明确持有 B。
```

对象聚合更像：

```text
几个 Object 被放进同一个聚合体。
它们可以互相通过 GetObject<T>() 查找。
```

这对 ns-3 的 Node、Protocol、Device 等对象组合很有用。

这篇先不深入展开。

只需要知道：

```text
Object 不只是引用计数。
它还支持 ns-3 的对象聚合模型。
```

---

## 23. Dispose / DoDispose 再放回 Object 系统看

在 `Ptr<T>` 那篇里，我们讲过 `Dispose()`。

现在放到 `Object` 系统里更容易理解。

`Object` 之间可能有复杂引用关系：

```text
Node 引用 Device
Device 引用 Channel
Protocol 引用 Node
多个 Object 聚合在一起
```

如果只靠引用计数，循环引用可能让对象无法释放。

所以 `Object` 提供：

```cpp
Dispose()
DoDispose()
```

`Dispose()` 会触发对象以及聚合对象的 `DoDispose()`。

子类在 `DoDispose()` 里应该：

```text
取消事件
清空 Ptr 成员
断开和其他 Object 的引用
释放仿真资源
调用父类 DoDispose()
```

ns-3 注释里也说，子类真正的销毁清理逻辑应该放到 `DoDispose()`，析构函数最好保持简单。

所以如果你未来给 RDMA 某个 `Object` 子类加入很多 `Ptr` 成员或事件句柄，应该考虑是否需要重写：

```cpp
DoDispose()
```

---

## 24. 回到 RdmaQueuePair

`RdmaQueuePair` 的 `GetTypeId()` 很简单：

代码来源：

```text
src/point-to-point/model/rdma-queue-pair.cc
```

```cpp
TypeId RdmaQueuePair::GetTypeId(void) {
    static TypeId tid = TypeId("ns3::RdmaQueuePair").SetParent<Object>();
    return tid;
}
```

它没有注册 Attribute。

这说明现在它主要只是作为 ns-3 `Object` 被引用计数管理、拥有 TypeId。

它的具体配置更多是在创建后通过普通成员函数完成：

```cpp
qp->ConfigureSender(...);
qp->SetInitialRate(...);
```

也就是说，不是所有 `Object` 子类都必须注册一堆 Attribute。

是否注册 Attribute，要看这个类是否有需要通过 ns-3 配置系统暴露的模型参数。

---

## 25. 回到 RdmaHw

`RdmaHw` 的 `GetTypeId()` 很长。

这说明 `RdmaHw` 是一个模型参数很多的核心对象。

比如：

```text
MinRate
Mtu
CcMode
FastReact
IrnEnable
TimelyAlpha
DctcpRateAI
```

这些不是临时状态。

它们是仿真实验中经常需要调的参数。

所以它们适合注册为 Attribute。

于是 `RdmaHw` 既是：

```text
RDMA host-side 模块入口
```

也是：

```text
一组 RDMA 模型参数的配置入口
```

这就是为什么它的 `GetTypeId()` 特别重要。

---

## 26. Object、Ptr、TypeId、Attribute 的关系

现在可以把几篇文章串起来。

```cpp
class RdmaHw : public Object
```

说明：

```text
RdmaHw 是 ns-3 对象。
```

```cpp
Ptr<RdmaHw>
```

说明：

```text
RdmaHw 可以被 ns-3 引用计数智能指针管理。
```

```cpp
TypeId RdmaHw::GetTypeId()
```

说明：

```text
RdmaHw 向 ns-3 注册自己的类型信息。
```

```cpp
.AddAttribute("Mtu", ...)
```

说明：

```text
RdmaHw 暴露了一个可配置参数 Mtu。
```

```cpp
CreateObject<RdmaHw>()
```

说明：

```text
按 ns-3 Object 流程创建 RdmaHw，并返回 Ptr<RdmaHw>。
```

这些东西不是孤立的。

它们是一套系统。

---

## 27. 和普通 C++ 类对比

普通 C++ 类：

```cpp
class Dog {
public:
    int age;
};
```

它没有：

```text
TypeId
Attribute
Ptr 引用计数
ObjectFactory
Dispose
TraceSource
```

如果你想用它，就直接：

```cpp
Dog d;
Dog* p = new Dog();
std::unique_ptr<Dog> dog(new Dog());
```

但 ns-3 `Object` 子类：

```cpp
class RdmaHw : public Object
```

它进入了仿真器对象系统。

它可以：

```text
被 Ptr 管理
被 TypeId 描述
被 Attribute 配置
被 ObjectFactory 创建
参与聚合
参与 Dispose 清理
注册 TraceSource
```

所以写 ns-3 模块时，要区分：

```text
这是普通 C++ 工具类？
还是 ns-3 仿真对象？
```

不是所有类都应该继承 `Object`。

比如你的：

```cpp
IRdmaCongestionController
```

它更像普通 C++ 策略接口。

所以用：

```cpp
std::unique_ptr<IRdmaCongestionController>
```

就很合适。

而：

```cpp
RdmaHw
RdmaQueuePair
QbbNetDevice
```

这些是 ns-3 对象，就适合进入 `Object` / `Ptr` / `TypeId` 体系。

---

## 28. 常见误解一：GetTypeId 会创建对象

不会。

```cpp
RdmaHw::GetTypeId()
```

返回的是类型信息。

它不是：

```cpp
new RdmaHw()
```

真正创建对象的是：

```cpp
CreateObject<RdmaHw>()
ObjectFactory::Create()
```

`GetTypeId()` 更像在说：

```text
如果你想了解 RdmaHw 这个类型，它的信息在这里。
```

---

## 29. 常见误解二：AddAttribute 会立刻改成员变量

也不完全是。

在 `GetTypeId()` 里：

```cpp
.AddAttribute("Mtu", ..., UintegerValue(1000), ...)
```

主要是在注册属性信息：

```text
属性叫什么
默认值是什么
怎么访问成员变量
怎么检查类型
```

真正把值写进某个对象实例，发生在对象构造、配置系统设置、或者显式 `SetAttribute()` 时。

所以 `AddAttribute` 是类型层面的注册。

`SetAttribute` 才是对象实例层面的设置。

---

## 30. 常见误解三：继承 Object 就自动有所有配置

继承 `Object` 只是进入 ns-3 对象系统。

但如果你想让某个成员变量能被配置系统设置，仍然要在 `GetTypeId()` 里注册：

```cpp
.AddAttribute(...)
```

否则这个成员变量只是普通成员变量。

比如 `RdmaQueuePair` 继承了 `Object`，但它没有给 `m_rate`、`m_win` 等状态注册 Attribute。

所以这些状态不会自动出现在配置系统里。

---

## 31. 什么时候应该写 AddAttribute

适合写成 Attribute 的通常是：

```text
模型参数
默认配置
仿真实验需要调整的 knob
希望被 helper / config 系统统一设置的值
希望出现在文档里的参数
```

不太适合写成 Attribute 的通常是：

```text
运行时瞬时状态
每个 packet 临时计算出的值
内部缓存
只在某个函数里使用的局部变量
不希望外部用户配置的实现细节
```

比如：

```cpp
m_mtu
m_cc_mode
m_irn
m_tmly_alpha
```

适合作为 Attribute。

而：

```cpp
snd_nxt
snd_una
ReceiverNextExpectedSeq
```

这种运行时协议状态，就不一定适合作为 Attribute。

---

## 32. 总结

ns-3 的对象系统可以用一句话理解：

```text
Object 让一个 C++ 类成为 ns-3 仿真对象。
```

`Object` 提供：

```text
引用计数
TypeId
Attribute
ObjectFactory
AggregateObject
Dispose / DoDispose
TraceSource
```

`TypeId` 描述一个类型：

```text
名字
父类
构造函数
Attribute
TraceSource
```

`Attribute` 描述一个可配置参数：

```text
属性名
说明
默认值
Accessor
Checker
```

回到 RDMA 代码：

```cpp
class RdmaHw : public Object
```

表示 `RdmaHw` 是 ns-3 对象。

```cpp
TypeId("ns3::RdmaHw").SetParent<Object>()
```

表示它在 ns-3 类型系统里的身份。

```cpp
.AddAttribute("Mtu", ...)
```

表示它暴露了一个可配置参数。

```cpp
Ptr<RdmaHw>
```

表示它由 ns-3 引用计数智能指针管理。

理解这些之后，再看 ns-3 模块代码，很多原本看起来奇怪的固定写法就变得有意义了。

它们不是仪式感。

它们是在把一个普通 C++ 类接入 ns-3 的仿真对象体系。
