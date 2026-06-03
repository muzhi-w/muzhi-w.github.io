---
title: "C++ 系统补课 00：从零建立 C++ 知识地图"
date: 2026-06-03 16:55:00 +0800
permalink: /posts/cpp-systematic-learning-map/
categories: [C++, 系统补课]
tags: [cpp, learning-map, ns3, rdma, source-code-reading]
description: "从为什么 C++ 知识会显得不系统讲起，把变量、类型、指针、引用、函数、类、生命周期、继承、多态、模板、STL、编译链接和 ns-3/RDMA 源码阅读串成一张学习地图。"
---

<!-- series-nav -->
> **系列位置**：C++ 系统补课，第 00 篇 / 共 19 篇
> **总目录**：[学习路线](/roadmap/)
> **下一篇**：[01：程序、变量、类型和值](/posts/cpp-program-variable-type-value/)


这篇是一个新的开始。

前面的文章已经讲过不少和 ns-3/RDMA 相关的内容：

```text
C++ 智能指针
C++ 模板
ns-3 Ptr<T>
ns-3 Object / TypeId / Attribute
ns-3 Simulator / EventId
ns-3 Packet / Header / Tag / Buffer
```

这些文章都很有用。

但如果读者一边读 ns-3/RDMA 源码，一边补 C++，很容易遇到一个更根本的问题：

```text
不是完全不会 C++。
而是 C++ 知识不够系统。
```

这两句话区别很大。

“完全不会”意味着从来没接触过。

“不够系统”意味着：

```text
很多点见过。
有些代码也能照着改。
但是这些点之间没有连成一张网。
```

于是读源码时，就会出现这种感觉：

```text
单独看一个词，好像知道。
放到一行代码里，突然就糊了。
```

比如：

代码来源：

```text
src/network/model/packet.h
```

```cpp
class Packet : public SimpleRefCount<Packet> {
```

这一行里面同时有：

```text
class
public 继承
模板
CRTP 风格
引用计数
对象生命周期
```

再比如：

代码来源：

```text
src/network/model/packet.h
```

```cpp
void AddHeader(const Header& header);
```

这一行里面同时有：

```text
函数声明
void 返回值
const
引用
基类引用
多态
Header 抽象类
```

再比如：

代码来源：

```text
src/core/model/simulator.h
```

```cpp
Simulator::Schedule(delay, &QbbNetDevice::Receive, dev, packet);
```

这一行里面又同时有：

```text
静态函数
函数模板
成员函数指针
对象参数
Ptr<T>
事件系统
回调思想
```

所以真正的困难不是某一个知识点。

真正的困难是：

```text
C++ 的知识点经常叠在一起出现。
```

这就是为什么需要从 0 开始，建立一个系统补课系列。

## 1. 这个系列的目标

这个系列不是为了刷题。

也不是为了背完一本 C++ 语法书。

它的目标很明确：

```text
帮助读者稳定、清楚、有底气地读懂 ns-3/RDMA 源码。
```

所以这个系列会有一个特点：

```text
每一个 C++ 概念，最后都要回到源码。
```

比如讲指针，不会只讲：

```cpp
int* p = &x;
```

还要回到：

```cpp
Simulator::Schedule(..., this);
```

比如讲引用，不会只讲：

```cpp
int& r = x;
```

还要回到：

```cpp
void AddHeader(const Header& header);
uint32_t RemoveHeader(Header& header);
```

比如讲继承和多态，不会只讲：

```cpp
class Dog : public Animal
```

而是要回到：

```cpp
class Packet : public SimpleRefCount<Packet>
class Header : public Chunk
class IRdmaCongestionController
```

也就是说，这个系列不是“抽象地学 C++”。

它是：

```text
为了读懂真实工程源码而学 C++。
```

## 2. 为什么会觉得 C++ 不系统

原因大概有三个。

### 2.1 C++ 同时有太多层

很多语言可以先按一条线学：

```text
变量 -> 函数 -> 类 -> 标准库
```

C++ 也可以这么学，但源码里不会这么温柔地出现。

真实 C++ 代码经常长这样：

```cpp
template <typename T>
Ptr<T> CreateObject(void);
```

这看起来只是一行声明。

但它里面有：

