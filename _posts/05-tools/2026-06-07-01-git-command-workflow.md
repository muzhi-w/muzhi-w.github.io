---
title: "Git 指令系统整理：从 status、branch 到 reset、merge 和远程同步"
date: 2026-06-07 09:00:00 +0800
permalink: /posts/git-command-workflow/
categories: [Git, 工具]
tags: [git, command-line, branch, merge, reset, stash, workflow]
description: "围绕真实开发场景系统整理 Git 常用指令：查看状态、提交、分支、撤回、合并、远程同步、stash、日志图和排错。"
---

## 前言

这篇文章不从 GitHub/Gitee 注册、SSH key 配置讲起。

这些内容我已经在另一篇文章里系统记录过：

```text
从零把代码推送到 GitHub/Gitee：创建仓库、配置 SSH、push、clone 和同步
```

这一篇专门解决另一个问题：

> 日常写代码时，Git 指令到底怎么用？

比如：

```text
我现在在哪个分支？
我有哪些文件被改了？
我有哪些提交？
我怎么创建实验分支？
我不小心提交到 main 了怎么办？
我想把实验分支合回 main 怎么办？
我想临时保存改动但不提交怎么办？
我怎么让命令行显示 VS Code 里那种分叉图？
```

这些问题不是“会不会 Git”的抽象问题，而是每天都会遇到的工程问题。

所以这篇文章按真实使用顺序来写。

核心目标是：

```text
先知道自己在哪里。
再知道自己改了什么。
然后决定保存、撤回、切分支、合并或同步。
```

---

## 1. Git 里最重要的几个概念

在背指令之前，先把 Git 的几个概念摆清楚。

### 1.1 工作区、暂存区、提交

Git 管理代码时，可以粗略分成三层：

```text
工作区 working tree
  你正在编辑的文件

暂存区 staging area / index
  准备进入下一次 commit 的文件快照

提交历史 commit history
  已经保存下来的版本记录
```

对应常用指令：

```bash
git status
git add
git commit
```

一个最普通的提交流程是：

```bash
git status
git add .
git commit -m "说明这次修改"
```

意思是：

```text
先看看改了什么
把要提交的改动放进暂存区
生成一次新的 commit
```

### 1.2 分支不是文件夹

Git 里的分支不是目录，也不是代码副本。

分支本质上只是一个指针：

```text
main 指向某个 commit
exp 指向另一个 commit
```

比如：

```text
* c3 experiment commit   exp
| * b2 main commit       main
|/
* a1 common commit
```

这里 `main` 和 `exp` 是两个分支名，它们分别指向不同的提交。

查看当前分支：

```bash
git branch --show-current
```

查看所有本地分支：

```bash
git branch
```

查看本地和远程所有分支：

```bash
git branch -a
```

### 1.3 HEAD 是当前位置

`HEAD` 表示你当前所在的位置。

通常它指向当前分支的最新提交：

```text
HEAD -> main
```

用日志可以看到：

```bash
git log --oneline --decorate -5
```

如果输出里有：

```text
606cfb3 (HEAD -> main) test
```

说明：

```text
当前在 main 分支
main 指向 606cfb3
HEAD 也在这里
```

---

## 2. 先学会查看状态

Git 里最重要的习惯是：

> 做任何危险操作之前，先看状态。

### 2.1 查看当前状态

```bash
git status
```

更短的版本：

```bash
git status --short
```

带分支信息：

```bash
git status --short --branch
```

常见输出：

```text
## main...origin/main
 M src/a.cc
?? notes.md
```

含义：

```text
当前在 main
main 跟踪 origin/main
src/a.cc 被修改了
notes.md 是新文件，还没有被 Git 跟踪
```

### 2.2 理解 status 里的符号

`git status --short` 常见符号：

```text
 M file     工作区修改了，但还没 add
M  file     已经 add 到暂存区
MM file     暂存区有一版，工作区又继续改了一版
A  file     新文件已经 add
?? file     新文件还没被 Git 跟踪
D  file     文件被删除
```

最常用判断：

```text
?? 表示新文件
 M 表示改过但没暂存
M  表示已经暂存
```
注意第一个 M 前有空格。

### 2.3 查看具体改了什么

看还没暂存的改动：

```bash
git diff
```

看已经暂存、准备提交的改动：

```bash
git diff --cached
```

看某个文件：

```bash
git diff path/to/file
```

看简短统计：

```bash
git diff --stat
```

我的习惯是：

```bash
git status --short --branch
git diff
```

先看改了哪些文件，再看每个文件具体改动。

---

## 3. 提交流程

### 3.1 提交所有改动

最常见：

