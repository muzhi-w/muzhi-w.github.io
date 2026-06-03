---
title: "C++ 系统补课 01：程序、变量、类型和值"
date: 2026-06-03 17:00:00 +0800
permalink: /posts/cpp-program-variable-type-value/
categories: [C++, 系统补课]
tags: [cpp, variable, type, value, scope, ns3, rdma]
description: "从 C++ 程序、变量、类型、值、表达式和作用域讲起，建立读懂 ns-3/RDMA 源码时最重要的第一个习惯：先看类型。"
---

<!-- series-nav -->
> **系列位置**：C++ 系统补课，第 01 篇 / 共 19 篇
> **总目录**：[学习路线](/roadmap/)
> **上一篇**：[00：从零建立 C++ 知识地图](/posts/cpp-systematic-learning-map/)
> **下一篇**：[02：内存、地址和指针](/posts/cpp-memory-address-pointer/)


上一篇文章先画了一张 C++ 知识地图。

这篇正式从第 1 层开始：

```text
程序、变量、类型和值
```

这一层看起来很基础，但它是读 C++ 源码的第一道门。

很多源码看不懂，并不是因为某个高级语法太难，而是最开始没有看清：

```text
这个名字是什么？
它是什么类型？
它代表什么值？
它在什么作用域里？
它能做哪些操作？
```

比如：

代码来源：

```text
src/point-to-point/model/rdma-queue-pair.h
```

```cpp
uint64_t m_size;
uint64_t snd_nxt, snd_una;
uint16_t m_pg;
uint32_t m_win;
DataRate m_rate;
Time m_nextAvail;
bool m_var_win;
```

这些都只是成员变量。

但每一个变量前面的类型都在告诉读者：

```text
m_size 是一个 64 位无符号整数。
snd_nxt 和 snd_una 是 64 位无符号整数。
m_pg 是 16 位无符号整数。
m_win 是 32 位无符号整数。
m_rate 是 DataRate 对象。
m_nextAvail 是 Time 对象。
m_var_win 是 bool。
```

如果只看变量名，不看类型，就很难真正理解代码。

所以这一篇的核心目标只有一个：

```text
养成读 C++ 源码时先看类型的习惯。
```

## 1. 什么是程序

一个 C++ 程序不是一堆随机文本。

它是由很多 C++ 语法单位组成的：

```text
变量
函数
类
对象
表达式
语句
头文件
源文件
命名空间
```

最小的入门程序通常长这样：

```cpp
#include <iostream>

int main() {
    std::cout << "hello C++" << std::endl;
    return 0;
}
```

这段里面已经有很多东西：

```text
#include <iostream>   引入标准输入输出库
int main()            定义主函数
std::cout             标准输出对象
"hello C++"           字符串字面值
return 0              返回整数 0
```

对 C++ 来说，程序最终会经过编译器处理。

大致过程是：

```text
源代码
  |
  v
编译
  |
  v
目标文件
  |
  v
链接
  |
  v
可执行程序
```

这篇先不深入编译链接。

这里只需要记住一点：

```text
C++ 源码里每个名字、每个表达式、每个函数调用，编译器都需要知道它的类型。
```

这就是为什么“类型”如此重要。

## 2. 什么是变量

变量可以先简单理解为：

```text
一个有名字的值。
```

例如：

```cpp
int x = 10;
```

这行代码里有三个核心部分：

```text
int   类型
x     变量名
10    初始值
```

也可以说：

```text
创建一个名叫 x 的变量。
它的类型是 int。
它当前保存的值是 10。
```

再看一个例子：

```cpp
double rate = 0.5;
```

这里：

```text
double  类型
rate    变量名
0.5     初始值
```

再看一个布尔变量：

```cpp
bool enabled = true;
```

这里：

```text
bool     类型
enabled 变量名
true    初始值
```

所以读变量声明时，可以固定按这个结构拆：

```text
类型 变量名 = 初始值;
```

当然，真实源码里经常更复杂。

比如：

```cpp
Ptr<Packet> p = Create<Packet>(payload_size);
```

也还是同一个结构：

```text
Ptr<Packet>              类型
p                        变量名
Create<Packet>(...)      初始值
```

只是类型变复杂了，初始值也变成了一个函数调用。

## 3. 什么是类型

类型是 C++ 里非常核心的概念。

可以先把类型理解成：

```text
一个值的种类。
```

比如：