```text
template
typename
函数模板
返回值类型
Ptr<T>
对象创建
生命周期管理
```

也就是说，C++ 的知识是分层的。

你可能已经碰到了第 8 层、第 9 层，但第 2 层、第 3 层还没完全稳。

这时就会感觉：

```text
好像懂一点。
但又好像哪里都不稳。
```

这不是你的问题。

这是 C++ 真实工程代码本身就会把很多层压在一起。

### 2.2 C++ 很多概念都和内存有关

C++ 里很多难点，本质都绕不开内存：

```text
指针
引用
对象生命周期
构造函数
析构函数
拷贝
移动
new/delete
RAII
智能指针
```

如果没有内存模型，很多东西只能死记硬背。

比如：

```cpp
void f(Packet p);
void f(Packet& p);
void f(const Packet& p);
void f(Packet* p);
void f(Ptr<Packet> p);
```

这几个函数参数看起来只是符号不同。

但它们背后完全不一样：

```text
是否拷贝对象？
是否允许修改对象？
是否可能为空？
是否延长生命周期？
所有权有没有变化？
```

所以这个系列会一直把 C++ 和内存放在一起讲。

不是为了制造压力。

而是因为：

```text
C++ 的很多语法，只有放到内存和生命周期里才真正讲得通。
```

### 2.3 源码阅读需要的是“组合能力”

单独学知识点时，可能感觉还行。

比如：

```text
知道什么是 class。
知道什么是指针。
知道什么是模板。
```

但是源码里不会分开考你。

源码会直接给你：

```cpp
Ptr<Packet> Copy(void) const;
```

这行里有：

```text
Ptr<Packet>        模板类型
Copy               成员函数
void               参数列表为空
const              const 成员函数
返回值             返回一个智能指针对象
```

所以源码阅读真正需要的是：

```text
把多个 C++ 概念同时放在脑子里。
```

这就是系统补课的意义。

不是只学更多点。

而是让这些点能互相连接。

## 3. 需要建立哪张地图

这套 C++ 地图分成 6 层。

```text
第 1 层：程序、类型和值
第 2 层：内存、指针和引用
第 3 层：函数和参数传递
第 4 层：类、对象和生命周期
第 5 层：继承、多态和抽象
第 6 层：工程能力和源码阅读
```

后面每一篇文章都在这张地图上。

下面先把每层讲清楚。

## 4. 第 1 层：程序、类型和值

这是最底层。

要先搞清楚：

```text
什么是程序？
什么是变量？
什么是类型？
什么是值？
什么是表达式？
什么是作用域？
```

比如：

```cpp
int x = 10;
double rate = 0.5;
bool enabled = true;
```

这一层看起来很简单。

但它是后面所有东西的地基。

因为 C++ 是强类型语言。

也就是说，一个东西不是随便存在的。

它一定有类型：

```cpp
int
uint32_t
double
bool
Time
DataRate
Ptr<Packet>
EventId
```

读源码时第一件事往往就是问：

```text
这个名字是什么类型？
```

比如：

```cpp
qp->m_rate
```

如果不知道它是 `DataRate`，就很难理解：

```cpp
qp->m_rate.GetBitRate()
```

再比如：

```cpp
Simulator::Now()
```

如果不知道它返回 `Time`，就很难理解：

```cpp
Simulator::Now().GetTimeStep()
```

所以第 1 层的目标是：

```text
看到一个变量，先能知道它是什么类型、代表什么值、活在哪个作用域里。
```

## 5. 第 2 层：内存、指针和引用

这是 C++ 最关键的一层。

要搞清楚：

```text
地址是什么？
指针是什么？
引用是什么？
nullptr 是什么？
解引用是什么？
对象在哪里？
什么时候会出现悬空指针？
```

比如：

```cpp
int x = 10;
int* p = &x;
int& r = x;
```

这三行背后是一整套内存模型。

以后读 ns-3 源码时，会不断遇到：

```cpp
T*
T&
const T&
Ptr<T>
Ptr<const T>
this
```

它们看起来相似，但含义不同。

比如：

```cpp
void AddHeader(const Header& header);
```

这里的 `const Header&` 表示：

```text
传进来的是某个 Header 对象的引用。
函数不会拷贝整个 Header。
函数也不应该修改这个 Header。
```

