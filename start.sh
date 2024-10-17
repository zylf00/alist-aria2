#!/bin/bash
ARIA2_RPC_PORT=${SERVER_PORT:-6800}       # Aria2 RPC端口，自动获取玩具端口，不用改 
rpc_secret="P3TERX"                       # Aria2 RPC 密钥
ALIST_PORT=${ALIST_PORT:-5244}  # alist端口
ADMIN_PASSWORD=${ADMIN_PASSWORD:-qwe123456}  # alist密码

# 统一输出格式的函数
log_info() {
    echo -e "\033[1;32m[信息]\033[0m $1"
}

log_error() {
    echo -e "\033[1;31m[错误]\033[0m $1"
}

# 检测处理器架构
ARCH=$(uname -m)
log_info "检测到处理器架构：$ARCH"


# 检查 aria2c 文件是否存在
if [[ ! -f "./aria2/aria2c" ]]; then
    log_info "未找到 aria2c 文件，正在下载..."
    curl -L -sS -o aria2.tar "https://github.com/zylf00/aria2-rongqi/raw/refs/heads/main/test/aria2.tar"
    tar -xf aria2.tar -C .
    rm aria2.tar
    if [[ ! -f "./aria2/aria2c" ]]; then
        log_error "下载后未能找到 aria2c 文件，退出。"
        exit 1
    fi
fi

# 将 RPC 端口和密钥写入 aria2.conf 配置文件
sed -i "s/^rpc-listen-port=.*/rpc-listen-port=${ARIA2_RPC_PORT}/" "./aria2/aria2.conf"
sed -i "s/^rpc-secret=.*/rpc-secret=${rpc_secret}/" "./aria2/aria2.conf"

# 启动 Aria2
chmod +x "./aria2/aria2c"
log_info "使用配置文件启动 Aria2 服务器，RPC 端口：$ARIA2_RPC_PORT"
"./aria2/aria2c" --conf-path="./aria2/aria2.conf" --log="./aria2/aria2.log" &


sleep 2

# 测试 Aria2 RPC 连接
log_info "正在测试 Aria2 RPC 连接"
response=$(curl -s -X POST http://127.0.0.1:"$ARIA2_RPC_PORT"/jsonrpc \
    -d '{"jsonrpc":"2.0","method":"aria2.getGlobalStat","id":"curltest","params":["token:'"$rpc_secret"'"]}' \
    -H 'Content-Type: application/json')

if echo "$response" | grep -q '"result"'; then
    log_info "Aria2 RPC 连接正常！"
else
    log_error "Aria2 RPC 连接失败！"
fi


# 更新 BT-Tracker
update_bt_tracker() {
    log_info "正在更新 BT-Tracker..."
    bash ./aria2/tracker.sh /home/container/aria2/aria2.conf >> /home/container/aria2/tracker.log
    log_info "BT-Tracker 更新完成！"
}
update_bt_tracker


install_and_config_alist() {
    log_info "正在安装 Alist..."

    # 判断系统架构，选择对应的下载链接
    if [[ "$ARCH" == "x86_64" || "$ARCH" == "amd64" ]]; then
        ALIST_URL="https://github.com/alist-org/alist/releases/download/v3.38.0/alist-linux-amd64.tar.gz"
    elif [[ "$ARCH" == "arm" || "$ARCH" == "armv7l" || "$ARCH" == "arm64" || "$ARCH" == "aarch64" ]]; then
        ALIST_URL="https://github.com/alist-org/alist/releases/download/v3.38.0/alist-linux-arm64.tar.gz"
    else
        log_error "不支持的架构：$ARCH"
        exit 1
    fi

    # 创建专属的 Alist 文件夹
    INSTALL_DIR="$HOME/alist"
    mkdir -p "$INSTALL_DIR"

    # 检查 Alist 文件是否存在
    if [[ ! -f "$INSTALL_DIR/alist" ]]; then
        log_info "未找到 Alist 文件，正在下载..."
        
        # 下载并解压 Alist 到专属目录
        curl -L -sS -o alist.tar.gz "$ALIST_URL"
        tar -zxvf alist.tar.gz -C "$INSTALL_DIR"
        rm -f alist.tar.gz
        chmod +x "$INSTALL_DIR/alist"

        log_info "Alist 下载并解压完成"
    else
        log_info "Alist 已存在，跳过下载"
    fi

    CONFIG_FILE="$HOME/data/config.json"
    
    # 如果配置文件不存在，先启动一次 Alist 生成配置文件
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_info "配置文件不存在，先启动 Alist 以生成配置文件..."
        nohup "$INSTALL_DIR/alist" server > "$INSTALL_DIR/alist_temp.log" 2>&1 &
        sleep 5  # 等待几秒钟确保 Alist 启动并生成配置文件

        if [[ -f "$CONFIG_FILE" ]]; then
            log_info "配置文件生成成功：$CONFIG_FILE"
            sleep 2
        else
            log_error "启动后配置文件仍然不存在，退出。"
            exit 1
        fi
    else
        log_info "检测到已有配置文件，直接进行配置更新..."
    fi

    # 使用 sed 修改配置文件中的端口
    sed -i "s/\"http_port\":.*/\"http_port\": $ALIST_PORT,/" "$CONFIG_FILE"
    log_info "Alist 配置已更新，端口：$ALIST_PORT"

    # 启动 Alist 并记录日志
    log_info "启动 Alist 服务..."
    nohup "$INSTALL_DIR/alist" server > "$INSTALL_DIR/alist.log" 2>&1 &
    "$INSTALL_DIR/alist" admin set "$ADMIN_PASSWORD"
    log_info "Alist 已安装并运行，日志位于 $INSTALL_DIR/alist.log"
}

# 执行 Alist 安装和配置
install_and_config_alist

install_jq() {
    # 判断系统架构，选择对应的下载链接
    if [[ "$ARCH" == "x86_64" || "$ARCH" == "amd64" ]]; then
        JQ_URL="https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64"
    elif [[ "$ARCH" == "arm" || "$ARCH" == "armv7l" || "$ARCH" == "arm64" || "$ARCH" == "aarch64" ]]; then
        JQ_URL="https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux-arm"
    else
        log_error "不支持的架构：$ARCH"
        exit 1
    fi

    # 创建文件夹并下载 jq
    [[ ! -d "$HOME/bin" ]] && mkdir -p "$HOME/bin"
    
    if [[ ! -f "$HOME/bin/jq" ]]; then
        curl -sL --fail -o "$HOME/bin/jq" "$JQ_URL"
        if [[ $? -ne 0 ]]; then
            log_error "jq 下载失败！"
            return 1
        fi
        chmod +x "$HOME/bin/jq"
    fi

    # 确保 jq 路径写入 .bashrc
    [[ ! -f "$HOME/.bashrc" ]] && touch "$HOME/.bashrc"
    grep -qxF 'export PATH="$HOME/bin:$PATH"' "$HOME/.bashrc" || echo 'export PATH="$HOME/bin:$PATH"' >> "$HOME/.bashrc"
    source "$HOME/.bashrc"
}

# 执行 jq 安装
install_jq
