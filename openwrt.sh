#!/bin/sh

# simsshclient 安装管理脚本
# 作者: 自动生成
# 兼容 OpenWrt/Ash 版本

# 配置变量
CHANGEFILEINFO="[*]"
APPVERSION="v9.3"
PROGRAM_NAME="simsshclient"
SERVICE_NAME="simsshclient"
INSTALL_DIR="/opt/simsshclient"
BIN_PATH="$INSTALL_DIR/simsshclient"
SERVICE_FILE="/etc/systemd/system/$SERVICE_NAME.service"
DOWNLOAD_URL="https://github.com/hivecassiny/simssh/releases/download/$APPVERSION/simsshclient_linux_amd64.tar.gz"
TEMP_DIR="/tmp/simsshclient_install"
LOG_FILE="/var/log/simsshclient_install.log"

# 颜色定义（简化，ash可能不支持\033）
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 日志函数
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# 打印消息（简化颜色处理）
print_color() {
    if [ -t 1 ]; then  # 检查是否在终端中
        echo "$2$1$NC"
    else
        echo "$1"
    fi
}

# 检查是否以root运行
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        print_color "错误: 此脚本需要root权限运行！" "$RED"
        print_color "请使用 sudo 或以 root 用户运行此脚本" "$YELLOW"
        exit 1
    fi
}

# 检查命令是否存在
check_command() {
    command -v "$1" >/dev/null 2>&1
}

# 安装依赖
install_dependencies() {
    log_message "检查系统依赖..."
    
    # OpenWrt 使用 opkg 包管理器
    if [ -f /etc/openwrt_release ] || [ -f /etc/opkg ]; then
        log_message "检测到 OpenWrt 系统"
        
        # 检查并安装必要工具
        for cmd in curl wget tar; do
            if ! check_command "$cmd"; then
                print_color "安装 $cmd..." "$YELLOW"
                opkg update >/dev/null 2>&1
                opkg install "$cmd" >/dev/null 2>&1 || {
                    print_color "安装 $cmd 失败" "$RED"
                    exit 1
                }
            fi
        done
        
        # OpenWrt 使用 procd 而不是 systemd，但你的服务文件是 systemd 格式
        # 检查是否安装了 systemd
        if ! check_command "systemctl"; then
            print_color "警告: 未找到 systemd，OpenWrt 通常使用 procd" "$YELLOW"
            print_color "将使用兼容的启动方式" "$YELLOW"
        fi
    else
        # 原系统的包管理器检查
        if check_command "apt-get"; then
            apt-get update
            for cmd in curl wget tar; do
                if ! check_command "$cmd"; then
                    apt-get install -y "$cmd"
                fi
            done
        elif check_command "yum"; then
            for cmd in curl wget tar; do
                if ! check_command "$cmd"; then
                    yum install -y "$cmd"
                fi
            done
        elif check_command "pacman"; then
            for cmd in curl wget tar; do
                if ! check_command "$cmd"; then
                    pacman -Sy --noconfirm "$cmd"
                fi
            done
        fi
    fi
    
    log_message "依赖检查完成"
}

# 下载文件
download_file() {
    local url="$1"
    local output="$2"
    
    log_message "正在下载: $url"
    
    # 尝试使用wget，如果失败则使用curl
    if check_command "wget"; then
        wget --no-check-certificate -O "$output" "$url" >/dev/null 2>&1 && return 0
    fi
    
    if check_command "curl"; then
        curl -k -L -o "$output" "$url" >/dev/null 2>&1 && return 0
    fi
    
    print_color "下载失败！" "$RED"
    return 1
}

# 安装程序
install_program() {
    print_color "\n开始安装 $PROGRAM_NAME..." "$BLUE"
    
    # 创建临时目录
    mkdir -p "$TEMP_DIR"
    
    # 下载文件
    local download_path="$TEMP_DIR/simsshclient.tar.gz"
    if ! download_file "$DOWNLOAD_URL" "$download_path"; then
        print_color "下载失败，请检查网络连接或URL是否正确" "$RED"
        rm -rf "$TEMP_DIR"
        exit 1
    fi
    
    # 检查文件是否下载成功
    if [ ! -f "$download_path" ]; then
        print_color "下载的文件不存在" "$RED"
        rm -rf "$TEMP_DIR"
        exit 1
    fi
    
    # 创建安装目录
    print_color "创建安装目录: $INSTALL_DIR" "$BLUE"
    mkdir -p "$INSTALL_DIR"
    
    # 解压文件
    print_color "解压文件..." "$BLUE"
    if ! tar -xzf "$download_path" -C "$INSTALL_DIR"; then
        print_color "解压失败！" "$RED"
        rm -rf "$TEMP_DIR"
        exit 1
    fi
    
    # 查找可执行文件
    if [ -f "$BIN_PATH" ]; then
        # 文件在正确位置
        true
    else
        # 查找并移动文件
        for file in "$INSTALL_DIR"/* "$INSTALL_DIR"/*/* 2>/dev/null; do
            if [ -x "$file" ] && [ "$(basename "$file")" = "simsshclient" ]; then
                mv "$file" "$BIN_PATH"
                break
            fi
        done
    fi
    
    if [ ! -f "$BIN_PATH" ]; then
        print_color "未找到可执行文件 simsshclient" "$RED"
        print_color "解压后的文件列表:" "$YELLOW"
        find "$INSTALL_DIR" -type f | tee -a "$LOG_FILE"
        exit 1
    fi
    
    # 设置执行权限
    chmod +x "$BIN_PATH"
    
    # 创建配置文件目录
    mkdir -p "$INSTALL_DIR/conf"
    
    # 清理临时文件
    rm -rf "$TEMP_DIR"
    
    print_color "程序文件安装完成" "$GREEN"
}

