---
layout: page
title: 学习路线
icon: fas fa-route
order: 2
permalink: /roadmap/
---

这页是整个博客的入口。

博客内容按三条主线组织：

```text
第一条线：C++ 系统补课
第二条线：ns-3 源码阅读
第三条线：RDMA / DCQCN 项目源码与模型
```

读者不需要按发布时间阅读。更推荐按下面的路线走。

## 1. C++ 系统补课

这一组文章从零开始建立 C++ 地基，目标是读懂 ns-3/RDMA 源码。

1. [00：从零建立 C++ 知识地图](/posts/cpp-systematic-learning-map/)
2. [01：程序、变量、类型和值](/posts/cpp-program-variable-type-value/)
3. [02：内存、地址和指针](/posts/cpp-memory-address-pointer/)
4. [03：引用、const 引用和函数参数](/posts/cpp-reference-const-reference-parameters/)
5. [04：函数、返回值和参数传递](/posts/cpp-functions-return-parameters/)
6. [05：const：从 const int 到 const 成员函数](/posts/cpp-const-from-variable-to-member-function/)
7. [06：class 和 struct：对象到底是什么](/posts/cpp-class-struct-object/)
8. [07：构造函数、初始化列表和 this 指针](/posts/cpp-constructor-initializer-this/)
9. [08：析构函数、栈对象、堆对象和 RAII](/posts/cpp-destructor-lifetime-raii/)
10. [09：拷贝构造、赋值运算符和对象复制](/posts/cpp-copy-constructor-assignment/)
11. [10：继承、多态、virtual 和 override](/posts/cpp-inheritance-polymorphism-virtual-override/)
12. [11：纯虚函数、接口类和虚析构函数](/posts/cpp-pure-virtual-interface-virtual-destructor/)
13. [12：头文件、源文件、include 和 namespace](/posts/cpp-header-source-include-namespace/)
14. [13：编译、链接、库和构建系统](/posts/cpp-compile-link-library-build/)
15. [14：STL 入门：string、vector、map 和 iterator](/posts/cpp-stl-string-vector-map-iterator/)
16. [15：函数指针、成员函数指针和 lambda](/posts/cpp-function-pointer-member-pointer-lambda/)
17. [16：模板：template、typename 和泛型](/posts/cpp-template-typename-generic/)
18. [17：智能指针和资源管理](/posts/cpp-smart-pointer-resource-management/)
19. [18：回到 ns-3：Ptr<T>、Object、Simulator、Packet](/posts/cpp-back-to-ns3-rdma-source-reading/)

## 2. C++ 工程实践

这一组更偏进阶应用，用真实重构和 ns-3 代码解释 C++ 概念。

1. [彻底理解 C++ 智能指针：从 new/delete 到 RAII](/posts/cpp-smart-pointers-raii/)
2. [彻底理解 C++ 模板：从 Ptr<T> 看懂 typename 和尖括号](/posts/cpp-templates-from-ns3-ptr/)

## 3. ns-3 源码阅读

这一组文章讲 ns-3 的核心机制，适合在 C++ 系统补课之后阅读。

1. [彻底理解 ns-3 的 Ptr：从引用计数到 RDMA 对象生命周期](/posts/ns3-ptr-reference-count/)
2. [彻底理解 ns-3 对象系统：Object、TypeId 和 Attribute](/posts/ns3-object-typeid-attribute/)
3. [彻底理解 ns-3 事件系统：Simulator、EventId 和 RDMA 定时器](/posts/ns3-simulator-eventid-rdma-timers/)
4. [彻底理解 ns-3 的 Packet：Header、Tag、Buffer 和 RDMA 报文生命周期](/posts/ns3-packet-header-tag-buffer-rdma/)

## 4. RDMA / DCQCN 源码与模型

这一组文章进入项目本身。

1. [DCQCN 流体模型详细推导](/posts/dcqcn-fluid-model/)
2. [从 C++ 虚函数到 RDMA 拥塞控制接口重构](/posts/rdma-congestion-controller-interface/)

后续适合继续补：

```text
RDMA QueuePair
RDMA 发送路径
RDMA 接收路径
DCQCN 实现细节
PFC / Qbb / SwitchMmu
Trace / Log / 调试体系
```

## 5. 工具与环境

1. [从零把代码推送到 GitHub/Gitee：创建仓库、配置 SSH、push、clone 和同步](/posts/git/)

## 6. 维护规则

为了避免文章越来越多之后失控，后续新增文章遵循这几条规则：

```text
1. 标题带系列前缀，例如 C++ 系统补课 02。
2. front matter 里的 categories 和 tags 要能对应到路线。
3. 系列文章开头保留“系列位置 / 上一篇 / 下一篇 / 总目录”。
4. _posts 暂时保持平铺，避免 Jekyll/Chirpy 把子目录名混进分类。
5. 内部系列关系记录在 _data/series.yml。
```