```cpp
int x = 10;
double y = 3.14;
bool ok = true;
```

这里有三种类型：

```text
int      整数
double   双精度浮点数
bool     布尔值
```

类型决定了很多事情。

### 3.1 类型决定这个值怎么存

`int` 通常用来存整数。

`double` 用来存小数。

`bool` 用来存真假。

`uint64_t` 用来存 64 位无符号整数。

`Time` 用来表示 ns-3 的时间。

`DataRate` 用来表示数据速率。

`Ptr<Packet>` 用来表示指向 `Packet` 对象的 ns-3 智能指针。

每种类型的存储方式不同。

比如：

```cpp
uint64_t size;
bool finished;
Time now;
DataRate rate;
```

这些变量在内存里的结构并不一样。

### 3.2 类型决定能做什么操作

`int` 可以加减乘除：

```cpp
int a = 10;
int b = 20;
int c = a + b;
```

`bool` 可以做条件判断：

```cpp
bool enabled = true;

if (enabled) {
    // ...
}
```

`Time` 可以做时间相关操作：

```cpp
Time now = Simulator::Now();
int64_t t = now.GetTimeStep();
```

`Ptr<Packet>` 可以通过 `->` 调用 `Packet` 的成员函数：

```cpp
Ptr<Packet> p = Create<Packet>(1000);
uint32_t size = p->GetSize();
```

这就是类型的力量。

类型不是摆设。

它决定了：

```text
这个变量能不能加减？
能不能调用成员函数？
能不能放进 if？
能不能传给某个函数？
```

## 4. 什么是值

值是变量当前保存的内容。

例如：

```cpp
int x = 10;
```

这里：

```text
x 是变量名。
int 是类型。
10 是值。
```

后面可以修改这个值：

```cpp
x = 20;
```

现在：

```text
x 的值从 10 变成 20。
```

类型没有变。

变量名也没有变。

变的是值。

这三个概念要分清：

```text
类型：int
名字：x
值：10 或 20
```

再看 ns-3 里的例子：

```cpp
Time m_nextAvail;
```

这里：

```text
类型：Time
名字：m_nextAvail
值：某个具体的 ns-3 仿真时间
```

又比如：

```cpp
DataRate m_rate;
```

这里：

```text
类型：DataRate
名字：m_rate
值：某个具体速率，比如 100Gbps
```

读源码时，不能只问“这个变量叫什么”。

还要问：

```text
它是什么类型？
它当前可能是什么值？
这个值会在哪里被修改？
```

## 5. 声明和初始化

C++ 里经常看到这种语句：

```cpp
int x;
```

这叫声明一个变量。

它告诉编译器：

```text
这里有一个变量，名字叫 x，类型是 int。
```

也可以在声明时给初始值：

```cpp
int x = 10;
```

这叫初始化。

初始化的意思是：

```text
变量刚创建出来时，就给它一个初始值。
```

再看：

```cpp
int x = 10;
x = 20;
```

第一行是初始化。

第二行是赋值。

区别是：

```text
初始化：变量创建时给值。
赋值：变量已经存在，后面再改值。
```

这个区别以后在构造函数、初始化列表、对象生命周期里会非常重要。

在 ns-3/RDMA 代码里也能看到初始化。

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

这里的：

```cpp
: size(0),
  win(0),
  base_rtt(0),
  var_win(false),
  flow_id(-1),
  timeout(Time(0))
```

叫初始化列表。

这部分后面会专门讲。

在当前阶段，只需要先看懂：

```text
这些成员变量在对象创建时被设置了初始值。
```

## 6. 基本类型

C++ 有一些常见基本类型。

### 6.1 整数类型

```cpp
int a = 10;
unsigned int b = 20;
long c = 100;
```

整数类型用来表示整数。

但工程代码里更常看到固定宽度整数。

比如：

```cpp
uint8_t
uint16_t
uint32_t
uint64_t
int32_t
int64_t
```

它们来自 `<stdint.h>` 或 `<cstdint>`。

含义大致是：

```text
uint8_t    8 位无符号整数
uint16_t   16 位无符号整数
uint32_t   32 位无符号整数
uint64_t   64 位无符号整数
int32_t    32 位有符号整数
int64_t    64 位有符号整数
```

`u` 表示 unsigned，也就是无符号。

无符号整数不能表示负数。

例如：

```cpp
uint32_t x = 10;
```

`x` 可以表示非负整数。

但不能自然表示 `-1` 这种负数。

