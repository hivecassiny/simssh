#!/bin/bash

# simsshclient 安装管理脚本 (OpenWrt iStoreOS专用版)
# 适配版本: iStoreOS 21.02.3
# 作者: 自动生成

# 配置变量
CHANGEFILEINFO="[*] OpenWrt iStoreOS 21.02.3专用版"
APPVERSION="v10.6"
PROGRAM_NAME="simsshclient"
SERVICE_NAME="simsshclient"
INSTALL_DIR="/opt/simsshclient"
BIN_PATH="$INSTALL_DIR/simsshclient"
INIT_SCRIPT="/etc/init.d/$SERVICE_NAME"
DOWNLOAD_URL="https://github.com/hivecassiny/simssh/releases/download/$APPVERSION/simsshclient_linux_amd64.tar.gz"
# 如果amd64版本不兼容，可能需要arm64版本
# DOWNLOAD_URL="https://github.com/hivecassiny/simssh/releases/download/$APPVERSION/simsshclient_linux_arm64.tar.gz"
TEMP_DIR="/tmp/simsshclient_install"
LOG_FILE="/var/log/simsshclient_install.log"

# 系统检测
OS_TYPE=""
ARCH_TYPE=""
DETECT_ARCH=$(uname -m)

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

# 检查系统类型
check_system() {
    print_color "检测系统中..." "$BLUE"
    
    # 检查是否是OpenWrt
    if [ -f "/etc/openwrt_release" ]; then
        OS_TYPE="openwrt"
        print_color "检测到 OpenWrt 系统" "$GREEN"
        
        # 读取版本信息
        if [ -f "/etc/openwrt_release" ]; then
            . /etc/openwrt_release
            print_color "发行版: $DISTRIB_DESCRIPTION" "$BLUE"
            print_color "版本: $DISTRIB_RELEASE" "$BLUE"
            print_color "架构: $DISTRIB_ARCH" "$BLUE"
            
            # 检查是否是iStoreOS
            if [[ "$DISTRIB_DESCRIPTION" == *"iStoreOS"* ]]; then
                print_color "检测到 iStoreOS 系统" "$GREEN"
                
                # 检查版本是否为21.02.3
                if [[ "$DISTRIB_RELEASE" != "21.02.3" ]]; then
                    print_color "警告: 当前版本为 $DISTRIB_RELEASE，脚本专为21.02.3版本优化" "$YELLOW"
                    read -p "是否继续? (y/n): " -n 1 -r
                    echo
                    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                        exit 1
                    fi
                fi
            else
                print_color "警告: 非iStoreOS系统，可能不完全兼容" "$YELLOW"
                read -p "是否继续? (y/n): " -n 1 -r
                echo
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    exit 1
                fi
            fi
            
            ARCH_TYPE="$DISTRIB_ARCH"
        fi
    else
        print_color "错误: 这不是OpenWrt系统！" "$RED"
        print_color "本脚本专为OpenWrt iStoreOS 21.02.3设计" "$RED"
        exit 1
    fi
    
    # 根据架构调整下载URL
    case "$ARCH_TYPE" in
        "x86_64"|"amd64")
            DOWNLOAD_URL="https://github.com/hivecassiny/simssh/releases/download/$APPVERSION/simsshclient_linux_amd64.tar.gz"
            print_color "使用AMD64版本" "$GREEN"
            ;;
        "aarch64"|"arm64")
            DOWNLOAD_URL="https://github.com/hivecassiny/simssh/releases/download/$APPVERSION/simsshclient_linux_arm64.tar.gz"
            print_color "使用ARM64版本" "$GREEN"
            ;;
        "arm"|"armv7l"|"armv6l")
            DOWNLOAD_URL="https://github.com/hivecassiny/simssh/releases/download/$APPVERSION/simsshclient_linux_arm.tar.gz"
            print_color "使用ARM版本" "$GREEN"
            ;;
        "mipsel"|"mips")
            DOWNLOAD_URL="https://github.com/hivecassiny/simssh/releases/download/$APPVERSION/simsshclient_linux_mipsle.tar.gz"
            print_color "使用MIPSLE版本" "$GREEN"
            ;;
        *)
            print_color "未知架构: $ARCH_TYPE，尝试使用amd64版本" "$YELLOW"
            ;;
    esac
    
    log_message "系统检测完成: $OS_TYPE $ARCH_TYPE"
}

