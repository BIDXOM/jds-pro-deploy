#!/usr/bin/env bash
# 一键搭建本地 Git 裸仓库 + SSH
# 用法:
#   sudo bash setup-git-server.sh "<RepoA[,RepoB,…]>" [SSH_PORT] [PUBKEY_FILE]
# 也可通过环境变量传入公钥:
#   export GIT_PUBKEY="ssh-ed25519 AAAA... user@host"
#   sudo bash setup-git-server.sh "QuantPilot" 2222

set -Eeuo pipefail
trap 'echo -e "\e[31m[ERR]\e[0m 出错，行号 $LINENO" >&2' ERR

REPOS_CSV="${1:-}"
SSH_PORT="${2:-22}"
PUBKEY_FILE="${3:-}"
GIT_USER="git"
REPO_ROOT="/opt/git"
BACKUP_DIR="/root/git-setup-backup-$(date +%Y%m%d%H%M%S)"

[[ $EUID -eq 0 ]] || { echo "请用 root 运行"; exit 1; }
[[ -n "$REPOS_CSV" ]] || { echo "用法: $0 \"RepoA[,RepoB]\" [SSH_PORT] [PUBKEY_FILE]"; exit 1; }

log(){ echo -e "\e[32m[OK]\e[0m $*"; }
warn(){ echo -e "\e[33m[WARN]\e[0m $*"; }

# -------- 安装基础包 --------
if command -v apt >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt update -y
  apt install -y git openssh-server ca-certificates
elif command -v yum >/dev/null 2>&1; then
  yum install -y git openssh-server ca-certificates || yum install -y git openssh openssh-server ca-certificates
elif command -v dnf >/dev/null 2>&1; then
  dnf install -y git openssh-server ca-certificates || dnf install -y git openssh openssh-server ca-certificates
else
  echo "未知包管理器，无法自动安装 git/openssh-server"; exit 1
fi
systemctl enable ssh || systemctl enable sshd || true
systemctl start ssh || systemctl start sshd || true
log "基础组件就绪"

# -------- 创建 git 用户（git-shell）--------
if ! id "$GIT_USER" &>/dev/null; then
  useradd --create-home --shell /usr/bin/git-shell "$GIT_USER" 2>/dev/null || \
  useradd --create-home --shell /usr/bin/git-shell "$GIT_USER" -U
  log "已创建用户 $GIT_USER (shell=git-shell)"
else
  # 若现有 shell 不是 git-shell，仍可使用
  warn "用户 $GIT_USER 已存在"
fi

# -------- 准备公钥 --------
PUBKEY_CONTENT=""

if [[ -n "${GIT_PUBKEY:-}" ]]; then
  PUBKEY_CONTENT="${GIT_PUBKEY}"
elif [[ -n "$PUBKEY_FILE" && -f "$PUBKEY_FILE" ]]; then
  PUBKEY_CONTENT="$(cat "$PUBKEY_FILE")"
elif [[ -f /root/.ssh/id_ed25519.pub ]]; then
  PUBKEY_CONTENT="$(cat /root/.ssh/id_ed25519.pub)"
elif [[ -f /root/.ssh/authorized_keys ]]; then
  PUBKEY_CONTENT="$(head -n1 /root/.ssh/authorized_keys)"
else
  warn "未发现公钥，将创建仓库，但暂时无法SSH登录。稍后可把公钥追加到 ~git/.ssh/authorized_keys"
fi

if [[ -n "$PUBKEY_CONTENT" ]]; then
  install -d -m 700 /home/$GIT_USER/.ssh
  touch /home/$GIT_USER/.ssh/authorized_keys
  grep -qF "$PUBKEY_CONTENT" /home/$GIT_USER/.ssh/authorized_keys || echo "$PUBKEY_CONTENT" >> /home/$GIT_USER/.ssh/authorized_keys
  chown -R $GIT_USER:$GIT_USER /home/$GIT_USER/.ssh
  chmod 600 /home/$GIT_USER/.ssh/authorized_keys
  log "已写入 ~${GIT_USER}/.ssh/authorized_keys"