```bash
git add .
git commit -m "说明这次修改"
```

但是 `git add .` 会把当前目录下所有改动都放进暂存区，包括新文件。

如果工作区里混着实验文件、日志文件、配置临时文件，就要小心。

### 3.2 只提交指定文件

```bash
git add src/a.cc src/a.h
git commit -m "fix parser state update"
```

这比 `git add .` 更安全。

尤其是做实验时，推荐明确列文件：

```bash
git add ns-3.19/src/point-to-point/model/rdma-hw.cc
git add ns-3.19/analysis/plot_dcqcn_convergence.py
git commit -m "temp: add dcqcn convergence instrumentation"
```

### 3.3 交互式选择部分改动

有时一个文件里既有正式修改，也有临时代码。

这时可以用：

```bash
git add -p
```

Git 会一块一块问你要不要暂存。

常用选择：

```text
y  暂存这一块
n  不暂存这一块
s  把这一块继续拆小
q  退出
```

这个命令很适合避免“顺手把调试代码也提交了”。

### 3.4 修改最后一次提交信息

如果刚提交完，发现 commit message 写错了：

```bash
git commit --amend -m "新的提交说明"
```

如果最后一次提交漏了一个文件：

```bash
git add missing-file.cc
git commit --amend
```

注意：

```text
如果这个提交已经 push 给别人了，amend 会改写历史，要谨慎。
```

---

## 4. 查看提交历史

### 4.1 一行一个提交

```bash
git log --oneline
```

看最近 10 个：

```bash
git log --oneline -10
```

### 4.2 查看某个提交改了什么

```bash
git show commit_id
```

只看文件列表：

```bash
git show --name-only commit_id
```

只看统计：

```bash
git show --stat commit_id
```

例如：

```bash
git show --stat 6d17815
```

### 4.3 查看某个文件的历史

```bash
git log --oneline -- path/to/file
```

带每次改动：

```bash
git log -p -- path/to/file
```

---

## 5. 分支操作

### 5.1 查看分支

查看本地分支：

```bash
git branch
```

查看远程分支：

```bash
git branch -r
```

查看所有分支：

```bash
git branch -a
```

查看每个分支指向哪个提交：

```bash
git branch -vv
```

### 5.2 创建分支

从当前提交创建新分支：

```bash
git switch -c exp/dcqcn-ecn-convergence
```

这条命令做两件事：

```text
创建 exp/dcqcn-ecn-convergence
切换到这个新分支
```

### 5.3 切换分支

```bash
git switch main
git switch exp/dcqcn-ecn-convergence
```

如果当前工作区有未提交改动，Git 可能允许你带着改动切过去，也可能因为冲突而拒绝。

切分支前最好先看：

```bash
git status --short --branch
```

### 5.4 删除分支

删除已经合并过的本地分支：

```bash
git branch -d exp/dcqcn-ecn-convergence
```

强制删除：

```bash
git branch -D exp/dcqcn-ecn-convergence
```

区别：

```text
-d 比较安全，没合并会拒绝删除
-D 是强制删除，慎用
```

### 5.5 重命名分支

重命名当前分支：

```bash
git branch -m new-name
```

把 `master` 改成 `main`：

```bash
git branch -M main
```

---

## 6. 临时实验分支怎么用

这是我最常用的 Git 工作方式。

当我想做一个实验，但不确定最后要不要保留时，不直接在 `main` 上提交，而是开一个实验分支。

### 6.1 创建实验分支

```bash
git switch main
git switch -c exp/my-experiment
```

然后在实验分支上随便改、随便提交：

```bash
git add .
git commit -m "temp: test new idea"
```

这样主分支不会被污染。

### 6.2 实验成功后合回 main

```bash
git switch main
git merge --no-ff exp/my-experiment
```

`--no-ff` 的意思是即使可以快进，也生成一个 merge commit。

好处是图上能看出来：

```text
这个功能是从一个实验分支合进来的
```

### 6.3 实验失败后丢掉分支

如果实验代码不要了：

```bash
git switch main
git branch -D exp/my-experiment
```

这样 `main` 不受影响。

### 6.4 实验暂时不合并

也可以什么都不做。

保留分支：

```text
main 继续做正式开发
exp/my-experiment 留着以后再看
```

这是 Git 分支最舒服的地方。

---

## 7. 合并分支

### 7.1 merge 的基本用法

把实验分支合进 main：

```bash
git switch main
git merge exp/dcqcn-ecn-convergence
```

如果想保留分支轨迹：

```bash
git switch main
git merge --no-ff exp/dcqcn-ecn-convergence
```

### 7.2 fast-forward 是什么

