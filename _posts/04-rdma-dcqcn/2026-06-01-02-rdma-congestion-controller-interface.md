---
title: "从 C++ 虚函数到 RDMA 拥塞控制接口重构"
date: 2026-06-01 12:00:00 +0800
permalink: /posts/rdma-congestion-controller-interface/
categories: [网络, ns-3]
tags: [cpp, virtual, destructor, rdma, congestion-control, ns3]
description: "从父类指针、虚函数、纯虚函数、析构函数和虚析构函数讲起，再分析 RDMA sender-side 拥塞控制接口的重构设计。"
---

<!-- series-nav -->
> **系列位置**：RDMA / DCQCN 源码与模型，第 02 篇 / 共 2 篇
> **总目录**：[学习路线](/roadmap/)
> **上一篇**：[DCQCN 流体模型详细推导](/posts/dcqcn-fluid-model/)


这篇文章记录一次 RDMA sender-side 拥塞控制接口的重构。

这次重构里，我引入了一个统一接口：

```cpp
class IRdmaCongestionController {
public:
    virtual ~IRdmaCongestionController() = default;

    virtual void InitQp(Ptr<RdmaQueuePair> qp,
                        Ptr<QbbNetDevice> dev,
                        Ptr<RdmaHw> hw) = 0;

    virtual void EnsureSenderReady(Ptr<RdmaQueuePair> qp,
                                   Ptr<QbbNetDevice> dev,
                                   Ptr<RdmaHw> hw) = 0;

    virtual void OnCongestionFeedback(Ptr<RdmaQueuePair> qp,
                                      Ptr<Packet> p,
                                      CustomHeader &ch,
                                      Ptr<RdmaHw> hw) {}

    virtual void OnAck(Ptr<RdmaQueuePair> qp,
                       Ptr<Packet> p,
                       CustomHeader &ch,
                       Ptr<RdmaHw> hw) {}

    virtual void OnNack(Ptr<RdmaQueuePair> qp,
                        Ptr<Packet> p,
                        CustomHeader &ch,
                        Ptr<RdmaHw> hw) {}

    virtual void CleanupQp(Ptr<RdmaQueuePair> qp,
                           Ptr<RdmaHw> hw) {}
};
```

这段代码看起来只是一个 C++ 接口，但它背后其实有几个非常重要的基础知识：

1. 父类指针为什么可以指向子类对象；
2. 虚函数解决什么问题；
3. 纯虚函数为什么适合定义接口；
4. 析构函数是什么；
5. 虚析构函数为什么必须写；
6. 为什么这些知识正好适合用来重构 RDMA 拥塞控制模块。

所以这篇文章先从 C++ 基础讲起，再回到我们的 RDMA 代码。

---

## 1. 从对象创建开始

先看两个简单的类：

```cpp
class Animal {
public:
    void Speak() {
        std::cout << "Animal speaks\n";
    }
};

class Dog : public Animal {
public:
    void Speak() {
        std::cout << "Dog barks\n";
    }
};
```

`Dog` 继承自 `Animal`，所以一个 `Dog` 对象本身也是一个 `Animal`。

### 1.1 直接创建对象：对象本身就在变量里

最直接的写法是：

```cpp
Dog d;
d.Speak();
```

这里创建了一个真正的 `Dog` 对象，变量名叫 `d`。

因为 `d` 的类型就是 `Dog`，所以：

```cpp
d.Speak();
```

调用的是：

```cpp
Dog::Speak()
```

这种写法里，`d` 不是指针，也不是引用，它就是对象本身。

可以粗略理解成：

```text
d 这个变量里面直接放着一个 Dog 对象
```

这种对象通常创建在当前作用域里。离开作用域时，它会自动销毁，不需要手动 `delete`。

例如：

```cpp
void Test() {
    Dog d;
    d.Speak();
}
```

当 `Test()` 函数结束时，`d` 会自动析构。

所以这种写法的特点是：

1. 写法简单；
2. 生命周期清楚；
3. 不需要手动释放；
4. 不适合表达“运行时再决定具体子类”的多态场景。

这里最后一点很重要。

如果你已经明确知道对象就是 `Dog`，那么：

```cpp
Dog d;
```

非常合适。

但如果你想让一段代码既能处理 `Dog`，也能处理 `Cat`，甚至以后还能处理更多子类，那么只写具体类型 `Dog d` 就不够灵活。

