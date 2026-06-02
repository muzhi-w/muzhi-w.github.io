---
title: "彻底理解 C++ 智能指针：从 new/delete 到 RAII"
date: 2026-06-02 8:00:00 +0800
categories: [C++, 工程实践]
tags: [cpp, smart-pointer, unique_ptr, shared_ptr, weak_ptr, raii, memory-management]
description: "从裸指针、所有权和 RAII 讲起，系统理解 unique_ptr、shared_ptr、weak_ptr，以及它们在 RDMA 拥塞控制接口重构中的作用。"
---

上一篇文章里，我们从 C++ 虚函数、纯虚函数和虚析构函数讲到了 RDMA sender-side 拥塞控制接口的重构。

当时有一行代码非常关键：

```cpp
std::unique_ptr<IRdmaCongestionController> m_ccController;
```

这行代码表面上只是一个成员变量，但它背后其实牵出了一整套 C++ 对象生命周期管理的问题：

1. 为什么这里不用普通裸指针？
2. `unique_ptr` 到底帮我们做了什么？
3. 什么叫“拥有一个对象”？
4. 对象什么时候被销毁？
5. `shared_ptr` 和 `unique_ptr` 的区别是什么？
6. `weak_ptr` 又是为了解决什么问题？
7. 为什么用了智能指针，父类析构函数仍然要写成 `virtual`？

这篇文章就专门把智能指针讲清楚。

先说结论：

> 智能指针不是为了让指针语法变高级。
>
> 智能指针真正解决的是对象生命周期和所有权问题。

如果没有理解“所有权”，那 `unique_ptr`、`shared_ptr`、`weak_ptr` 都只是几个长得很像的模板类。

如果理解了“所有权”，智能指针就会变成非常自然的工具。

---

## 1. 从普通对象开始

先看最简单的对象创建方式：

```cpp
class Dog {
public:
    Dog() {
        std::cout << "Dog created\n";
    }

    ~Dog() {
        std::cout << "Dog destroyed\n";
    }

    void Speak() {
        std::cout << "Dog barks\n";
    }
};
```

如果这样写：

```cpp
void Test() {
    Dog d;
    d.Speak();
}
```

这里的 `d` 是一个普通局部对象。

它的生命周期很清楚：

```text
进入 Test()
创建 Dog d
调用 d.Speak()
离开 Test()
自动调用 d 的析构函数
```

也就是说：

```cpp
Dog d;
```

这种写法不需要手动释放对象。

`d` 离开作用域时，C++ 会自动调用：

```cpp
Dog::~Dog()
```

所以普通局部对象最大的优点是：

```text
生命周期跟作用域绑定。
```

这句话非常重要，因为后面的智能指针也是建立在这个思想上。

---

## 2. 用 new 创建对象

有时我们会这样创建对象：

```cpp
Dog* d = new Dog();
d->Speak();
delete d;
```

这里发生了几件事：

```cpp
new Dog()
```

会在堆上创建一个 `Dog` 对象，并返回这个对象的地址。

```cpp
Dog* d
```

只是一个指针变量，它保存这个地址。

所以：

```text
d 不是 Dog 对象本身。
d 只是 Dog 对象的地址。
```

因为对象是用 `new` 创建的，所以后面必须写：

```cpp
delete d;
```

`delete d` 会做两件事：

1. 调用 `Dog` 的析构函数；
2. 释放堆上的内存。

如果忘了写 `delete`，对象的析构函数不会执行，堆内存也不会释放。

这就是内存泄漏。

---

## 3. 裸指针的问题不是“指针”，而是“所有权不清楚”

看这段代码：

```cpp
Dog* d = new Dog();
```

现在问一个问题：

```text
谁负责 delete 这个 Dog？
```

从代码上看，答案并不明显。

也许是当前函数负责：

```cpp
void Test() {
    Dog* d = new Dog();
    d->Speak();
    delete d;
}
```

也许是另一个函数负责：

```cpp
void DestroyDog(Dog* d) {
    delete d;
}

void Test() {
    Dog* d = new Dog();
    DestroyDog(d);
}
```

也许是某个类负责：

```cpp
class Kennel {
public:
    Kennel(Dog* dog)
        : m_dog(dog) {}

    ~Kennel() {
        delete m_dog;
    }

private:
    Dog* m_dog;
};
```

问题在于：

```cpp
Dog* d
```

这个类型本身只说明：

```text
d 是一个指向 Dog 的指针。
```

但它没有说明：

```text
d 是否拥有这个 Dog？
d 是否负责 delete 这个 Dog？
d 能不能是 nullptr？
d 指向的 Dog 会不会已经被别人释放？
```

这就是裸指针最麻烦的地方：

> 裸指针只表达“指向”，不表达“拥有”。

而智能指针最重要的价值就是：

> 智能指针把“所有权”写进了类型里。

---

## 4. 什么是所有权

“所有权”这个词听起来有点抽象，但它其实就是一个很朴素的问题：