fi

# -------- 创建裸仓库 --------
mkdir -p "$REPO_ROOT"
chown -R $GIT_USER:$GIT_USER "$REPO_ROOT"

IFS=',' read -r -a REPOS <<< "$REPOS_CSV"
for name in "${REPOS[@]}"; do
  name="$(echo "$name" | xargs)"   # trim
  [[ -n "$name" ]] || continue
  repo_path="${REPO_ROOT}/${name}.git"
  if [[ -d "$repo_path" ]]; then
    warn "已存在: $repo_path"
  else
    sudo -u "$GIT_USER" git init --bare "$repo_path"
    log "创建裸仓库: $repo_path"
  fi
done

# -------- 配置 sshd --------
SSHD_CFG="$(test -f /etc/ssh/sshd_config && echo /etc/ssh/sshd_config || echo /etc/ssh/sshd_config.d/00-sshd.conf)"
mkdir -p "$BACKUP_DIR"
cp -a /etc/ssh/sshd_config* "$BACKUP_DIR/" 2>/dev/null || true

# 设置端口
if grep -qE '^[# ]*Port ' "$SSHD_CFG"; then
  sed -i "s/^[# ]*Port .*/Port ${SSH_PORT}/" "$SSHD_CFG"
else
  echo "Port ${SSH_PORT}" >> "$SSHD_CFG"
fi

# 强制允许公钥认证；可选关闭密码登录（更安全，如需密码登录把下面这一行注释掉）
if grep -qE '^[# ]*PasswordAuthentication ' "$SSHD_CFG"; then
  sed -i 's/^[# ]*PasswordAuthentication .*/PasswordAuthentication no/' "$SSHD_CFG"
else
  echo "PasswordAuthentication no" >> "$SSHD_CFG"
fi
if grep -qE '^[# ]*PubkeyAuthentication ' "$SSHD_CFG"; then
  sed -i 's/^[# ]*PubkeyAuthentication .*/PubkeyAuthentication yes/' "$SSHD_CFG"
else
  echo "PubkeyAuthentication yes" >> "$SSHD_CFG"
fi

# 为 git 用户限制可执行命令（git-shell 已经限制了交互）
if ! grep -q "^$GIT_USER:" /etc/shells 2>/dev/null; then
  echo "/usr/bin/git-shell" >> /etc/shells || true
fi

# reload ssh
systemctl restart ssh || systemctl restart sshd
log "sshd 已重载（端口: ${SSH_PORT}, 密码登录: 禁用）"

# -------- 放行防火墙 --------
if command -v ufw >/dev/null 2>&1; then
  ufw allow "${SSH_PORT}"/tcp || true
  log "UFW 已放行 ${SSH_PORT}/tcp"
elif command -v firewall-cmd >/dev/null 2>&1; then
  firewall-cmd --add-port="${SSH_PORT}"/tcp --permanent || true
  firewall-cmd --reload || true
  log "firewalld 已放行 ${SSH_PORT}/tcp"
else
  warn "未检测到 UFW/firewalld，如有安全组/自建防火墙请自行放行 ${SSH_PORT}/tcp"
fi

echo
echo "======== 部署完成 ========"
echo "裸仓库根目录: ${REPO_ROOT}"
echo "SSH 用户:     ${GIT_USER}"
echo "SSH 端口:     ${SSH_PORT}"
echo "备份目录:     ${BACKUP_DIR}"
echo
for name in "${REPOS[@]}"; do
  name="$(echo "$name" | xargs)"
  [[ -n "$name" ]] || continue
  echo "克隆示例："
  echo "  git clone ssh://${GIT_USER}@<服务器IP>:${SSH_PORT}${REPO_ROOT}/${name}.git"
done
echo
if [[ -z "$PUBKEY_CONTENT" ]]; then
  echo "[提示] 你还没有为 ${GIT_USER} 写入公钥。把你的公钥追加到：/home/${GIT_USER}/.ssh/authorized_keys"
fi
