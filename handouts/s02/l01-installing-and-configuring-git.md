---
title: "Installing and configuring Git"
kicker: "FLUX CD · SECTION 2 · LECTURE 1"
description: "This lecture covers installing Git on Windows, macOS, and Linux, then configuring Git for local use and setting up SSH authentication for remote"
---

<a href="https://devcloudlab.com"><img src="../../assets/img/devcloudlab-logo.png" alt="DevCloudLab" height="72"></a>

# Installing and configuring Git

*Section 2, Lecture 1 — from the **Flux CD** course by [DevCloudLab](https://devcloudlab.com).*

---

## What you'll learn

- Install Git on Windows, macOS, and Linux and verify the installation
- Configure your Git identity (user name and email) and default text editor
- Generate an SSH key pair and register it with the SSH agent
- Add your public key to GitLab and test the SSH connection
- Locate and read your global Git configuration file

## Overview

This lecture covers installing Git on Windows, macOS, and Linux, then configuring Git for local use and setting up SSH authentication for remote repositories.

## Installation Commands

### Windows

1. Download Git for Windows from https://gitforwindows.org
2. Run the installer and accept the defaults
3. Verify installation:
   ```bash
   git --version
   ```

### macOS

1. Using Homebrew (if installed):
   ```bash
   brew install git
   ```
2. Or download from https://git-scm.com/download/mac and run the installer
3. Verify installation:
   ```bash
   git --version
   ```

### Linux (Ubuntu/Debian)

1. Update your package manager:
   ```bash
   sudo apt update
   ```
   Fetch the latest list of available packages.

2. Install Git:
   ```bash
   sudo apt install git -y
   ```
   The `-y` flag skips the confirmation prompt.

3. Verify installation:
   ```bash
   git --version
   ```
   Display the installed Git version number.

## Configuring Git

### Set Your User Information

Git needs to know your name and email for every commit:

```bash
git config --global user.name "Your Name"
```
Sets your name globally on this machine.

```bash
git config --global user.email "your.email@example.com"
```
Sets your email globally on this machine.

### Verify Your Configuration

```bash
git config --global user.name
```
Display the configured user name.

```bash
git config --global user.email
```
Display the configured email address.

### Set Your Default Text Editor

Git uses a text editor for commit messages and merge conflict resolution. Choose one:

**Vim (default, minimal):**
```bash
git config --global core.editor "vim"
```

**Visual Studio Code:**
```bash
git config --global core.editor "code"
```
Only works if you have the `code` command in your PATH.

**Sublime Text:**
```bash
git config --global core.editor "subl"
```
Only works if you have the `subl` command in your PATH.

**Nano (simple):**
```bash
git config --global core.editor "nano"
```

### Verify Editor Configuration

```bash
git config --global core.editor
```
Display the configured editor.

## SSH Authentication Setup

SSH lets you authenticate to Git repositories without storing passwords in plaintext.

### Step 1: Generate an SSH Key Pair

```bash
ssh-keygen -t ed25519 -C "your.email@example.com"
```
Generate a new SSH key using Ed25519 (modern and secure). The `-C` flag adds a comment (email) to label the key.

- When prompted for a file location, press Enter to accept the default: `~/.ssh/id_ed25519`
- When prompted for a passphrase, press Enter twice to skip (for this lab; production keys should have a passphrase)

### Step 2: Start the SSH Agent

```bash
eval "$(ssh-agent -s)"
```
Start the SSH agent, a background process that holds decrypted keys in memory.

### Step 3: Add Your Key to the Agent

```bash
ssh-add ~/.ssh/id_ed25519
```
Register your private key with the agent so it can be used for authentication.

### Step 4: Display Your Public Key

```bash
cat ~/.ssh/id_ed25519.pub
```
Print the contents of your public key. This is the value you will upload to GitLab. It should look like:

```
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIxxx... your.email@example.com
```

## Adding Your SSH Key to GitLab

1. Visit https://gitlab.com and log in
2. Click your profile icon (top right corner)
3. Select Preferences
4. Click SSH Keys (left sidebar)
5. Paste your public key (from `cat ~/.ssh/id_ed25519.pub`) into the Key box
6. Click Add key

### Test Your SSH Connection

```bash
ssh -T git@gitlab.com
```
Attempt to connect to GitLab via SSH.

The first time you connect, SSH has no record of gitlab.com and asks you to confirm its host key:

```
The authenticity of host 'gitlab.com (...)' can't be established.
ED25519 key fingerprint is SHA256:...
Are you sure you want to continue connecting (yes/no/[fingerprint])?
```

Type `yes` and press Enter — pressing Enter on its own just re-asks. If everything is set up correctly, a welcome message from GitLab follows.

## Reference: Global Configuration Files

Your Git configuration is stored in a plain text file in your home directory:

**Location:** `~/.gitconfig`

**Example content:**
```
[user]
    name = Your Name
    email = your.email@example.com
[core]
    editor = vim
[ssh]
    # Additional SSH options can go here
```

You can also view all your global configuration with:
```bash
git config --global -l
```
List all global Git settings.

## Further Reading

- **Official Git Documentation:** https://git-scm.com/doc
- **Git Configuration Reference:** https://git-scm.com/docs/git-config
- **SSH Keys Guide:** https://git-scm.com/book/en/v2/Git-on-the-Server-Generating-Your-SSH-Public-Key
- **GitLab SSH Documentation:** https://docs.gitlab.com/ee/user/ssh.html
- **GitHub SSH Setup (if using GitHub):** https://docs.github.com/en/authentication/connecting-to-github-with-ssh

## Troubleshooting

### Issue: `git: command not found`
**Solution:** Git is not installed or not in your PATH. Reinstall Git or add it to your PATH environment variable.

### Issue: `ssh-add` fails with "Could not open a connection to your authentication agent"
**Solution:** The SSH agent is not running. Start it with `eval "$(ssh-agent -s)"` first.

### Issue: SSH connection to GitLab fails
**Solution:** Verify your public key was uploaded to GitLab. Check that there are no extra spaces or line breaks in the pasted key.

### Issue: Permission denied when trying to use SSH key
**Solution:** Ensure your private key file has the correct permissions. Run `chmod 600 ~/.ssh/id_ed25519`.

---

<p align="center">
  <a href="https://devcloudlab.com"><img src="../../assets/img/devcloudlab-logo.png" alt="DevCloudLab" height="88"></a>
</p>

<p align="center">
  <strong>Built by DevCloudLab</strong><br>
  Hands-on cloud-native courses — Kubernetes, GitOps, CI/CD and the cloud.<br>
  <a href="https://devcloudlab.com"><strong>Visit DevCloudLab.com →</strong></a>
</p>