### 6.2 浮点类型

```cpp
float a = 0.5f;
double b = 0.5;
```

浮点类型用来表示小数。

RDMA 拥塞控制里经常会看到：

```cpp
double m_alpha;
```

`alpha` 这种权重、比例、概率、梯度，通常就会用 `double`。

### 6.3 布尔类型

```cpp
bool enabled = true;
bool finished = false;
```

`bool` 只有两个值：

```text
true
false
```

在 RDMA 状态里，布尔值常用来表示某个开关或状态。

比如：

```cpp
bool m_var_win;
bool m_first_cnp;
bool m_alpha_cnp_arrived;
```

看到 `bool` 类型时，读者可以先把它理解成：

```text
这是一个是/否开关。
```

## 7. ns-3 里常见的对象类型

真实工程里不只有基本类型。

ns-3 里到处都是对象类型。

比如：

```cpp
Time
DataRate
EventId
Ptr<Packet>
Ipv4Address
Buffer
PacketMetadata
```

这些不是 C++ 内置基本类型。

它们是类类型。

### 7.1 Time

代码来源：

```text
src/core/model/nstime.h
```

简化自源码：

```cpp
class Time
{
public:
    enum Unit {
        S,
        MS,
        US,
        NS,
        PS,
        FS
    };

    double GetSeconds(void) const;
    int64_t GetTimeStep(void) const;
};
```

`Time` 是 ns-3 里的时间对象。

它不是普通整数。

它有自己的成员函数：

```cpp
GetSeconds()
GetMilliSeconds()
GetMicroSeconds()
GetNanoSeconds()
GetTimeStep()
```

所以：

```cpp
Time now = Simulator::Now();
```

表示：

```text
now 是一个 Time 类型的变量。
它保存当前仿真时间。
```

后面可以写：

```cpp
double seconds = now.GetSeconds();
int64_t step = now.GetTimeStep();
```

这就是对象类型和基本类型的不同。

对象类型不仅保存数据，还能提供操作。

### 7.2 DataRate

`DataRate` 表示数据速率。

在 RDMA 里常见：

```cpp
DataRate m_rate;
DataRate m_max_rate;
DataRate m_targetRate;
```

它代表：

```text
当前速率
最大速率
目标速率
```

这种类型比裸 `uint64_t` 更清楚。

如果只写：

```cpp
uint64_t m_rate;
```

读者还要猜：

```text
这是 bit/s？
Byte/s？
packet/s？
某种内部单位？
```

而写成：

```cpp
DataRate m_rate;
```

语义就更明确：

```text
这是一个数据速率对象。
```

### 7.3 Ptr<Packet>

代码来源：

```text
src/network/model/packet.h
```

```cpp
class Packet : public SimpleRefCount<Packet> {
```

`Packet` 是一个类。

但在 ns-3 里，代码通常不会直接到处传 `Packet` 对象。

更常见的是：

```cpp
Ptr<Packet> p;
```

这表示：

```text
p 是一个 ns-3 智能指针。
它指向一个 Packet 对象。
```

例如：

```cpp
Ptr<Packet> p = Create<Packet>(payload_size);
uint32_t size = p->GetSize();
```

这里：

```text
Ptr<Packet> 是类型。
p 是变量名。
Create<Packet>(payload_size) 是初始值。
p->GetSize() 是通过指针调用 Packet 的成员函数。
```

后面讲指针、模板、智能指针时，会把这一行彻底拆开。

当前只需要先知道：

```text
Ptr<Packet> 也是一种类型。
```

## 8. 表达式是什么

表达式可以先理解成：

```text
能计算出一个值的代码片段。
```

例如：

```cpp
1 + 2
```

这是表达式，结果是 `3`。

```cpp
x + y
```

也是表达式，结果取决于 `x` 和 `y` 的值。

函数调用也是表达式：

```cpp
p->GetSize()
```

这个表达式的结果类型是 `uint32_t`。

再比如：

```cpp
Simulator::Now()
```

这个表达式的结果类型是 `Time`。

再比如：

```cpp
Simulator::Now().GetTimeStep()
```

可以拆成两步：

```text
Simulator::Now()              得到一个 Time 对象
Time 对象 .GetTimeStep()      得到一个 int64_t 值
```

读表达式时，最重要的是问：

```text
这个表达式算出来的类型是什么？
```

比如：

```cpp
uint32_t size = p->GetSize();
```