```text
谁负责销毁这个对象？
```

如果一个对象由某段代码负责销毁，我们就说这段代码拥有这个对象。

比如：

```cpp
Dog* d = new Dog();
```

如果当前函数最后会写：

```cpp
delete d;
```

那当前函数就拥有这个对象。

如果当前函数只是临时用一下：

```cpp
void PrintDog(Dog* d) {
    d->Speak();
}
```

那 `PrintDog` 并不拥有这个对象。

它只是借用这个对象。

所以指针有两种完全不同的语义：

```text
拥有对象的指针：负责 delete。
不拥有对象的指针：只是临时访问，不负责 delete。
```

裸指针的问题是，这两种语义都可以写成：

```cpp
Dog* d
```

类型一样，但含义完全不同。

这会让代码越来越难维护。

---

## 5. new/delete 最容易出错的地方

假设我们写一段代码：

```cpp
void ProcessDog() {
    Dog* d = new Dog();

    d->Speak();

    delete d;
}
```

看起来没问题。

但是只要逻辑稍微复杂一点，问题就来了。

比如中途提前返回：

```cpp
void ProcessDog(bool failed) {
    Dog* d = new Dog();

    if (failed) {
        return;
    }

    d->Speak();

    delete d;
}
```

如果 `failed == true`，函数会直接 `return`。

这时：

```cpp
delete d;
```

不会执行。

对象泄漏了。

再比如异常：

```cpp
void ProcessDog() {
    Dog* d = new Dog();

    MayThrow();

    d->Speak();

    delete d;
}
```

如果 `MayThrow()` 抛出异常，函数会提前离开，`delete d` 也不会执行。

对象又泄漏了。

为了修补这个问题，我们可能会写很多清理逻辑：

```cpp
void ProcessDog(bool failed) {
    Dog* d = new Dog();

    if (failed) {
        delete d;
        return;
    }

    d->Speak();

    delete d;
}
```

但这样代码会越来越脆弱。

只要多一个分支，就要记得多写一次 `delete`。

这不是一个好的工程模型。

好的工程模型应该是：

```text
资源释放不依赖程序员记性。
资源释放应该由对象生命周期自动触发。
```

这就是 RAII。

---

## 6. RAII 是什么

RAII 全称是：

```text
Resource Acquisition Is Initialization
```

直译是：

```text
资源获取即初始化
```

这个名字不太直观。

可以更简单地理解成：

```text
把资源交给一个对象管理。
对象构造时拿到资源。
对象析构时释放资源。
```

比如写一个简单的数组管理类：

```cpp
class IntBuffer {
public:
    explicit IntBuffer(std::size_t n)
        : m_data(new int[n]) {}

    ~IntBuffer() {
        delete[] m_data;
    }

    int* Data() {
        return m_data;
    }

private:
    int* m_data;
};
```

现在这样用：

```cpp
void Test(bool failed) {
    IntBuffer buffer(100);

    if (failed) {
        return;
    }

    buffer.Data()[0] = 1;
}
```

即使中途 `return`，`buffer` 离开作用域时也会自动调用析构函数。

析构函数里会执行：

```cpp
delete[] m_data;
```

所以资源不会泄漏。

这就是 RAII 的核心：

```text
不要让资源裸奔。
把资源包进一个对象里。
利用对象析构函数自动释放资源。
```

智能指针就是 RAII 的典型应用。

---

## 7. unique_ptr：独占所有权

最常用的智能指针之一是：

```cpp
std::unique_ptr
```

使用它需要包含头文件：

```cpp
#include <memory>
```

最简单的例子：

```cpp
#include <memory>

void Test() {
    std::unique_ptr<Dog> d(new Dog());
    d->Speak();
}
```

这里没有写：

```cpp
delete d;
```

但是 `Dog` 对象仍然会被销毁。

原因是：

```text
d 是一个局部对象。
d 离开作用域时，std::unique_ptr<Dog> 的析构函数会自动执行。
unique_ptr 的析构函数内部会 delete 它管理的 Dog 对象。
```

所以这段代码相当于把：

```cpp
delete d;
```

交给 `unique_ptr` 自动完成。

---

## 8. unique_ptr 解决了提前 return 的问题

再看前面的泄漏例子。

原来是：

```cpp
void ProcessDog(bool failed) {
    Dog* d = new Dog();

    if (failed) {
        return;
    }

    d->Speak();

    delete d;
}
```

改成 `unique_ptr`：

```cpp
void ProcessDog(bool failed) {
    std::unique_ptr<Dog> d(new Dog());

    if (failed) {
        return;
    }

    d->Speak();
}
```

现在即使 `failed == true`，函数提前返回，`d` 也会离开作用域。

于是 `unique_ptr` 的析构函数会执行，并自动删除内部的 `Dog` 对象。

这个模型比手写 `delete` 稳定得多。

因为资源释放不再分散在各个分支里，而是集中到对象析构过程里。