# 检查是否以root运行
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_color "错误: 此脚本需要root权限运行！" "$RED"
        print_color "请使用 root 用户运行此脚本" "$YELLOW"
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
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        print_color "安装缺少的依赖: ${missing_deps[*]}" "$YELLOW"
        
        # OpenWrt使用opkg
        if check_command "opkg"; then
            opkg update
            for dep in "${missing_deps[@]}"; do
                opkg install "$dep"
            done
        else
            print_color "错误: opkg包管理器未找到" "$RED"
            exit 1
        fi
    fi
    
    # 检查/opt目录是否存在，不存在则创建
    if [ ! -d "/opt" ]; then
        print_color "创建/opt目录..." "$YELLOW"
        mkdir -p /opt
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
        if wget --no-check-certificate --timeout=30 -O "$output" "$url"; then
            return 0
        fi
    fi
    
    if check_command "curl"; then
        if curl -k -L --connect-timeout 30 -o "$output" "$url"; then
            return 0
        fi
    fi
    
    print_color "下载失败！" "$RED"
    print_color "请检查网络连接或URL是否正确" "$YELLOW"
    print_color "URL: $url" "$YELLOW"
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
        print_color "下载失败" "$RED"
        rm -rf "$TEMP_DIR"
        exit 1
    fi
    
    # 检查文件是否下载成功
    if [[ ! -f "$download_path" ]]; then
        print_color "下载的文件不存在" "$RED"
        rm -rf "$TEMP_DIR"
        exit 1
    fi
    
    # 检查文件大小
    local file_size=$(stat -c%s "$download_path" 2>/dev/null || stat -f%z "$download_path")
    if [ "$file_size" -lt 1024 ]; then
        print_color "下载的文件大小异常，可能下载失败" "$RED"
        rm -rf "$TEMP_DIR"
        exit 1
    fi
    
    # 创建安装目录
    print_color "创建安装目录: $INSTALL_DIR" "$BLUE"
    mkdir -p "$INSTALL_DIR"
    
    # 解压文件
    print_color "解压文件..." "$BLUE"
    if ! tar -xzf "$download_path" -C "$INSTALL_DIR" 2>/dev/null; then
        print_color "解压失败！" "$RED"
        print_color "可能是架构不匹配，请检查下载的版本是否正确" "$YELLOW"
        rm -rf "$TEMP_DIR"
        exit 1
    fi
    
    # 检查可执行文件是否存在
    if [[ ! -f "$BIN_PATH" ]]; then
        # 在解压目录中查找
        found_files=$(find "$INSTALL_DIR" -name "*simsshclient*" -type f 2>/dev/null)
        
        if [ -n "$found_files" ]; then
            # 找到文件，移动到正确位置
            first_file=$(echo "$found_files" | head -n1)
            print_color "找到文件: $first_file" "$YELLOW"
            mv "$first_file" "$BIN_PATH"
        fi
        
        if [[ ! -f "$BIN_PATH" ]]; then
            print_color "未找到可执行文件 simsshclient" "$RED"
            print_color "解压后的文件列表:" "$YELLOW"
            find "$INSTALL_DIR" -type f | tee -a "$LOG_FILE"
            print_color "请检查下载的压缩包内容" "$YELLOW"
            exit 1
        fi
    fi
    
    # 设置执行权限
    chmod +x "$BIN_PATH"
    
    # 创建配置文件目录
    mkdir -p "$INSTALL_DIR/conf"
    
    # 检查二进制文件是否可以运行
    print_color "检查二进制文件兼容性..." "$BLUE"
    if "$BIN_PATH" --version 2>&1 | head -n1; then
        print_color "二进制文件运行正常" "$GREEN"
    elif "$BIN_PATH" -v 2>&1 | head -n1; then
        print_color "二进制文件运行正常" "$GREEN"
    else
        print_color "警告: 无法直接运行二进制文件，可能需要手动配置" "$YELLOW"
        # 检查文件类型
        file "$BIN_PATH" | tee -a "$LOG_FILE"
    fi
    
    # 清理临时文件
    rm -rf "$TEMP_DIR"
    
    print_color "程序文件安装完成" "$GREEN"
}

