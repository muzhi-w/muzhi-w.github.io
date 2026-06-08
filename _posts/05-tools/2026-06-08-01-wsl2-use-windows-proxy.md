---
title: "让 WSL2 使用 Windows 下的代理网络"
date: 2026-06-08 15:00:00 +0800
permalink: /posts/wsl2-use-windows-proxy/
categories: [工具, 网络]
tags: [wsl, wsl2, proxy, windows, clash, terminal]
---

## 前言

我在 Windows 上开了代理软件，浏览器可以正常走代理，但进入 WSL2 之后，命令行里的 `git` 不一定会自动使用 Windows 的代理。

所以这篇文章只解决一个问题：

```text
怎么让 WSL2 里的命令行程序，用上 Windows 下已经开的代理网络？
```

我的当前环境是：

```text
Windows 上的代理端口：127.0.0.1:7890
WSL 发行版：Ubuntu-20.04
WSL 类型：WSL2
WSL 里的代理配置：http://127.0.0.1:7890
```

最终写进 `~/.bashrc` 的配置是：

```bash
export HTTP_PROXY=http://127.0.0.1:7890
export HTTPS_PROXY=http://127.0.0.1:7890
export http_proxy=http://127.0.0.1:7890
export https_proxy=http://127.0.0.1:7890
```

这套配置的作用是：

```text
WSL2 里的命令行程序
        ↓
读取 HTTP_PROXY / HTTPS_PROXY
        ↓
连接 Windows 上的 127.0.0.1:7890
        ↓
通过 Windows 代理软件访问外部网络
```

---

## 1. 先理解这件事的方向

这里不是在搭建服务器，也不是让别人访问我的 WSL。

这里的方向是：

```text
WSL2 主动访问外部网络
```

我希望它们不要直接访问外网（因为我没在WSL2里开代理软件），而是先经过 Windows 上已经运行的代理软件：

```text
git 等指令
        ↓
Windows 代理软件
        ↓
GitHub、其他网站
```

所以，我们需要告诉命令行程序：

```text
访问 HTTP / HTTPS 时，请使用这个代理地址。
```

这个代理地址在我这里就是：

```text
http://127.0.0.1:7890
```

---

## 2. 先确认 Windows 代理端口

第一步不是急着改 WSL，而是先确认 Windows 下代理软件的端口。我自己的电脑的端口是 `7890`。

如果想在 PowerShell 中查看 Windows 系统代理，可以执行：

```powershell
Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" |
  Select-Object ProxyEnable, ProxyServer, AutoConfigURL
```

---

## 3. 在 WSL2 里测试能不能连到 7890

确认 Windows 代理开着之后，进入 WSL2，先不要急着写配置。

先测试 WSL 能不能访问这个代理端口：

```bash
timeout 1 bash -lc '</dev/tcp/127.0.0.1/7890' && echo open || echo closed
```

如果输出：

```text
open
```

说明 WSL2 可以直接访问 `127.0.0.1:7890`。

我当前这台机器就是这种情况。

如果这一步通了，后面配置就很简单。

---

## 4. 写入 ~/.bashrc

把代理环境变量写进：

```bash
~/.bashrc
```

打开文件：

```bash
nano ~/.bashrc
```

在文件末尾加入：

```bash
# Proxy for WSL commands.
export HTTP_PROXY=http://127.0.0.1:7890
export HTTPS_PROXY=http://127.0.0.1:7890
export http_proxy=http://127.0.0.1:7890
export https_proxy=http://127.0.0.1:7890
```

保存后让配置立即生效：

```bash
source ~/.bashrc
```

或者直接关掉 WSL 终端，重新打开一个终端。

检查环境变量：

```bash
env | grep -i proxy
```

如果看到：

```text
HTTP_PROXY=http://127.0.0.1:7890
HTTPS_PROXY=http://127.0.0.1:7890
http_proxy=http://127.0.0.1:7890
https_proxy=http://127.0.0.1:7890
```

说明配置已经进入当前 shell 环境。

---

## 5. 为什么大小写都要写

这里写了四行：

```bash
export HTTP_PROXY=http://127.0.0.1:7890
export HTTPS_PROXY=http://127.0.0.1:7890
export http_proxy=http://127.0.0.1:7890
export https_proxy=http://127.0.0.1:7890
```

看起来有点重复，但这是为了兼容不同命令行工具。

有些程序读取大写：

```text
HTTP_PROXY
HTTPS_PROXY
```

有些程序读取小写：

```text
http_proxy
https_proxy
```

所以最省心的做法就是大小写都写。

另外注意：

```bash
export HTTPS_PROXY=http://127.0.0.1:7890
```

这里虽然变量名是 `HTTPS_PROXY`，但值一般仍然写 `http://...`。

它的意思是：

```text
访问 HTTPS 网站时，通过 HTTP 代理隧道出去。
```

不是说代理地址本身一定要写成 `https://...`。

---

## 6. 验证是否真的走代理

配置完以后，先测试 `curl`：

```bash
curl -I https://github.com
```

如果能正常返回响应头，说明当前 shell 里的代理环境变量已经生效。

也可以对比测试：

```bash
curl -I -x http://127.0.0.1:7890 https://github.com
```

第一条是让 `curl` 自动读取环境变量。

第二条是手动指定代理。

如果第二条能通，第一条不通，说明代理端口本身没问题，但环境变量可能没有生效。

这时检查：

```bash
env | grep -i proxy
```

---

## 7. 如果 127.0.0.1:7890 不通怎么办

如果执行：

```bash
timeout 1 bash -lc '</dev/tcp/127.0.0.1/7890' && echo open || echo closed
```

结果是：

```text
closed
```

说明 WSL 当前不能直接连到 Windows 的 `127.0.0.1:7890`。

这时可以按下面顺序排查。

### 7.1 确认 Windows 代理软件正在运行

先回到 Windows，确认代理软件真的开着。

重点看两件事：

```text
1. 代理软件是否运行
2. HTTP 代理端口是否是 7890
```

很多时候不是 WSL 的问题，而是代理软件端口改了。

### 7.2 确认 Windows 系统代理已经开启

在 PowerShell 中执行：

```powershell
Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" |
  Select-Object ProxyEnable, ProxyServer, AutoConfigURL
```

重点看：

```text
ProxyEnable 是否为 1
ProxyServer 是否是 127.0.0.1:7890
```

### 7.3 尝试使用 Windows 网关 IP

有些 WSL2 环境不能直接用 `127.0.0.1` 访问 Windows 代理。

这时可以尝试找到 Windows 主机在 WSL 网络里的网关 IP：

```bash
ip route | awk '/default/ {print $3}'
```

假设输出是：

```text
172.20.160.1
```

就把代理地址改成：

```bash
export HTTP_PROXY=http://172.20.160.1:7890
export HTTPS_PROXY=http://172.20.160.1:7890
export http_proxy=http://172.20.160.1:7890
export https_proxy=http://172.20.160.1:7890
```

然后测试：

```bash
curl -I -x http://172.20.160.1:7890 https://github.com
```

如果这样能通，说明当前环境需要通过 Windows 网关 IP 访问代理。

### 7.4 打开代理软件的 Allow LAN

如果使用网关 IP 仍然不通，可能是代理软件只监听了：

```text
127.0.0.1
```

这表示只有 Windows 本机能访问它。

如果 WSL 通过网关 IP 访问代理，就需要代理软件监听更大的范围，比如：

```text
0.0.0.0
```

很多代理软件里这个选项叫：

```text
Allow LAN
允许局域网连接
```

打开之后再测试。

---