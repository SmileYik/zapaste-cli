# zapaste-cli

`zapaste-cli` is a command-line tool built with Zig designed to interact with [Zapaste](https://github.com/SmileYik/zapaste) services. It provides a terminal-based interface to manage pastes and files via the Zapaste RESTful API.

[English](#zapaste-cli) | [中文](./README.zh.md)

---

## Key Features

* **Create Pastes**: Create new pastes with custom content, expiration settings, and privacy options.


* **File Uploads**: Attach multiple files to new or existing pastes directly from your local machine.


* **Manage Existing Content**: Update or reset the content, settings, and attachments of existing pastes.


* **Security**: Support for password-protected pastes and private visibility.


* **Global Configuration**: Set and save default API URLs and authentication credentials for persistent use.

---

## Installation

### Build from Source

Ensure you have the Zig compiler (version is 0.15.2) installed:

```bash
git clone https://github.com/SmileYik/zapaste-cli
cd zapaste-cli
zig build -Doptimize=ReleaseFast
```

The executable will be located in `zig-out/bin/zapaste-cli`.

---

## Usage and Commands

### 1. Global Options

* `-u, --url <url>`: Set the API base URL (temporarily overrides config).

* `-t, --token <token>`: Set the API authentication token.

* `-h, --help`: Display the help message.


### 2. Configuration (`config`)

Configure the global API endpoint and authentication details.

```bash
zapaste-cli config <url> [-u <user>] [-p <password>]
```

### 3. Create (`create`)

Create a new paste. The content is a required parameter.

```bash
zapaste-cli create <content> [options...]
```

* `-f, --file <path>`: Path to a file to upload (can be used multiple times).

* `-n, --name <name>`: Set a specific name for the paste.

* `-p, --password <pwd>`: Protect the paste with a password.

* `--private`: Set the paste to private.

* `-r, --readonly`: Set the paste to read-only mode.

* `-B, --burn-after-reads <count>`: Set the number of reads before auto-destruction.



### 4. Update (`update`)

Modify an existing paste.

```bash
zapaste-cli update <target_name> [options...]
```

* `-p, --password <pwd>`: The current password required for verification.

* `-c, --content <text>`: The new text content.

* `-nn, --new-name <name>`: Change the paste name.

* `-P, --new-password <pwd>`: Change the paste password.


### 5. Upload (`upload`)

Upload files to an existing paste.

```bash
zapaste-cli upload <target_name> -f /path/to/file [-p <password>]
```

### 6. Reset (`reset`)

Reset the state of a paste.

```bash
zapaste-cli reset <target_name> [options...]
```

* `-C, --create-if-not-exists`: Create the paste if the target name does not exist.

* `-ca, --clean-attachments`: Remove all existing attachments from the paste.

---

## Examples

**Create a private paste:**

```bash
zapaste-cli create "Secret message" --private
```

**Create a read-only paste with files:**

```bash
zapaste-cli create "Attached documents" --name "my-files" -r -f "./doc.pdf" -f "./image.png"
```

**Update content of a password-protected paste:**

```bash
zapaste-cli update "target-name" -p "current-password" -c "New updated content"
```

**Upload a log file to a specific paste:**

```bash
zapaste-cli upload "logs-share" --file "/var/log/syslog"
```