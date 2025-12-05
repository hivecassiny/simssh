#!/bin/bash

# simsshclient 安装脚本 v2.0
# 支持安装、卸载、更新功能
# 支持多种Linux发行版：Ubuntu, Debian, CentOS, RHEL, Fedora, Arch, etc.

set -e

# 配置变量
INSTALL_DIR="/opt/simsshclient"
BINARY_NAME="simsshclient"
SERVICE_NAME="simsshclient"
DOWNLOAD_URL="https://github.com/hivecassiny/simssh/releases/download/v1.0.0/simsshclient_linux_amd64.tar.gz"
LATEST_VERSION_URL="https://api.github.com/repos/hivecassiny/simssh/releases/latest"
CONFIG_DIR="$INSTALL_DIR/conf"
BACKUP_DIR="$INSTALL_DIR/backups"
TEMP_DIR="/tmp/simsshclient_install"
LOG_FILE="/tmp/simsshclient_install.log"
VERSION_FILE="$INSTALL_DIR/version.txt"

# 颜色输出函数
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

log_debug() {
    echo -e "${BLUE}[DEBUG]${NC} $1" | tee -a "$LOG_FILE"
}

# 检查root权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "需要root权限运行此脚本"
        log_error "请使用: sudo $0"
        exit 1
    fi
}

# 检测系统类型
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        OS_VERSION=$VERSION_ID
        OS_NAME=$NAME
    elif [ -f /etc/redhat-release ]; then
        OS="rhel"
        OS_VERSION=$(cat /etc/redhat-release | sed -e 's/.*release \([0-9]\+\).*/\1/')
        OS_NAME=$(cat /etc/redhat-release)
    elif [ -f /etc/debian_version ]; then
        OS="debian"
        OS_VERSION=$(cat /etc/debian_version)
        OS_NAME="Debian $(cat /etc/debian_version)"
    else
        OS=$(uname -s)
        OS_VERSION=$(uname -r)
        OS_NAME=$OS
    fi
    
    log_info "检测到系统: $OS_NAME"
    log_info "系统版本: $OS_VERSION"
}

# 安装依赖
install_dependencies() {
    log_info "正在安装必要的依赖..."
    
    case $OS in
        ubuntu|debian)
            apt-get update
            apt-get install -y wget tar systemd curl jq
            ;;
        centos|rhel|fedora)
            if command -v dnf &> /dev/null; then
                dnf install -y wget tar systemd curl jq
            else
                yum install -y wget tar systemd curl jq
            fi
            ;;
        arch|manjaro)
            pacman -Sy --noconfirm wget tar systemd curl jq
            ;;
        *)
            log_warn "未知的发行版，尝试使用通用方式安装..."
            # 检查是否已安装jq，如果未安装则尝试安装或跳过
            if ! command -v jq &> /dev/null; then
                log_warn "jq未安装，某些功能可能受限"
            fi
            ;;
    esac
    
    # 检查是否安装了必要的命令
    for cmd in wget tar; do
        if ! command -v $cmd &> /dev/null; then
            log_error "$cmd 未安装，请手动安装后重试"
            exit 1
        fi
    done
}

# 停止服务
stop_service() {
    log_info "停止服务..."
    
    if systemctl --version &> /dev/null && systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
        systemctl stop "$SERVICE_NAME"
        sleep 2
    elif [ -f "/etc/init.d/$SERVICE_NAME" ] && service "$SERVICE_NAME" status &>/dev/null; then
        service "$SERVICE_NAME" stop
        sleep 2
    fi
    
    # 确保进程被杀死
    pkill -f "$BINARY_NAME" 2>/dev/null || true
    sleep 1
}

# 启动服务
start_service() {
    log_info "启动服务..."
    
    if systemctl --version &> /dev/null && [ -f "/etc/systemd/system/$SERVICE_NAME.service" ]; then
        if systemctl start "$SERVICE_NAME"; then
            log_info "服务启动成功"
            sleep 2
            systemctl status "$SERVICE_NAME" --no-pager
            return 0
        else
            log_warn "服务启动失败"
            systemctl status "$SERVICE_NAME" --no-pager || true
            return 1
        fi
    elif [ -f "/etc/init.d/$SERVICE_NAME" ]; then
        if service "$SERVICE_NAME" start; then
            log_info "服务启动成功"
            return 0
        else
            log_warn "服务启动失败"
            return 1
        fi
    fi
    
    return 1
}