左边是：

```text
uint32_t size
```

右边是：

```text
p->GetSize()
```

这行能成立，说明 `p->GetSize()` 的结果可以放进 `uint32_t`。

## 9. 语句是什么

语句是 C++ 程序里的执行单位。

例如：

```cpp
int x = 10;
```

这是一个声明语句。

```cpp
x = 20;
```

这是一个赋值语句。

```cpp
return x;
```

这是一个返回语句。

```cpp
if (x > 0) {
    x = x - 1;
}
```

这是一个条件语句。

函数调用也可以成为语句：

```cpp
p->AddHeader(ipHeader);
```

这个语句的含义是：

```text
调用 p 指向的 Packet 对象的 AddHeader 函数。
```

语句和表达式的关系可以简单理解为：

```text
表达式产生值。
语句执行动作。
```

例如：

```cpp
uint32_t size = p->GetSize();
```

里面：

```text
p->GetSize() 是表达式。
整行是一个声明并初始化变量的语句。
```

## 10. 作用域是什么

作用域表示一个名字在哪一段代码里有效。

先看最简单的例子：

```cpp
int main() {
    int x = 10;

    if (x > 0) {
        int y = 20;
    }

    return 0;
}
```

这里：

```text
x 在 main 函数的大括号里有效。
y 只在 if 的大括号里有效。
```

出了大括号，变量名就不可见了。

比如：

```cpp
if (x > 0) {
    int y = 20;
}

y = 30;  // 错误：这里看不到 y
```

作用域在 C++ 源码阅读里非常重要。

因为同一个名字，可能出现在不同作用域里。

例如：

```cpp
class Packet {
private:
    Buffer m_buffer;
};
```

`m_buffer` 是 `Packet` 的成员变量。

它属于 `Packet` 对象。

而函数里的局部变量：

```cpp
void f() {
    Buffer buffer;
}
```

这里的 `buffer` 只属于函数 `f` 的局部作用域。

以后讲 class 时，会更系统地区分：

```text
局部变量
成员变量
全局变量
静态变量
命名空间里的名字
```

当前先记住：

```text
变量名不是全世界都有效。
它只在自己的作用域里有效。
```

## 11. 从源码里看类型：RdmaQueuePair

回到 RDMA 源码。

代码来源：

```text
src/point-to-point/model/rdma-queue-pair.h
```

简化自源码：

```cpp
class RdmaQueuePair : public Object {
public:
    Time startTime;

    uint16_t sport, dport;
    uint64_t m_size;
    uint64_t snd_nxt, snd_una;
    uint16_t m_pg;
    uint16_t m_ipid;
    uint32_t m_win;
    uint64_t m_baseRtt;
    DataRate m_max_rate;
    bool m_var_win;
    Time m_nextAvail;
    uint32_t wp;
    uint32_t lastPktSize;
    int32_t m_flow_id;
    Time m_timeout;
    DataRate m_rate;
};
```

读这段时，最重要的不是立刻理解所有 RDMA 逻辑。

第一步只是看类型。

```text
Time startTime       开始时间
uint16_t sport       源端口
uint16_t dport       目的端口
uint64_t m_size      flow 总大小
uint64_t snd_nxt     下一个要发送的序号
uint64_t snd_una     尚未确认的最高序号相关状态
uint16_t m_pg        priority group
uint32_t m_win       窗口大小
DataRate m_max_rate  最大速率
bool m_var_win       是否使用可变窗口
Time m_nextAvail     下一次可发送时间
DataRate m_rate      当前速率
```

变量名提供语义。

类型提供约束。

比如：

```cpp
bool m_var_win;
```

一看到 `bool`，就知道它大概率是一个开关。

再比如：

```cpp
Time m_nextAvail;
```

一看到 `Time`，就知道它不是普通整数，而是 ns-3 时间对象。

再比如：

```cpp
DataRate m_rate;
```

一看到 `DataRate`，就知道后面可能会调用：

```cpp
m_rate.GetBitRate()
```

这就是“先看类型”的价值。

## 12. 从源码里看类型：Packet

代码来源：

```text
src/network/model/packet.h
```

简化自源码：

```cpp
class Packet : public SimpleRefCount<Packet> {
public:
    Packet();
    uint32_t GetSize(void) const;
    Ptr<Packet> Copy(void) const;

private:
    Buffer m_buffer;
    ByteTagList m_byteTagList;
    PacketTagList m_packetTagList;
    PacketMetadata m_metadata;
};
```

