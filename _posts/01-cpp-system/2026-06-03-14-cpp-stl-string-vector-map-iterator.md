---
title: "C++ 系统补课 14：STL 入门：string、vector、map 和 iterator"
date: 2026-06-03 17:13:00 +0800
permalink: /posts/cpp-stl-string-vector-map-iterator/
categories: [C++, 系统补课]
tags: [cpp, stl, string, vector, map, iterator, ns3]
description: "从 string、vector、map 和 iterator 讲起，理解 C++ 标准库容器在 ns-3/RDMA 源码中的常见使用方式。"
---

<!-- series-nav -->
> **系列位置**：C++ 系统补课，第 14 篇 / 共 19 篇
> **总目录**：[学习路线](/roadmap/)
> **上一篇**：[13：编译、链接、库和构建系统](/posts/cpp-compile-link-library-build/)
> **下一篇**：[15：函数指针、成员函数指针和 lambda](/posts/cpp-function-pointer-member-pointer-lambda/)


STL 是 C++ 标准库的重要部分。

真实工程里经常使用：

```cpp
std::string
std::vector
std::map
std::set
iterator
algorithm
```

这篇先讲最常见的几个。

## 1. std::string

`std::string` 表示字符串。

```cpp
std::string name = "ns3";
```

它比 C 风格字符串更方便。

常见操作：

```cpp
name.size();
name.empty();
name + "_suffix";
```

## 2. std::vector

`std::vector<T>` 是动态数组。

```cpp
std::vector<int> xs;
xs.push_back(1);
xs.push_back(2);
```

可以用下标访问：

```cpp
int x = xs[0];
```

也可以遍历：

```cpp
for (uint32_t i = 0; i < xs.size(); i++) {
    ...
}
```

ns-3/RDMA 里常见：

```cpp
std::vector<Ptr<QbbNetDevice> >
```

表示：

```text
一个动态数组，里面存 QbbNetDevice 的 Ptr。
```

## 3. std::map

`std::map<K, V>` 是键值映射。

```cpp
std::map<uint32_t, Ptr<RdmaQueuePair> > qpMap;
```

含义：

```text
用 uint32_t 作为 key。
用 Ptr<RdmaQueuePair> 作为 value。
```

访问：

```cpp
qpMap[key]
```

查找：

```cpp
auto it = qpMap.find(key);
if (it != qpMap.end()) {
    ...
}
```

## 4. iterator

iterator 是容器里的“位置指针”。

例如：

```cpp
std::map<uint32_t, int> m;

for (auto it = m.begin(); it != m.end(); ++it) {
    uint32_t key = it->first;
    int value = it->second;
}
```

`it->first` 是 key。

`it->second` 是 value。

## 5. range-for

现代 C++ 常用：

```cpp
for (auto& item : container) {
    ...
}
```

例如：

```cpp
for (auto& it : m_qpMap) {
    Ptr<RdmaQueuePair> qp = it.second;
}
```

这里：

```text
it 是 map 中的一个 key-value 对。
it.first 是 key。
it.second 是 value。
```

## 6. auto 和 STL

STL 类型经常很长。

例如：

```cpp
std::map<uint32_t, Ptr<RdmaQueuePair> >::iterator it;
```

可以写成：

```cpp
auto it = m_qpMap.find(key);
```

但读者要主动推导：

```text
it 是 map iterator。
```

## 7. 容器里的对象生命周期

如果 vector 里存对象：

```cpp
std::vector<Packet> packets;
```

容器会保存对象本身。

如果存指针：

```cpp
std::vector<Ptr<Packet> > packets;
```

容器保存的是智能指针。

这两者生命周期含义不同。

ns-3 里常存 `Ptr<T>`，因为对象通常由引用计数管理。

## 8. 小结

STL 是工程阅读必备工具。

先掌握：

```text
string：字符串
vector：动态数组
map：键值映射
iterator：容器位置
auto：简化复杂类型
```

下一篇进入：

```text
C++ 系统补课 15：函数指针、成员函数指针和 lambda
```