### 1.2 创建对象时也可以传构造参数

真实代码里，对象往往不是空着创建的，而是带参数创建。

比如：

```cpp
class Dog : public Animal {
public:
    Dog(std::string name, int age)
        : m_name(name), m_age(age) {}

    void Speak() {
        std::cout << m_name << " barks\n";
    }

private:
    std::string m_name;
    int m_age;
};
```

那就可以这样创建：

```cpp
Dog d("Lucky", 3);
d.Speak();
```

或者用更现代一点的统一初始化写法：

```cpp
Dog d{"Lucky", 3};
d.Speak();
```

这两种都表示：创建一个 `Dog` 对象，并用 `"Lucky"` 和 `3` 初始化它。

所以对象创建不是只有：

```cpp
Dog d;
```

还可以是：

```cpp
Dog d("Lucky", 3);
Dog d{"Lucky", 3};
```

它们的共同点是：变量 `d` 仍然是对象本身。

### 1.3 用 new 创建对象：变量里放的是地址

也可以写成：

```cpp
Dog* d = new Dog();
d->Speak();
delete d;
```

这里：

```cpp
new Dog()
```

表示在堆上创建一个 `Dog` 对象，并返回它的地址。

```cpp
Dog* d
```

表示用一个 `Dog` 类型的指针保存这个地址。

因为用了 `new`，所以后面必须 `delete`：

```cpp
delete d;
```

否则堆上的对象不会自动释放。

这种写法和前面的区别是：

```cpp
Dog d;
```

变量 `d` 里面就是对象本身。

而：

```cpp
Dog* d = new Dog();
```

变量 `d` 里面放的是对象地址。

对象本身在堆上。

所以访问成员函数时，写法也不同：

```cpp
d.Speak();   // d 是对象
d->Speak();  // d 是指针
```

`->` 可以理解成：

```cpp
(*d).Speak();
```

先通过指针找到对象，再调用对象的成员函数。

### 1.4 父类指针指向子类对象

更关键的是这种写法：

```cpp
Animal* a = new Dog();
a->Speak();
delete a;
```

这句话要拆开看。

```cpp
new Dog()
```

创建的真实对象是 `Dog`。

但是：

```cpp
Animal* a
```

表示我们用父类指针 `Animal*` 去保存这个 `Dog` 对象的地址。

这是允许的，因为 `Dog` 继承自 `Animal`。一个 `Dog` 可以被当成一种 `Animal` 来看。

但是这里马上出现一个问题：

```cpp
a->Speak();
```

到底应该调用：

```cpp
Animal::Speak()
```

还是：

```cpp
Dog::Speak()
```

这就是虚函数要解决的问题。

这种写法是多态最常见的入口。

因为调用方可以只保存父类指针：

```cpp
Animal* a;
```

真实对象却可以在运行时决定：

```cpp
a = new Dog();
```

假设系统里还有另一个子类 `Cat`，也可以是：

```cpp
a = new Cat();
```

这就给程序留下了扩展空间。

我们的 RDMA 代码里也是同样的思想：

```cpp
IRdmaCongestionController* cc;
```

它背后的真实对象可以是：

```cpp
DcqcnCongestionController
HpccCongestionController
TimelyCongestionController
DctcpCongestionController
```

### 1.5 父类引用绑定子类对象

除了父类指针，还可以用父类引用：

```cpp
Dog d;
Animal& a = d;
a.Speak();
```

这里 `a` 不是一个新对象。

它只是 `d` 的另一个名字，只不过是从 `Animal` 的视角去看 `d`。

引用和指针一样，也可以触发虚函数多态。

如果 `Speak()` 是虚函数，那么：

```cpp
a.Speak();
```

会调用：

```cpp
Dog::Speak()
```

父类引用的好处是不用 `new/delete`，生命周期仍然由原来的对象 `d` 管理。

但是引用一旦绑定到某个对象，后面不能再改绑到另一个对象。

指针则可以重新指向别的对象：

```cpp
Animal* a = new Dog();
delete a;

a = new Cat();
delete a;
```

所以指针更灵活，引用更简单安全。

### 1.6 父类对象接子类对象：对象切片

还有一种写法很容易误解：

```cpp
Animal a = Dog();
a.Speak();
```

这不是多态。

