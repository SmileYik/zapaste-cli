# zapaste-cli

`zapaste-cli` 是一个基于 Zig 开发的命令行工具，旨在通过终端与 [Zapaste](https://github.com/SmileYik/zapaste) 服务进行交互。它完整支持 Zapaste 的 RESTful API，涵盖剪贴板的创建、更新、重置及文件上传等功能。

---

## 主要功能

* **创建剪贴板**：支持设置内容、密码、私有模式及阅后即焚。
* **更新剪贴板**：修改现有剪贴板的内容、名称、权限或添加新附件。
* **重置剪贴板**：一键清空或重新设置剪贴板内容与附件。
* **文件上传**：直接将本地文件同步至指定的剪贴板。
* **全局配置**：临时或永久配置 API 地址及身份验证信息。

---

## 安装

### 编译安装

确保你已安装 Zig 0.15.2 编译器：

```bash
git clone https://github.com/SmileYik/zapaste-cli
cd zapaste-cli
zig build -Doptimize=ReleaseFast
```

编译产物位于 `zig-out/bin/zapaste-cli`。
---

## 核心命令与用法

### 1. 全局选项

* `-u, --url <url>`: 设置 API 地址（临时覆盖配置）。
* `-t, --token <token>`: 设置 API 验证 Token。
* `-h, --help`: 查看帮助信息。

### 2. 配置 (config)

设置默认的 API 地址和身份验证信息。

```bash
zapaste-cli config <url> [-u <user>] [-p <password>]
```

### 3. 创建 (create)

新建剪贴板。

```bash
zapaste-cli create <content> [options...]
```

* `-f, --file <path>`: 添加附件（可多次使用-f去添加附件）。
* `-n, --name <name>`: 指定剪贴板名称。
* `-p, --password <pwd>`: 设置剪贴板密码。
* `--private`: 设为私有。
* `-r, --readonly`: 设为只读。
* `-B, --burn-after-reads <count>`: 设置阅后即焚次数。

### 4. 更新 (update)

更新现有的剪贴板。

```bash
zapaste-cli update <target-paste-name> [options...]
```

* `-p, --password <pwd>`: 验证现有密码。
* `-c, --content <text>`: 修改文本内容。
* `-nn, --new-name <name>`: 修改剪贴板名称。
* `-P, --new-password <pwd>`: 修改剪贴板密码。

### 5. 上传 (upload)

向指定剪贴板追加文件。

```bash
zapaste-cli upload <target-paste-name> -f /path/to/file [-p <password>]
```

### 6. 重置 (reset)

重置剪贴板状态。

```bash
zapaste-cli reset <target-paste-name> [options...]
```

* `-C, --create-if-not-exists`: 若不存在则新建。
* `-ca, --clean-attachments`: 清空已有附件。

---

## 使用示例

**创建一个私有剪贴板：**

```bash
zapaste-cli create "这是一条秘密内容" --private
```

**创建一个带附件的只读剪贴板：**

```bash
zapaste-cli create "查看附件" --name "my-files" -r -f "./doc.pdf" -f "./img.png"
```

**更新加密剪贴板的内容：**

```bash
zapaste-cli update "test-paste" -p "old-password" -c "新内容"
```

**上传文件到指定剪贴板：**

```bash
zapaste-cli upload "data-share" -f "/tmp/logs.zip"
```
