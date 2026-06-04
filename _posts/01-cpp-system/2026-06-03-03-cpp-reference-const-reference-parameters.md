---
title: "C++ 系统补课 03：引用、const 引用和函数参数"
date: 2026-06-03 17:02:00 +0800
permalink: /posts/cpp-reference-const-reference-parameters/
categories: [C++, 系统补课]
tags: [cpp, reference, const-reference, parameter, ns3, header]
description: "从 T&、const T& 和函数参数讲起，理解为什么 ns-3 里 AddHeader 使用 const Header&，RemoveHeader 使用 Header&。"
---

<!-- series-nav -->
> **系列位置**：C++ 系统补课，第 03 篇 / 共 19 篇
> **总目录**：[学习路线](/roadmap/)
> **上一篇**：[02：内存、地址和指针](/posts/cpp-memory-address-pointer/)
> **下一篇**：[04：函数、返回值和参数传递](/posts/cpp-functions-return-parameters/)


上一篇讲了指针。

这篇讲引用。

引用是 C++ 里非常常见的参数形式：

```cpp
T&
const T&
```

在 ns-3 里尤其常见。

代码来源：

```text
src/network/model/packet.h
```

```cpp
void AddHeader(const Header& header);
uint32_t RemoveHeader(Header& header);
uint32_t PeekHeader(Header& header) const;
```

这三行是理解引用的好例子。

这一篇的主线可以先记成四句话：

```text
值传递：函数拿到一份拷贝。
T&：函数拿到原对象的可修改别名。
const T&：函数拿到原对象的只读别名。
成员函数末尾 const：函数不修改当前对象。
```

## 1. 引用是什么

引用可以先理解成：

```text
一个对象的别名。
```

例如：

```cpp
int x = 10;
int& r = x;
```

这里：

```text
r 是 x 的引用。
r 是 x 的另一个名字。
```

修改 `r`，就是修改 `x`：

```cpp
r = 20;
```

此时：

```text
x 的值也变成 20。
```

因为 `r` 并不是一个新 int。

它引用的就是 `x`。

## 2. 引用和指针的直观区别

指针写法：

```cpp
int x = 10;
int* p = &x;
*p = 20;
```

引用写法：

```cpp
int x = 10;
int& r = x;
r = 20;
```

两者都能间接操作原对象。

但形式不同：

```text
指针需要保存地址，并通过 *p 解引用。
引用像原对象的别名，直接使用 r。
```

指针可以是 `nullptr`。

引用一般必须绑定到一个有效对象。

所以函数参数里，如果一个对象必须存在，经常使用引用。

## 3. 值传递和普通引用参数 T&

### 3.1 值传递：函数拿到的是副本

先看一个大家初学时容易误解的版本：

```cpp
void setTo20(int x) {
    x = 20;
}
```

调用：

```cpp
int a = 10;
setTo20(a);
```

执行后，`a` 不会变成 `20`。

它仍然是：

```text
a == 10
```

为什么？

因为这里的参数类型是：

```cpp
int x
```

这叫值传递。

函数调用时，C++ 会把 `a` 的值复制一份，放进函数参数 `x` 里面。

可以理解成：

```text
调用前：

a: [10]

调用 setTo20(a) 时：

a: [10]
x: [10]   // x 是 a 的一份拷贝
```

进入函数后：

```cpp
x = 20;
```

改的是函数里面这个局部变量 `x`。

不是外面的 `a`。

所以函数结束前可以理解成：

```text
a: [10]
x: [20]
```

函数结束后，参数 `x` 离开作用域，生命周期结束。

外面的 `a` 从头到尾都没有被改。

所以：

```text
void setTo20(int x)
```

要读成：

```text
传进来一个 int 的值。
函数内部拿到的是一份拷贝。
修改 x 不会修改调用者的变量。
```

### 3.2 引用传递：函数拿到的是别名

再看引用版本：

```cpp
void setTo20(int& x) {
    x = 20;
}
```

调用：

```cpp
int a = 10;
setTo20(a);
```

执行后：

```text
a 变成 20。
```

因为 `x` 是 `a` 的引用。

也就是说，函数里面的 `x` 不是新对象。

它就是外面 `a` 的另一个名字。

可以理解成：

```text
调用 setTo20(a) 时：

a: [10]
^
|
x   // x 是 a 的别名，不是一份拷贝
```

进入函数后：

```cpp
x = 20;
```