再比如：

```cpp
Simulator::Schedule(delay, &QbbNetDevice::Receive, this, packet);
```

这里的 `this` 是：

```text
当前对象的地址。
```

它是一个裸指针。

事件系统会保存这个指针，用来以后调用成员函数。

所以这一层学不稳，后面读 ns-3 会一直卡。

第 2 层的目标是：

```text
看到 *、&、this、Ptr<T> 时，脑子里能立刻知道它们和对象地址、生命周期的关系。
```

## 6. 第 3 层：函数和参数传递

函数是 C++ 程序的基本动作单位。

要搞清楚：

```text
函数声明
函数定义
返回值
参数
值传递
引用传递
指针传递
const 参数
函数重载
```

比如：

```cpp
uint32_t RemoveHeader(Header& header);
```

这行可以拆成：

```text
uint32_t   返回值类型
RemoveHeader 函数名
Header&    参数类型
header     参数名
```

`Header& header` 的意思是：

```text
调用者传进来的 Header 对象会被这个函数填充。
```

所以可以这样用：

```cpp
Ipv4Header h;
p->RemoveHeader(h);
```

调用结束后，`h` 里面就有从 packet 里解析出来的 IPv4 字段。

再比如：

```cpp
uint32_t PeekHeader(Header& header) const;
```

最后的 `const` 又表示：

```text
这个成员函数不会修改当前 Packet 对象的逻辑内容。
```

所以第 3 层的目标是：

```text
看到函数声明，就能读出它的输入、输出、是否修改参数、是否修改对象。
```

## 7. 第 4 层：类、对象和生命周期

C++ 的工程代码主要由类组成。

要搞清楚：

```text
class 和 struct
成员变量
成员函数
public/private/protected
构造函数
析构函数
初始化列表
this 指针
对象创建
对象销毁
```

比如：

```cpp
class Packet : public SimpleRefCount<Packet> {
public:
    Packet();
    Ptr<Packet> Copy(void) const;

private:
    Buffer m_buffer;
    ByteTagList m_byteTagList;
    PacketTagList m_packetTagList;
    PacketMetadata m_metadata;
};
```

这里就有很多层含义：

```text
Packet 是一个类。
Packet 继承 SimpleRefCount<Packet>。
Packet 有 public 构造函数。
Packet 有 private 成员变量。
Packet 对象内部保存 Buffer 和 TagList。
```

类不是语法装饰。

类是在定义：

```text
一种对象长什么样。
它拥有什么数据。
它能执行什么操作。
它什么时候创建。
它什么时候销毁。
```

ns-3 里到处是对象：

```text
Packet
Node
NetDevice
Channel
RdmaHw
RdmaQueuePair
QbbNetDevice
QbbChannel
```

所以第 4 层的目标是：

```text
看到一个 class，能知道这个对象负责什么，它有哪些状态，它的生命周期由谁管理。
```

## 8. 第 5 层：继承、多态和抽象

这一层是 C++ 源码阅读的难点。

要搞清楚：

```text
继承
基类
派生类
virtual
override
纯虚函数
接口类
虚析构函数
基类指针指向派生类对象
```

比如：

```cpp
class Header : public Chunk
```

这表示：

```text
Header 是一种 Chunk。
```

再比如所有具体 header 都可以继承 `Header`：

```text
Ipv4Header
UdpHeader
SeqTsHeader
qbbHeader
CnHeader
PauseHeader
```

于是 `Packet::AddHeader` 可以写成：

```cpp
void AddHeader(const Header& header);
```

它不需要知道传进来具体是 `Ipv4Header` 还是 `UdpHeader`。

只要这个对象是一个 `Header`，并且实现了：

```cpp
GetSerializedSize()
Serialize()
Deserialize()
Print()
```

就可以工作。

这就是多态。

RDMA 拥塞控制接口重构也是类似思想。

这种场景通常会希望有一个抽象接口：

```cpp
class IRdmaCongestionController {
public:
    virtual ~IRdmaCongestionController() {}
    virtual void OnCongestionFeedback(...) = 0;
};
```

然后不同算法实现它：

```text
DCQCN
HPCC
TIMELY
DCTCP
```

第 5 层的目标是：