这里不是“父类变量指向子类对象”，而是把一个 `Dog` 对象拷贝成一个 `Animal` 对象。

`Dog` 里属于子类的部分会被切掉，只保留 `Animal` 那一部分。

这叫对象切片。

所以最后：

```cpp
Animal a
```

真的就是一个 `Animal` 对象，不再是完整的 `Dog` 对象。

因此，多态场景里要避免这样写：

```cpp
Animal a = Dog(); // 不适合多态
```

应该使用父类指针或父类引用：

```cpp
Animal* a = new Dog();
```

或者：

```cpp
Dog d;
Animal& a = d;
```

### 1.7 智能指针：自动管理 new 出来的对象

前面这种写法：

```cpp
Animal* a = new Dog();
a->Speak();
delete a;
```

能表达多态，但有一个麻烦：必须记得 `delete`。

如果中途函数返回了，或者抛异常了，或者某个分支忘记写 `delete`，就可能泄漏对象。

所以现代 C++ 更常用智能指针：

```cpp
std::unique_ptr<Animal> a = std::make_unique<Dog>();
a->Speak();
```

它表达的意思和下面类似：

```cpp
Animal* a = new Dog();
```

但是 `unique_ptr` 会自动负责销毁对象。

当 `a` 离开作用域时，它会自动做类似下面的事情：

```cpp
delete 内部保存的指针;
```

所以我们不用手动写：

```cpp
delete a;
```

我们的 RDMA 代码里用的就是这种思想：

```cpp
std::unique_ptr<IRdmaCongestionController> m_ccController;
```

它表示：

> `RdmaHw` 独占拥有一个拥塞控制 controller，并且会在自己销毁时自动释放这个 controller。

不过智能指针本身是一个很大的主题。

这一篇只讲到理解当前重构需要的程度：`unique_ptr<父类>` 可以保存 `new 子类`，并自动管理它的生命周期。

后面可以单独写一篇文章，专门讲 `unique_ptr`、`shared_ptr`、`weak_ptr`、所有权和 RAII。

---

## 2. 虚函数解决什么问题

如果父类里的函数不是虚函数：

```cpp
class Animal {
public:
    void Speak() {
        std::cout << "Animal speaks\n";
    }
};
```

那么：

```cpp
Animal* a = new Dog();
a->Speak();
```

调用的是：

```cpp
Animal::Speak()
```

原因是：编译器看到 `a` 的类型是 `Animal*`，所以按照 `Animal` 的函数来调用。

这种调用在编译阶段就决定了，通常叫静态绑定。

如果我们把父类函数改成虚函数：

```cpp
class Animal {
public:
    virtual void Speak() {
        std::cout << "Animal speaks\n";
    }
};
```

子类重写它：

```cpp
class Dog : public Animal {
public:
    void Speak() override {
        std::cout << "Dog barks\n";
    }
};
```

再执行：

```cpp
Animal* a = new Dog();
a->Speak();
```

实际调用的就是：

```cpp
Dog::Speak()
```

这就是虚函数的核心作用：

> 通过父类指针或父类引用调用函数时，真正执行哪个版本，由对象的真实类型决定。

这也叫运行时多态。

### 2.1 override 的作用

子类里通常会写：

```cpp
void Speak() override
```

`override` 表示：我明确声明这个函数是在重写父类的虚函数。

它不是必须写，但非常推荐写。

如果父类函数是：

```cpp
virtual void Speak(int x);
```

而子类误写成：

```cpp
void Speak() override;
```

编译器会直接报错，因为这个函数并没有真正重写父类函数。

所以 `override` 可以帮我们尽早发现函数签名写错的问题。

---

## 3. 对象创建方式小结

到这里，我们其实已经见过了几种不同的对象创建和保存方式。

最容易混的是：变量里到底放的是对象本身、对象地址，还是只是另一个对象的引用。

可以用下面这张表记住：

| 写法 | 真实对象 | 变量里是什么 | 是否适合多态 |
|---|---|---|---|
| `Dog d;` | `Dog` | 对象本身 | 不涉及父类多态 |
| `Dog* d = new Dog();` | `Dog` | `Dog` 对象地址 | 不涉及父类多态 |
| `Animal* a = new Dog();` | `Dog` | 子类对象地址，但用父类指针保存 | 适合 |
| `Dog d; Animal& a = d;` | `Dog` | `d` 的父类引用 | 适合 |
| `Animal a = Dog();` | `Animal` | 对象本身，但发生对象切片 | 不适合 |
| `std::unique_ptr<Animal> a = std::make_unique<Dog>();` | `Dog` | 自动管理的父类指针 | 适合 |

