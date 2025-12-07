#!/bin/sh

# simsshclient 安装管理脚本 (OpenWrt/iStoreOS专用版)
# 作者: 自动生成

# 配置变量
CHANGEFILEINFO="[*]"
APPVERSION="v9.3"
PROGRAM_NAME="simsshclient"
SERVICE_NAME="simsshclient"
INSTALL_DIR="/opt/simsshclient"
BIN_PATH="$INSTALL_DIR/simsshclient"
SERVICE_FILE="/etc/init.d/$SERVICE_NAME"  # OpenWrt使用init.d
DOWNLOAD_URL="https://github.com/hivecassiny/simssh/releases/download/$APPVERSION/simsshclient_linux_amd64.tar.gz"
TEMP_DIR="/tmp/simsshclient_install"
LOG_FILE="/var/log/simsshclient_install.log"

# 简单的颜色定义（兼容ash）
RED='\e[31m'
GREEN='\e[32m'
YELLOW='\e[33m'
BLUE='\e[34m'
NC='\e[0m'

# 日志函数
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# 打印颜色消息
print_color() {
    printf "${2}%s${NC}\n" "$1"
}

# 检查是否以root运行
check_root() {
    if [ $(id -u) -ne 0 ]; then
        print_color "错误: 此脚本需要root权限运行！" "$RED"
        print_color "请使用 sudo 或以 root 用户运行此脚本" "$YELLOW"
        exit 1
    fi
}

# 检查命令是否存在
check_command() {
    command -v "$1" >/dev/null 2>&1
    return $?
}

# 安装OpenWrt依赖
install_opkg_deps() {
    log_message "检查OpenWrt系统依赖..."
    
    # 更新opkg列表
    print_color "更新软件包列表..." "$BLUE"
    opkg update >/dev/null 2>&1
    
    # 检查并安装必要工具
    for cmd in curl wget tar; do
        if ! check_command "$cmd"; then
            print_color "安装 $cmd..." "$YELLOW"
            opkg install "$cmd" >/dev/null 2>&1
            if [ $? -ne 0 ]; then
                print_color "安装 $cmd 失败，尝试继续..." "$RED"
            fi
        fi
    done
    
    log_message "依赖检查完成"
}

# 下载文件
download_file() {
    local url="$1"
    local output="$2"
    
    log_message "正在下载: $url"
    
    # 优先使用wget
    if check_command "wget"; then
        if wget --no-check-certificate -O "$output" "$url" 2>>"$LOG_FILE"; then
            return 0
        fi
    fi
    
    # 回退到curl
    if check_command "curl"; then
        if curl -k -L -o "$output" "$url" 2>>"$LOG_FILE"; then
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
    rm -rf "$TEMP_DIR" 2>/dev/null
    mkdir -p "$TEMP_DIR"
    
    # 下载文件
    local download_path="$TEMP_DIR/simsshclient.tar.gz"
    if ! download_file "$DOWNLOAD_URL" "$download_path"; then
        print_color "下载失败，请检查网络连接或URL是否正确" "$RED"
        rm -rf "$TEMP_DIR" 2>/dev/null
        exit 1
    fi
    
    # 检查文件是否下载成功
    if [ ! -f "$download_path" ]; then
        print_color "下载的文件不存在" "$RED"
        rm -rf "$TEMP_DIR" 2>/dev/null
        exit 1
    fi
    
    # 创建安装目录
    print_color "创建安装目录: $INSTALL_DIR" "$BLUE"
    rm -rf "$INSTALL_DIR" 2>/dev/null
    mkdir -p "$INSTALL_DIR"
    
    # 解压文件
    print_color "解压文件..." "$BLUE"
    if ! tar -xzf "$download_path" -C "$INSTALL_DIR" 2>>"$LOG_FILE"; then
        print_color "解压失败！" "$RED"
        rm -rf "$TEMP_DIR" 2>/dev/null
        exit 1
    fi
    
    # 查找可执行文件
    BIN_FOUND=0
    # 先在根目录查找
    if [ -f "$INSTALL_DIR/simsshclient" ]; then
        BIN_FOUND=1
    else
        # 递归查找
        for file in $(find "$INSTALL_DIR" -type f 2>/dev/null); do
            if [ -x "$file" ] && [ "$(basename "$file")" = "simsshclient" ] || [ "$(basename "$file")" = "$PROGRAM_NAME" ]; then
                mv "$file" "$BIN_PATH" 2>/dev/null
                BIN_FOUND=1
                break
            fi
        done
    fi
    
    if [ $BIN_FOUND -eq 0 ]; then
        print_color "未找到可执行文件 simsshclient" "$RED"
        print_color "解压后的文件列表:" "$YELLOW"
        find "$INSTALL_DIR" -type f 2>/dev/null | tee -a "$LOG_FILE"
        print_color "请检查下载的文件是否正确" "$RED"
        exit 1
    fi
    
    # 设置执行权限
    chmod 755 "$BIN_PATH"
    
    # 检查文件是否为有效的可执行文件
    if ! "$BIN_PATH" --version >/dev/null 2>&1 && ! "$BIN_PATH" -v >/dev/null 2>&1 && ! "$BIN_PATH" version >/dev/null 2>&1; then
        print_color "警告: 可执行文件可能不是正确的程序" "$YELLOW"
        file "$BIN_PATH" | tee -a "$LOG_FILE"
    fi
    
    # 创建配置文件目录
    mkdir -p "$INSTALL_DIR/conf"
    
    # 清理临时文件
    rm -rf "$TEMP_DIR" 2>/dev/null
    
    print_color "程序文件安装完成" "$GREEN"
}