# 创建OpenWrt init.d服务
create_openwrt_service() {
    print_color "创建OpenWrt服务..." "$BLUE"
    
    # 检查服务是否已存在
    if [[ -f "$INIT_SCRIPT" ]]; then
        print_color "服务文件已存在，将覆盖..." "$YELLOW"
        "$INIT_SCRIPT" stop 2>/dev/null
        "$INIT_SCRIPT" disable 2>/dev/null
        rm -f "$INIT_SCRIPT"
    fi
    
    # 创建init.d脚本
    cat > "$INIT_SCRIPT" << 'EOF'
#!/bin/sh /etc/rc.common
# SimSSH Client Service for OpenWrt

USE_PROCD=1
START=99
STOP=01

APP_NAME="simsshclient"
INSTALL_DIR="/opt/simsshclient"
BIN_PATH="$INSTALL_DIR/simsshclient"

start_service() {
    procd_open_instance
    procd_set_param command "$BIN_PATH"
    
    procd_set_param respawn 3600 5 0
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_set_param pidfile /var/run/$APP_NAME.pid
    
    procd_close_instance
}

stop_service() {
    # 停止服务
    killall -9 simsshclient 2>/dev/null
    rm -f /var/run/$APP_NAME.pid
}

restart() {
    stop
    sleep 2
    start
}

status() {
    if pgrep -f "$BIN_PATH" > /dev/null; then
        echo "正在运行"
        return 0
    else
        echo "未运行"
        return 1
    fi
}
EOF
    
    # 设置执行权限
    chmod +x "$INIT_SCRIPT"
    
    # 启用服务
    "$INIT_SCRIPT" enable
    
    print_color "OpenWrt服务创建完成" "$GREEN"
}

# 启动服务
start_service() {
    print_color "启动服务..." "$BLUE"
    
    if "$INIT_SCRIPT" start; then
        print_color "服务启动成功" "$GREEN"
        
        # 等待2秒检查状态
        sleep 2
        show_status
    else
        print_color "服务启动失败" "$RED"
        print_color "查看日志: logread | grep $SERVICE_NAME" "$YELLOW"
        logread | grep "$SERVICE_NAME" | tail -20
    fi
}

# 显示服务状态
show_status() {
    print_color "\n服务状态:" "$BLUE"
    
    if [ -f "$INIT_SCRIPT" ]; then
        "$INIT_SCRIPT" status
    else
        print_color "服务脚本不存在" "$RED"
    fi
    
    print_color "\n进程状态:" "$BLUE"
    if pgrep -f "simsshclient" > /dev/null; then
        print_color "simsshclient 进程正在运行" "$GREEN"
        ps | grep -v grep | grep "simsshclient"
    else
        print_color "simsshclient 进程未运行" "$RED"
    fi
    
    print_color "\n监听端口:" "$BLUE"
    netstat -tuln | grep -E "(Proto|LISTEN)" | head -10
}

# 显示安装信息
show_install_info() {
    print_color "\n========== 安装完成 ==========" "$GREEN"
    print_color "程序名称: $PROGRAM_NAME" "$BLUE"
    print_color "系统版本: iStoreOS 21.02.3" "$BLUE"
    print_color "系统架构: $ARCH_TYPE" "$BLUE"
    print_color "安装目录: $INSTALL_DIR" "$BLUE"
    print_color "配置文件: $INSTALL_DIR/conf/" "$BLUE"
    print_color "服务名称: $SERVICE_NAME" "$BLUE"
    print_color "服务脚本: $INIT_SCRIPT" "$BLUE"
    print_color "日志文件: $LOG_FILE" "$BLUE"
    print_color "下载URL: $DOWNLOAD_URL" "$BLUE"
    print_color "" "$BLUE"
    print_color "管理命令:" "$BLUE"
    print_color "  /etc/init.d/$SERVICE_NAME start    # 启动服务" "$YELLOW"
    print_color "  /etc/init.d/$SERVICE_NAME stop     # 停止服务" "$YELLOW"
    print_color "  /etc/init.d/$SERVICE_NAME restart  # 重启服务" "$YELLOW"
    print_color "  /etc/init.d/$SERVICE_NAME status   # 查看状态" "$YELLOW"
    print_color "  /etc/init.d/$SERVICE_NAME enable   # 启用开机启动" "$YELLOW"
    print_color "  /etc/init.d/$SERVICE_NAME disable  # 禁用开机启动" "$YELLOW"
    print_color "" "$BLUE"
    print_color "查看日志:" "$BLUE"
    print_color "  logread | grep $SERVICE_NAME       # 查看服务日志" "$YELLOW"
    print_color "  ps | grep simsshclient             # 查看进程" "$YELLOW"
    print_color "" "$BLUE"
    print_color "卸载命令: $0 --uninstall" "$RED"
    print_color "==============================" "$GREEN"
}

