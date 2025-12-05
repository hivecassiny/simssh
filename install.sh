#!/bin/bash

# simsshclient 安装管理脚本
# 版本: 9.1
# 作者: 自动生成

# 配置变量
CHANGEFILEINFO="[*]"
APPVERSION="v9.1"
PROGRAM_NAME="simsshclient"
SERVICE_NAME="simsshclient"
INSTALL_DIR="/opt/simsshclient"
BIN_PATH="$INSTALL_DIR/simsshclient"
SERVICE_FILE="/etc/systemd/system/$SERVICE_NAME.service"
DOWNLOAD_URL="https://github.com/hivecassiny/simssh/releases/download/$APPVERSION/simsshclient_linux_amd64.tar.gz"
TEMP_DIR="/tmp/simsshclient_install"
LOG_FILE="/var/log/simsshclient_install.log"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_message() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# 打印彩色消息
print_color() {
    echo -e "${2}${1}${NC}"
}

# 检查是否以root运行
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_color "错误: 此脚本需要root权限运行！" "$RED"
        print_color "请使用 sudo 或以 root 用户运行此脚本" "$YELLOW"
        exit 1
    fi
}

# 检查命令是否存在
check_command() {
    if ! command -v "$1" &> /dev/null; then
        return 1
    fi
    return 0
}

# 安装依赖
install_dependencies() {
    log_message "检查系统依赖..."
    
    local missing_deps=()
    
    if ! check_command "curl"; then
        missing_deps+=("curl")
    fi
    
    if ! check_command "wget"; then
        missing_deps+=("wget")
    fi
    
    if ! check_command "tar"; then
        missing_deps+=("tar")
    fi
    
    if ! check_command "systemctl"; then
        print_color "错误: systemd 未找到，系统可能不支持systemd" "$RED"
        exit 1
    fi
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        print_color "安装缺少的依赖: ${missing_deps[*]}" "$YELLOW"
        
        if [[ -f /etc/debian_version ]]; then
            apt-get update
            apt-get install -y "${missing_deps[@]}"
        elif [[ -f /etc/redhat-release ]]; then
            yum install -y "${missing_deps[@]}"
        elif [[ -f /etc/arch-release ]]; then
            pacman -Sy --noconfirm "${missing_deps[@]}"
        else
            print_color "无法确定包管理器，请手动安装: ${missing_deps[*]}" "$RED"
            exit 1
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
        if wget --no-check-certificate -O "$output" "$url"; then
            return 0
        fi
    fi
    
    if check_command "curl"; then
        if curl -k -L -o "$output" "$url"; then
            return 0
        fi
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
    if [[ ! -f "$download_path" ]]; then
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
    
    # 检查可执行文件是否存在
    if [[ ! -f "$BIN_PATH" ]]; then
        # 可能在解压后的子目录中
        find "$INSTALL_DIR" -name "simsshclient" -type f -exec mv {} "$INSTALL_DIR/" \;
        
        if [[ ! -f "$BIN_PATH" ]]; then
            print_color "未找到可执行文件 simsshclient" "$RED"
            print_color "解压后的文件列表:" "$YELLOW"
            find "$INSTALL_DIR" -type f | tee -a "$LOG_FILE"
            exit 1
        fi
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
    if [[ -f "$SERVICE_FILE" ]]; then
        print_color "服务文件已存在，将覆盖..." "$YELLOW"
        systemctl stop "$SERVICE_NAME" 2>/dev/null
        systemctl disable "$SERVICE_NAME" 2>/dev/null
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
    
    # 重新加载systemd
    systemctl daemon-reload
    
    # 启用服务
    systemctl enable "$SERVICE_NAME"
    
    print_color "系统服务创建完成" "$GREEN"
}

# 启动服务
start_service() {
    print_color "启动服务..." "$BLUE"
    
    if systemctl start "$SERVICE_NAME"; then
        print_color "服务启动成功" "$GREEN"
        
        # 等待2秒检查状态
        sleep 2
        show_status
    else
        print_color "服务启动失败" "$RED"
        journalctl -u "$SERVICE_NAME" -n 20 --no-pager
    fi
}

# 显示服务状态
show_status() {
    print_color "\n服务状态:" "$BLUE"
    systemctl status "$SERVICE_NAME" --no-pager
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
    print_color "管理命令:" "$BLUE"
    print_color "  sudo systemctl start $SERVICE_NAME    # 启动服务" "$YELLOW"
    print_color "  sudo systemctl stop $SERVICE_NAME     # 停止服务" "$YELLOW"
    print_color "  sudo systemctl restart $SERVICE_NAME  # 重启服务" "$YELLOW"
    print_color "  sudo systemctl status $SERVICE_NAME   # 查看状态" "$YELLOW"
    print_color "  sudo journalctl -u $SERVICE_NAME -f   # 查看日志" "$YELLOW"
    print_color "" "$BLUE"
    print_color "卸载命令: sudo $0 --uninstall" "$RED"
    print_color "==============================" "$GREEN"
}

# 卸载程序
uninstall_program() {
    print_color "\n开始卸载 $PROGRAM_NAME..." "$RED"
    
    # 停止服务
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        print_color "停止服务..." "$YELLOW"
        systemctl stop "$SERVICE_NAME"
    fi
    
    # 禁用服务
    if systemctl is-enabled --quiet "$SERVICE_NAME" 2>/dev/null; then
        print_color "禁用服务..." "$YELLOW"
        systemctl disable "$SERVICE_NAME"
    fi
    
    # 删除服务文件
    if [[ -f "$SERVICE_FILE" ]]; then
        print_color "删除服务文件: $SERVICE_FILE" "$YELLOW"
        rm -f "$SERVICE_FILE"
        systemctl daemon-reload
        systemctl reset-failed
    fi
    
    # 删除安装目录
    if [[ -d "$INSTALL_DIR" ]]; then
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
    echo "  sudo $0 --install    # 安装程序"
    echo "  sudo $0 --uninstall  # 卸载程序"
    echo "  sudo $0 --status     # 查看状态"
}

# 显示版本
show_version() {
    echo "simsshclient 安装管理脚本 v1.0.0"
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

# 主菜单
show_menu() {
    clear
    print_color "========================================" "$BLUE"
    print_color "    simsshclient 安装管理程序" "$GREEN" "$APPVERSION"
    print_color "$CHANGEFILEINFO"
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
    read -p "请输入选择 (1-9): " choice
    
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
            systemctl stop "$SERVICE_NAME"
            print_color "服务已停止" "$GREEN"
            ;;
        6)
            check_root
            systemctl restart "$SERVICE_NAME"
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
    read -p "按回车键继续..."
    show_menu
}

# 处理命令行参数
if [[ $# -gt 0 ]]; then
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
            systemctl stop "$SERVICE_NAME"
            ;;
        --restart)
            check_root
            systemctl restart "$SERVICE_NAME"
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