---

## 9. make_unique：更推荐的创建方式

现代 C++ 更推荐这样写：

```cpp
auto d = std::make_unique<Dog>();
```

而不是：

```cpp
std::unique_ptr<Dog> d(new Dog());
```

完整例子：

```cpp
void Test() {
    auto d = std::make_unique<Dog>();
    d->Speak();
}
```

`std::make_unique<Dog>()` 会创建一个 `Dog` 对象，并返回：

```cpp
std::unique_ptr<Dog>
```

这种写法更简洁，也更不容易在复杂表达式里出错。

### 9.1 unique_ptr 的几种创建语法

先看 C++11 里最基础的写法：

```cpp
std::unique_ptr<Dog> d(new Dog());
```

这句话可以拆成两部分：

```cpp
new Dog()
```

表示在堆上创建一个 `Dog` 对象，并返回它的裸指针。

```cpp
std::unique_ptr<Dog>(...)
```

表示创建一个 `unique_ptr<Dog>`，让它接管这个裸指针。

所以完整语义是：

```text
创建一个 Dog 对象。
立刻交给 unique_ptr<Dog> 管理。
以后不用手动 delete。
```

也可以写成直接初始化：

```cpp
std::unique_ptr<Dog> d(new Dog());
```

或者临时对象写法：

```cpp
std::unique_ptr<Dog>(new Dog())
```

第二种经常出现在 `return` 语句里：

```cpp
std::unique_ptr<Dog> CreateDog() {
    return std::unique_ptr<Dog>(new Dog());
}
```

注意，不要写成：

```cpp
std::unique_ptr<Dog> d = new Dog();  // 错误写法
```

`new Dog()` 返回的是裸指针 `Dog*`，而左边需要的是 `std::unique_ptr<Dog>`。

`unique_ptr` 的构造函数是显式的，所以应该明确写出：

```cpp
std::unique_ptr<Dog> d(new Dog());
```

或者在 C++14 之后写：

```cpp
auto d = std::make_unique<Dog>();
```

如果涉及多态，也可以让父类智能指针管理子类对象：

```cpp
std::unique_ptr<Animal> a(new Dog());
```

这里真实对象是 `Dog`，但智能指针类型是：

```cpp
std::unique_ptr<Animal>
```

这要求 `Dog` 继承自 `Animal`。

如果以后通过 `Animal*` 销毁真实的 `Dog` 对象，`Animal` 的析构函数还应该是 `virtual`。

不过要注意：

```text
std::make_unique 是 C++14 引入的。
```

如果项目还停留在 C++11，就可能需要写：

```cpp
std::unique_ptr<Dog> d(new Dog());
```

你现在看的 ns-3 老版本代码里，经常会看到这种写法。

这不是因为 `make_unique` 不好，而是因为老项目的 C++ 标准可能比较旧。

---

## 10. unique_ptr 的核心语义：唯一拥有者

`unique_ptr` 里的 `unique` 很关键。

它表示：

```text
同一时刻只能有一个 unique_ptr 拥有这个对象。
```

比如：

```cpp
std::unique_ptr<Dog> d1 = std::make_unique<Dog>();
std::unique_ptr<Dog> d2 = d1;  // 编译错误
```

为什么不能拷贝？

因为如果允许拷贝，就会出现两个 `unique_ptr` 同时认为自己拥有同一个 `Dog`：

```text
d1 觉得自己负责 delete Dog
d2 也觉得自己负责 delete Dog
```

那最后就可能发生重复释放。

所以 `unique_ptr` 禁止拷贝。

它用类型系统强制表达：

```text
这个对象只能有一个拥有者。
```

---

## 11. unique_ptr 可以移动

虽然 `unique_ptr` 不能拷贝，但它可以移动。

移动表示：

```text
把所有权从一个 unique_ptr 转移给另一个 unique_ptr。
```

例如：

```cpp
std::unique_ptr<Dog> d1 = std::make_unique<Dog>();
std::unique_ptr<Dog> d2 = std::move(d1);
```

执行之后：

```text
d2 拥有 Dog 对象。
d1 不再拥有 Dog 对象。
```

通常此时：

```cpp
d1 == nullptr
```

所以移动不是复制一份对象。

移动只是转移所有权。

可以粗略理解成：

```text
d1 把钥匙交给 d2。
d1 自己不再有钥匙。
```

在代码里，移动所有权经常用于函数返回。

例如：

```cpp
std::unique_ptr<Dog> CreateDog() {
    return std::make_unique<Dog>();
}

void Test() {
    std::unique_ptr<Dog> d = CreateDog();
    d->Speak();
}
```

`CreateDog()` 创建对象，然后把所有权交给调用者。

这非常适合工厂函数。

---

## 12. unique_ptr 作为函数参数

函数参数里的 `unique_ptr` 很有表达力。

如果函数这样写：

```cpp
void UseDog(Dog* d) {
    d->Speak();
}
```