# 创建OpenWrt init.d服务
create_openwrt_service() {
    print_color "创建OpenWrt服务脚本..." "$BLUE"
    
    # 检查服务是否已存在
    if [ -f "$SERVICE_FILE" ]; then
        print_color "服务文件已存在，将覆盖..." "$YELLOW"
        /etc/init.d/"$SERVICE_NAME" stop >/dev/null 2>&1
        /etc/init.d/"$SERVICE_NAME" disable >/dev/null 2>&1
        rm -f "$SERVICE_FILE"
    fi
    
    # 创建OpenWrt init.d服务文件
    cat > "$SERVICE_FILE" << EOF
#!/bin/sh /etc/rc.common
# simsshclient - OpenWrt init.d script

USE_PROCD=1
START=99
STOP=10

start_service() {
    procd_open_instance
    procd_set_param command "$BIN_PATH"
    procd_set_param respawn 300 5 10
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_set_param user root
    procd_set_param pidfile /var/run/simsshclient.pid
    procd_set_param limits core="unlimited"
    procd_close_instance
}

stop_service() {
    killall -9 simsshclient 2>/dev/null
    rm -f /var/run/simsshclient.pid 2>/dev/null
}
EOF
    
    # 设置执行权限
    chmod 755 "$SERVICE_FILE"
    
    # 添加启动脚本
    print_color "启用服务..." "$BLUE"
    "$SERVICE_FILE" enable
    
    print_color "OpenWrt服务创建完成" "$GREEN"
}

# 启动服务
start_service() {
    print_color "启动服务..." "$BLUE"
    
    if [ -f "$SERVICE_FILE" ]; then
        if "$SERVICE_FILE" start; then
            print_color "服务启动成功" "$GREEN"
            sleep 2
            show_status
        else
            print_color "服务启动失败" "$RED"
            log_message "尝试手动启动..."
            if start-stop-daemon -S -b -m -p /var/run/simsshclient.pid -x "$BIN_PATH"; then
                print_color "手动启动成功" "$GREEN"
            else
                print_color "启动完全失败，请检查日志" "$RED"
                tail -n 20 "$LOG_FILE"
            fi
        fi
    else
        print_color "服务文件不存在，尝试手动启动" "$YELLOW"
        start-stop-daemon -S -b -m -p /var/run/simsshclient.pid -x "$BIN_PATH"
        if [ $? -eq 0 ]; then
            print_color "手动启动成功" "$GREEN"
        else
            print_color "启动失败" "$RED"
        fi
    fi
}

# 显示服务状态
show_status() {
    print_color "\n服务状态:" "$BLUE"
    echo "========================="
    
    # 检查进程
    if ps | grep -v grep | grep -q "$PROGRAM_NAME"; then
        print_color "✓ 服务正在运行" "$GREEN"
        ps | grep -v grep | grep "$PROGRAM_NAME"
    else
        print_color "✗ 服务未运行" "$RED"
    fi
    
    echo "-------------------------"
    
    # 检查端口
    if netstat -tlnp 2>/dev/null | grep -q "$PROGRAM_NAME"; then
        print_color "端口监听状态:" "$GREEN"
        netstat -tlnp 2>/dev/null | grep "$PROGRAM_NAME"
    fi
    
    echo "========================="
}

# 显示安装信息
show_install_info() {
    print_color "\n========== 安装完成 ==========" "$GREEN"
    print_color "程序名称: $PROGRAM_NAME" "$BLUE"
    print_color "版本: $APPVERSION" "$BLUE"
    print_color "安装目录: $INSTALL_DIR" "$BLUE"
    print_color "配置文件: $INSTALL_DIR/conf/" "$BLUE"
    print_color "服务名称: $SERVICE_NAME" "$BLUE"
    print_color "服务文件: $SERVICE_FILE" "$BLUE"
    print_color "日志文件: $LOG_FILE" "$BLUE"
    print_color "" "$BLUE"
    print_color "管理命令:" "$BLUE"
    print_color "  /etc/init.d/simsshclient start    # 启动服务" "$YELLOW"
    print_color "  /etc/init.d/simsshclient stop     # 停止服务" "$YELLOW"
    print_color "  /etc/init.d/simsshclient restart  # 重启服务" "$YELLOW"
    print_color "  /etc/init.d/simsshclient enable   # 启用开机启动" "$YELLOW"
    print_color "  /etc/init.d/simsshclient disable  # 禁用开机启动" "$YELLOW"
    print_color "" "$BLUE"
    print_color "查看日志: logread -e simsshclient" "$YELLOW"
    print_color "实时日志: logread -f | grep simsshclient" "$YELLOW"
    print_color "" "$BLUE"
    print_color "卸载命令: $0 --uninstall" "$RED"
    print_color "==============================" "$GREEN"
}