因为 `x` 引用的就是 `a`，所以改 `x` 等于改 `a`。

这说明：

```text
T& 参数允许函数修改调用者传入的对象。
```

这也是 `int x` 和 `int& x` 在函数参数里最关键的区别：

```cpp
void f(int x);    // 值传递：复制一份，函数里改 x，不影响外面
void f(int& x);   // 引用传递：x 是外面对象的别名，函数里改 x，会影响外面
```

## 4. const 引用参数 const T&

### 4.1 const T& 为什么避免拷贝

再看：

```cpp
void printValue(const int& x) {
    // 只能读 x，不能改 x
}
```

`const int&` 的意思是：

```text
引用一个 int 对象。
但这个函数不应该通过这个引用修改它。
```

为什么不直接值传递？

比如：

```cpp
void f(Packet p);
```

这会复制一个 `Packet`。

如果对象很大，复制成本高。

从内存角度看，调用代码如果是：

```cpp
Packet pkt;
f(pkt);
```

那么 `void f(Packet p)` 大致可以理解成：

```text
调用前：

pkt: [一个 Packet 对象]

调用 f(pkt) 时：

pkt: [原来的 Packet 对象]
p:   [复制出来的 Packet 对象]
```

函数参数 `p` 是一个新的 `Packet` 对象。

它不是外面的 `pkt`。

它只是用 `pkt` 拷贝构造出来的一份副本。

所以函数里面如果写：

```cpp
void f(Packet p) {
    // 修改 p
}
```

修改的是副本 `p`。

外面的 `pkt` 不会被修改。

但代价是：

```text
为了创建这个副本，程序需要复制 Packet 对象内部的数据。
```

如果对象很小，比如 `int`，复制通常不贵。

但如果对象比较大，或者内部管理复杂资源，复制就可能比较重。

而：

```cpp
void f(const Packet& p);
```

不复制整个对象。

也不允许函数修改它。

从内存角度看，`const Packet& p` 大致是：

```text
调用前：

pkt: [一个 Packet 对象]

调用 f(pkt) 时：

pkt: [一个 Packet 对象]
^
|
p    // p 是 pkt 的只读别名，不是新的 Packet 对象
```

这里没有创建第二个 `Packet` 对象。

函数里面的 `p` 直接引用外面的 `pkt`。

但因为类型是：

```cpp
const Packet& p
```

所以函数不能通过 `p` 修改 `pkt`。

这就同时满足了两个目标：

```text
不复制对象。
不修改对象。
```

这就是 `const T&` 常见的原因：

```text
避免拷贝，同时保证只读。
```

### 4.2 为什么不直接传指针

到这里，引用看起来很像指针。

那为什么不直接传指针？

比如写成：

```cpp
void f(const Packet* p);
```

这当然也不会复制整个 `Packet`。

因为传进去的只是一个地址。

但是指针和引用表达的接口含义不一样。

如果参数是：

```cpp
void f(const Packet& p);
```

它表达的是：

```text
调用者必须传进来一个真实存在的 Packet 对象。
函数不会复制它。
函数也不会修改它。
```

调用方式也很自然：

```cpp
Packet pkt;
f(pkt);
```

函数里面像使用普通对象一样使用它：

```cpp
void f(const Packet& p) {
    uint32_t size = p.GetSize();
}
```

如果参数是：

```cpp
void f(const Packet* p);
```

它表达的是：

```text
调用者传进来的是一个 Packet 对象的地址。
这个地址可能有效，也可能是 nullptr。
```

调用时也要显式取地址：

```cpp
Packet pkt;
f(&pkt);
```

函数里面一般要先考虑空指针：

```cpp
void f(const Packet* p) {
    if (p == nullptr) {
        return;
    }

    uint32_t size = p->GetSize();
}
```

所以：

```text
const T& 更适合表达：这个对象必须存在，我只是只读使用它。
const T* 更适合表达：这里传的是地址，而且这个地址可能为空。
```

在 ns-3 的 `AddHeader` 里：

```cpp
void AddHeader(const Header& header);
```

意思就是：

```text
调用者必须给一个 Header 对象。
AddHeader 只读取这个 header。
AddHeader 不保存这个 header 的地址。
AddHeader 不修改这个 header。
```

如果写成：

```cpp
void AddHeader(const Header* header);
```

反而会让读者多想一层：

```text
header 会不会是 nullptr？
AddHeader 里面是不是要检查空指针？
这个指针会不会被保存起来？
```