它表达的是：

```text
UseDog 临时使用 Dog。
UseDog 不负责销毁 Dog。
```

如果这样写：

```cpp
void UseDog(Dog& d) {
    d.Speak();
}
```

它表达的是：

```text
UseDog 临时使用 Dog。
Dog 必须存在，不能是 nullptr。
UseDog 不负责销毁 Dog。
```

如果这样写：

```cpp
void TakeDog(std::unique_ptr<Dog> d) {
    d->Speak();
}
```

含义就完全不同了：

```text
TakeDog 接管 Dog 的所有权。
调用者把 Dog 交出去了。
TakeDog 结束时，如果没有继续转移所有权，Dog 会被销毁。
```

调用时必须显式移动：

```cpp
std::unique_ptr<Dog> d = std::make_unique<Dog>();
TakeDog(std::move(d));
```

`std::move(d)` 的含义是：

```text
我愿意把 d 拥有的对象交出去。
```

这种写法很好，因为所有权转移在代码里非常明显。

---

## 13. get、release 和 reset

`unique_ptr` 还有几个常见成员函数。

第一个是 `get()`：

```cpp
std::unique_ptr<Dog> d = std::make_unique<Dog>();
Dog* raw = d.get();
```

`get()` 返回内部裸指针。

但是注意：

```text
raw 不拥有对象。
raw 不能 delete。
```

它只是临时观察 `unique_ptr` 管理的对象。

第二个是 `reset()`：

```cpp
d.reset();
```

这会删除当前管理的对象，并让 `d` 变成空。

也可以让它管理一个新对象：

```cpp
d.reset(new Dog());
```

第三个是 `release()`：

```cpp
Dog* raw = d.release();
```

`release()` 会放弃所有权，并返回内部裸指针。

执行之后：

```text
d 不再拥有 Dog。
raw 变成需要手动 delete 的裸指针。
```

所以 `release()` 要非常小心。

除非你明确要把对象交给某个只能接收裸指针的旧接口，否则尽量少用。

---

## 14. unique_ptr 和多态

智能指针和多态经常一起出现。

比如：

```cpp
class Animal {
public:
    virtual ~Animal() = default;
    virtual void Speak() = 0;
};

class Dog : public Animal {
public:
    void Speak() override {
        std::cout << "Dog barks\n";
    }
};
```

现在可以写：

```cpp
std::unique_ptr<Animal> a = std::make_unique<Dog>();
a->Speak();
```

虽然 `a` 的静态类型是：

```cpp
std::unique_ptr<Animal>
```

但它内部真实管理的是一个：

```cpp
Dog
```

调用：

```cpp
a->Speak();
```

会通过虚函数机制调用：

```cpp
Dog::Speak()
```

这就是智能指针和多态结合的典型写法。

不过这里还有一个非常重要的点：

```cpp
class Animal {
public:
    virtual ~Animal() = default;
};
```

析构函数必须是 `virtual`。

因为 `unique_ptr<Animal>` 销毁时，本质上会通过 `Animal*` 删除内部对象。

如果真实对象是 `Dog`，但 `Animal` 的析构函数不是虚函数，那么通过 `Animal*` 删除 `Dog` 对象是不安全的。

所以规则是：

> 只要基类准备被多态使用，并且对象可能通过基类指针销毁，基类析构函数就应该是 virtual。

这和上一篇文章里的 `IRdmaCongestionController` 完全对应。

---

## 15. shared_ptr：共享所有权

`unique_ptr` 表示独占所有权。

但有些场景里，一个对象确实需要被多个地方共同持有。

这时可以使用：

```cpp
std::shared_ptr
```

例子：

```cpp
std::shared_ptr<Dog> d1 = std::make_shared<Dog>();
std::shared_ptr<Dog> d2 = d1;
```

这里 `d1` 和 `d2` 共同拥有同一个 `Dog` 对象。

`shared_ptr` 内部有一个引用计数。

可以粗略理解成：

```text
有几个 shared_ptr 正在拥有这个对象？
```

上面的代码执行后：

```text
引用计数是 2。
```

当 `d1` 销毁时：

```text
引用计数从 2 变成 1。
对象还不能销毁。
```

当 `d2` 也销毁时：

```text
引用计数从 1 变成 0。
最后一个拥有者没了。
对象销毁。
```

所以 `shared_ptr` 的语义是：

```text
多个 shared_ptr 共享一个对象。
最后一个 shared_ptr 消失时，对象自动销毁。
```

---

## 16. make_shared

创建 `shared_ptr` 时，通常推荐：

```cpp
auto d = std::make_shared<Dog>();
```

而不是：

```cpp
std::shared_ptr<Dog> d(new Dog());
```

`make_shared` 通常更简洁，也更高效。

因为 `shared_ptr` 除了管理对象本身，还需要管理一块控制信息，比如引用计数。

`make_shared` 可以把对象和控制信息一起分配，减少一次内存分配。

普通使用时，优先写：