# 禁用服务自启动
disable_service() {
    log_info "禁用服务自启动..."
    
    if systemctl --version &> /dev/null && [ -f "/etc/systemd/system/$SERVICE_NAME.service" ]; then
        systemctl disable "$SERVICE_NAME" 2>/dev/null || true
        log_info "已禁用systemd服务自启动"
    fi
    
    if [ -f "/etc/init.d/$SERVICE_NAME" ]; then
        if command -v update-rc.d &> /dev/null; then
            update-rc.d -f "$SERVICE_NAME" remove 2>/dev/null || true
        elif command -v chkconfig &> /dev/null; then
            chkconfig --del "$SERVICE_NAME" 2>/dev/null || true
        fi
        log_info "已禁用SysV init服务自启动"
    fi
}

# 删除服务文件
remove_service_files() {
    log_info "删除服务文件..."
    
    # 删除systemd服务文件
    if [ -f "/etc/systemd/system/$SERVICE_NAME.service" ]; then
        rm -f "/etc/systemd/system/$SERVICE_NAME.service"
        log_info "已删除systemd服务文件"
    fi
    
    # 删除SysV init脚本
    if [ -f "/etc/init.d/$SERVICE_NAME" ]; then
        rm -f "/etc/init.d/$SERVICE_NAME"
        log_info "已删除SysV init脚本"
    fi
    
    # 重新加载systemd
    if systemctl --version &> /dev/null; then
        systemctl daemon-reload 2>/dev/null || true
    fi
}

# 备份配置
backup_config() {
    local backup_name="config_backup_$(date +%Y%m%d_%H%M%S).tar.gz"
    local backup_path="$BACKUP_DIR/$backup_name"
    
    mkdir -p "$BACKUP_DIR"
    
    if [ -d "$CONFIG_DIR" ]; then
        log_info "备份配置文件到: $backup_path"
        tar -czf "$backup_path" -C "$INSTALL_DIR" "conf" 2>/dev/null || true
        
        # 同时备份版本信息
        if [ -f "$VERSION_FILE" ]; then
            cp "$VERSION_FILE" "$BACKUP_DIR/version_backup.txt"
        fi
        
        log_info "备份完成"
    fi
}

# 恢复配置
restore_config() {
    local backup_file="$1"
    
    if [ -z "$backup_file" ]; then
        # 查找最新的备份文件
        backup_file=$(ls -t "$BACKUP_DIR"/config_backup_*.tar.gz 2>/dev/null | head -1)
    fi
    
    if [ -n "$backup_file" ] && [ -f "$backup_file" ]; then
        log_info "从备份恢复配置: $backup_file"
        
        # 删除现有配置
        rm -rf "$CONFIG_DIR"
        
        # 恢复备份
        tar -xzf "$backup_file" -C "$INSTALL_DIR"
        
        # 恢复版本信息
        if [ -f "$BACKUP_DIR/version_backup.txt" ]; then
            cp "$BACKUP_DIR/version_backup.txt" "$VERSION_FILE"
        fi
        
        log_info "配置恢复完成"
        return 0
    else
        log_error "未找到备份文件"
        return 1
    fi
}

