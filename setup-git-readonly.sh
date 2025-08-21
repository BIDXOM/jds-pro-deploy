#!/usr/bin/env bash
# 一键部署只读 Git 服务器（git-daemon，git:// 协议）
# 用法: sudo bash setup-git-readonly.sh "<RepoA[,RepoB,…]>" [PORT]
set -Eeuo pipefail
trap 'echo -e "\e[31m[ERR]\e[0m 出错，行 $LINENO" >&2' ERR

REPOS_CSV="${1:-}"; PORT="${2:-9418}"
REPO_ROOT="/opt/git"
UNIT="/etc/systemd/system/git-daemon.service"

[[ $EUID -eq 0 ]] || { echo "请用 root 运行"; exit 1; }
[[ -n "$REPOS_CSV" ]] || { echo "用法: $0 \"RepoA[,RepoB]\" [PORT]"; exit 1; }

ok(){ echo -e "\e[32m[OK]\e[0m $*"; }
warn(){ echo -e "\e[33m[WARN]\e[0m $*"; }

# 1) 安装 git
if command -v apt >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt update -y && apt install -y git
elif command -v yum >/dev/null 2>&1; then
  yum install -y git
elif command -v dnf >/dev/null 2>&1; then
  dnf install -y git
else
  echo "未找到可用包管理器"; exit 1
fi
ok "git 已安装"

# 2) 创建裸仓库，并显式允许被 git-daemon 导出
mkdir -p "$REPO_ROOT"
IFS=',' read -r -a REPOS <<< "$REPOS_CSV"
for name in "${REPOS[@]}"; do
  name="$(echo "$name" | xargs)"
  [[ -n "$name" ]] || continue
  path="${REPO_ROOT}/${name}.git"
  if [[ ! -d "$path" ]]; then
    git init --bare "$path"
    ok "创建裸仓库: $path"
  else
    warn "已存在: $path"
  fi
  # 只导出打了标记的仓库（更安全）
  touch "${path}/git-daemon-export-ok"
done

# 3) 写 systemd 服务（只读：不启用 receive-pack）
cat > "$UNIT" <<EOF
[Unit]
Description=Read-only Git daemon
After=network.target

[Service]
Type=simple
ExecStart=$(command -v git) daemon \\
  --reuseaddr \\
  --base-path=${REPO_ROOT} \\
  --listen=0.0.0.0 \\
  --port=${PORT} \\
  --verbose \\
  --export-all \\
  --enable=upload-pack \\
  --disable=receive-pack \\
  ${REPO_ROOT}
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# 说明：
# - 默认 git-daemon 就不会开启 receive-pack，这里显式 --disable 更保险
# - 如果只想导出打标记的仓库，可把 --export-all 去掉；上面已 touch git-daemon-export-ok

systemctl daemon-reload
systemctl enable git-daemon
systemctl restart git-daemon
ok "git-daemon 已启动 (端口: ${PORT})"

# 4) 放行防火墙
if command -v ufw >/dev/null 2>&1; then
  ufw allow "${PORT}"/tcp || true
  ok "UFW 已放行 ${PORT}/tcp"
elif command -v firewall-cmd >/dev/null 2>&1; then
  firewall-cmd --add-port="${PORT}"/tcp --permanent || true
  firewall-cmd --reload || true
  ok "firewalld 已放行 ${PORT}/tcp"
else
  warn "未检测到 UFW/firewalld，如用云厂商安全组请放行 ${PORT}/tcp"
fi

echo
echo "======== 部署完成（只读） ========"
echo "仓库根： ${REPO_ROOT}"
echo "服务URL 例： git://<服务器IP>:${PORT}/<repo>.git"
for name in "${REPOS[@]}"; do
  name="$(echo "$name" | xargs)"; [[ -n "$name" ]] || continue
  echo "克隆示例： git clone git://<服务器IP>:${PORT}/${name}.git"
done