```cpp
auto p = std::make_shared<T>(args...);
```

---

## 17. shared_ptr 不是“更安全的 unique_ptr”

很多人刚学智能指针时，会觉得：

```text
shared_ptr 好像更强。
既然可以共享，那是不是都用 shared_ptr 就行？
```

不是。

`shared_ptr` 不是默认选择。

默认更应该先想：

```text
这个对象有没有唯一明确的拥有者？
```

如果有，用 `unique_ptr`。

只有当对象确实需要多个拥有者共同延长生命周期时，才用 `shared_ptr`。

原因有几个。

第一，`shared_ptr` 的语义更复杂。

看到：

```cpp
std::shared_ptr<Dog> d;
```

你就要问：

```text
谁还持有这个 Dog？
这个 Dog 到底什么时候释放？
有没有循环引用？
```

第二，`shared_ptr` 有额外开销。

它需要维护引用计数。

第三，`shared_ptr` 容易让所有权变模糊。

如果很多地方都拿着 `shared_ptr`，那么对象生命周期会被拉得很长。

最后可能没人能清楚地说：

```text
这个对象到底应该归谁管？
```

所以一个实用规则是：

```text
能用 unique_ptr，就不要先用 shared_ptr。
确实需要共享所有权，再用 shared_ptr。
```

---

## 18. shared_ptr 作为函数参数

函数参数里的 `shared_ptr` 也应该表达清楚语义。

如果函数只是临时使用对象，不应该随手传 `shared_ptr`：

```cpp
void PrintDog(std::shared_ptr<Dog> d) {
    d->Speak();
}
```

这样写会拷贝一份 `shared_ptr`，引用计数会增加。

它表达的是：

```text
PrintDog 在执行期间也共享拥有这个 Dog。
```

如果只是临时访问，通常更适合：

```cpp
void PrintDog(const Dog& d) {
    d.Speak();
}
```

或者对象可以为空时：

```cpp
void PrintDog(const Dog* d) {
    if (d != nullptr) {
        d->Speak();
    }
}
```

如果函数确实要保存一份 `shared_ptr`，让对象生命周期延长，那传 `shared_ptr` 才合理：

```cpp
class DogPrinter {
public:
    explicit DogPrinter(std::shared_ptr<Dog> dog)
        : m_dog(dog) {}

    void Print() {
        m_dog->Speak();
    }

private:
    std::shared_ptr<Dog> m_dog;
};
```

这里 `DogPrinter` 确实需要共享拥有 `Dog`。

所以 `shared_ptr` 是合理的。

---

## 19. shared_ptr 的循环引用问题

`shared_ptr` 最大的经典坑是循环引用。

比如有两个类：

```cpp
class B;

class A {
public:
    std::shared_ptr<B> b;
};

class B {
public:
    std::shared_ptr<A> a;
};
```

然后这样创建：

```cpp
std::shared_ptr<A> pa = std::make_shared<A>();
std::shared_ptr<B> pb = std::make_shared<B>();

pa->b = pb;
pb->a = pa;
```

现在引用关系是：

```text
pa 拥有 A
pb 拥有 B
A 通过 shared_ptr 拥有 B
B 通过 shared_ptr 拥有 A
```

当函数结束时，局部变量 `pa` 和 `pb` 销毁。

但是：

```text
A 里面还持有 B
B 里面还持有 A
```

于是引用计数都不会变成 0。

两个对象互相拉住对方，谁都释放不了。

这就是循环引用。

解决这个问题需要：

```cpp
std::weak_ptr
```

---

## 20. weak_ptr：观察但不拥有

`weak_ptr` 的核心语义是：

```text
我知道这个对象，但我不拥有它。
```

它必须配合 `shared_ptr` 使用。

比如把刚才的代码改成：

```cpp
class B;

class A {
public:
    std::shared_ptr<B> b;
};

class B {
public:
    std::weak_ptr<A> a;
};
```

现在：

```text
A 拥有 B。
B 只是观察 A。
```

`B` 里面的 `weak_ptr<A>` 不会增加 `A` 的引用计数。

所以当外部 `shared_ptr<A>` 消失时，`A` 可以正常销毁。

`weak_ptr` 不能直接使用对象。

要先调用：

```cpp
lock()
```

例如：

```cpp
std::weak_ptr<A> weakA = pa;

if (std::shared_ptr<A> locked = weakA.lock()) {
    // 对象还活着，可以安全使用
} else {
    // 对象已经销毁
}
```

`lock()` 的意思是：

```text
如果对象还活着，就临时拿到一个 shared_ptr。
如果对象已经没了，就得到空 shared_ptr。
```

所以 `weak_ptr` 适合表达：

```text
我需要知道这个对象。
但我不应该延长它的生命周期。
```

---

## 21. 三种智能指针的区别

可以用一句话区分：

```text
unique_ptr：我独占这个对象。
shared_ptr：我们共同拥有这个对象。
weak_ptr：我观察这个对象，但不拥有它。
```