# 下载和解压文件
download_and_extract() {
    local download_url=${1:-$DOWNLOAD_URL}
    
    log_info "创建临时目录: $TEMP_DIR"
    rm -rf "$TEMP_DIR"
    mkdir -p "$TEMP_DIR"
    
    log_info "下载文件..."
    cd "$TEMP_DIR"
    
    if ! wget --no-check-certificate -O simsshclient.tar.gz "$download_url"; then
        log_error "下载失败，请检查网络连接"
        return 1
    fi
    
    log_info "解压文件..."
    tar -xzf simsshclient.tar.gz
    
    # 检查文件是否存在
    if [[ ! -f "$BINARY_NAME" ]]; then
        # 可能在tar包内的子目录中
        if find . -name "$BINARY_NAME" -type f | grep -q .; then
            BINARY_PATH=$(find . -name "$BINARY_NAME" -type f | head -1)
            log_info "找到文件在: $BINARY_PATH"
        else
            log_error "在下载的包中未找到 $BINARY_NAME"
            log_info "包内容:"
            tar -tzf simsshclient.tar.gz
            return 1
        fi
    else
        BINARY_PATH="./$BINARY_NAME"
    fi
    
    # 检查文件是否可执行
    if [[ ! -x "$BINARY_PATH" ]]; then
        log_info "添加执行权限..."
        chmod +x "$BINARY_PATH"
    fi
    
    # 获取版本信息
    local version=$(echo "$download_url" | grep -o 'v[0-9]\+\.[0-9]\+\.[0-9]\+' || echo "unknown")
    echo "$version" > "$TEMP_DIR/version.txt"
    
    return 0
}

# 安装程序
install_program() {
    log_info "安装到目录: $INSTALL_DIR"
    
    # 创建安装目录
    mkdir -p "$INSTALL_DIR"
    
    # 备份现有配置
    if [ -d "$CONFIG_DIR" ]; then
        backup_config
    fi
    
    # 停止服务
    stop_service
    
    # 复制文件
    cp "$BINARY_PATH" "$INSTALL_DIR/$BINARY_NAME"
    chmod +x "$INSTALL_DIR/$BINARY_NAME"
    
    # 复制版本信息
    if [ -f "$TEMP_DIR/version.txt" ]; then
        cp "$TEMP_DIR/version.txt" "$VERSION_FILE"
    fi
    
    # 创建配置文件目录（如果不存在）
    mkdir -p "$CONFIG_DIR"
    
    # 创建示例配置文件（如果不存在）
    if [[ ! -f "$CONFIG_DIR/config.yaml" ]]; then
        cat > "$CONFIG_DIR/config.yaml" << EOF
# simsshclient 配置文件
# 请根据实际情况修改配置

server:
  address: "your_server_address:port"
  ssl: true
  
client:
  name: "$(hostname)"
  group: "default"
  
log:
  level: "info"
  path: "/var/log/simsshclient.log"
EOF
        log_info "已创建示例配置文件: $CONFIG_DIR/config.yaml"
    fi
    
    # 创建日志目录
    mkdir -p "/var/log/simsshclient"
    chmod 755 "/var/log/simsshclient"
}

# 创建systemd服务
create_systemd_service() {
    log_info "创建systemd服务..."
    
    SERVICE_FILE="/etc/systemd/system/$SERVICE_NAME.service"
    
    cat > "$SERVICE_FILE" << EOF
[Unit]
Description=simsshclient Service
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/$BINARY_NAME -c $CONFIG_DIR/config.yaml
Restart=always
RestartSec=10
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=$SERVICE_NAME

# 安全配置
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF
    
    chmod 644 "$SERVICE_FILE"
    log_info "systemd服务文件已创建: $SERVICE_FILE"
}