如果 `main` 没有新的提交，而 `exp` 只是从 `main` 往前走了几步：

```text
A -- B main
      \
       C -- D exp
```

这时把 `exp` 合回 `main`，Git 可以直接把 `main` 指针移动到 `D`：

```text
A -- B -- C -- D main, exp
```

这叫 fast-forward。

如果想保留合并节点，用：

```bash
git merge --no-ff exp
```

### 7.3 合并冲突

如果两个分支改了同一个地方，merge 可能冲突。

Git 会提示：

```text
CONFLICT (content): Merge conflict in file.cc
```

文件里会出现：

```text
<<<<<<< HEAD
main 上的内容
=======
exp 上的内容
>>>>>>> exp
```

处理方式：

```text
手动编辑成最终想要的内容
删除 <<<<<<< ======= >>>>>>> 这些标记
git add 冲突文件
git commit
```

如果想放弃这次 merge：

```bash
git merge --abort
```

---

## 8. 撤回和回退

这一节非常重要。

Git 里“撤回”有很多种，先判断你想撤回什么。

### 8.1 撤回工作区某个文件的修改

如果一个文件改坏了，还没提交，想恢复到最近一次 commit：

```bash
git restore path/to/file
```

注意：

```text
这会丢掉这个文件当前未提交的改动。
```

撤回所有未暂存改动：

```bash
git restore .
```

这个命令要谨慎。

### 8.2 取消暂存

如果已经 `git add` 了，但不想让它进入下一次 commit：

```bash
git restore --staged path/to/file
```

取消所有暂存：

```bash
git restore --staged .
```

这不会删除工作区改动，只是从暂存区拿出来。

### 8.3 撤回最后一次提交，但保留代码

这是最常见的误提交处理。

比如不小心在 `main` 上提交了，但还没 push：

```bash
git reset --mixed HEAD~1
```

效果：

```text
最后一次 commit 消失
代码改动保留在工作区
文件变成未暂存状态
```

这里的 `HEAD~1` 可以换成别的位置。

`HEAD` 表示当前提交，`HEAD~1` 表示当前提交的上一个提交。

所以：

```bash
git reset --mixed HEAD~1
```

意思是撤回最近 1 次提交。

如果想撤回最近 2 次提交，可以写：

```bash
git reset --mixed HEAD~2
```

如果想撤回最近 3 次提交，可以写：

```bash
git reset --mixed HEAD~3
```

也可以直接写某个 commit id：

```bash
git reset --mixed 6d17815
```

这条命令的意思是：

```text
把当前分支指针移动到 6d17815
6d17815 之后的提交会从当前分支历史上消失
但这些提交带来的代码改动会保留在工作区
```

所以 `reset` 后面的参数，本质上是在回答一个问题：

```text
我想把当前分支退回到哪个提交？
```

常见写法可以这样记：

```bash
git reset --mixed HEAD~1       # 回退 1 个提交
git reset --mixed HEAD~3       # 回退 3 个提交
git reset --mixed commit_id    # 回到指定提交
```

如果只是撤回刚刚那一次误提交，用 `HEAD~1` 最方便。

如果想回到某个明确版本，先看提交历史：

```bash
git log --oneline
```

找到目标提交 id 后，再执行：

```bash
git reset --mixed 目标commit_id
```

如果想保留暂存状态：

```bash
git reset --soft HEAD~1
```

效果：

```text
最后一次 commit 消失
改动还在暂存区
```

如果提交和代码都不要：

```bash
git reset --hard HEAD~1
```

这个非常危险。

```text
reset --hard 会直接丢掉改动。
没把握不要用。
```

### 8.4 已经 push 了怎么办

如果提交已经 push 到远程，并且别人可能已经拉取了，不要轻易 `reset --hard` 再强推。

更安全的方式是 `revert`：

```bash
git revert commit_id
```

`revert` 会生成一个新的提交，用来抵消旧提交。

区别：

```text
reset  改写历史
revert 不改写历史，只新增一个反向提交
```

团队协作时，优先用 `revert`。

### 8.5 reset 三种模式对比

```text
git reset --soft HEAD~1
  commit 撤回
  暂存区保留
  工作区保留

git reset --mixed HEAD~1
  commit 撤回
  暂存区清空
  工作区保留

git reset --hard HEAD~1
  commit 撤回
  暂存区清空
  工作区也恢复
```

我最常用的是：

```bash
git reset --mixed HEAD~1
```

因为它能撤回提交，但不丢代码。

---

## 9. stash：临时保存改动

有时你正在改代码，突然需要切分支，但当前改动还不适合提交。

这时用 stash。

### 9.1 保存当前改动