再具体一点：

| 类型 | 所有权语义 | 能否拷贝 | 何时销毁对象 | 典型用途 |
| --- | --- | --- | --- | --- |
| `std::unique_ptr<T>` | 独占所有权 | 不能拷贝，只能移动 | `unique_ptr` 销毁或 reset 时 | 一个对象有唯一拥有者 |
| `std::shared_ptr<T>` | 共享所有权 | 可以拷贝 | 最后一个 `shared_ptr` 销毁时 | 多个地方共同拥有对象 |
| `std::weak_ptr<T>` | 不拥有，只观察 | 可以拷贝 | 不影响对象生命周期 | 打破循环引用、缓存观察 |

选择时可以按这个顺序想：

```text
1. 这个对象能不能放在栈上？
2. 如果必须动态分配，它有没有唯一拥有者？
3. 如果有，用 unique_ptr。
4. 如果确实需要多个拥有者，用 shared_ptr。
5. 如果只是观察 shared_ptr 管理的对象，用 weak_ptr。
```

很多时候，正确答案其实是第一条：

```cpp
Dog d;
```

能用普通对象，就不用动态分配。

智能指针不是为了替代所有对象创建方式。

它是为了管理那些确实需要动态生命周期的对象。

---

## 22. 智能指针不是垃圾回收

智能指针经常让人想到垃圾回收，但它们不是同一个东西。

垃圾回收通常是运行时系统自动发现哪些对象已经不可达，然后回收它们。

C++ 智能指针不是这样。

`unique_ptr` 的释放时机非常明确：

```text
unique_ptr 离开作用域时释放。
```

`shared_ptr` 的释放时机也很明确：

```text
最后一个 shared_ptr 消失时释放。
```

所以智能指针仍然是确定性的资源管理。

这对 C++ 很重要。

因为 C++ 管理的不只是内存，还可能是：

1. 文件句柄；
2. socket；
3. 锁；
4. 定时事件；
5. GPU 资源；
6. 仿真器里的状态对象。

这些资源很多都需要在确定时机释放。

RAII 的价值就在这里。

---

## 23. 常见错误一：同一个裸指针交给两个智能指针

这是一种非常危险的写法：

```cpp
Dog* raw = new Dog();

std::unique_ptr<Dog> d1(raw);
std::unique_ptr<Dog> d2(raw);
```

现在 `d1` 和 `d2` 都以为自己拥有这个 `Dog`。

当它们销毁时，会对同一块内存执行两次 `delete`。

这是严重错误。

`shared_ptr` 也有类似问题：

```cpp
Dog* raw = new Dog();

std::shared_ptr<Dog> d1(raw);
std::shared_ptr<Dog> d2(raw);
```

很多人以为：

```text
两个 shared_ptr 指向同一个裸指针，所以它们会共享引用计数。
```

但实际上不是。

这样会创建两个独立的控制块。

`d1` 有自己的引用计数。

`d2` 也有自己的引用计数。

它们都认为自己是唯一一组拥有者。

最后同样可能重复释放。

正确做法是：

```cpp
std::shared_ptr<Dog> d1 = std::make_shared<Dog>();
std::shared_ptr<Dog> d2 = d1;
```

也就是说：

```text
先创建一个 shared_ptr，再从这个 shared_ptr 拷贝。
```

---

## 24. 常见错误二：滥用 shared_ptr

看到内存管理问题后，有人会干脆所有地方都用 `shared_ptr`。

这并不好。

比如：

```cpp
class RdmaHw {
private:
    std::shared_ptr<IRdmaCongestionController> m_ccController;
};
```

如果 controller 只属于一个 `RdmaHw`，那这就不是最准确的表达。

因为 `shared_ptr` 暗示：

```text
这个 controller 可能被多个地方共同拥有。
```

但真实语义是：

```text
RdmaHw 拥有它自己的 controller。
外部不应该共同拥有这个 controller。
```

这时更好的类型是：

```cpp
std::unique_ptr<IRdmaCongestionController> m_ccController;
```

类型本身就把设计意图说清楚了。

代码的可维护性也更好。

---

## 25. 常见错误三：以为用了智能指针就不需要 virtual 析构函数

这是一个很容易混淆的点。

假设：

```cpp
class Animal {
public:
    virtual void Speak() = 0;
};

class Dog : public Animal {
public:
    ~Dog() {
        std::cout << "Dog destroyed\n";
    }

    void Speak() override {
        std::cout << "Dog barks\n";
    }
};
```

然后：

```cpp
std::unique_ptr<Animal> a = std::make_unique<Dog>();
```

这里 `unique_ptr<Animal>` 最后会删除一个 `Animal*`。

但真实对象是 `Dog`。

如果 `Animal` 的析构函数不是虚函数，那么销毁过程是不安全的。

正确写法是：

```cpp
class Animal {
public:
    virtual ~Animal() = default;
    virtual void Speak() = 0;
};
```