# 卸载程序
uninstall_program() {
    print_color "\n开始卸载 $PROGRAM_NAME..." "$RED"
    
    # 停止服务
    if [ -f "$SERVICE_FILE" ]; then
        print_color "停止服务..." "$YELLOW"
        "$SERVICE_FILE" stop >/dev/null 2>&1
        "$SERVICE_FILE" disable >/dev/null 2>&1
    fi
    
    # 确保进程停止
    killall -9 "$PROGRAM_NAME" 2>/dev/null
    sleep 2
    
    # 删除服务文件
    if [ -f "$SERVICE_FILE" ]; then
        print_color "删除服务文件: $SERVICE_FILE" "$YELLOW"
        rm -f "$SERVICE_FILE"
    fi
    
    # 删除启动链接
    rm -f /etc/rc.d/*"$SERVICE_NAME"* 2>/dev/null
    
    # 删除安装目录
    if [ -d "$INSTALL_DIR" ]; then
        print_color "删除安装目录: $INSTALL_DIR" "$YELLOW"
        rm -rf "$INSTALL_DIR"
    fi
    
    # 删除PID文件
    rm -f /var/run/simsshclient.pid 2>/dev/null
    
    print_color "$PROGRAM_NAME 已完全卸载" "$GREEN"
}

# 检查安装
check_install() {
    if [ -f "$BIN_PATH" ]; then
        return 0
    else
        return 1
    fi
}

# 显示帮助
show_help() {
    echo "Usage: $0 [command]"
    echo
    echo "Commands:"
    echo "  install     Install simsshclient"
    echo "  uninstall   Uninstall simsshclient"
    echo "  reinstall   Reinstall simsshclient"
    echo "  status      Show service status"
    echo "  start       Start service"
    echo "  stop        Stop service"
    echo "  restart     Restart service"
    echo "  help        Show this help"
    echo
    echo "Examples:"
    echo "  $0 install    # Install simsshclient"
    echo "  $0 status     # Check status"
}

# 主安装函数
main_install() {
    print_color "开始安装 simsshclient $APPVERSION..." "$BLUE"
    check_root
    
    # 检查是否是OpenWrt系统
    if [ ! -f /etc/openwrt_release ] && [ ! -d /etc/opkg ]; then
        print_color "错误: 此脚本仅支持 OpenWrt/iStoreOS 系统！" "$RED"
        exit 1
    fi
    
    install_opkg_deps
    install_program
    create_openwrt_service
    start_service
    show_install_info
    
    print_color "\n安装完成！" "$GREEN"
}

# 处理命令行参数
case "$1" in
    install|--install|-i)
        main_install
        ;;
    uninstall|--uninstall|-u)
        check_root
        uninstall_program
        ;;
    reinstall|--reinstall|-r)
        check_root
        uninstall_program
        sleep 3
        main_install
        ;;
    status|--status|-s)
        show_status
        ;;
    start|--start)
        check_root
        start_service
        ;;
    stop|--stop)
        check_root
        if [ -f "$SERVICE_FILE" ]; then
            "$SERVICE_FILE" stop
        else
            killall -9 "$PROGRAM_NAME" 2>/dev/null
        fi
        print_color "服务已停止" "$GREEN"
        ;;
    restart|--restart)
        check_root
        if [ -f "$SERVICE_FILE" ]; then
            "$SERVICE_FILE" restart
        else
            killall -9 "$PROGRAM_NAME" 2>/dev/null
            sleep 2
            start-stop-daemon -S -b -m -p /var/run/simsshclient.pid -x "$BIN_PATH"
        fi
        print_color "服务已重启" "$GREEN"
        sleep 1
        show_status
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        # 显示简单菜单
        echo "========================================"
        echo "    simsshclient 安装管理器"
        echo "    OpenWrt/iStoreOS专用版"
        echo "========================================"
        echo
        echo "请选择操作:"
        echo "  1. 安装 simsshclient"
        echo "  2. 卸载 simsshclient"
        echo "  3. 重启服务"
        echo "  4. 查看状态"
        echo "  5. 退出"
        echo
        echo "或使用命令行参数: $0 [install|uninstall|status]"
        echo
        printf "请输入选择 (1-5): "
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
                if [ -f "$SERVICE_FILE" ]; then
                    "$SERVICE_FILE" restart
                elif check_install; then
                    killall -9 "$PROGRAM_NAME" 2>/dev/null
                    sleep 2
                    start-stop-daemon -S -b -m -p /var/run/simsshclient.pid -x "$BIN_PATH"
                else
                    print_color "程序未安装" "$RED"
                fi
                ;;
            4)
                show_status
                ;;
            5)
                exit 0
                ;;
            *)
                print_color "无效选择" "$RED"
                exit 1
                ;;
        esac
        ;;
esac