所以，理解虚函数之前，先记住这句话：

> 多态通常依赖父类指针或父类引用；如果把子类对象直接赋值给父类对象，就会发生对象切片。

---

## 4. 纯虚函数和接口

有时候父类并不想提供默认实现，只想规定“子类必须有这个函数”。

这时可以写成纯虚函数：

```cpp
class Animal {
public:
    virtual void Speak() = 0;
};
```

这里的：

```cpp
= 0
```

表示 `Speak` 是纯虚函数。

包含纯虚函数的类叫抽象类，不能直接创建对象：

```cpp
Animal a; // 错误
```

它的作用是定义接口，强制子类实现：

```cpp
class Dog : public Animal {
public:
    void Speak() override {
        std::cout << "Dog barks\n";
    }
};
```

所以纯虚函数非常适合表达这种语义：

> 父类规定接口，子类提供具体行为。

这正是我们后面定义 `IRdmaCongestionController` 的基础。

---

## 5. 析构函数是什么

析构函数是在对象销毁时自动调用的函数。

例如：

```cpp
class Buffer {
public:
    Buffer() {
        data = new int[100];
    }

    ~Buffer() {
        delete[] data;
    }

private:
    int* data;
};
```

这里：

```cpp
~Buffer()
```

就是析构函数。

构造函数里申请资源：

```cpp
data = new int[100];
```

析构函数里释放资源：

```cpp
delete[] data;
```

如果没有析构函数释放这块内存，对象没了，但堆内存还在，就会发生资源泄漏。

析构函数的特点是：

1. 名字固定为 `~类名()`；
2. 没有返回值；
3. 不能随便带普通参数；
4. 对象销毁时自动调用；
5. 常用于释放资源。

对象销毁通常发生在下面几种情况。

局部对象离开作用域：

```cpp
{
    Buffer b;
}
```

`delete` 指针：

```cpp
Buffer* b = new Buffer();
delete b;
```

智能指针销毁：

```cpp
std::unique_ptr<Buffer> b = std::make_unique<Buffer>();
```

当 `unique_ptr` 自己销毁时，它会自动删除里面的 `Buffer` 对象。

---

## 6. 继承下的析构顺序

看这个例子：

```cpp
class Animal {
public:
    ~Animal() {
        std::cout << "Animal destroyed\n";
    }
};

class Dog : public Animal {
public:
    ~Dog() {
        std::cout << "Dog destroyed\n";
    }
};
```

如果直接创建：

```cpp
Dog d;
```

销毁时顺序是：

```text
Dog destroyed
Animal destroyed
```

也就是：

```text
先子类析构
再父类析构
```

这是合理的，因为一个 `Dog` 对象里包含了一个 `Animal` 基类部分。销毁完整对象时，要先销毁外层的 `Dog` 部分，再销毁里面的 `Animal` 部分。

---

## 7. 为什么需要虚析构函数

危险出现在这种场景：

```cpp
Animal* a = new Dog();
delete a;
```

真实对象是 `Dog`，但我们通过 `Animal*` 去删除它。

如果 `Animal` 的析构函数不是虚函数，那么通过父类指针删除子类对象时，可能无法正确调用 `Dog::~Dog()`。

假设 `Dog` 里有资源：

```cpp
class Dog : public Animal {
public:
    Dog() {
        data = new int[100];
    }

    ~Dog() {
        delete[] data;
        std::cout << "Dog destroyed\n";
    }

private:
    int* data;
};
```

如果 `Dog::~Dog()` 没有被调用，那么：

```cpp
delete[] data;
```

就不会执行，资源就泄漏了。

解决方法是把父类析构函数写成虚函数：

```cpp
class Animal {
public:
    virtual ~Animal() = default;
};
```

这样：

```cpp
Animal* a = new Dog();
delete a;
```

就会正确执行完整析构流程：

```text
Dog::~Dog()
Animal::~Animal()
```

所以规则很简单：

> 只要一个类要作为多态基类使用，就应该有 virtual 析构函数。

普通虚函数保证普通函数调用能走到子类实现。