要注意一个细节：

`shared_ptr` 在某些构造方式下会保存更具体的删除器，因此有时看起来即使基类析构函数不是 `virtual`，也能正确销毁子类。

但不要依赖这种细节来设计多态基类。

工程上更清晰、更稳妥的规则仍然是：

> 多态基类应该有 virtual 析构函数。

尤其是接口类。

---

## 26. 常见错误四：返回局部对象的地址

智能指针还容易和另一个经典错误放在一起讨论。

错误写法：

```cpp
Dog* CreateDog() {
    Dog d;
    return &d;
}
```

这里 `d` 是局部对象。

函数返回时，`d` 已经销毁了。

返回它的地址没有意义。

正确方式之一是直接返回对象：

```cpp
Dog CreateDog() {
    Dog d;
    return d;
}
```

现代 C++ 会通过返回值优化或移动语义处理得很好。

如果确实需要动态分配，并且要把所有权交给调用者，可以返回 `unique_ptr`：

```cpp
std::unique_ptr<Dog> CreateDog() {
    return std::make_unique<Dog>();
}
```

这个函数的语义非常清楚：

```text
CreateDog 创建一个 Dog。
调用者获得这个 Dog 的唯一所有权。
```

---

## 27. 常见错误五：把 get() 得到的指针 delete 掉

错误写法：

```cpp
std::unique_ptr<Dog> d = std::make_unique<Dog>();

Dog* raw = d.get();
delete raw;  // 错误
```

`raw` 只是观察指针。

真正拥有对象的是 `d`。

如果手动 `delete raw`，后面 `d` 析构时还会再 delete 一次。

所以规则是：

```text
从智能指针 get() 出来的裸指针，不能手动 delete。
```

如果你只是要传给一个不接管所有权的旧接口，可以这样：

```cpp
LegacyUseDog(d.get());
```

但这个旧接口不能保存这个指针并在以后使用，除非你能保证智能指针活得更久。

---

## 28. 回到 RDMA 拥塞控制接口

现在回到我们的代码。

重构之后，`RdmaHw` 里有一个成员：

```cpp
std::unique_ptr<IRdmaCongestionController> m_ccController;
```

这行代码表达了非常明确的设计：

```text
RdmaHw 拥有一个拥塞控制器。
这个拥塞控制器只属于这个 RdmaHw。
RdmaHw 销毁时，controller 自动销毁。
外部不应该共同拥有这个 controller。
```

所以这里用 `unique_ptr` 是自然的。

如果用裸指针：

```cpp
IRdmaCongestionController* m_ccController;
```

那就会出现很多问题：

```text
谁 new？
谁 delete？
RdmaHw 析构时要不要 delete？
初始化失败时怎么办？
中途切换算法时怎么办？
如果忘记 delete 会不会泄漏？
```

这些问题会污染 `RdmaHw` 的主逻辑。

而 `unique_ptr` 把这些问题收束起来：

```text
m_ccController 拥有 controller。
m_ccController 析构时释放 controller。
```

---

## 29. 为什么 factory 返回 unique_ptr

你的 factory 逻辑大概是这样的：

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

它的语义是：

```text
factory 根据 ccMode 创建一个具体 controller。
然后把这个 controller 的所有权交给调用者。
```

调用者一般是：

```cpp
m_ccController = RdmaCcFactory::Create(m_cc_mode);
```

也就是说：

```text
RdmaCcFactory 负责创建。
RdmaHw 接收所有权。
RdmaHw 之后负责拥有和销毁。
```

这种所有权流动非常清楚。

单独看这一句：

```cpp
return std::unique_ptr<IRdmaCongestionController>(new DcqcnCongestionController());
```

它其实可以拆成三步理解。

第一步：

```cpp
new DcqcnCongestionController()
```

在堆上创建一个真正的 `DcqcnCongestionController` 对象。

这个表达式返回的是一个裸指针：

```cpp
DcqcnCongestionController*
```

第二步：

```cpp
std::unique_ptr<IRdmaCongestionController>(...)
```

创建一个 `unique_ptr` 临时对象，让它接管刚才 `new` 出来的 controller。

虽然真实对象是：

```cpp
DcqcnCongestionController
```

但因为 `DcqcnCongestionController` 继承了：

```cpp
IRdmaCongestionController
```

所以可以用父类智能指针来管理子类对象：

```cpp
std::unique_ptr<IRdmaCongestionController>
```

第三步：

```cpp
return ...
```

把这个 `unique_ptr` 返回给调用者。

如果写得啰嗦一点，大概相当于：

```cpp
std::unique_ptr<IRdmaCongestionController> RdmaCcFactory::Create(uint32_t ccMode) {
    IRdmaCongestionController* raw = new DcqcnCongestionController();
    std::unique_ptr<IRdmaCongestionController> controller(raw);
    return controller;
}
```

真实代码里不这样拆开写，是因为一行就能清楚表达：

