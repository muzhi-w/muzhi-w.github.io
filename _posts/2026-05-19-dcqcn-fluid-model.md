---
title: "DCQCN 流体模型详细推导"
date: 2026-05-19 12:00:00 +0800
categories: [网络, 拥塞控制]
tags: [dcqcn, rdma, ecn, fluid-model]
description: "从 DCQCN 的离散算法出发，推导论文中的流体模型方程，并解释 Equations (5)-(9) 的来源。"
math: true
---

本文只推导 DCQCN 的流体模型。目标是把 DCQCN 论文中的流体模型从离散算法一步一步推到连续时间方程，尤其解释为什么会得到论文里的 Equations (5)-(9)。

DCQCN 的核心是一个闭环：

$$
q(t)
\rightarrow
p(t)
\rightarrow
\text{ECN/CNP feedback}
\rightarrow
\alpha(t), R_T(t), R_C(t)
\rightarrow
q(t).
$$

其中 $q(t)$ 是瓶颈队列，$p(t)$ 是 ECN 标记概率，$\alpha(t)$ 是拥塞程度估计，$R_C(t)$ 是 current rate，$R_T(t)$ 是 target rate。流体模型的任务，就是把 packet-level 的标记、CNP、计时器、byte counter 等离散事件，近似成连续时间微分方程。

---

## 1. DCQCN 算法回顾

DCQCN 包含三个角色：

1. **CP, Congestion Point**：交换机瓶颈队列。它根据队列长度对到达包进行 ECN 标记。
2. **NP, Notification Point**：接收端。它看到 ECN 标记包后，向发送端生成 CNP。
3. **RP, Reaction Point**：发送端。它收到 CNP 后降低发送速率；如果一段时间没有收到 CNP，则通过 timer 和 byte counter 恢复速率。

发送端维护三个关键状态：

$$
R_C(t): \text{current rate},
\qquad
R_T(t): \text{target rate},
\qquad
\alpha(t): \text{rate reduction factor}.
$$

收到 CNP 时，RP 执行：

$$
R_T \leftarrow R_C,
$$

$$
R_C \leftarrow R_C\left(1-\frac{\alpha}{2}\right),
$$

$$
\alpha \leftarrow (1-g)\alpha + g.
$$

没有收到 CNP 而 alpha timer 到期时，RP 执行：

$$
\alpha \leftarrow (1-g)\alpha.
$$

恢复阶段有两个升速触发器：

1. **byte counter**：每发送 $B$ 个数据单位后触发一次 rate increase；
2. **timer**：每隔 $T$ 时间触发一次 rate increase。

rate increase 又分为 fast recovery 和 additive increase。论文的流体模型忽略 hyper increase，只建模 rate decrease、fast recovery 和 additive increase。

fast recovery 中：

$$
R_C \leftarrow \frac{R_T+R_C}{2}.
$$

additive increase 中：

$$
R_T \leftarrow R_T+R_{AI},
$$

$$
R_C \leftarrow \frac{R_T+R_C}{2}.
$$

这里 $R_{AI}$ 是 additive increase step。

---

## 2. 变量和参数

流体模型考虑 $N$ 个 greedy flows 共享一个瓶颈链路。瓶颈容量为 $C$。为了先得到可分析模型，论文一开始假设这些流具有相同速率，所以每个流的 current rate 都写成同一个 $R_C(t)$。

主要变量：

$$
R_C(t): \text{每条流的 current rate},
$$

$$
R_T(t): \text{每条流的 target rate},
$$

$$
\alpha(t): \text{每条流的拥塞估计因子},
$$

$$
q(t): \text{瓶颈队列长度},
$$

$$
p(t): \text{时刻 } t \text{ 的 ECN 标记概率}.
$$

主要参数：

$$
K_{\min}, K_{\max}, P_{\max}: \text{RED/ECN 标记参数},
$$

$$
g: \alpha \text{ 更新权重},
$$

$$
N: \text{瓶颈处竞争流数量},
$$

$$
C: \text{瓶颈链路容量},
$$

$$
F: \text{fast recovery steps},
$$

$$
B: \text{byte counter 触发阈值},
$$

$$
T: \text{timer rate increase 周期},
$$

$$
R_{AI}: \text{additive increase 步长},
$$

$$
\tau^*: \text{控制环路延迟},
$$

$$
\tau': \alpha \text{ 更新周期}.
$$

另外，为了描述“某个 CNP 生成窗口内是否至少有一个包被标记”，后面会使用一个反馈观察窗口 $\tau$。它对应论文中 $R_C$ 和 $R_T$ 减速项里的时间尺度。

为了让指数项有清晰含义，本文默认速率、时间和数据单位已经做了统一归一化，使得：

$$
R_C \cdot \Delta t
$$

表示时间 $\Delta t$ 内发送的数据单位数量。因此 $\tau R_C$、$\tau' R_C$、$T R_C$、$B$ 都可以作为指数里的“包数/数据单位数”。

---

## 3. ECN 标记概率方程

交换机 CP 根据瓶颈队列长度 $q(t)$ 对包做 RED-like ECN 标记。论文使用：