# 创建SysV init脚本（用于老版本系统）
create_sysv_init() {
    log_info "创建SysV init脚本..."
    
    INIT_FILE="/etc/init.d/$SERVICE_NAME"
    
    cat > "$INIT_FILE" << EOF
#!/bin/bash
#
# simsshclient - simsshclient init script
#
### BEGIN INIT INFO
# Provides:          $SERVICE_NAME
# Required-Start:    \$network \$local_fs \$remote_fs
# Required-Stop:     \$network \$local_fs \$remote_fs
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: simsshclient Service
# Description:       Start/Stop simsshclient
### END INIT INFO

NAME="$SERVICE_NAME"
DAEMON="$INSTALL_DIR/$BINARY_NAME"
CONFIG="$CONFIG_DIR/config.yaml"
PIDFILE="/var/run/\$NAME.pid"
LOGFILE="/var/log/\$NAME.log"
DAEMON_OPTS="-c \$CONFIG"

# 获取PID
get_pid() {
    cat "\$PIDFILE" 2>/dev/null
}

# 检查是否运行中
is_running() {
    [ -f "\$PIDFILE" ] && ps -p \$(get_pid) > /dev/null 2>&1
}

case "\$1" in
    start)
        if is_running; then
            echo "\$NAME 已经在运行 (pid: \$(get_pid))"
            exit 0
        fi
        echo "启动 \$NAME..."
        cd "$INSTALL_DIR"
        \$DAEMON \$DAEMON_OPTS >> "\$LOGFILE" 2>&1 &
        echo \$! > "\$PIDFILE"
        sleep 2
        if is_running; then
            echo "\$NAME 启动成功 (pid: \$(get_pid))"
        else
            echo "\$NAME 启动失败"
            exit 1
        fi
        ;;
    stop)
        if is_running; then
            echo "停止 \$NAME..."
            kill \$(get_pid)
            rm -f "\$PIDFILE"
            sleep 2
            echo "\$NAME 已停止"
        else
            echo "\$NAME 未在运行"
        fi
        ;;
    restart)
        \$0 stop
        sleep 2
        \$0 start
        ;;
    status)
        if is_running; then
            echo "\$NAME 正在运行 (pid: \$(get_pid))"
        else
            echo "\$NAME 已停止"
            exit 1
        fi
        ;;
    *)
        echo "使用方法: \$0 {start|stop|restart|status}"
        exit 1
        ;;
esac

exit 0
EOF
    
    chmod 755 "$INIT_FILE"
    log_info "SysV init脚本已创建: $INIT_FILE"
}

# 设置启动项
setup_startup() {
    log_info "设置启动项..."
    
    # 优先使用systemd
    if systemctl --version &> /dev/null; then
        create_systemd_service
        systemctl daemon-reload
        systemctl enable "$SERVICE_NAME"
        log_info "已启用systemd服务自启动"
    # 尝试使用SysV init
    elif command -v update-rc.d &> /dev/null; then
        create_sysv_init
        update-rc.d "$SERVICE_NAME" defaults
        log_info "已设置SysV init启动项"
    elif command -v chkconfig &> /dev/null; then
        create_sysv_init
        chkconfig --add "$SERVICE_NAME"
        chkconfig "$SERVICE_NAME" on
        log_info "已设置chkconfig启动项"
    else
        create_sysv_init
        log_warn "无法自动设置启动项，请手动设置"
        log_info "可以手动执行: ln -s /etc/init.d/$SERVICE_NAME /etc/rc.d/"
    fi
}