但实际语义并不是这样。

所以这里用 `const Header&` 更清楚。

## 5. AddHeader 为什么是 const Header&

代码来源：

```text
src/network/model/packet.h
```

```cpp
void AddHeader(const Header& header);
```

`AddHeader` 的任务是：

```text
把 header 序列化进 Packet 的 Buffer。
```

### 5.1 序列化是什么意思

这里的“序列化”需要单独解释一下。

一个 `Header` 对象在 C++ 里通常是一组字段。

比如可以想象一个简化版 IPv4 header：

```text
source address
destination address
ttl
protocol
checksum
```

这些字段在 C++ 对象里是“有类型的成员变量”。

但真正放进 `Packet` 的时候，不能直接放一个 C++ 对象。

网络包里放的是字节。

所以要把这些字段按照协议规定的格式，写成一段连续的字节。

这个过程就叫序列化：

```text
C++ Header 对象  ->  Packet Buffer 里的字节
```

可以画成：

```text
header 对象：

ttl = 64
protocol = 17
src = 10.0.0.1
dst = 10.0.0.2

序列化后：

Packet Buffer:
[字节][字节][字节][字节][字节]...
```

注意，序列化不是简单地把 C++ 对象在内存里的样子原封不动复制进去。

它要按照网络协议规定的格式写入。

ns-3 的 `Header` 接口也正是这样设计的。

### 5.2 Header 接口里的 Serialize 和 Deserialize

代码来源：

```text
src/network/model/header.h
```

```cpp
virtual uint32_t GetSerializedSize(void) const = 0;
virtual void Serialize(Buffer::Iterator start) const = 0;
virtual uint32_t Deserialize(Buffer::Iterator start) = 0;
```

这三个函数可以这样读：

```text
GetSerializedSize：这个 header 序列化以后需要多少字节。
Serialize：把 header 对象写成字节，放进 Buffer。
Deserialize：从 Buffer 里的字节重新解析出 header 对象。
```

其中：

```cpp
virtual void Serialize(Buffer::Iterator start) const = 0;
```

末尾有 `const`。

这说明序列化只需要读取当前 header 对象，不应该修改当前 header 对象。

而：

```cpp
virtual uint32_t Deserialize(Buffer::Iterator start) = 0;
```

没有 `const`。

因为反序列化需要把 Buffer 里的字节读出来，填进当前 header 对象。

所以：

```text
Serialize：对象 -> 字节，只读对象。
Deserialize：字节 -> 对象，要修改对象。
```

### 5.3 回到 AddHeader

它需要读取 `header` 的内容。

但不需要修改传进来的 `header` 对象。

所以参数类型是：

```cpp
const Header& header
```

可以读成：

```text
传进来一个 Header 对象的引用。
不拷贝。
不修改。
```

这非常合理。

例如：

```cpp
Ipv4Header ipHeader;
p->AddHeader(ipHeader);
```

`AddHeader` 只需要读取 `ipHeader` 里的字段并序列化。

它不应该把调用者手里的 `ipHeader` 改掉。

## 6. RemoveHeader 为什么是 Header&

代码来源：

```text
src/network/model/packet.h
```

```cpp
uint32_t RemoveHeader(Header& header);
```

`RemoveHeader` 的任务是：

```text
从 Packet 的 Buffer 开头解析 header 字节。
把解析结果填进调用者传入的 header 对象。
然后从 Packet 中删除这段 header。
```

所以它必须修改 `header`。

例如：

```cpp
Ipv4Header h;
p->RemoveHeader(h);
```

调用前：

```text
h 是一个空的 Ipv4Header 对象。
```

调用后：

```text
h 里被填入 packet 中解析出来的 IPv4 字段。
```

所以参数不能是 `const Header&`。

它必须是：

```cpp
Header& header
```

也就是：

```text
可以修改的引用。
```

## 7. PeekHeader 为什么也是 Header&

```cpp
uint32_t PeekHeader(Header& header) const;
```

`PeekHeader` 不删除 packet 里的 header。

但它仍然需要把解析结果填进 `header` 对象。

所以参数仍然是：

```cpp
Header& header
```

### 7.1 成员函数末尾 const 修饰当前对象

而函数末尾的 `const`：

```cpp
... const;
```

表示：

```text
PeekHeader 不修改当前 Packet 对象。
```

这里最容易混淆的是：