# 创建系统服务
create_service() {
    print_color "创建系统服务..." "$BLUE"
    
    # 检查服务是否已存在
    if [ -f "$SERVICE_FILE" ]; then
        print_color "服务文件已存在，将覆盖..." "$YELLOW"
        if check_command "systemctl"; then
            systemctl stop "$SERVICE_NAME" 2>/dev/null
            systemctl disable "$SERVICE_NAME" 2>/dev/null
        fi
    fi
    
    # 创建服务文件
    cat > "$SERVICE_FILE" << EOF
[Unit]
Description=SimSSH Client Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=$BIN_PATH
Restart=always
RestartSec=3
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=$SERVICE_NAME

# 安全设置
NoNewPrivileges=true
ProtectSystem=strict
PrivateTmp=true
PrivateDevices=true
ProtectHome=true
ReadWritePaths=$INSTALL_DIR

[Install]
WantedBy=multi-user.target
EOF
    
    # 如果 systemd 存在，使用它
    if check_command "systemctl"; then
        systemctl daemon-reload
        systemctl enable "$SERVICE_NAME"
        print_color "系统服务创建完成" "$GREEN"
    else
        print_color "systemd 未找到，请手动设置启动" "$YELLOW"
        print_color "服务文件已创建: $SERVICE_FILE" "$BLUE"
    fi
}

# 启动服务
start_service() {
    print_color "启动服务..." "$BLUE"
    
    if check_command "systemctl"; then
        if systemctl start "$SERVICE_NAME"; then
            print_color "服务启动成功" "$GREEN"
            sleep 2
            show_status
        else
            print_color "服务启动失败" "$RED"
            if check_command "journalctl"; then
                journalctl -u "$SERVICE_NAME" -n 20 --no-pager
            fi
        fi
    else
        print_color "无法启动服务，缺少 systemctl" "$RED"
        print_color "请手动运行: $BIN_PATH" "$YELLOW"
    fi
}

# 显示服务状态
show_status() {
    print_color "\n服务状态:" "$BLUE"
    if check_command "systemctl"; then
        systemctl status "$SERVICE_NAME" --no-pager 2>/dev/null || {
            print_color "无法获取服务状态" "$RED"
            ps aux | grep -v grep | grep "$PROGRAM_NAME"
        }
    else
        print_color "使用 systemctl 检查状态" "$YELLOW"
        ps aux | grep -v grep | grep "$PROGRAM_NAME"
    fi
}

# 显示安装信息
show_install_info() {
    print_color "\n========== 安装完成 ==========" "$GREEN"
    print_color "程序名称: $PROGRAM_NAME" "$BLUE"
    print_color "安装目录: $INSTALL_DIR" "$BLUE"
    print_color "配置文件: $INSTALL_DIR/conf/" "$BLUE"
    print_color "服务名称: $SERVICE_NAME" "$BLUE"
    print_color "服务文件: $SERVICE_FILE" "$BLUE"
    print_color "日志文件: $LOG_FILE" "$BLUE"
    print_color "" "$BLUE"
    
    if check_command "systemctl"; then
        print_color "管理命令:" "$BLUE"
        print_color "  systemctl start $SERVICE_NAME    # 启动服务" "$YELLOW"
        print_color "  systemctl stop $SERVICE_NAME     # 停止服务" "$YELLOW"
        print_color "  systemctl restart $SERVICE_NAME  # 重启服务" "$YELLOW"
        print_color "  systemctl status $SERVICE_NAME   # 查看状态" "$YELLOW"
        print_color "  journalctl -u $SERVICE_NAME -f   # 查看日志" "$YELLOW"
    else
        print_color "启动命令:" "$BLUE"
        print_color "  $BIN_PATH &" "$YELLOW"
    fi
    
    print_color "" "$BLUE"
    print_color "卸载命令: $0 --uninstall" "$RED"
    print_color "==============================" "$GREEN"
}