$$
p(t)=
\begin{cases}
0, & q(t)\le K_{\min},\\[4pt]
\dfrac{q(t)-K_{\min}}{K_{\max}-K_{\min}}P_{\max},
& K_{\min}<q(t)\le K_{\max},\\[10pt]
1, & q(t)>K_{\max}.
\end{cases}
\tag{5}
$$

这个方程的含义很直接：

当队列低于 $K_{\min}$ 时，不标记；

当队列处于 $(K_{\min},K_{\max}]$ 时，标记概率随队列线性增长；

当队列超过 $K_{\max}$ 时，所有包都被标记。

如果令：

$$
K_{\min}=K_{\max},
\qquad
P_{\max}=1,
$$

就退化成 DCTCP-like 的 cut-off marking：队列低于阈值不标记，高于阈值全部标记。DCQCN 论文后面说明，RED-like marking 对公平性和多瓶颈场景更有帮助。

---

## 4. 队列方程

瓶颈链路容量为 $C$，每条流速率为 $R_C(t)$，共有 $N$ 条流。因此瓶颈入口总输入速率为：

$$
N R_C(t).
$$

如果暂时忽略 PFC，并在队列非空或围绕工作点分析，则队列变化率等于输入速率减去服务速率：

$$
\frac{dq}{dt}=N R_C(t)-C.
\tag{6}
$$

这是论文里的 Equation (6)。

更严格地说，真实队列不能为负。如果要保留非负约束，可以写成：

$$
\frac{dq}{dt}=
\begin{cases}
N R_C(t)-C, & q(t)>0,\\[4pt]
\left[N R_C(t)-C\right]^+, & q(t)=0.
\end{cases}
$$

但 DCQCN 论文的流体模型主要用于拥塞控制参数分析，关心的是瓶颈附近的队列动态，因此直接使用：

$$
\dot q(t)=N R_C(t)-C.
$$

这个方程也说明了闭环的第一段因果关系：

$$
R_C(t) \rightarrow q(t) \rightarrow p(t).
$$

发送速率越高，队列越容易上升；队列越高，ECN 标记概率 $p(t)$ 越大。

---

## 5. 一个关键概率：窗口内至少一个包被标记

后面的 $\alpha$、$R_C$、$R_T$ 方程都依赖同一个概率结构：

> 在一个长度为 $\Delta$ 的观察窗口内，发送端对应的数据包中，至少有一个包被 ECN 标记的概率是多少？

先考虑一个固定窗口长度 $\Delta$。

由于控制反馈有延迟，发送端在时刻 $t$ 感受到的 CNP，来自大约 $$t-\tau^*$$ 时刻瓶颈处的标记情况。因此后面常用延迟变量：

$$
p_d(t)=p(t-\tau^*),
$$

$$
R_d(t)=R_C(t-\tau^*).
$$

在长度为 $\Delta$ 的窗口里，大约发送了：

$$
\Delta R_d(t)
$$

个数据单位。

单个数据单位不被标记的概率是：

$$
1-p_d(t).
$$

如果近似认为这些标记事件相互独立，则全部不被标记的概率是：

$$
\left(1-p_d(t)\right)^{\Delta R_d(t)}.
$$

所以窗口内至少有一个包被标记的概率为：

$$
H_{\Delta}(t)
=1-\left(1-p_d(t)\right)^{\Delta R_d(t)}.
$$

展开回原变量：

$$
H_{\Delta}(t)
=1-\left(1-p(t-\tau^*)\right)^{\Delta R_C(t-\tau^*)}.
$$

这个 $H_\Delta(t)$ 是整个 DCQCN 流体模型里最重要的概率量。它把 packet-level 标记概率 $p(t)$ 转换成了“一个控制窗口内是否产生拥塞反馈”的概率。

---

## 6. $\alpha(t)$ 方程推导

$\alpha$ 是 DCQCN 对拥塞程度的平滑估计。它的离散更新规则是：

收到 CNP：

$$
\alpha_{\text{new}}=(1-g)\alpha+g.
$$

没有收到 CNP：

$$
\alpha_{\text{new}}=(1-g)\alpha.
$$

设 $\alpha$ 的更新周期为 $\tau'$。那么在一个 $\tau'$ 长度的周期内，收到拥塞反馈的概率是：