```text
看到基类、虚函数、接口类时，能理解它们为什么存在，以及运行时到底调用哪个函数。
```

## 9. 第 6 层：工程能力和源码阅读

最后一层是工程层。

要搞清楚：

```text
.h 和 .cc
include
include guard
namespace
编译
链接
库
STL 容器
模板
回调
成员函数指针
智能指针
```

这层不是“语法细节”。

它决定你能不能真的读工程。

比如你看到：

```cpp
#include "ns3/packet.h"
```

要知道它是在引入声明。

看到：

```cpp
namespace ns3 {
```

要知道后面的类和函数都在 `ns3` 命名空间里。

看到：

```cpp
template <typename T>
```

要知道这是模板。

看到：

```cpp
std::vector<Ptr<QbbNetDevice> >
```

要知道这是标准库容器，里面存的是 ns-3 智能指针。

看到：

```cpp
Simulator::Schedule(delay, &Class::Function, object, arg);
```

要知道这是成员函数指针、模板、事件系统一起工作。

第 6 层的目标是：

```text
从单行代码阅读，进入文件级、模块级、调用链级阅读。
```

也就是从：

```text
这行代码什么意思？
```

进一步变成：

```text
这个类负责什么？
这个文件属于哪个模块？
这个对象由谁创建？
这个函数什么时候被调用？
这个 packet 从哪里来，又到哪里去？
```

## 10. 系统补课系列路线

后面的文章按这个顺序展开。

```text
00. 从零建立 C++ 知识地图
01. 程序、变量、类型和值
02. 内存、地址和指针
03. 引用、const 引用和函数参数
04. 函数、返回值和参数传递
05. const：从 const int 到 const 成员函数
06. class 和 struct：对象到底是什么
07. 构造函数、初始化列表和 this 指针
08. 析构函数、栈对象、堆对象和 RAII
09. 拷贝构造、赋值运算符和对象复制
10. 继承、多态、virtual 和 override
11. 纯虚函数、接口类和虚析构函数
12. 头文件、源文件、include 和 namespace
13. 编译、链接、库和构建系统
14. STL 入门：string、vector、map 和 iterator
15. 函数指针、成员函数指针和 lambda
16. 模板：template、typename 和泛型
17. 智能指针和资源管理
18. 回到 ns-3：Ptr<T>、Object、Simulator、Packet
```

注意，这个顺序不是唯一正确顺序。

但它适合这个系列的目标：

```text
从零开始，把 C++ 知识补成一条能读 ns-3/RDMA 源码的路线。
```

## 11. 每篇文章要怎么写

为了避免又变成散点，这个系列每篇都按同一个结构写。

```text
1. 这个概念解决什么问题？
2. 最简单的代码是什么？
3. 它在内存里大概发生了什么？
4. 容易混淆的点是什么？
5. 它在 ns-3/RDMA 源码里长什么样？
6. 读源码时应该怎么判断？
7. 小结和下一篇连接
```

比如第 02 篇讲指针，会这样写：

```text
指针为什么存在？
地址是什么？
T* 是什么？
*p 是什么？
&x 是什么？
nullptr 是什么？
this 是什么？
裸指针和 Ptr<T> 有什么区别？
Simulator::Schedule 里传 this 有什么风险？
```

第 03 篇讲引用，会这样写：

```text
引用为什么存在？
T& 和 T* 有什么不同？
const T& 为什么常见？
Header& header 为什么可以被 RemoveHeader 填充？
const Header& header 为什么适合 AddHeader？
```

第 10 篇讲多态，会这样写：

```text
为什么 AddHeader 可以接受 const Header&？
为什么传进去 Ipv4Header 也可以？
virtual 是怎么让 Serialize 调到派生类版本的？
为什么基类析构函数经常要 virtual？
```

这样每篇都不是孤立的。

它们会互相连接。

## 12. 哪些可以先不学太深

从 0 开始，不等于一上来什么都学到极致。

有些东西可以先知道概念，后面再深入。

比如：

```text
模板元编程
右值引用
完美转发
SFINAE
concepts
多线程内存模型
异常安全的高级规则
复杂 allocator
```

这些不是不重要。

只是对于当前目标：

```text
读懂 ns-3/RDMA 主线源码
```

它们不是第一优先级。