```text
new 出一个具体 controller。
立刻交给 unique_ptr 管理。
把 unique_ptr 返回出去。
```

然后调用方：

```cpp
m_ccController = RdmaCcFactory::Create(m_cc_mode);
```

会把这个返回的 `unique_ptr` 移动到 `RdmaHw` 的成员变量 `m_ccController` 里。

从这一刻开始，controller 就归 `RdmaHw` 管了。

当 `m_ccController` 被销毁或被重新赋值时，旧 controller 会自动销毁。

如果项目支持 C++14，也可以写得更现代：

```cpp
return std::make_unique<DcqcnCongestionController>();
```

但在老项目里，使用：

```cpp
std::unique_ptr<IRdmaCongestionController>(new DcqcnCongestionController())
```

也是合理的。

---

## 30. 为什么这里不用 shared_ptr

再问一个问题：

```text
m_ccController 为什么不是 shared_ptr？
```

因为 controller 不需要共享所有权。

拥塞控制器是 `RdmaHw` 的内部策略对象。

它的生命周期应该跟着 `RdmaHw` 走。

外部模块最多只是通过 `RdmaHw` 间接触发它的行为，不应该共同拥有它。

如果使用：

```cpp
std::shared_ptr<IRdmaCongestionController> m_ccController;
```

就会给读代码的人一个暗示：

```text
也许别的地方也会持有这个 controller。
也许这个 controller 会活得比 RdmaHw 更久。
```

但这不是我们想表达的。

所以 `unique_ptr` 更准确。

好的类型不是越强越好，而是越贴近语义越好。

---

## 31. ns-3 里的 Ptr 和 std::unique_ptr

在 ns-3 代码里，你还会经常看到：

```cpp
Ptr<RdmaQueuePair> qp
Ptr<QbbNetDevice> dev
Ptr<RdmaHw> hw
```

这是 ns-3 自己的智能指针 `Ptr<T>`。

它和 `std::unique_ptr` 不是同一个东西。

`Ptr<T>` 通常配合 ns-3 的对象引用计数机制使用。

它更接近一种引用计数智能指针。

而：

```cpp
std::unique_ptr<IRdmaCongestionController>
```

表达的是标准 C++ 的独占所有权。

在你的重构里，两者的角色不同：

```text
Ptr<RdmaQueuePair>：ns-3 对仿真对象的引用管理。
std::unique_ptr<IRdmaCongestionController>：RdmaHw 独占拥有一个策略对象。
```

所以不要看到都是“指针”就把它们混在一起。

关键还是看所有权语义。

---

## 32. 智能指针选择规则

最后总结一套实用判断规则。

第一，能不用动态分配，就不用动态分配。

```cpp
Dog d;
```

这种写法最简单。

第二，如果对象需要动态分配，并且只有一个拥有者，用 `unique_ptr`。

```cpp
std::unique_ptr<Dog> d = std::make_unique<Dog>();
```

第三，如果对象要从函数返回，并交给调用者拥有，用 `unique_ptr`。

```cpp
std::unique_ptr<Dog> CreateDog();
```

第四，如果多个地方确实需要共同拥有对象，用 `shared_ptr`。

```cpp
std::shared_ptr<Dog> d = std::make_shared<Dog>();
```

第五，如果只是观察 `shared_ptr` 管理的对象，不想延长它的生命周期，用 `weak_ptr`。

```cpp
std::weak_ptr<Dog> weakDog = d;
```

第六，如果只是临时使用对象，不要为了省事传智能指针。

可以传引用：

```cpp
void UseDog(Dog& d);
```

或者传裸指针表示可以为空：

```cpp
void UseDog(Dog* d);
```

第七，多态基类要有虚析构函数。

```cpp
class Interface {
public:
    virtual ~Interface() = default;
};
```

---

## 33. 总结

智能指针要解决的核心问题不是“怎么让指针更好看”，而是：

```text
对象由谁拥有？
对象什么时候销毁？
资源释放能不能自动发生？
所有权转移能不能在类型里表达出来？
```

`unique_ptr` 表达独占所有权。

`shared_ptr` 表达共享所有权。

`weak_ptr` 表达观察但不拥有。

RAII 则是它们背后的思想：

```text
资源交给对象管理。
对象构造时获得资源。
对象析构时释放资源。
```

回到 RDMA 拥塞控制重构：

```cpp
std::unique_ptr<IRdmaCongestionController> m_ccController;
```

这行代码真正表达的是：

```text
RdmaHw 独占拥有一个拥塞控制器。
controller 的具体类型可以是 DCQCN、HPCC、TIMELY 或 DCTCP。
RdmaHw 不需要手写 delete。
controller 会随着 m_ccController 自动销毁。
因为它通过接口基类销毁，所以 IRdmaCongestionController 必须有 virtual 析构函数。
```

理解到这里，智能指针就不再只是语法，而是 C++ 工程设计里表达生命周期和所有权的工具。