$$
H_{\tau'}(t)
=1-\left(1-p(t-\tau^*)\right)^{\tau' R_C(t-\tau^*)}.
$$

为了书写简洁，令：

$$
H_{\tau'}(t)=H.
$$

则一个周期后的 $\alpha$ 的条件期望为：

$$
\mathbb{E}[\alpha_{\text{new}}]
=
H\left((1-g)\alpha+g\right)
+(1-H)(1-g)\alpha.
$$

整理：

$$
\mathbb{E}[\alpha_{\text{new}}]
=H(1-g)\alpha+Hg+(1-H)(1-g)\alpha.
$$

前两项里关于 $(1-g)\alpha$ 的部分可以合并：

$$
H(1-g)\alpha+(1-H)(1-g)\alpha
=
(1-g)\alpha.
$$

因此：

$$
\mathbb{E}[\alpha_{\text{new}}]
=(1-g)\alpha+gH.
$$

一个周期内的平均变化量是：

$$
\Delta \alpha
=
\mathbb{E}[\alpha_{\text{new}}]-\alpha.
$$

代入上式：

$$
\Delta \alpha
=(1-g)\alpha+gH-\alpha.
$$

$$
\Delta \alpha
=-g\alpha+gH.
$$

$$
\Delta \alpha
=g(H-\alpha).
$$

把离散变化除以更新周期 $\tau'$，得到流体近似：

$$
\frac{d\alpha}{dt}
=
\frac{g}{\tau'}\left(H_{\tau'}(t)-\alpha(t)\right).
$$

代回 $H_{\tau'}(t)$，得到论文 Equation (7)：

$$
\frac{d\alpha}{dt}
=
\frac{g}{\tau'}
\left(
\left(
1-
\left(1-p(t-\tau^*)\right)^{\tau'R_C(t-\tau^*)}
\right)
-\alpha(t)
\right).
\tag{7}
$$

这个方程很像一阶低通滤波：

$$
\dot \alpha
=
\frac{g}{\tau'}
\left(
\text{当前窗口拥塞反馈概率}
-
\text{当前拥塞估计}
\right).
$$

如果窗口内 CNP 概率高于当前 $\alpha$，$\alpha$ 上升；如果窗口内 CNP 概率低于当前 $\alpha$，$\alpha$ 下降。

---

## 7. $R_C(t)$ 方程推导

$R_C(t)$ 是 current rate。它有两类变化：

1. 收到 CNP 后减速；
2. 没有持续拥塞时，通过 byte counter 和 timer 升速。

所以可以写成：

$$
\frac{dR_C}{dt}
=
\left.\frac{dR_C}{dt}\right|_{\text{decrease}}
+
\left.\frac{dR_C}{dt}\right|_{\text{increase-byte}}
+
\left.\frac{dR_C}{dt}\right|_{\text{increase-timer}}.
$$

下面分别推导。

### 7.1 CNP 导致的减速项

收到 CNP 时，DCQCN 执行：

$$
R_C \leftarrow R_C\left(1-\frac{\alpha}{2}\right).
$$

因此一次 CNP 导致的 current rate 变化量为：

$$
\Delta R_C
=
R_C\left(1-\frac{\alpha}{2}\right)-R_C.
$$

整理：

$$
\Delta R_C
=
-\frac{\alpha R_C}{2}.
$$

在一个长度为 $\tau$ 的反馈窗口内，产生至少一次拥塞反馈的概率是：

$$
H_{\tau}(t)
=
1-\left(1-p(t-\tau^*)\right)^{\tau R_C(t-\tau^*)}.
$$

所以一个周期内 current rate 的期望变化量是：

$$
\mathbb{E}[\Delta R_C]
=
-\frac{\alpha(t)R_C(t)}{2}H_{\tau}(t).
$$

除以周期长度 $\tau$，得到减速项：

$$
\left.\frac{dR_C}{dt}\right|_{\text{decrease}}
=
-
\frac{R_C(t)\alpha(t)}{2\tau}
\left(
1-\left(1-p(t-\tau^*)\right)^{\tau R_C(t-\tau^*)}
\right).
$$

这就是 Equation (9) 的第一项。

### 7.2 byte counter 升速事件的发生率

byte counter 的规则是：每发送 $B$ 个数据单位，触发一次 rate increase。

但有一个重要细节：如果这 $B$ 个数据单位中出现 ECN 标记，那么后续会收到 CNP，恢复过程会被打断。因此一次 byte counter rate increase 成功发生的条件是：

$$
B \text{ 个连续数据单位都没有被标记}.
$$

单个数据单位不被标记的概率是：

$$
1-p_d(t).
$$

连续 $B$ 个都不被标记的概率为：

$$
a_B(t)=\left(1-p_d(t)\right)^B.
$$

把一次“连续 $B$ 个未标记”的尝试看成成功，出现标记导致恢复中断看成失败。成功次数服从几何型结构：在一次失败前，连续成功 $m$ 次的概率近似为：

$$
\Pr(C_B=m)=a_B(t)^m\left(1-a_B(t)\right),
\qquad m=0,1,2,\ldots
$$

因此失败前成功次数的期望是：

$$
\mathbb{E}[C_B]
=
\sum_{m=0}^{\infty}m a_B^m(1-a_B).
$$

利用几何级数公式：

$$
\sum_{m=0}^{\infty}m x^m
=
\frac{x}{(1-x)^2},
\qquad |x|<1,
$$

得到：

$$
\mathbb{E}[C_B]
=(1-a_B)\frac{a_B}{(1-a_B)^2}.
$$

$$
\mathbb{E}[C_B]
=
\frac{a_B}{1-a_B}.
$$

代回：

$$
\mathbb{E}[C_B]
=
\frac{(1-p_d)^B}{1-(1-p_d)^B}.
$$

也可以写成：

$$
\mathbb{E}[C_B]
=
\frac{1}{(1-p_d)^{-B}-1}.
$$

另一方面，packet-level 标记到达率近似为：

$$
R_d(t)p_d(t).
$$

因此 byte counter 成功升速事件的发生率近似为：

$$
\lambda_B(t)
=
R_d(t)p_d(t)
\frac{1}{(1-p_d(t))^{-B}-1}.
$$

即：

$$
\lambda_B(t)
=
\frac{R_C(t-\tau^*)p(t-\tau^*)}
{\left(1-p(t-\tau^*)\right)^{-B}-1}.
$$

这个式子有很强的直觉：

如果 $p$ 很大，标记频繁，连续 $B$ 个未标记的机会少，byte counter 很难成功触发；

如果 $p$ 很小，恢复过程很少被打断，byte counter 升速事件更容易发生。

### 7.3 byte counter 对 $R_C$ 的贡献

无论处于 fast recovery 还是 additive increase，只要触发一次普通 rate increase，current rate 都向 target rate 靠近：

$$
R_C \leftarrow \frac{R_T+R_C}{2}.
$$

因此一次 rate increase 对 $R_C$ 的变化量是：

$$
\Delta R_C
=
\frac{R_T+R_C}{2}-R_C.
$$

整理：

$$
\Delta R_C
=
\frac{R_T-R_C}{2}.
$$

所以 byte counter 对 current rate 的连续贡献为：

$$
\left.\frac{dR_C}{dt}\right|_{\text{increase-byte}}
=
\frac{R_T(t)-R_C(t)}{2}\lambda_B(t).
$$

代入 $\lambda_B(t)$：

$$
\left.\frac{dR_C}{dt}\right|_{\text{increase-byte}}
=
\frac{R_T(t)-R_C(t)}{2}
\frac{R_C(t-\tau^*)p(t-\tau^*)}
{\left(1-p(t-\tau^*)\right)^{-B}-1}.
$$

这就是 Equation (9) 的第二项。

### 7.4 timer 升速事件的发生率

timer 的逻辑与 byte counter 类似，只是它按时间触发。每隔 $T$ 时间，timer 尝试触发一次 rate increase。

在一个 timer 周期内，大约发送：

$$
T R_d(t)
$$

个数据单位。

如果这些数据单位都没有被标记，则 timer rate increase 可以成功推进。该概率为：

$$
a_T(t)
=
\left(1-p_d(t)\right)^{T R_d(t)}.
$$

使用与 byte counter 同样的几何型推导，失败前成功 timer 事件的期望次数为：

$$
\frac{a_T(t)}{1-a_T(t)}
=
\frac{1}{a_T(t)^{-1}-1}.
$$

因为：

$$
a_T(t)^{-1}
=
\left(1-p_d(t)\right)^{-T R_d(t)}.
$$

所以：

$$
\frac{a_T(t)}{1-a_T(t)}
=
\frac{1}
{\left(1-p_d(t)\right)^{-T R_d(t)}-1}.
$$

乘以标记到达率 $R_d(t)p_d(t)$，得到成功 timer 升速事件率：

$$
\lambda_T(t)
=
\frac{R_d(t)p_d(t)}
{\left(1-p_d(t)\right)^{-T R_d(t)}-1}.
$$

展开写成原变量：

$$
\lambda_T(t)
=
\frac{R_C(t-\tau^*)p(t-\tau^*)}
{\left(1-p(t-\tau^*)\right)^{-T R_C(t-\tau^*)}-1}.
$$

### 7.5 timer 对 $R_C$ 的贡献

一次 timer rate increase 对 current rate 的变化量仍然是：

$$
\Delta R_C
=
\frac{R_T-R_C}{2}.
$$

所以：

$$
\left.\frac{dR_C}{dt}\right|_{\text{increase-timer}}
=
\frac{R_T(t)-R_C(t)}{2}\lambda_T(t).
$$

代入 $\lambda_T(t)$：

$$
\left.\frac{dR_C}{dt}\right|_{\text{increase-timer}}
=
\frac{R_T(t)-R_C(t)}{2}
\frac{R_C(t-\tau^*)p(t-\tau^*)}
{\left(1-p(t-\tau^*)\right)^{-T R_C(t-\tau^*)}-1}.
$$

### 7.6 合并得到 $R_C$ 方程

把减速项、byte counter 升速项、timer 升速项相加，得到：

$$
\frac{dR_C}{dt}
=
-
\frac{R_C(t)\alpha(t)}{2\tau}
\left(
1-\left(1-p(t-\tau^*)\right)^{\tau R_C(t-\tau^*)}
\right)
$$

$$
\quad
+
\frac{R_T(t)-R_C(t)}{2}
\frac{R_C(t-\tau^*)p(t-\tau^*)}
{\left(1-p(t-\tau^*)\right)^{-B}-1}
$$

$$
\quad
+
\frac{R_T(t)-R_C(t)}{2}
\frac{R_C(t-\tau^*)p(t-\tau^*)}
{\left(1-p(t-\tau^*)\right)^{-T R_C(t-\tau^*)}-1}.
\tag{9}
$$

这就是论文里的 current rate 方程。

它的结构非常清晰：

$$
\dot R_C
=
\text{CNP 减速}
+
\text{byte counter 升速}
+
\text{timer 升速}.
$$

其中 CNP 减速项由 $\alpha$ 和窗口内至少一个标记的概率控制；两个升速项由“连续无标记恢复成功”的事件率控制。

---

## 8. $R_T(t)$ 方程推导

$R_T(t)$ 是 target rate。它和 $R_C(t)$ 的区别是：

1. 收到 CNP 时，$R_T$ 被重置为当前 $R_C$；
2. fast recovery 中，$R_T$ 不变；
3. additive increase 中，$R_T$ 每次增加 $R_{AI}$。

因此：

$$
\frac{dR_T}{dt}
=
\left.\frac{dR_T}{dt}\right|_{\text{decrease}}
+
\left.\frac{dR_T}{dt}\right|_{\text{increase-byte}}
+
\left.\frac{dR_T}{dt}\right|_{\text{increase-timer}}.
$$

### 8.1 CNP 导致的 $R_T$ 下降项

收到 CNP 时：

$$
R_T \leftarrow R_C.
$$

因此一次 CNP 造成的 target rate 变化为：

$$
\Delta R_T
=
R_C-R_T.
$$

也就是：

$$
\Delta R_T
=
-(R_T-R_C).
$$

在一个长度为 $\tau$ 的反馈窗口内产生至少一次 CNP 的概率为：

$$
H_{\tau}(t)
=
1-\left(1-p(t-\tau^*)\right)^{\tau R_C(t-\tau^*)}.
$$

因此期望变化量为：

$$
\mathbb{E}[\Delta R_T]
=
-(R_T(t)-R_C(t))H_{\tau}(t).
$$

除以 $\tau$，得到：

$$
\left.\frac{dR_T}{dt}\right|_{\text{decrease}}
=
-
\frac{R_T(t)-R_C(t)}{\tau}
\left(
1-\left(1-p(t-\tau^*)\right)^{\tau R_C(t-\tau^*)}
\right).
$$

这就是 Equation (8) 的第一项。

### 8.2 为什么 $R_T$ 的升速项要乘 fast recovery 因子

current rate $R_C$ 在 fast recovery 和 additive increase 中都会改变，因为两者都会执行：

$$
R_C \leftarrow \frac{R_T+R_C}{2}.
$$

但 target rate $R_T$ 只有在 additive increase 中才增加：

$$
R_T \leftarrow R_T+R_{AI}.
$$

fast recovery 前 $F$ 次 rate increase 不增加 $R_T$。因此，若要计算 $R_T$ 的增长率，不能只看 rate increase 事件发生率，还要乘上“该事件已经进入 additive increase 阶段”的概率。

对 byte counter 来说，一次 byte counter success 的概率是：

$$
a_B(t)=\left(1-p_d(t)\right)^B.
$$

要进入 additive increase，需要已经连续完成 $F$ 次 fast recovery steps，所以近似概率为：

$$
a_B(t)^F
=
\left(1-p_d(t)\right)^{F B}.
$$

对 timer 来说，一次 timer success 的概率是：

$$
a_T(t)=\left(1-p_d(t)\right)^{T R_d(t)}.
$$

连续完成 $F$ 次 timer fast recovery steps 的概率为：

$$
a_T(t)^F
=
\left(1-p_d(t)\right)^{F T R_d(t)}.
$$

这就是 Equation (8) 中两个升速项分子里出现：

$$
\left(1-p_d(t)\right)^{F B}
$$

和：

$$
\left(1-p_d(t)\right)^{F T R_d(t)}
$$

的原因。

### 8.3 byte counter 对 $R_T$ 的贡献

前面已经推导过 byte counter 成功 rate increase 的事件率：

$$
\lambda_B(t)
=
\frac{R_d(t)p_d(t)}
{\left(1-p_d(t)\right)^{-B}-1}.
$$

但只有 additive increase 阶段才会让 $R_T$ 增加。进入 additive increase 的近似概率为：

$$
\left(1-p_d(t)\right)^{F B}.
$$

因此能够使 $R_T$ 增长的 byte counter 事件率为：

$$
\lambda_{B,AI}(t)
=
\left(1-p_d(t)\right)^{F B}\lambda_B(t).
$$

代入 $\lambda_B(t)$：

$$
\lambda_{B,AI}(t)
=
\frac{
R_d(t)p_d(t)\left(1-p_d(t)\right)^{F B}
}
{\left(1-p_d(t)\right)^{-B}-1}.
$$

每次 additive increase 使 $R_T$ 增加 $R_{AI}$，因此：

$$
\left.\frac{dR_T}{dt}\right|_{\text{increase-byte}}
=
R_{AI}\lambda_{B,AI}(t).
$$

即：

$$
\left.\frac{dR_T}{dt}\right|_{\text{increase-byte}}
=
R_{AI} R_C(t-\tau^*)
\frac{
\left(1-p(t-\tau^*)\right)^{F B}p(t-\tau^*)
}
{\left(1-p(t-\tau^*)\right)^{-B}-1}.
$$

这就是 Equation (8) 的第二项。

### 8.4 timer 对 $R_T$ 的贡献

timer 成功 rate increase 的事件率为：

$$
\lambda_T(t)
=
\frac{R_d(t)p_d(t)}
{\left(1-p_d(t)\right)^{-T R_d(t)}-1}.
$$

进入 additive increase 的近似概率是：

$$
\left(1-p_d(t)\right)^{F T R_d(t)}.
$$

因此能够使 $R_T$ 增长的 timer 事件率为：

$$
\lambda_{T,AI}(t)
=
\left(1-p_d(t)\right)^{F T R_d(t)}
\lambda_T(t).
$$

代入：

$$
\lambda_{T,AI}(t)
=
\frac{
R_d(t)p_d(t)\left(1-p_d(t)\right)^{F T R_d(t)}
}
{\left(1-p_d(t)\right)^{-T R_d(t)}-1}.
$$

每次 additive increase 增加 $R_{AI}$，所以：

$$
\left.\frac{dR_T}{dt}\right|_{\text{increase-timer}}
=
R_{AI}\lambda_{T,AI}(t).
$$

展开：

$$
\left.\frac{dR_T}{dt}\right|_{\text{increase-timer}}
=
R_{AI}R_C(t-\tau^*)
\frac{
\left(1-p(t-\tau^*)\right)^{F T R_C(t-\tau^*)}p(t-\tau^*)
}
{\left(1-p(t-\tau^*)\right)^{-T R_C(t-\tau^*)}-1}.
$$

这就是 Equation (8) 的第三项。

### 8.5 合并得到 $R_T$ 方程

把三项相加：

$$
\frac{dR_T}{dt}
=
-
\frac{R_T(t)-R_C(t)}{\tau}
\left(
1-
\left(1-p(t-\tau^*)\right)^{\tau R_C(t-\tau^*)}
\right)
$$

$$
\quad
+
R_{AI}R_C(t-\tau^*)
\frac{
\left(1-p(t-\tau^*)\right)^{F B}p(t-\tau^*)
}
{\left(1-p(t-\tau^*)\right)^{-B}-1}
$$

$$
\quad
+
R_{AI}R_C(t-\tau^*)
\frac{
\left(1-p(t-\tau^*)\right)^{F T R_C(t-\tau^*)}p(t-\tau^*)
}
{\left(1-p(t-\tau^*)\right)^{-T R_C(t-\tau^*)}-1}.
\tag{8}
$$

这就是论文的 target rate 方程。

它的结构也很清楚：

$$
\dot R_T
=
\text{CNP 把 } R_T \text{ 拉回 } R_C
+
\text{byte counter additive increase}
+
\text{timer additive increase}.
$$

---

## 9. DCQCN 流体模型总方程

到这里，DCQCN 的流体模型可以完整写成：

### ECN 标记概率

$$
p(t)=
\begin{cases}
0, & q(t)\le K_{\min},\\[4pt]
\dfrac{q(t)-K_{\min}}{K_{\max}-K_{\min}}P_{\max},
& K_{\min}<q(t)\le K_{\max},\\[10pt]
1, & q(t)>K_{\max}.
\end{cases}
\tag{5}
$$

### 队列方程

$$
\frac{dq}{dt}=N R_C(t)-C.
\tag{6}
$$

### alpha 方程

$$
\frac{d\alpha}{dt}
=
\frac{g}{\tau'}
\left(
\left(
1-
\left(1-p(t-\tau^*)\right)^{\tau'R_C(t-\tau^*)}
\right)
-\alpha(t)
\right).
\tag{7}
$$

### target rate 方程

$$
\frac{dR_T}{dt}
=
-
\frac{R_T(t)-R_C(t)}{\tau}
\left(
1-
\left(1-p(t-\tau^*)\right)^{\tau R_C(t-\tau^*)}
\right)
$$

$$
\quad
+
R_{AI}R_C(t-\tau^*)
\frac{
\left(1-p(t-\tau^*)\right)^{F B}p(t-\tau^*)
}
{\left(1-p(t-\tau^*)\right)^{-B}-1}
$$

$$
\quad
+
R_{AI}R_C(t-\tau^*)
\frac{
\left(1-p(t-\tau^*)\right)^{F T R_C(t-\tau^*)}p(t-\tau^*)
}
{\left(1-p(t-\tau^*)\right)^{-T R_C(t-\tau^*)}-1}.
\tag{8}
$$

### current rate 方程

$$
\frac{dR_C}{dt}
=
-
\frac{R_C(t)\alpha(t)}{2\tau}
\left(
1-
\left(1-p(t-\tau^*)\right)^{\tau R_C(t-\tau^*)}
\right)
$$

$$
\quad
+
\frac{R_T(t)-R_C(t)}{2}
\frac{R_C(t-\tau^*)p(t-\tau^*)}
{\left(1-p(t-\tau^*)\right)^{-B}-1}
$$

$$
\quad
+
\frac{R_T(t)-R_C(t)}{2}
\frac{R_C(t-\tau^*)p(t-\tau^*)}
{\left(1-p(t-\tau^*)\right)^{-T R_C(t-\tau^*)}-1}.
\tag{9}
$$

这五个方程就是 DCQCN 论文中的核心流体模型。

{% comment %}
---

## 10. 固定点分析

固定点表示系统达到稳定状态：

$$
\frac{dq}{dt}=0,
\qquad
\frac{d\alpha}{dt}=0,
\qquad
\frac{dR_T}{dt}=0,
\qquad
\frac{dR_C}{dt}=0.
$$

先看队列方程：

$$
\frac{dq}{dt}=N R_C(t)-C.
$$

令其为 0：

$$
N R_C^*=C.
$$

所以：

$$
\boxed{
R_C^*=\frac{C}{N}.
}
\tag{10}
$$

这个固定点表示所有 $N$ 条流公平分享瓶颈带宽，每条流得到 $C/N$。

接下来，固定点处：

$$
R_d=R_C(t-\tau^*)=R_C^*=\frac{C}{N}.
$$

设固定点标记概率为：

$$
p^*.
$$

则 alpha 固定点由：

$$
\frac{d\alpha}{dt}=0
$$

得到：

$$
\alpha^*
=
1-\left(1-p^*\right)^{\tau'R_C^*}.
$$

也就是：

$$
\boxed{
\alpha^*
=
1-\left(1-p^*\right)^{\tau'C/N}.
}
$$

这说明在稳定状态下，$\alpha$ 等于一个 alpha 更新窗口内至少产生一次拥塞反馈的概率。

再看 $R_C$ 和 $R_T$ 的固定点。定义：

$$
H_{\tau}^*
=
1-\left(1-p^*\right)^{\tau R_C^*}.
$$

定义 byte counter 成功升速事件率：

$$
\lambda_B^*
=
\frac{R_C^*p^*}
{\left(1-p^*\right)^{-B}-1}.
$$

定义 timer 成功升速事件率：

$$
\lambda_T^*
=
\frac{R_C^*p^*}
{\left(1-p^*\right)^{-T R_C^*}-1}.
$$

再定义进入 additive increase 后，对 $R_T$ 有贡献的事件率：

$$
\lambda_{B,AI}^*
=
\left(1-p^*\right)^{F B}\lambda_B^*,
$$

$$
\lambda_{T,AI}^*
=
\left(1-p^*\right)^{F T R_C^*}\lambda_T^*.
$$

由 $\dot R_C=0$，得到减速和升速平衡：

$$
\frac{R_C^*\alpha^*}{2\tau}H_{\tau}^*
=
\frac{R_T^*-R_C^*}{2}
\left(
\lambda_B^*+\lambda_T^*
\right).
$$

所以：

$$
R_T^*-R_C^*
=
\frac{
R_C^*\alpha^*H_{\tau}^*
}
{
\tau(\lambda_B^*+\lambda_T^*)
}.
$$

由 $\dot R_T=0$，得到：

$$
\frac{R_T^*-R_C^*}{\tau}H_{\tau}^*
=
R_{AI}
\left(
\lambda_{B,AI}^*+\lambda_{T,AI}^*
\right).
$$

所以：

$$
R_T^*-R_C^*
=
\frac{
\tau R_{AI}
\left(
\lambda_{B,AI}^*+\lambda_{T,AI}^*
\right)
}
{H_{\tau}^*}.
$$

两个表达式必须相等。于是可以把固定点问题转化为关于 $$p^*$$ 的方程：

$$
\frac{
R_C^*\alpha^*H_{\tau}^*
}
{
\tau(\lambda_B^*+\lambda_T^*)
}
=
\frac{
\tau R_{AI}
\left(
\lambda_{B,AI}^*+\lambda_{T,AI}^*
\right)
}
{H_{\tau}^*}.
$$

其中：

$$
R_C^*=\frac{C}{N},
$$

$$
\alpha^*
=
1-\left(1-p^*\right)^{\tau'R_C^*},
$$

$$
H_{\tau}^*
=
1-\left(1-p^*\right)^{\tau R_C^*},
$$

$$
\lambda_B^*
=
\frac{R_C^*p^*}
{\left(1-p^*\right)^{-B}-1},
$$

$$
\lambda_T^*
=
\frac{R_C^*p^*}
{\left(1-p^*\right)^{-T R_C^*}-1}.
$$

论文指出，在合理参数下 $$p^*$$ 的解唯一，并且 $$p^*$$ 通常小于 1%。这也是为什么使用 RED-like marking 时，稳定队列通常位于靠近 $K_{\min}$ 的区域。

如果固定点处位于 RED 线性区间：

$$
K_{\min}<q^*\le K_{\max},
$$

则由 Equation (5)：

$$
p^*
=
\frac{q^*-K_{\min}}{K_{\max}-K_{\min}}P_{\max}.
$$

反解得到：

$$
\boxed{
q^*
=
K_{\min}
+
\frac{p^*}{P_{\max}}
\left(K_{\max}-K_{\min}\right).
}
$$

这就把协议参数 $B,T,F,R_{AI},g,\tau,\tau'$ 和队列固定点 $$q^*$$ 连接起来了。

---

## 11. 参数直觉

### 11.1 $g$：alpha 的平滑程度

$$
\dot \alpha
=
\frac{g}{\tau'}(H_{\tau'}-\alpha).
$$

$g$ 越大，$\alpha$ 越快跟随最新拥塞反馈；系统更敏感，但也更容易振荡。

$g$ 越小，$\alpha$ 越平滑；队列波动更小，但收敛可能更慢。

论文实验中发现较小的 $g$ 可以降低队列长度和振荡。

### 11.2 byte counter $B$：为什么可能带来不公平

byte counter 的成功升速事件率为：

$$
\lambda_B
=
\frac{R_C p}{(1-p)^{-B}-1}.
$$

它与 $R_C$ 成正相关。速率更高的流，每单位时间发送更多数据，因此 byte counter 更容易被触发，也更容易升速。

这会导致一个问题：快流更容易继续变快，慢流恢复更慢。

因此如果 $B$ 过小，byte counter 机制可能强化不公平。增大 $B$ 可以减弱这种效应，但会降低恢复速度。

### 11.3 timer $T$：为什么更利于公平恢复

timer 不直接按发送字节数触发，而是按时间触发。虽然 timer 成功概率仍然受 $T R_C$ 影响，但相比 byte counter，它不会让高发送速率流天然获得那么强的触发频率优势。

因此缩短 timer，让 timer 主导恢复过程，有助于改善不同速率流之间的公平收敛。

### 11.4 RED-like marking：为什么比 cut-off marking 更细腻

cut-off marking 中，超过阈值后所有包都被标记。这种反馈非常硬，容易造成同步和振荡。

RED-like marking 让标记概率随队列逐渐增加：

$$
p(q)
=
\frac{q-K_{\min}}{K_{\max}-K_{\min}}P_{\max}.
$$

这样更快的流会因为发送更多包而更可能收到 CNP，从而更快退让。它给 DCQCN 提供了一种近似“按贡献比例反馈”的机制。

### 11.5 $$\tau^*$$：反馈延迟

所有反馈项都使用：

$$
p(t-\tau^*),
\qquad
R_C(t-\tau^*).
$$

这说明发送端此刻收到的 CNP，不反映此刻的队列，而反映一个控制环路延迟之前的队列。

延迟越大，控制越滞后，越容易出现过冲和振荡。因此 DCQCN 参数必须和数据中心 RTT、CNP 生成间隔、NIC 处理延迟一起调。

---

## 12. 这个模型做了哪些近似

DCQCN 流体模型很有用，但它不是 packet-level 仿真的完全替代。它做了几个关键近似：

1. **连续速率近似**：把包发送、标记、CNP 生成这些离散事件近似成连续过程。
2. **独立标记近似**：推导 $(1-p)^m$ 时，近似认为不同包的标记事件独立。
3. **相同速率近似**：基础模型先假设 $N$ 条流有相同 $R_C(t)$。论文后面扩展到不同速率流时，需要为每条流分别写 $R_C^i,R_T^i,\alpha^i$，再通过队列方程耦合。
4. **忽略 PFC**：模型假设 ECN/DCQCN 在 PFC 之前发挥作用，因此不把 PFC pause/resume 写入主方程。
5. **忽略 hyper increase**：模型只包含 rate decrease、fast recovery 和 additive increase。
6. **小标记概率区域更可靠**：论文指出合理参数下 $p$ 通常小于 1%，此时几何型近似和 RED 线性区间解释更自然。

这些近似的目的不是让模型覆盖所有细节，而是捕捉 DCQCN 参数如何影响收敛、公平性、队列长度和振荡。

---

## 13. 从模型看 DCQCN 的本质

DCQCN 的流体模型可以压缩成三句话：

第一，队列由总输入和瓶颈容量决定：

$$
\dot q=N R_C-C.
$$

第二，队列通过 RED 变成标记概率：

$$
q \rightarrow p(q).
$$

第三，标记概率通过 CNP 概率改变发送端状态：

$$
p
\rightarrow
\alpha, R_C, R_T.
$$

其中 $\alpha$ 是对拥塞概率的平滑估计，$R_C$ 是实际发送速率，$R_T$ 是恢复过程追逐的目标速率。

减速靠 CNP：

$$
R_C \leftarrow R_C\left(1-\frac{\alpha}{2}\right).
$$

升速靠 byte counter 和 timer：

$$
R_C \leftarrow \frac{R_T+R_C}{2},
\qquad
R_T \leftarrow R_T+R_{AI}.
$$

所以 DCQCN 的控制逻辑本质上是在做一件事：

> 当队列升高时，通过 ECN/CNP 增大 $\alpha$，降低 $R_C$；当拥塞反馈减少时，通过 timer 和 byte counter 让 $R_C$ 逐步追向并抬高 $R_T$。

流体模型把这个离散闭环写成了可计算的微分方程组。它不仅解释了为什么公平固定点是：

$$
R_C^*=\frac{C}{N},
$$

也解释了为什么参数 $g,B,T,K_{\min},K_{\max},P_{\max},R_{AI}$ 会影响收敛速度、队列长度和振荡幅度。
{% endcomment %}