虚析构函数保证通过父类指针销毁对象时，也能完整销毁子类对象。

### 7.1 什么时候应该写虚析构函数

实际写代码时，可以用下面几条规则判断。

第一种情况：类里有虚函数，并且它会作为父类使用。

这种类基本就应该写虚析构函数：

```cpp
class Animal {
public:
    virtual ~Animal() = default;
    virtual void Speak() = 0;
};
```

原因是：既然它已经有虚函数，说明你希望通过父类指针或父类引用使用子类对象。那将来就很可能出现：

```cpp
Animal* a = new Dog();
delete a;
```

为了让这件事安全，父类析构函数应该是 virtual。

第二种情况：这个类是接口类。

接口类通常长这样：

```cpp
class Interface {
public:
    virtual ~Interface() = default;
    virtual void Run() = 0;
};
```

接口类几乎总是为了让子类继承，并通过父类指针调用，所以应该写虚析构函数。

我们的 `IRdmaCongestionController` 就是这种情况。

第三种情况：你会把子类对象交给 `std::unique_ptr<父类>` 或 `std::shared_ptr<父类>` 管理。

例如：

```cpp
std::unique_ptr<Animal> a = std::make_unique<Dog>();
```

这里 `unique_ptr` 销毁时，本质上还是通过 `Animal*` 删除真实的 `Dog` 对象。

所以 `Animal` 的析构函数应该是 virtual。

这和我们的代码完全对应：

```cpp
std::unique_ptr<IRdmaCongestionController> m_ccController;
```

它保存的真实对象可能是 `DcqcnCongestionController`、`HpccCongestionController`、`TimelyCongestionController` 或 `DctcpCongestionController`。

所以 `IRdmaCongestionController` 必须有虚析构函数。

第四种情况：基类本身管理资源，或者子类未来可能管理资源。

即使当前子类里没有显式写析构函数，也不代表以后不会有。

比如今天的 `DcqcnCongestionController` 可能只是 adapter，没有自己的资源；但未来某个 controller 可能持有缓存、统计对象、事件句柄或其他需要清理的状态。

如果基类析构函数一开始就写成 virtual，后面扩展会更安全。

### 7.2 什么时候不一定需要虚析构函数

不是所有类都需要虚析构函数。

如果一个类只是普通值类型，不打算被继承，也不会通过父类指针删除子类对象，就不需要：

```cpp
class Point {
public:
    int x;
    int y;
};
```

这种类没有多态需求，写 virtual 反而会引入额外的多态机制。

还有一种情况：一个类虽然被继承，但你明确不允许通过父类指针删除它。

这种设计有时会把析构函数写成 `protected` 且非 virtual：

```cpp
class Base {
protected:
    ~Base() = default;
};
```

这样外部代码不能写：

```cpp
Base* p = new Derived();
delete p; // 编译不通过
```

不过这属于更专门的设计技巧。对于我们这里的接口类，最合适的就是：

```cpp
virtual ~IRdmaCongestionController() = default;
```

### 7.3 最实用的判断口诀

可以记住这条：

> 只要一个类准备用来“父类指针指向子类对象”，并且对象可能通过这个父类指针被销毁，就写 virtual 析构函数。

再短一点：

> 多态基类，虚析构。

---

## 8. default 是什么意思

我们的代码里写的是：

```cpp
virtual ~IRdmaCongestionController() = default;
```

这句话可以拆成两部分。

第一部分：

```cpp
virtual ~IRdmaCongestionController()
```

表示这是虚析构函数。

第二部分：

```cpp
= default
```

表示析构函数的具体实现交给编译器默认生成。

也就是说，我们不需要自己写特殊清理逻辑，但需要明确告诉 C++：

> 这个类是一个多态基类，通过父类指针删除子类对象时必须安全。

---

## 9. 回到 RDMA 拥塞控制重构

现在回到我们的 RDMA 代码。

原来的问题是：`RdmaHw` 承担了太多职责。

它不仅要负责：

1. 收包；
2. 查找 QP；
3. 处理 ACK/NACK；
4. 处理 CNP；
5. 调用可靠性逻辑；
6. 调用拥塞控制逻辑；
7. 根据不同 `ccMode` 区分不同算法。

如果后面继续加入 HPCC、TIMELY、DCTCP、HP3 等算法，很容易在 `RdmaHw` 里继续增加：