当前最优先的是：

```text
类型
内存
指针
引用
函数参数
class
构造和析构
继承和多态
头文件和编译链接
STL 基础
模板基础
智能指针基础
```

先把这些打稳，就能读很多真实源码。

## 13. 前面已经铺过哪些内容

虽然说从 0 开始，但并不是前面的文章作废。

相反，前面的文章会变成后面的“应用篇”。

前面已经讲过：

```text
C++ 智能指针
C++ 模板
ns-3 Ptr<T>
ns-3 Object / TypeId / Attribute
ns-3 Simulator / EventId
ns-3 Packet / Header / Tag / Buffer
```

这些内容可以先放在一边。

等系统补课写到对应位置时，再把它们接回来。

比如：

```text
讲完指针和生命周期，再回头看智能指针。
讲完 class 和继承，再回头看 Object / TypeId。
讲完函数指针和成员函数指针，再回头看 Simulator::Schedule。
讲完 Header 和多态，再回头看 Packet::AddHeader。
```

这样以前那些“有点懂但不稳”的文章，会变成新的知识网上的节点。

它们不会浪费。

## 14. 从零开始的正确心态

从 0 开始，最容易出现一个误区：

```text
是不是基础太差，才要从基础开始？
```

不是。

真正读工程源码时，基础不稳反而最费时间。

因为每次遇到一行复杂代码，都要临时补好几个概念。

这会让脑子一直处在“救火模式”。

系统补课的目的就是从救火模式切出来。

变成：

```text
知道这行代码用了哪些概念。
知道这些概念在地图上的位置。
知道哪里还没学完。
知道下一步补什么。
```

这会让学习变得安静很多。

不是一下子什么都会。

而是终于知道：

```text
现在在哪里。
接下来往哪里走。
为什么要走这一步。
```

## 15. 以后读源码的四个问题

在系统补课过程中，每次看到一行 C++ 源码，都可以问四个问题。

第一个问题：

```text
这里有哪些类型？
```

例如：

```cpp
Ptr<Packet> p;
```

这里的类型是：

```text
Ptr<Packet>
```

它不是裸 `Packet`，也不是 `Packet*`。

它是 ns-3 的引用计数智能指针。

第二个问题：

```text
这里有没有对象生命周期问题？
```

例如：

```cpp
Simulator::Schedule(delay, &Foo::Bar, this);
```

要问：

```text
this 指向的对象会不会在事件触发前被销毁？
```

第三个问题：

```text
这里有没有多态？
```

例如：

```cpp
void AddHeader(const Header& header);
```

要问：

```text
实际传进来的是哪个派生类 header？
Serialize 调用的是谁的实现？
```

第四个问题：

```text
这里属于哪个工程层次？
```

比如：

```cpp
packet->PeekHeader(ch);
```

要问：

```text
这是在解析 packet 吗？
这是在修改 packet 吗？
这是在接收路径还是发送路径？
```

这四个问题会贯穿整个系列。

## 16. 下一篇写什么

下一篇正式开始第 1 层。

标题可以是：

```text
C++ 系统补课 01：程序、变量、类型和值
```

这篇要讲：

```text
什么是程序
什么是变量
什么是类型
什么是值
什么是表达式
什么是作用域
为什么 C++ 里类型如此重要
uint32_t、Time、DataRate、Ptr<Packet> 这些类型该怎么看
```

这一篇不会难。

但它很重要。

因为从这篇开始，读者需要养成一个习惯：

```text
读任何 C++ 代码，先看类型。
```

类型看清楚了，很多代码就不会飘。

## 17. 总结

这篇没有讲具体语法细节。

它只是做了一件事：

```text
给 C++ 系统补课画一张地图。
```

这张地图分成 6 层：

```text
程序、类型和值
内存、指针和引用
函数和参数传递
类、对象和生命周期
继承、多态和抽象
工程能力和源码阅读
```

后面的每一篇都会沿着这张地图往前走。

最终目标不是“看起来学了很多 C++”。

最终目标是：

```text
能够系统地读懂 ns-3/RDMA 源码。
```

这一次从 0 开始，不是为了否定前面已经学过的东西。

而是为了把它们放回正确的位置。

等地图建起来，前面那些散点就会慢慢连成路。