这段里有很多类型：

```text
Packet                 类名
SimpleRefCount<Packet> 基类类型
uint32_t               GetSize 的返回值类型
Ptr<Packet>            Copy 的返回值类型
Buffer                 m_buffer 的类型
ByteTagList            m_byteTagList 的类型
PacketTagList          m_packetTagList 的类型
PacketMetadata         m_metadata 的类型
```

只看这一层，就能得到很多信息。

```text
Packet 是一个引用计数对象。
GetSize 返回一个 32 位无符号整数。
Copy 返回一个 Ptr<Packet>，不是裸 Packet。
Packet 内部有 Buffer 和两类 TagList。
```

这就是源码阅读的第一步：

```text
先不要急着问所有函数怎么实现。
先把类型读出来。
```

类型读出来以后，代码会清楚很多。

## 13. 从源码里看类型：Time

代码来源：

```text
src/core/model/nstime.h
```

简化自源码：

```cpp
class Time
{
public:
    double GetSeconds(void) const;
    int64_t GetTimeStep(void) const;
};
```

这说明：

```text
Time 是一个类。
GetSeconds 返回 double。
GetTimeStep 返回 int64_t。
```

于是读下面这种代码时：

```cpp
double t = Simulator::Now().GetSeconds();
```

可以拆成：

```text
Simulator::Now()           返回 Time
GetSeconds()               返回 double
double t                   用 double 接住结果
```

再看：

```cpp
uint64_t now = Simulator::Now().GetTimeStep();
```

这就要注意：

```text
GetTimeStep() 返回 int64_t。
左边用 uint64_t 接住。
这里发生了有符号到无符号的转换。
```

这种转换不一定错。

但读源码时要意识到：

```text
类型发生变化了。
```

## 14. 有符号和无符号

C++ 里整数有两大类：

```text
signed    有符号，可以表示负数
unsigned  无符号，只表示非负数
```

例如：

```cpp
int32_t a = -1;
uint32_t b = 1;
```

`a` 可以是负数。

`b` 不应该是负数。

在 RDMA 源码里：

```cpp
uint64_t m_size;
uint32_t m_win;
int32_t m_flow_id;
```

为什么 `m_size` 和 `m_win` 是无符号？

因为：

```text
flow size 不应该是负数。
window size 不应该是负数。
```

为什么 `m_flow_id` 可能是 `int32_t`？

因为它可能需要用 `-1` 表示某种无效值或默认值。

比如：

```cpp
flow_id(-1)
```

如果 `flow_id` 是 `uint32_t`，那 `-1` 会变成一个很大的无符号数。

所以有符号/无符号不是随便选的。

它和语义有关。

读源码时看到整数类型，可以顺手问一句：

```text
这个值有没有可能是负数？
如果不可能，为什么不用 unsigned？
如果用了 unsigned，代码里有没有拿 -1 当特殊值？
```

## 15. 类型转换

有时候代码需要显式转换类型。

例如：

```cpp
DataRate firstRate(
    static_cast<uint64_t>(
        qp->m_rate.GetBitRate() * config.rate_on_first_cnp));
```

这类代码里有很多类型变化。

可以拆成：

```text
qp->m_rate                    DataRate
qp->m_rate.GetBitRate()       通常是整数 bit rate
config.rate_on_first_cnp      可能是 double 比例
两者相乘                    可能产生浮点结果
static_cast<uint64_t>(...)    转回 uint64_t
DataRate firstRate(...)       用 uint64_t 构造 DataRate
```

`static_cast<uint64_t>` 的意思是：

```text
明确告诉编译器，把这个值转换成 uint64_t。
```

这通常比隐式转换更清楚。

读源码时看到 `static_cast`，要停一下。

它往往表示：

```text
这里的类型发生了有意识的变化。
```

## 16. auto 要怎么看

C++ 里还会看到：

```cpp
auto x = expression;
```

`auto` 的意思是：

```text
让编译器根据右边表达式推导 x 的类型。
```

例如：

```cpp
auto now = Simulator::Now();
```

因为 `Simulator::Now()` 返回 `Time`，所以：

```text
now 的类型是 Time。
```

再比如：

```cpp
auto size = p->GetSize();
```

如果 `p->GetSize()` 返回 `uint32_t`，那么：

```text
size 的类型是 uint32_t。
```

`auto` 很方便。