```cpp
if (m_cc_mode == ...)
```

或者：

```cpp
switch (m_cc_mode)
```

这样 `RdmaHw` 会越来越臃肿。

所以重构目标是：

> 让 `RdmaHw` 只负责发现事件和分发事件，具体拥塞控制算法负责处理事件。

这就是 `IRdmaCongestionController` 的设计目的。

---

## 10. IRdmaCongestionController 接口分析

接口定义在 `rdma-congestion-controller.h`：

```cpp
class IRdmaCongestionController {
public:
    virtual ~IRdmaCongestionController() = default;

    virtual void InitQp(Ptr<RdmaQueuePair> qp, Ptr<QbbNetDevice> dev, Ptr<RdmaHw> hw) = 0;

    virtual void EnsureSenderReady(Ptr<RdmaQueuePair> qp, Ptr<QbbNetDevice> dev,
                                   Ptr<RdmaHw> hw) = 0;

    virtual void OnCongestionFeedback(Ptr<RdmaQueuePair> qp, Ptr<Packet> p,
                                      CustomHeader &ch, Ptr<RdmaHw> hw) {
        (void)qp;
        (void)p;
        (void)ch;
        (void)hw;
    }

    virtual void OnAck(Ptr<RdmaQueuePair> qp, Ptr<Packet> p, CustomHeader &ch,
                       Ptr<RdmaHw> hw) {
        (void)qp;
        (void)p;
        (void)ch;
        (void)hw;
    }

    virtual void OnNack(Ptr<RdmaQueuePair> qp, Ptr<Packet> p, CustomHeader &ch,
                        Ptr<RdmaHw> hw) {
        (void)qp;
        (void)p;
        (void)ch;
        (void)hw;
    }

    virtual void CleanupQp(Ptr<RdmaQueuePair> qp, Ptr<RdmaHw> hw) {
        (void)qp;
        (void)hw;
    }
};
```

这个接口表达了一件事：

> RDMA sender 侧拥塞控制算法虽然不同，但它们和 `RdmaHw` 的交互时机是稳定的。

这些时机包括：

1. QP 创建；
2. 发送前确认 sender-side 状态；
3. 收到 CNP 或 congestion feedback；
4. 收到 ACK；
5. 收到 NACK；
6. QP 完成后的清理。

稳定的是事件，变化的是算法。

所以我们把稳定事件抽象成接口，把具体行为交给子类。

---

## 11. 为什么 InitQp 和 EnsureSenderReady 是纯虚函数

接口里这两个函数是纯虚函数：

```cpp
virtual void InitQp(...) = 0;
virtual void EnsureSenderReady(...) = 0;
```

这表示所有拥塞控制算法都必须实现它们。

### 11.1 InitQp

`InitQp` 在 QP 创建时调用。

每个 sender-side 拥塞控制算法都需要初始化自己的状态。例如：

1. 当前发送速率；
2. target rate；
3. alpha；
4. RTT 或 INT 相关状态；
5. 定时器；
6. QP 上挂载的算法私有状态。

所以这个函数必须由具体算法实现。

### 11.2 EnsureSenderReady

`EnsureSenderReady` 在发送前确认 sender-side CC 状态是否已经准备好。

有些状态可能不是在 QP 创建时一次性完成的，所以发送前需要兜底确认。

这个动作对所有算法都是必要的，所以也设计成纯虚函数。

---

## 12. 为什么 OnAck、OnNack、OnCongestionFeedback 有默认空实现

下面几个函数不是纯虚函数：

```cpp
OnCongestionFeedback(...)
OnAck(...)
OnNack(...)
CleanupQp(...)
```

它们都有默认空实现。

原因是不同算法关心的反馈不同。

DCQCN 主要关心 CNP，所以它重写：

```cpp
OnCongestionFeedback(...)
```

HPCC 主要关心 ACK 中携带的 INT 或 feedback，所以它重写：

```cpp
OnAck(...)
```

TIMELY 更关心 ACK 反馈中的 RTT 信息。

DCTCP 也可能主要通过 ACK 路径观察拥塞信息。

如果所有函数都设计成纯虚函数，那么每个算法都要写一堆自己不关心的空函数。

所以这里采用了更轻的设计：

> 必须支持的生命周期函数用纯虚函数；可选事件用默认空实现。

这样每个算法只需要 override 自己真正关心的事件。