# 创建管理脚本
create_management_script() {
    log_info "创建管理脚本..."
    
    MANAGEMENT_SCRIPT="/usr/local/bin/${SERVICE_NAME}_ctl"
    
    cat > "$MANAGEMENT_SCRIPT" << EOF
#!/bin/bash

SERVICE_NAME="$SERVICE_NAME"
INSTALL_DIR="$INSTALL_DIR"
CONFIG_DIR="$CONFIG_DIR"
BACKUP_DIR="$BACKUP_DIR"

case "\$1" in
    start|stop|restart|status)
        if systemctl --version &> /dev/null 2>&1 && [ -f "/etc/systemd/system/\$SERVICE_NAME.service" ]; then
            systemctl \$1 \$SERVICE_NAME
        elif [ -f "/etc/init.d/\$SERVICE_NAME" ]; then
            service \$SERVICE_NAME \$1
        else
            echo "服务未安装或无法管理"
            exit 1
        fi
        ;;
    logs)
        if systemctl --version &> /dev/null 2>&1 && [ -f "/etc/systemd/system/\$SERVICE_NAME.service" ]; then
            journalctl -u \$SERVICE_NAME -f \$2
        else
            tail -f /var/log/\$SERVICE_NAME.log
        fi
        ;;
    config)
        \${EDITOR:-vi} "\$CONFIG_DIR/config.yaml"
        ;;
    reload)
        \$0 restart
        ;;
    backup)
        mkdir -p "\$BACKUP_DIR"
        backup_name="config_backup_\$(date +%Y%m%d_%H%M%S).tar.gz"
        tar -czf "\$BACKUP_DIR/\$backup_name" -C "\$INSTALL_DIR" "conf"
        echo "配置已备份到: \$BACKUP_DIR/\$backup_name"
        ;;
    restore)
        if [ -z "\$2" ]; then
            echo "请指定备份文件"
            echo "可用备份:"
            ls -lh "\$BACKUP_DIR"/config_backup_*.tar.gz 2>/dev/null || echo "无备份文件"
            exit 1
        fi
        
        if [ ! -f "\$2" ]; then
            # 尝试在备份目录中查找
            if [ -f "\$BACKUP_DIR/\$2" ]; then
                backup_file="\$BACKUP_DIR/\$2"
            elif [ -f "\$2" ]; then
                backup_file="\$2"
            else
                echo "备份文件不存在: \$2"
                exit 1
            fi
        else
            backup_file="\$2"
        fi
        
        \$0 stop
        echo "正在恢复配置..."
        rm -rf "\$CONFIG_DIR"
        tar -xzf "\$backup_file" -C "\$INSTALL_DIR"
        echo "配置恢复完成"
        \$0 start
        ;;
    version)
        if [ -f "\$INSTALL_DIR/version.txt" ]; then
            echo "当前版本: \$(cat \$INSTALL_DIR/version.txt)"
        else
            echo "版本信息未找到"
        fi
        ;;
    *)
        echo "simsshclient 管理工具"
        echo "用法: \$0 {start|stop|restart|status|logs|config|reload|backup|restore|version}"
        echo ""
        echo "   start             启动服务"
        echo "   stop              停止服务"
        echo "   restart           重启服务"
        echo "   status            查看状态"
        echo "   logs [options]    查看日志"
        echo "   config            编辑配置"
        echo "   reload            重新加载配置"
        echo "   backup            备份配置"
        echo "   restore <file>    恢复配置"
        echo "   version           查看版本"
        echo ""
        echo "配置目录: \$CONFIG_DIR"
        echo "备份目录: \$BACKUP_DIR"
        ;;
esac
EOF
    
    chmod +x "$MANAGEMENT_SCRIPT"
    log_info "管理脚本已创建: $MANAGEMENT_SCRIPT"
}

# 检查新版本
check_update() {
    log_info "检查新版本..."
    
    if ! command -v jq &> /dev/null; then
        log_warn "jq未安装，无法检查新版本"
        return 1
    fi
    
    local current_version="unknown"
    if [ -f "$VERSION_FILE" ]; then
        current_version=$(cat "$VERSION_FILE")
    fi
    
    log_info "当前版本: $current_version"
    
    # 获取最新版本信息
    local latest_info
    if latest_info=$(curl -s "$LATEST_VERSION_URL"); then
        local latest_version=$(echo "$latest_info" | jq -r '.tag_name')
        local download_url=$(echo "$latest_info" | jq -r '.assets[] | select(.name | contains("linux_amd64.tar.gz")) | .browser_download_url' | head -1)
        
        if [ -n "$latest_version" ] && [ "$latest_version" != "null" ]; then
            log_info "最新版本: $latest_version"
            
            if [ "$latest_version" != "$current_version" ]; then
                log_info "发现新版本: $latest_version"
                echo "$latest_version" > "$TEMP_DIR/latest_version.txt"
                echo "$download_url" > "$TEMP_DIR/latest_url.txt"
                return 0
            else
                log_info "已经是最新版本"
                return 1
            fi
        fi
    fi
    
    log_warn "无法获取版本信息"
    return 1
}