# 卸载程序
uninstall_program() {
    print_color "\n开始卸载 $PROGRAM_NAME..." "$RED"
    
    # 停止服务
    if [ -f "$INIT_SCRIPT" ]; then
        print_color "停止服务..." "$YELLOW"
        "$INIT_SCRIPT" stop
        "$INIT_SCRIPT" disable
    fi
    
    # 删除服务文件
    if [[ -f "$INIT_SCRIPT" ]]; then
        print_color "删除服务文件: $INIT_SCRIPT" "$YELLOW"
        rm -f "$INIT_SCRIPT"
    fi
    
    # 删除安装目录
    if [[ -d "$INSTALL_DIR" ]]; then
        print_color "删除安装目录: $INSTALL_DIR" "$YELLOW"
        rm -rf "$INSTALL_DIR"
    fi
    
    # 清理进程
    pkill -f "simsshclient" 2>/dev/null
    sleep 1
    pkill -9 -f "simsshclient" 2>/dev/null
    
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
    echo "注意: 此脚本专为OpenWrt iStoreOS 21.02.3设计"
    echo
    echo "示例:"
    echo "  $0 --install    # 安装程序"
    echo "  $0 --uninstall  # 卸载程序"
    echo "  $0 --status     # 查看状态"
}

# 显示版本
show_version() {
    echo "simsshclient OpenWrt专用安装管理脚本 v2.0.0"
    echo "适配系统: iStoreOS 21.02.3"
    echo "支持架构: x86_64, aarch64, arm, mipsel"
}

# 主安装函数
main_install() {
    check_root
    check_system
    install_dependencies
    install_program
    create_openwrt_service
    start_service
    show_install_info
}

# 主菜单
show_menu() {
    clear
    print_color "========================================" "$BLUE"
    print_color "  simsshclient $APPVERSION OpenWrt专用版" "$GREEN" 
    print_color "  $CHANGEFILEINFO" "$YELLOW"
    print_color "  检测系统: $DISTRIB_DESCRIPTION" "$BLUE"
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
    print_color "  9. 系统信息" "$BLUE"
    print_color "  0. 退出" "$BLUE"
    echo
    print_color "========================================" "$BLUE"
    echo
    read -p "请输入选择 (0-9): " choice
    
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
            if [ -f "$INIT_SCRIPT" ]; then
                "$INIT_SCRIPT" stop
                print_color "服务已停止" "$GREEN"
            else
                print_color "服务脚本不存在" "$RED"
            fi
            ;;
        6)
            check_root
            if [ -f "$INIT_SCRIPT" ]; then
                "$INIT_SCRIPT" restart
                print_color "服务已重启" "$GREEN"
                show_status
            else
                print_color "服务脚本不存在" "$RED"
            fi
            ;;
        7)
            show_status
            ;;
        8)
            show_install_info
            ;;
        9)
            print_color "\n系统信息:" "$BLUE"
            cat /etc/openwrt_release
            echo
            print_color "架构信息:" "$BLUE"
            uname -a
            echo
            print_color "磁盘空间:" "$BLUE"
            df -h / /opt /tmp
            ;;
        0)
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

# 初始化：检测系统
check_system

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
            if [ -f "$INIT_SCRIPT" ]; then
                "$INIT_SCRIPT" stop
            else
                print_color "服务脚本不存在" "$RED"
            fi
            ;;
        --restart)
            check_root
            if [ -f "$INIT_SCRIPT" ]; then
                "$INIT_SCRIPT" restart
                show_status
            else
                print_color "服务脚本不存在" "$RED"
            fi
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