---

## 13. 为什么这里必须有虚析构函数

接口第一行是：

```cpp
virtual ~IRdmaCongestionController() = default;
```

这不是装饰，而是必须的。

因为 `RdmaHw` 里保存的是：

```cpp
std::unique_ptr<IRdmaCongestionController> m_ccController;
```

但是 factory 创建的真实对象可能是：

```cpp
new DcqcnCongestionController()
new HpccCongestionController()
new TimelyCongestionController()
new DctcpCongestionController()
```

也就是说，真实对象是子类，但保存它的是父类指针。

当 `m_ccController` 被销毁时，`unique_ptr` 会自动删除它内部保存的对象。

本质上就是：

```cpp
delete IRdmaCongestionController*;
```

如果 `IRdmaCongestionController` 的析构函数不是 virtual，那么通过父类指针删除子类对象就不安全。

所以接口类必须写：

```cpp
virtual ~IRdmaCongestionController() = default;
```

这保证了以后即使某个具体 controller 增加了自己的资源，也能在销毁时正确调用子类析构函数。

---

## 14. Factory 负责创建具体算法

重构后，具体选择哪个拥塞控制算法，不放在 `RdmaHw` 主流程里，而是交给 `RdmaCcFactory`。

`rdma-cc-factory.cc` 里大致是：

```cpp
std::unique_ptr<IRdmaCongestionController> RdmaCcFactory::Create(uint32_t ccMode) {
    switch (ccMode) {
        case CC_MODE_DCQCN:
            return std::unique_ptr<IRdmaCongestionController>(new DcqcnCongestionController());

        case CC_MODE_HPCC:
            return std::unique_ptr<IRdmaCongestionController>(new HpccCongestionController());

        case CC_MODE_TIMELY:
            return std::unique_ptr<IRdmaCongestionController>(new TimelyCongestionController());

        case CC_MODE_DCTCP:
            return std::unique_ptr<IRdmaCongestionController>(new DctcpCongestionController());

        default:
            return std::unique_ptr<IRdmaCongestionController>();
    }
}
```

它的职责很单一：

> 根据 `ccMode` 创建对应的 `IRdmaCongestionController` 子类对象。

`RdmaHw` 只需要：

```cpp
m_ccController = RdmaCcFactory::Create(m_cc_mode);
```

之后就可以统一调用：

```cpp
m_ccController->OnAck(qp, p, ch, this);
m_ccController->OnNack(qp, p, ch, this);
m_ccController->OnCongestionFeedback(qp, p, ch, this);
```

这里的关键是：`m_ccController` 的类型是父类接口，但运行时实际执行哪个函数，由真实子类决定。

这就是虚函数在我们重构里的直接作用。

---

## 15. DCQCN controller 是一个 adapter

以 DCQCN 为例。

我们没有把所有 DCQCN 算法逻辑都搬进 `DcqcnCongestionController`，而是让它作为 adapter。

当前关系是：

```text
RdmaHw
  -> IRdmaCongestionController
    -> DcqcnCongestionController
      -> RdmaDcqcn
```

`DcqcnCongestionController` 的职责是把统一接口转发给旧的 `RdmaDcqcn` 实现。

例如 QP 初始化：

```cpp
void DcqcnCongestionController::InitQp(Ptr<RdmaQueuePair> qp, Ptr<QbbNetDevice> dev,
                                       Ptr<RdmaHw> hw) {
    (void)hw;
    RdmaDcqcn::InitQpState(qp, dev->GetDataRate());
}
```

发送前确认状态：

```cpp
void DcqcnCongestionController::EnsureSenderReady(Ptr<RdmaQueuePair> qp,
                                                  Ptr<QbbNetDevice> dev,
                                                  Ptr<RdmaHw> hw) {
    RdmaDcqcn::EnsureReady(qp, dev, hw);
}
```

收到 CNP：

```cpp
void DcqcnCongestionController::OnCongestionFeedback(Ptr<RdmaQueuePair> qp,
                                                     Ptr<Packet> p,
                                                     CustomHeader &ch,
                                                     Ptr<RdmaHw> hw) {
    (void)p;
    (void)ch;
    RdmaDcqcn::OnCongestionFeedback(qp, hw);
}
```

QP 完成后清理：