但对初学源码阅读的人来说，`auto` 会隐藏类型。

所以看到 `auto` 时，读者需要主动补全：

```text
右边表达式是什么类型？
auto 最后推导成什么类型？
```

这也是“先看类型”的一部分。

## 17. 类型和语义不是一回事

类型告诉代码怎么存、怎么操作。

但类型不一定完全告诉业务含义。

例如：

```cpp
uint32_t a;
uint32_t b;
```

这两个变量类型一样。

但语义可能完全不同：

```text
a 可能是 packet size。
b 可能是 node id。
```

所以读源码时要结合：

```text
类型
变量名
上下文
注释
函数名
```

比如：

```cpp
uint32_t m_win;
uint32_t lastPktSize;
```

它们都是 `uint32_t`。

但：

```text
m_win       表示窗口大小
lastPktSize 表示上一个 packet 的大小
```

类型负责约束。

名字负责语义。

上下文负责解释。

三者要一起看。

## 18. 读源码时的第一套问题

这一篇对应的源码阅读问题很简单。

看到一行 C++ 代码，先问：

```text
1. 这里出现了哪些名字？
2. 每个名字是什么类型？
3. 每个变量当前代表什么值？
4. 这个值有没有可能被修改？
5. 这个名字在哪个作用域里有效？
6. 这个表达式最终算出来是什么类型？
```

例如：

```cpp
uint32_t size = p->GetSize();
```

可以这样读：

```text
size 是一个 uint32_t 局部变量。
p 是一个 Ptr<Packet>。
p->GetSize() 是一个函数调用表达式。
这个表达式返回 uint32_t。
返回值被用来初始化 size。
```

再看：

```cpp
Time txTime = Seconds(m_bps.CalculateTxTime(p->GetSize()));
```

可以这样读：

```text
p->GetSize() 得到 packet 字节数。
m_bps.CalculateTxTime(...) 根据链路速率计算发送时间。
Seconds(...) 把秒数包装成 ns-3 Time 对象。
txTime 是 Time 类型。
```

这个读法一开始会慢。

但它能把代码读实。

## 19. 常见错误

### 错误 1：只看变量名，不看类型

比如看到：

```cpp
m_nextAvail
```

只根据名字猜：

```text
下一个可用时间。
```

这还不够。

还要看类型：

```cpp
Time m_nextAvail;
```

这说明它是 ns-3 的时间对象。

不是普通整数。

### 错误 2：把类型和值混在一起

```cpp
int x = 10;
```

这里：

```text
int 是类型。
x 是名字。
10 是值。
```

不要把三者混掉。

### 错误 3：忽略有符号和无符号

```cpp
uint32_t x = -1;
```

这类代码要非常小心。

`uint32_t` 是无符号整数。

`-1` 不是一个正常的非负值。

如果代码故意这么写，通常是在利用二进制表示。

如果不是故意，就可能是 bug。

### 错误 4：把 Time 当普通整数

```cpp
Time t = Simulator::Now();
```

`t` 不是裸整数。

它是 `Time` 对象。

要取具体数值，需要调用：

```cpp
t.GetSeconds()
t.GetTimeStep()
```

### 错误 5：看到 auto 就跳过去

```cpp
auto now = Simulator::Now();
```

这里不能只知道 `now` 是 `auto`。

要进一步推导：

```text
Simulator::Now() 返回 Time。
所以 now 是 Time。
```

## 20. 小结

这一篇讲的是 C++ 最底层的东西：

```text
程序
变量
类型
值
表达式
语句
作用域
```

核心结论很简单：

```text
读 C++ 源码，先看类型。
```

变量声明可以拆成：

```text
类型 变量名 = 初始值;
```

函数调用表达式要问：

```text
它返回什么类型？
```

对象类型要问：

```text
它有哪些成员函数？
它能做哪些操作？
```

ns-3/RDMA 源码里的很多名字，只有看清类型才会清楚：

```text
Time
DataRate
Ptr<Packet>
EventId
uint32_t
uint64_t
bool
double
```

下一篇进入第 2 层：

```text
C++ 系统补课 02：内存、地址和指针
```

那一篇会开始解释：

```text
变量在内存里意味着什么？
地址是什么？
T* 是什么？
&x 是什么？
*p 是什么？
this 是什么？
为什么 ns-3 事件系统里经常传 this？
```

从那一篇开始，C++ 最重要也最容易混乱的部分就正式登场了。