```bash
git stash push -m "临时保存：说明一下"
```

如果还包括未跟踪的新文件：

```bash
git stash push -u -m "临时保存：包括新文件"
```

### 9.2 查看 stash 列表

```bash
git stash list
```

输出类似：

```text
stash@{0}: On main: 临时保存：包括新文件
```

### 9.3 恢复 stash

恢复但保留 stash 记录：

```bash
git stash apply stash@{0}
```

恢复并删除 stash 记录：

```bash
git stash pop stash@{0}
```

### 9.4 删除 stash

删除某一个：

```bash
git stash drop stash@{0}
```

清空所有 stash：

```bash
git stash clear
```

stash 适合短期临时保存。

如果一个实验要保留几天甚至几周，更推荐开分支。

---

## 10. 远程仓库

### 10.1 查看远程仓库

```bash
git remote -v
```

输出类似：

```text
origin  git@github.com:muzhi-w/repo.git (fetch)
origin  git@github.com:muzhi-w/repo.git (push)
```

### 10.2 添加远程仓库

```bash
git remote add origin git@github.com:your-name/your-repo.git
```

如果已经有 `origin`，想改地址：

```bash
git remote set-url origin git@github.com:your-name/your-repo.git
```

### 10.3 拉取远程信息

```bash
git fetch origin
```

`fetch` 只更新远程分支信息，不会自动改你的工作区。

看远程分支：

```bash
git branch -r
```

### 10.4 pull 和 fetch 的区别

粗略理解：

```text
git fetch
  只下载远程信息
  不自动合并

git pull
  fetch + merge
  下载后自动合并到当前分支
```

所以不确定远程有什么变化时，可以先：

```bash
git fetch origin
git log --graph --oneline --decorate --all -20
```

看清楚后再决定 merge 或 pull。

### 10.5 第一次 push

```bash
git push -u origin main
```

`-u` 的意思是建立 upstream 跟踪关系。

以后就可以直接：

```bash
git push
git pull
```

查看跟踪关系：

```bash
git branch -vv
```

### 10.6 推送实验分支

```bash
git push -u origin exp/dcqcn-ecn-convergence
```

如果实验分支只是本地临时用，不想上传远程，可以不 push。

### 10.7 删除远程分支

```bash
git push origin --delete exp/dcqcn-ecn-convergence
```

删除本地远程分支缓存：

```bash
git fetch --prune
```

---

## 11. rebase 简单理解

`rebase` 的作用是把一串提交“搬到”另一个基础提交后面。

例如：

```text
      C -- D exp
     /
A -- B -- E -- F main
```

在 `exp` 上执行：

```bash
git rebase main
```

会变成：

```text
A -- B -- E -- F main
              \
               C' -- D' exp
```

注意 `C'` 和 `D'` 是新的提交，不是原来的 `C` 和 `D`。

所以：

```text
rebase 会改写提交历史。
```

个人分支、本地分支可以用。

已经 push 且别人也在用的公共分支，要谨慎。

### 11.1 用 rebase 更新实验分支

如果 main 有新提交，想让 exp 基于最新 main：

```bash
git switch exp/dcqcn-ecn-convergence
git rebase main
```

如果冲突，解决冲突后：

```bash
git add 冲突文件
git rebase --continue
```

放弃 rebase：

```bash
git rebase --abort
```

### 11.2 merge 和 rebase 怎么选

我的简单规则：

```text
想保留真实分支合并历史：用 merge
想让个人分支历史更线性：用 rebase
不熟悉时：优先 merge
```

---

## 12. 常见真实场景

### 12.1 我不小心在 main 上提交了

如果还没 push：

```bash
git reset --mixed HEAD~1
git switch exp/dcqcn-ecn-convergence
git add .
git commit -m "temp: experiment"
```

解释：

```text
先撤回 main 上的错误提交，但保留代码
切到实验分支
重新提交
```

如果已经 push，而且远程 main 是公开历史：

```bash
git revert commit_id
```

### 12.2 我想临时做实验，但不想污染 main

```bash
git switch main
git switch -c exp/my-test
```

实验中正常提交：

```bash
git add .
git commit -m "temp: my test"
```

实验成功合回：

```bash
git switch main
git merge --no-ff exp/my-test
```

实验失败丢掉：

```bash
git switch main
git branch -D exp/my-test
```

### 12.3 我想看 main 和 exp 差了什么

看两个分支各自多了几个提交：

```bash
git rev-list --left-right --count main...exp/dcqcn-ecn-convergence
```

看提交列表：

```bash
git log --oneline --left-right main...exp/dcqcn-ecn-convergence
```

看代码差异：