```cpp
void DcqcnCongestionController::CleanupQp(Ptr<RdmaQueuePair> qp, Ptr<RdmaHw> hw) {
    (void)hw;
    RdmaDcqcn::CancelQpEvents(qp);
}
```

这样做的好处是：不用一次性重写旧的 DCQCN 逻辑，也能先把它接入新的接口体系。

---

## 16. RdmaHw 现在只做事件分发

重构后，`RdmaHw` 里面和拥塞控制相关的逻辑变成了统一分发。

收到 ACK：

```cpp
void RdmaHw::OnAckForSenderCc(Ptr<RdmaQueuePair> qp, Ptr<Packet> p, CustomHeader& ch) {
    if (m_ccController) {
        m_ccController->OnAck(qp, p, ch, this);
    }
}
```

收到 NACK：

```cpp
void RdmaHw::OnNackForSenderCc(Ptr<RdmaQueuePair> qp, Ptr<Packet> p, CustomHeader& ch) {
    if (m_ccController) {
        m_ccController->OnNack(qp, p, ch, this);
    }
}
```

收到 CNP：

```cpp
void RdmaHw::DispatchCongestionFeedback(Ptr<RdmaQueuePair> qp,
                                        Ptr<Packet> p,
                                        CustomHeader& ch) {
    if (m_ccController) {
        m_ccController->OnCongestionFeedback(qp, p, ch, this);
        return;
    }
}
```

这使得 `RdmaHw` 不再需要关心当前算法到底是 DCQCN、HPCC、TIMELY 还是 DCTCP。

它只需要把事件交给统一接口。

---

## 17. ACK/NACK 和 CNP 的语义也被分开了

这次重构还配合了一个重要变化：把 transport feedback 和 congestion feedback 分开。

ACK/NACK 主要属于 transport / reliability 语义。

CNP 属于 congestion-control feedback。

现在收到 ACK/NACK 时，大致路径是：

```text
RdmaHw::ReceiveAck
-> RdmaHw::HandleAckOrNackFeedback
-> RdmaTxReliability::HandleAckOrNackTransport
-> RdmaHw::OnAckForSenderCc / OnNackForSenderCc
-> IRdmaCongestionController::OnAck / OnNack
-> 具体拥塞控制算法
```

收到 CNP 时，大致路径是：

```text
RdmaHw::Receive
-> RdmaHw::ReceiveCnp
-> RdmaHw::DispatchCongestionFeedback
-> IRdmaCongestionController::OnCongestionFeedback
-> 具体拥塞控制算法
```

这样：

```text
RdmaTxReliability 负责可靠性
IRdmaCongestionController 负责拥塞控制
```

两个模块的边界就更清楚了。

---

## 18. 新增算法时会更简单

重构后，如果要新增一个算法，比如 `Hp3CongestionController`，理想情况下只需要：

1. 新建 `rdma-hp3-controller.h/.cc`；
2. 继承 `IRdmaCongestionController`；
3. 实现 `InitQp`；
4. 实现 `EnsureSenderReady`；
5. 根据算法需要重写 `OnAck`、`OnNack` 或 `OnCongestionFeedback`；
6. 在 `RdmaCcFactory` 里注册新的 `ccMode`。

`RdmaHw` 的主流程不需要继续膨胀。

这就是这次接口重构最大的收益。

---

## 19. 总结

这次重构表面上是在写一个 C++ 接口，实际上是在重新划分 RDMA sender 侧的模块边界。

C++ 层面：

1. 父类指针可以指向子类对象；
2. 虚函数让父类指针调用到子类实现；
3. 纯虚函数适合定义必须实现的接口；
4. 析构函数负责对象销毁时的清理；
5. 虚析构函数保证通过父类指针删除子类对象时是安全的；
6. `std::unique_ptr<IRdmaCongestionController>` 自动管理 controller 生命周期。

RDMA 设计层面：

1. `RdmaHw` 负责事件分发；
2. `IRdmaCongestionController` 定义统一 sender-side 拥塞控制接口；
3. DCQCN、HPCC、TIMELY、DCTCP 各自实现自己关心的事件；
4. `RdmaCcFactory` 负责根据 `ccMode` 创建具体 controller；
5. 新增拥塞控制算法时，尽量不再修改 `RdmaHw` 主流程。

最终目标是：

> 让 RDMA 主流程稳定下来，让拥塞控制算法变成可替换、可扩展的模块。