# 卸载程序
uninstall_program() {
    log_info "开始卸载 simsshclient..."
    
    # 停止服务
    stop_service
    
    # 禁用服务自启动
    disable_service
    
    # 删除服务文件
    remove_service_files
    
    # 删除管理脚本
    if [ -f "/usr/local/bin/${SERVICE_NAME}_ctl" ]; then
        rm -f "/usr/local/bin/${SERVICE_NAME}_ctl"
        log_info "已删除管理脚本"
    fi
    
    # 询问是否删除配置和备份
    if [ -d "$INSTALL_DIR" ]; then
        echo ""
        echo "请选择卸载选项:"
        echo "1) 完全删除所有文件（包括配置和备份）"
        echo "2) 只删除程序文件，保留配置和备份"
        echo "3) 取消卸载"
        echo -n "请选择 [1-3]: "
        
        read -r choice
        case $choice in
            1)
                log_info "删除所有文件..."
                rm -rf "$INSTALL_DIR"
                log_info "已删除安装目录: $INSTALL_DIR"
                ;;
            2)
                log_info "保留配置和备份..."
                # 只删除程序文件和版本信息
                rm -f "$INSTALL_DIR/$BINARY_NAME"
                rm -f "$INSTALL_DIR/version.txt"
                log_info "程序文件已删除，配置和备份已保留"
                ;;
            3)
                log_info "卸载已取消"
                exit 0
                ;;
            *)
                log_warn "无效选择，默认保留配置"
                rm -f "$INSTALL_DIR/$BINARY_NAME"
                rm -f "$INSTALL_DIR/version.txt"
                ;;
        esac
    fi
    
    # 删除日志文件
    if [ -d "/var/log/simsshclient" ]; then
        rm -rf "/var/log/simsshclient"
        log_info "已删除日志目录"
    fi
    
    log_info "卸载完成!"
}

# 显示安装完成信息
show_completion_info() {
    local version="unknown"
    if [ -f "$VERSION_FILE" ]; then
        version=$(cat "$VERSION_FILE")
    fi
    
    echo ""
    log_info "================================================"
    log_info "simsshclient 安装完成!"
    log_info "版本: $version"
    log_info "安装目录: $INSTALL_DIR"
    log_info "配置文件: $CONFIG_DIR/config.yaml"
    log_info "备份目录: $BACKUP_DIR"
    log_info ""
    
    if systemctl --version &> /dev/null && [ -f "/etc/systemd/system/$SERVICE_NAME.service" ]; then
        log_info "管理命令:"
        log_info "  启动服务: systemctl start $SERVICE_NAME"
        log_info "  停止服务: systemctl stop $SERVICE_NAME"
        log_info "  查看状态: systemctl status $SERVICE_NAME"
        log_info "  查看日志: journalctl -u $SERVICE_NAME -f"
    elif [ -f "/etc/init.d/$SERVICE_NAME" ]; then
        log_info "管理命令:"
        log_info "  启动服务: service $SERVICE_NAME start"
        log_info "  停止服务: service $SERVICE_NAME stop"
        log_info "  重启服务: service $SERVICE_NAME restart"
        log_info "  查看状态: service $SERVICE_NAME status"
    fi
    
    log_info ""
    log_info "简化的管理命令: ${SERVICE_NAME}_ctl"
    log_info "例如: ${SERVICE_NAME}_ctl start"
    log_info "      ${SERVICE_NAME}_ctl logs"
    log_info "      ${SERVICE_NAME}_ctl config"
    log_info "      ${SERVICE_NAME}_ctl backup"
    log_info "      ${SERVICE_NAME}_ctl version"
    log_info ""
    log_info "请编辑配置文件后重启服务:"
    log_info "  ${SERVICE_NAME}_ctl config"
    log_info "  ${SERVICE_NAME}_ctl restart"
    log_info "================================================"
    echo ""
}

# 清理临时文件
cleanup() {
    log_info "清理临时文件..."
    rm -rf "$TEMP_DIR"
}

# 显示帮助信息
show_help() {
    echo "simsshclient 安装管理脚本"
    echo ""
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  install        安装 simsshclient（默认）"
    echo "  uninstall      卸载 simsshclient"
    echo "  update         更新到最新版本"
    echo "  check-update   检查更新"
    echo "  reinstall      重新安装"
    echo "  backup         备份配置"
    echo "  restore <file> 恢复配置"
    echo "  status         查看安装状态"
    echo "  help           显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0 install      # 安装程序"
    echo "  $0 uninstall    # 卸载程序"
    echo "  $0 update       # 更新到最新版本"
    echo "  $0 status       # 查看状态"
}