```bash
git diff main...exp/dcqcn-ecn-convergence
```

只看文件统计：

```bash
git diff --stat main...exp/dcqcn-ecn-convergence
```

### 12.4 我想知道某个文件是谁改的

```bash
git blame path/to/file
```

这个命令会显示每一行来自哪个提交。

如果只想看某个范围：

```bash
git blame -L 120,180 path/to/file
```

### 12.5 我想恢复某个文件到 main 的版本

当前在实验分支，想把某个文件恢复成 main 的样子：

```bash
git restore --source main -- path/to/file
```

或者从某个提交恢复：

```bash
git restore --source commit_id -- path/to/file
```

### 12.6 我想找回刚才 reset 掉的提交

先看引用日志：

```bash
git reflog
```

会看到类似：

```text
606cfb3 HEAD@{1}: commit: test
6d17815 HEAD@{2}: reset: moving to HEAD~1
```

如果想回到某个提交：

```bash
git reset --hard 606cfb3
```

注意：

```text
reflog 是救命工具，但 reset --hard 仍然危险。
```

---

## 13. .gitignore

有些文件不应该进入 Git：

```text
编译产物
日志文件
临时输出
密钥
token
大体积实验结果
IDE 缓存
```

可以写 `.gitignore`。

例子：

```gitignore
# build outputs
build/
dist/
_site/

# Python
__pycache__/
*.pyc

# logs and outputs
*.log
output/
mix/output/

# secrets
.env
*.pem
id_rsa
id_ed25519

# editor
.vscode/
.idea/
```

如果一个文件已经被 Git 跟踪，后来再加 `.gitignore` 不会自动取消跟踪。

需要：

```bash
git rm --cached path/to/file
```

只是不再跟踪，不删除本地文件。

---

## 14. 一套安全工作流

我现在比较推荐这样的流程。

### 14.1 每次开始工作前

```bash
git status --short --branch
git branch --show-current
```

确认：

```text
在哪个分支
有没有未提交改动
```

### 14.2 做正式修改

```bash
git switch main
git pull
```

改代码后：

```bash
git status --short
git diff
git add 指定文件
git diff --cached
git commit -m "清楚说明这次修改"
```

### 14.3 做实验修改

```bash
git switch main
git switch -c exp/experiment-name
```

实验中可以多次提交：

```bash
git add .
git commit -m "temp: describe experiment step"
```

最后决定：

```text
成功：merge 回 main
失败：删除分支
暂缓：保留分支
```

### 14.4 提交前检查

```bash
git status --short --branch
git diff --cached
git log --oneline --decorate -5
```

确认无误后：

```bash
git push
```

---

## 15. 常用指令速查

### 查看

```bash
git status
git status --short --branch
git diff
git diff --cached
git log --oneline -10
git log --graph --oneline --decorate --all
git branch -a
git branch -vv
git remote -v
```

### 提交

```bash
git add .
git add path/to/file
git add -p
git commit -m "message"
git commit --amend
```

### 分支

```bash
git switch main
git switch -c exp/name
git branch
git branch -d exp/name
git branch -D exp/name
```

### 合并

```bash
git merge exp/name
git merge --no-ff exp/name
git merge --abort
```

### 撤回

```bash
git restore path/to/file
git restore --staged path/to/file
git reset --soft HEAD~1
git reset --mixed HEAD~1
git reset --hard HEAD~1
git revert commit_id
```

### 临时保存

```bash
git stash push -m "message"
git stash push -u -m "message"
git stash list
git stash apply stash@{0}
git stash pop stash@{0}
```

### 远程

```bash
git fetch origin
git pull
git push
git push -u origin main
git push -u origin exp/name
git remote add origin git@github.com:user/repo.git
git remote set-url origin git@github.com:user/repo.git
```

---

## 16. 我自己的简单原则

最后总结几条自己的使用原则。

第一，做事前先看状态：

```bash
git status --short --branch
```

第二，正式代码进 `main`，不确定的东西进实验分支：

```bash
git switch -c exp/something
```

第三，提交前看 diff：

```bash
git diff --cached
```

第四，不确定会不会丢代码时，不要直接 `reset --hard`。

第五，已经 push 给别人看的历史，优先用 `revert`，少用强推。

第六，想看分叉图，用：

```bash
git log --graph --oneline --decorate --all
```

Git 的难点不在于指令数量，而在于每次操作前要知道：

```text
我在哪里？
我改了什么？
这些改动是在工作区、暂存区，还是已经进入提交历史？
我要保留历史，还是改写历史？
```

只要这几个问题想清楚，Git 就会从“玄学工具”变成一个很可靠的版本管理系统。