```text
这个 const 不是在说参数 header 不能改。
这个 const 是在说当前 Packet 对象不能改。
```

为什么？

因为 `PeekHeader` 是 `Packet` 的成员函数。

成员函数末尾的 `const`，修饰的是函数里面隐含的 `this`。

先看一个简单例子：

```cpp
class Counter {
public:
    int Get() const {
        return m_value;
    }

    void Set(int value) {
        m_value = value;
    }

private:
    int m_value;
};
```

这里：

```cpp
int Get() const
```

表示：

```text
Get 可以读取当前 Counter 对象。
但 Get 不应该修改当前 Counter 对象。
```

所以在 `Get()` 里面，下面这种事情不允许：

```cpp
int Get() const {
    m_value = 10;  // 错误：const 成员函数不能修改当前对象的成员变量
    return m_value;
}
```

而：

```cpp
void Set(int value)
```

末尾没有 `const`。

它可以修改当前对象：

```cpp
void Set(int value) {
    m_value = value;
}
```

回到 ns-3：

```cpp
uint32_t PeekHeader(Header& header) const;
```

### 7.2 同时修改 header，又不修改 Packet

这行里面有两个不同的对象：

```text
1. 当前 Packet 对象，也就是调用 PeekHeader 的那个 packet。
2. 参数 header，也就是调用者传进来的 Header 对象。
```

末尾的 `const` 管的是第 1 个：

```text
PeekHeader 不应该修改当前 Packet。
```

参数里的 `Header& header` 管的是第 2 个：

```text
PeekHeader 可以修改传进来的 header。
```

所以这两个并不矛盾。

`PeekHeader` 的语义是：

```text
从当前 Packet 里读 header 字节。
把解析结果填进参数 header。
但是不从当前 Packet 里删除这些字节。
```

也就是说：

```text
header 被填充了。
Packet 没被改变。
```

所以这行要分开读：

```cpp
uint32_t PeekHeader(Header& header) const;
```

含义是：

```text
会修改参数 header。
不会修改当前 Packet 对象。
返回读取的字节数。
```

## 8. const T& 和多态

`AddHeader` 的参数是：

```cpp
const Header& header
```

但实际传进去的可能是：

```text
Ipv4Header
UdpHeader
SeqTsHeader
qbbHeader
CnHeader
PauseHeader
```

这是因为这些类都继承自 `Header`。

基类引用可以绑定到派生类对象。

例如：

```cpp
Ipv4Header ip;
const Header& h = ip;
```

这就是多态的入口。

后面讲继承和 virtual 时，会继续深入。

当前先记住：

```text
const Header& 可以接住各种具体 Header 对象。
```

## 9. 引用不是所有权

引用只是别名。

它不表示拥有对象。

比如：

```cpp
void AddHeader(const Header& header);
```

`Packet` 并没有拥有这个 `header` 对象。

它只是临时读取它，把它序列化进 Buffer。

函数返回后，`header` 仍然归调用者管理。

这和智能指针不同。

```cpp
Ptr<Packet> p
```

可能参与引用计数生命周期。

但：

```cpp
Header& header
```

只是引用，不负责生命周期。

## 10. 读源码时的检查问题

看到引用参数，可以问：

```text
1. 是 T& 还是 const T&？
2. 函数会不会修改这个参数？
3. 是否为了避免拷贝？
4. 这个引用有没有绑定到派生类对象？
5. 函数末尾有没有 const？那表示是否修改当前对象。
```

例如：

```cpp
void AddHeader(const Header& header);
```

读成：

```text
只读传入 header。
不复制。
允许传入 Header 的派生类对象。
```

例如：

```cpp
uint32_t RemoveHeader(Header& header);
```

读成：

```text
会把解析结果写进 header。
因此 header 必须是可修改引用。
```

## 11. 小结

这一篇的核心是：

```text
T& 是可修改引用。
const T& 是只读引用。
引用不是对象所有权。
引用参数常用于避免拷贝。
```

ns-3 里的 `Packet` API 非常适合理解引用：

```cpp
void AddHeader(const Header& header);        // 读取 header，不修改 header；会修改 Packet
uint32_t RemoveHeader(Header& header);       // 解析并填充 header；会修改 Packet
uint32_t PeekHeader(Header& header) const;   // 解析并填充 header；不修改 Packet
```

下一篇进入：

```text
C++ 系统补课 04：函数、返回值和参数传递
```

那一篇会把值传递、指针传递、引用传递放在一起比较。
