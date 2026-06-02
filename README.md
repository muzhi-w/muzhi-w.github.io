# Chirpy Starter

[![Gem Version](https://img.shields.io/gem/v/jekyll-theme-chirpy)][gem]&nbsp;
[![GitHub license](https://img.shields.io/github/license/cotes2020/chirpy-starter.svg?color=blue)][mit]

A minimal, ready-to-use template for creating a blog with the [**Chirpy**][chirpy] Jekyll theme. Get up and running in minutes with all critical files pre-configured.

## Why This Starter Exists

When installing Chirpy through [RubyGems.org][gem], Jekyll can only read a subset of theme files (`_data`, `_layouts`, `_includes`, `_sass`, `assets`) and limited `_config.yml` options from the gem. As a result, users cannot enjoy the full out-of-the-box experience that Chirpy offers.

To unlock all features, the following files must be present in your Jekyll site:

```shell
.
├── _config.yml
├── _plugins
├── _tabs
└── index.html
```

This starter bundles those files from the latest **Chirpy** release along with a [CD][CD] workflow, so you can start writing immediately.

## Local Preview

本仓库是 Jekyll + Chirpy 博客。以后如果想在本地查看博客网页，在 WSL 里进入仓库目录：

```bash
cd ~/project/muzhi-w.github.io
```

先确认当前 Ruby 是 rbenv 里的新版本，而不是 Ubuntu 20.04 自带的 Ruby 2.7：

```bash
source ~/.bashrc
ruby -v
```

期望看到类似：

```text
ruby 3.3.11
```

第一次运行，或者 Gemfile 依赖变化后，安装依赖：

```bash
bundle _2.4.22_ install
```

启动本地预览服务：

```bash
bundle _2.4.22_ exec jekyll serve --host 0.0.0.0 --port 4000 --future
```

然后在浏览器打开：

```text
http://localhost:4000/
```

某篇文章也可以直接打开，例如：

```text
http://localhost:4000/posts/cpp-smart-pointers-raii/
```

停止本地服务：

```text
Ctrl+C
```

### Notes

`--future` 用来显示发布日期还没到的文章。比如文章 front matter 里写了：

```yaml
date: 2026-06-02 12:00:00 +0800
```

如果当前时间还没到这个发布时间，普通 `jekyll serve` 会跳过这篇文章；加上 `--future` 就可以在本地提前预览。

如果 `4000` 端口已经被占用，可以换一个端口：

```bash
bundle _2.4.22_ exec jekyll serve --host 0.0.0.0 --port 4001 --future
```

然后打开：

```text
http://localhost:4001/
```

如果在终端里用 `curl http://127.0.0.1:4000/` 看到 `502 Bad Gateway`，通常是因为 WSL 里配置了代理。可以这样绕过代理测试本地服务：

```bash
curl --noproxy '*' -I http://127.0.0.1:4000/
```

### Fresh WSL Setup

如果换了一台新机器，或者 WSL 环境重装了，需要重新准备 Ruby/Jekyll 环境。

安装系统依赖：

```bash
sudo apt update
sudo apt install git curl build-essential libssl-dev libreadline-dev zlib1g-dev libyaml-dev libffi-dev libgdbm-dev libncurses5-dev libdb-dev
```

安装 rbenv：

```bash
curl -fsSL https://github.com/rbenv/rbenv-installer/raw/main/bin/rbenv-installer | bash
```

把 rbenv 加到 `~/.bashrc`：

```bash
export PATH="$HOME/.rbenv/bin:$PATH"
eval "$(rbenv init - bash)"
```

让配置立即生效：

```bash
source ~/.bashrc
```

安装 Ruby 3.3.11。这个 WSL 环境里 `/usr/bin/gcc` 可能被切到了旧的 `gcc-4.8`，所以安装 Ruby 时临时指定 `gcc-9/g++-9`：

```bash
CC=/usr/bin/gcc-9 CXX=/usr/bin/g++-9 rbenv install 3.3.11
rbenv global 3.3.11
```

安装 Bundler：

```bash
gem install bundler -v 2.4.22
```

之后回到博客目录运行：

```bash
cd ~/project/muzhi-w.github.io
bundle _2.4.22_ install
bundle _2.4.22_ exec jekyll serve --host 0.0.0.0 --port 4000 --future
```

## Usage

Check out the [theme's docs](https://github.com/cotes2020/jekyll-theme-chirpy/wiki).

## Contributing

This repository is automatically updated with new releases from the theme repository. If you encounter any issues or want to contribute to its improvement, please visit the [theme repository][chirpy] to provide feedback.

## License

This work is published under [MIT][mit] License.

[gem]: https://rubygems.org/gems/jekyll-theme-chirpy
[chirpy]: https://github.com/cotes2020/jekyll-theme-chirpy/
[CD]: https://en.wikipedia.org/wiki/Continuous_deployment
[mit]: https://github.com/cotes2020/chirpy-starter/blob/master/LICENSE