# 卸载程序
uninstall_program() {
    print_color "\n开始卸载 $PROGRAM_NAME..." "$RED"
    
    # 停止服务
    if check_command "systemctl"; then
        if systemctl is-active "$SERVICE_NAME" 2>/dev/null; then
            print_color "停止服务..." "$YELLOW"
            systemctl stop "$SERVICE_NAME"
        fi
        
        if systemctl is-enabled "$SERVICE_NAME" 2>/dev/null; then
            print_color "禁用服务..." "$YELLOW"
            systemctl disable "$SERVICE_NAME"
        fi
    else
        # 手动停止进程
        pkill -f "$PROGRAM_NAME" 2>/dev/null && print_color "停止进程..." "$YELLOW"
    fi
    
    # 删除服务文件
    if [ -f "$SERVICE_FILE" ]; then
        print_color "删除服务文件: $SERVICE_FILE" "$YELLOW"
        rm -f "$SERVICE_FILE"
        if check_command "systemctl"; then
            systemctl daemon-reload
            systemctl reset-failed
        fi
    fi
    
    # 删除安装目录
    if [ -d "$INSTALL_DIR" ]; then
        print_color "删除安装目录: $INSTALL_DIR" "$YELLOW"
        rm -rf "$INSTALL_DIR"
    fi
    
    print_color "$PROGRAM_NAME 已完全卸载" "$GREEN"
}

# 显示帮助
show_help() {
    echo "用法: $0 [选项]"
    echo
    echo "选项:"
    echo "  --install       安装程序 (默认选项)"
    echo "  --uninstall     卸载程序"
    echo "  --reinstall     重新安装程序"
    echo "  --status        显示服务状态"
    echo "  --start         启动服务"
    echo "  --stop          停止服务"
    echo "  --restart       重启服务"
    echo "  --help          显示此帮助信息"
    echo "  --version       显示版本信息"
    echo
    echo "示例:"
    echo "  $0 --install    # 安装程序"
    echo "  $0 --uninstall  # 卸载程序"
    echo "  $0 --status     # 查看状态"
}

# 显示版本
show_version() {
    echo "simsshclient 安装管理脚本 v1.0.0 (OpenWrt兼容版)"
}

# 主安装函数
main_install() {
    check_root
    install_dependencies
    install_program
    create_service
    start_service
    show_install_info
}

# 主菜单（简化，避免复杂的交互）
show_menu() {
    clear
    print_color "========================================" "$BLUE"
    print_color "    simsshclient $APPVERSION 安装管理程序" "$GREEN" 
    print_color "    $CHANGEFILEINFO" "$YELLOW"
    print_color "========================================" "$BLUE"
    echo
    print_color "请选择操作:" "$BLUE"
    echo
    print_color "  1. 安装 simsshclient" "$YELLOW"
    print_color "  2. 卸载 simsshclient" "$RED"
    print_color "  3. 重新安装 simsshclient" "$YELLOW"
    print_color "  4. 启动服务" "$GREEN"
    print_color "  5. 停止服务" "$RED"
    print_color "  6. 重启服务" "$YELLOW"
    print_color "  7. 查看服务状态" "$BLUE"
    print_color "  8. 查看安装信息" "$BLUE"
    print_color "  9. 退出" "$BLUE"
    echo
    print_color "========================================" "$BLUE"
    echo
    printf "请输入选择 (1-9): "
    read choice
    
    case $choice in
        1)
            main_install
            ;;
        2)
            check_root
            uninstall_program
            ;;
        3)
            check_root
            uninstall_program
            sleep 2
            main_install
            ;;
        4)
            check_root
            start_service
            ;;
        5)
            check_root
            if check_command "systemctl"; then
                systemctl stop "$SERVICE_NAME"
            else
                pkill -f "$PROGRAM_NAME"
            fi
            print_color "服务已停止" "$GREEN"
            ;;
        6)
            check_root
            if check_command "systemctl"; then
                systemctl restart "$SERVICE_NAME"
            else
                pkill -f "$PROGRAM_NAME" && sleep 2
                "$BIN_PATH" &
            fi
            print_color "服务已重启" "$GREEN"
            show_status
            ;;
        7)
            show_status
            ;;
        8)
            show_install_info
            ;;
        9)
            print_color "再见！" "$GREEN"
            exit 0
            ;;
        *)
            print_color "无效的选择！" "$RED"
            ;;
    esac
    
    echo
    printf "按回车键继续..."
    read dummy
    show_menu
}

# 处理命令行参数
if [ $# -gt 0 ]; then
    case "$1" in
        --install|-i)
            main_install
            ;;
        --uninstall|-u)
            check_root
            uninstall_program
            ;;
        --reinstall|-r)
            check_root
            uninstall_program
            sleep 2
            main_install
            ;;
        --status|-s)
            show_status
            ;;
        --start)
            check_root
            start_service
            ;;
        --stop)
            check_root
            if check_command "systemctl"; then
                systemctl stop "$SERVICE_NAME"
            else
                pkill -f "$PROGRAM_NAME"
            fi
            ;;
        --restart)
            check_root
            if check_command "systemctl"; then
                systemctl restart "$SERVICE_NAME"
            else
                pkill -f "$PROGRAM_NAME" && sleep 2
                "$BIN_PATH" &
            fi
            show_status
            ;;
        --help|-h)
            show_help
            ;;
        --version|-v)
            show_version
            ;;
        *)
            echo "未知选项: $1"
            echo "使用 --help 查看帮助"
            exit 1
            ;;
    esac
else
    # 如果没有参数，显示菜单
    show_menu
fi