# 显示状态
show_status() {
    echo "simsshclient 状态信息"
    echo "======================"
    
    if [ -f "$INSTALL_DIR/$BINARY_NAME" ]; then
        echo "安装状态: 已安装"
        echo "安装目录: $INSTALL_DIR"
        
        if [ -f "$VERSION_FILE" ]; then
            echo "版本: $(cat "$VERSION_FILE")"
        fi
        
        if systemctl --version &> /dev/null && systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
            echo "服务状态: 运行中"
            systemctl status "$SERVICE_NAME" --no-pager | grep -A 3 "Active:"
        elif [ -f "/etc/init.d/$SERVICE_NAME" ] && service "$SERVICE_NAME" status &>/dev/null; then
            echo "服务状态: 运行中"
        else
            echo "服务状态: 未运行"
        fi
        
        echo "配置文件: $CONFIG_DIR/config.yaml"
        
        if [ -d "$BACKUP_DIR" ]; then
            echo "备份数量: $(ls "$BACKUP_DIR"/*.tar.gz 2>/dev/null | wc -l)"
        fi
    else
        echo "安装状态: 未安装"
    fi
}

# 安装主函数
install_main() {
    log_info "开始安装 simsshclient..."
    log_info "安装日志: $LOG_FILE"
    
    check_root
    detect_os
    install_dependencies
    download_and_extract
    install_program
    setup_startup
    create_management_script
    start_service
    show_completion_info
    cleanup
    
    log_info "安装完成!"
}

# 更新主函数
update_main() {
    log_info "开始更新 simsshclient..."
    
    check_root
    
    if [ ! -f "$INSTALL_DIR/$BINARY_NAME" ]; then
        log_error "simsshclient 未安装，请先安装"
        exit 1
    fi
    
    if check_update; then
        local latest_version=$(cat "$TEMP_DIR/latest_version.txt")
        local latest_url=$(cat "$TEMP_DIR/latest_url.txt")
        
        if [ -z "$latest_url" ]; then
            log_error "无法获取下载链接"
            exit 1
        fi
        
        log_info "开始更新到版本: $latest_version"
        
        # 备份配置
        backup_config
        
        # 停止服务
        stop_service
        
        # 下载新版本
        if download_and_extract "$latest_url"; then
            # 安装新版本
            cp "$BINARY_PATH" "$INSTALL_DIR/$BINARY_NAME"
            chmod +x "$INSTALL_DIR/$BINARY_NAME"
            
            # 更新版本信息
            if [ -f "$TEMP_DIR/version.txt" ]; then
                cp "$TEMP_DIR/version.txt" "$VERSION_FILE"
            fi
            
            log_info "程序更新完成"
            
            # 启动服务
            if start_service; then
                log_info "更新成功! 当前版本: $latest_version"
            else
                log_warn "程序更新完成但服务启动失败"
            fi
        else
            log_error "下载新版本失败"
            exit 1
        fi
    else
        log_info "已经是最新版本"
    fi
    
    cleanup
}

# 主函数
main() {
    local action=${1:-"install"}
    
    case $action in
        install)
            install_main
            ;;
        uninstall)
            uninstall_program
            ;;
        update)
            update_main
            ;;
        check-update)
            check_root
            check_update
            ;;
        reinstall)
            log_info "重新安装 simsshclient..."
            stop_service
            rm -rf "$INSTALL_DIR"
            install_main
            ;;
        backup)
            check_root
            backup_config
            ;;
        restore)
            check_root
            if [ -z "$2" ]; then
                log_error "请指定备份文件"
                exit 1
            fi
            restore_config "$2"
            ;;
        status)
            show_status
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            log_error "未知操作: $action"
            show_help
            exit 1
            ;;
    esac
}

# 异常处理
trap 'log_error "安装过程中出现错误，退出码: $?"; cleanup; exit 1' ERR

# 运行主函数
main "$@"
