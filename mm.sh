#!/bin/bash

set -e

# GitHub 安装支持
# 使用方法1（推荐）: 设置环境变量后执行
#   SCRIPT_GITHUB_URL="https://raw.githubusercontent.com/user/repo/branch/mm.sh" bash <(curl -sSL https://raw.githubusercontent.com/user/repo/branch/mm.sh) install
# 使用方法2: 直接执行，脚本会使用本地版本
#   bash mm.sh install
# 使用方法3: 安装后使用系统命令
#   mm install
SCRIPT_GITHUB_URL="https://ghfast.top/https://raw.githubusercontent.com/yqt5420/iptv/refs/heads/master/mm.sh"
# 配置变量
TPROXY_PORT=7893
ROUTING_MARK=255
PROXY_FWMARK=1
PROXY_ROUTE_TABLE=100
COMMON_PORTS_TCP='{ 80, 443, 3389, 8080, 8443, 1080, 3128, 8081, 9080 }'

# 保留IP地址
ReservedIP4='{ 127.0.0.0/8, 10.0.0.0/8, 192.168.0.0/16, 100.64.0.0/10, 169.254.0.0/16, 172.16.0.0/12, 224.0.0.0/4, 240.0.0.0/4, 255.255.255.255/32 }'
CustomBypassIP='{ 192.168.0.0/16 }'

# 自动识别网络接口
detect_interfaces() {
    # 获取默认路由接口
    local default_if=$(ip route show default | awk '/default/ {print $5}' | head -n1)
    
    # 获取docker相关接口
    local docker_interfaces=""
    if command -v docker >/dev/null 2>&1; then
        # 检测docker网桥和虚拟接口
        for iface in $(ip link show | grep -E '^[0-9]+: (docker|br-)' | awk -F': ' '{print $2}' | awk '{print $1}'); do
            if [ -n "$docker_interfaces" ]; then
                docker_interfaces="$docker_interfaces, $iface"
            else
                docker_interfaces="$iface"
            fi
        done
    fi
    
    # 获取本地回环接口
    local lo_if="lo"
    
    # 构建接口列表
    local all_interfaces="$lo_if"
    if [ -n "$default_if" ] && [ "$default_if" != "lo" ]; then
        all_interfaces="$all_interfaces, $default_if"
    fi
    if [ -n "$docker_interfaces" ]; then
        all_interfaces="$all_interfaces, $docker_interfaces"
    fi
    
    echo "$all_interfaces"
}

# 获取主网络接口（用于output链）
get_main_interface() {
    local main_if=$(ip route show default | awk '/default/ {print $5}' | head -n1)
    echo "${main_if:-eth0}"
}

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查root权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本需要root权限运行"
        exit 1
    fi
}

# 识别系统架构
get_arch() {
    local arch_raw=$(uname -m)
    case "$arch_raw" in
        x86_64)              echo "amd64"  ;;
        i?86)                echo "386"    ;;
        aarch64|arm64)       echo "arm64"  ;;
        armv7l)              echo "armv7"  ;;
        s390x)               echo "s390x"  ;;
        *)
            log_error "不支持的架构: ${arch_raw}"
            exit 1
            ;;
    esac
}

# 简化的链接处理
get_url() {
    local url="$1"

    if [[ "$url" =~ ^https://github.com/ ]]; then
        echo "https://gh-proxy.org/${url}"
        return 0
    fi

    echo "$url"
    return 0
}

# 检测脚本的GitHub URL（如果是从curl下载的）
detect_script_url() {
    # 检查是否通过curl下载（通过检查脚本内容或环境变量）
    # 如果设置了SCRIPT_GITHUB_URL环境变量，直接使用
    if [ -n "${SCRIPT_GITHUB_URL:-}" ]; then
        echo "$SCRIPT_GITHUB_URL"
        return 0
    fi
    
    # 尝试从脚本自身检测（如果脚本中有标记）
    # 这里可以手动设置，或者通过参数传递
    echo ""
}

# 安装脚本为系统命令
install_script_as_command() {
    local cmd_name="mm"  # 使用 mm 作为命令名
    local install_path="/usr/local/bin/$cmd_name"
    local script_url="${SCRIPT_GITHUB_URL:-}"
    local config_file="/etc/mihomo/mm_script_url.conf"

    # 如果提供了github URL，保存到配置文件
    if [ -n "$script_url" ]; then
        echo "$script_url" > "$config_file" 2>/dev/null || true
        log_info "已保存 GitHub URL: $script_url"
    elif [ -f "$config_file" ]; then
        # 如果配置文件存在，读取保存的URL
        script_url=$(cat "$config_file" 2>/dev/null || echo "")
    fi

    # 如果提供了github URL，则从github下载；否则使用当前脚本
    if [ -n "$script_url" ]; then
        log_info "从 GitHub 下载最新脚本: $script_url"
        if curl -sSL "$script_url" -o "$install_path" 2>/dev/null; then
            chmod +x "$install_path"
            log_info "已从 GitHub 安装脚本为系统命令: $cmd_name"
        else
            log_warn "从 GitHub 下载脚本失败，使用本地脚本"
            cp -f "$0" "$install_path"
            chmod +x "$install_path"
            log_info "已将本地脚本安装为系统命令: $cmd_name"
        fi
    else
        # 复制当前脚本到系统命令路径
        cp -f "$0" "$install_path"
        chmod +x "$install_path"
        log_info "已将脚本安装为系统命令: $cmd_name"
    fi
    
    log_info "现在你可以直接使用 '$cmd_name <命令>' 来管理 mihomo 服务"
}

# 卸载系统命令
uninstall_script_command() {
    local cmd_name="mm"
    local install_path="/usr/local/bin/$cmd_name"
    local config_file="/etc/mihomo/mm_script_url.conf"

    if [[ -f "$install_path" ]]; then
        rm -f "$install_path"
        log_info "已移除系统命令: $cmd_name"
    fi
    
    # 清理保存的GitHub URL配置
    if [ -f "$config_file" ]; then
        rm -f "$config_file"
    fi
}

# 创建nftables配置文件
create_nftables_config() {
    local main_if=$(get_main_interface)
    local bypass_interfaces=$(detect_interfaces)
    
    # 构建接口匹配表达式
    local bypass_if_list=""
    if [ -n "$bypass_interfaces" ]; then
        # 将接口列表转换为nftables格式: { lo, docker0, br-xxx }
        bypass_if_list="{ $(echo "$bypass_interfaces" | sed 's/, */, /g') }"
    else
        bypass_if_list="{ lo }"
    fi
    
    cat > /etc/mihomo/nftables.conf << EOF
table inet mihomo {
    chain prerouting_tproxy {
        type filter hook prerouting priority filter; policy accept;
        iifname $bypass_if_list accept comment "放行容器回程"
        ip daddr $CustomBypassIP accept comment "绕过某些地址"
        fib daddr type local meta l4proto { tcp, udp } th dport $TPROXY_PORT reject with icmpx type host-unreachable comment "直接访问tproxy端口拒绝, 防止回环"
        fib daddr type local accept comment "本机绕过"
        ip daddr $ReservedIP4 accept comment "保留地址绕过"
        meta l4proto tcp socket transparent 1 meta mark set $PROXY_FWMARK accept comment "绕过已经建立的透明代理"
        meta l4proto { tcp, udp } tproxy to :$TPROXY_PORT meta mark set $PROXY_FWMARK comment "其他流量透明代理"
    }

    chain output_tproxy {
        type route hook output priority filter; policy accept;
        oifname != $main_if accept comment "绕过本机内部通信的流量(接口lo)"
        meta mark $ROUTING_MARK accept comment "绕过本机mihomo发出的流量"
        ip daddr $CustomBypassIP accept comment "绕过某些地址"
        fib daddr type local accept comment "本机绕过"
        ip daddr $ReservedIP4 accept comment "保留地址绕过"
        meta l4proto { tcp, udp } th dport $COMMON_PORTS_TCP meta mark set $PROXY_FWMARK comment "其他流量重路由到prerouting"
    }
    chain nat_p {
        type nat hook prerouting priority filter; policy accept;
        meta l4proto { tcp, udp } th dport 53 redirect to :1053 comment "DNS重定向prerouting到1053"
    }
    chain nat_output{
        type nat hook output priority filter; policy accept;
        meta l4proto { tcp, udp } th dport 53 redirect to :1053 comment "DNS重定向output到1053"

    }
}
EOF
    log_info "nftables 配置文件已创建: /etc/mihomo/nftables.conf"
    log_info "主网络接口: $main_if"
    log_info "本地接口: $bypass_interfaces"
}

# 软件下载
download_mihomo() {
    local arch=$(get_arch)
    local version_url="https://github.com/MetaCubeX/mihomo/releases/download/Prerelease-Alpha/version.txt"

    log_info "获取 mihomo 版本信息..."
    local version=$(curl -sSL "$(get_url "$version_url")") || {
        log_error "获取 mihomo 远程版本失败"
        exit 1
    }

    local filename="mihomo-linux-${arch}-${version}.gz"
    [ "$arch" = "amd64" ] && filename="mihomo-linux-${arch}-compatible-${version}.gz"

    local download_url="https://github.com/MetaCubeX/mihomo/releases/download/Prerelease-Alpha/${filename}"

    log_info "下载 mihomo..."
    # 增加重试机制
    for i in {1..3}; do
        if wget -q -O "$filename" "$(get_url "$download_url")"; then
            break
        elif [ $i -eq 3 ]; then
            log_error "mihomo 下载失败，请检查网络后重试"
            exit 1
        else
            log_warn "下载失败，第$i次重试..."
            sleep 2
        fi
    done

    log_info "解压 mihomo..."
    if ! gunzip "$filename"; then
        log_error "mihomo 解压失败"
        exit 1
    fi

    local binary_name="mihomo-linux-${arch}-${version}"
    [ "$arch" = "amd64" ] && binary_name="mihomo-linux-${arch}-compatible-${version}"

    if [ -f "$binary_name" ]; then
        mv "$binary_name" /usr/local/bin/mihomo
        chmod +x /usr/local/bin/mihomo
        log_info "mihomo 已安装到 /usr/local/bin/mihomo"
    else
        log_error "找不到解压后的文件"
        exit 1
    fi
}

# 创建systemd服务文件
create_systemd_service() {
    # 在函数内部使用变量，这样在heredoc中会被正确展开
    local fwmark=$PROXY_FWMARK
    local route_table=$PROXY_ROUTE_TABLE
    
    cat > /etc/systemd/system/mihomo.service << EOF
[Unit]
Description=mihomo transparent proxy service
After=network.target
Wants=network.target
Requires=network.target
Documentation=https://github.com/MetaCubeX/mihomo

[Service]
Type=simple
User=root
Group=root
RuntimeDirectory=mihomo
StateDirectory=mihomo
CacheDirectory=mihomo
LogsDirectory=mihomo

# 启动前准备
ExecStartPre=+/bin/bash -c 'echo "正在启动mihomo服务..."'
ExecStartPre=+/bin/bash -c 'sysctl -w net.ipv4.ip_forward=1 > /dev/null'
ExecStartPre=+/bin/bash -c 'sysctl -w net.core.default_qdisc=fq > /dev/null'
ExecStartPre=+/bin/bash -c 'sysctl -w net.ipv4.tcp_congestion_control=bbr > /dev/null'

# 启动mihomo
ExecStart=/usr/local/bin/mihomo -d /etc/mihomo

# 等待mihomo启动后再设置防火墙规则
ExecStartPost=+/bin/bash -c 'echo "等待mihomo启动..."'
ExecStartPost=+/bin/sleep 5
ExecStartPost=+/bin/bash -c 'echo "正在设置网络规则..."'
# 启动后设置防火墙规则
ExecStartPost=+/bin/bash -c 'ip -f inet rule add fwmark $fwmark lookup $route_table 2>/dev/null || true'
ExecStartPost=+/bin/bash -c 'ip -f inet route add local default dev lo table $route_table 2>/dev/null || true'
ExecStartPost=+/bin/bash -c 'nft -f /etc/mihomo/nftables.conf 2>/dev/null || true'

# 停止后清理防火墙规则（只清理mihomo表，不破坏其他规则）
ExecStop=+/bin/bash -c 'echo "正在清理网络规则..."'
ExecStop=+/bin/bash -c 'pkill mihomo 2>/dev/null || true'
ExecStop=+/bin/bash -c 'ip -f inet rule del fwmark $fwmark lookup $route_table 2>/dev/null || true'
ExecStop=+/bin/bash -c 'ip -f inet route flush table $route_table 2>/dev/null || true'
ExecStop=+/bin/bash -c 'nft delete table inet mihomo 2>/dev/null || true'

# 重新加载时只重新加载mihomo表
ExecReload=+/bin/bash -c 'nft delete table inet mihomo 2>/dev/null || true'
ExecReload=+/bin/bash -c 'nft -f /etc/mihomo/nftables.conf 2>/dev/null || true'

Restart=on-failure
RestartSec=5s
LimitNOFILE=infinity
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
NoNewPrivileges=yes

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    log_info "systemd 服务文件已创建"
}

# 创建配置目录和示例配置
create_config() {
    if [ ! -d /etc/mihomo ]; then
        mkdir -p /etc/mihomo
        log_info "创建配置目录 /etc/mihomo"
    fi

    if [ ! -f /etc/mihomo/config.yaml ]; then
        cat > /etc/mihomo/config.yaml << 'EOF'
# mihomo 配置文件示例
# 请根据实际情况修改此配置
mixed-port: 7890
socks-port: 7891
tproxy-port: 7893
routing-mark: 255
allow-lan: true
bind-address: '*'
mode: rule
log-level: error
ipv6: true
external-controller: 0.0.0.0:9090
external-ui: ./UI
external-ui-url: "https://ghfast.top/https://github.com/Zephyruso/zashboard/archive/refs/heads/gh-pages.zip"
keep-alive-interval: 15
keep-alive-idle: 15
tcp-concurrent: true
unified-delay: true
geo-auto-update: true
geo-update-interval: 24
geox-url: {geoip: "https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/geoip.dat", geosite: "https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/geosite.dat", mmdb: "https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/country.mmdb", asn: "https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/GeoLite2-ASN.mmdb"}
profile: {store-selected: true, store-fake-ip: true}
# enable: false=关闭TUN模式，true=开启（开启后为全局系统代理，需管理员权限）
dns: {enable: true, respect-rules: true, ipv6: true, listen: 0.0.0.0:1053, enhanced-mode: fake-ip, fake-ip-range: 198.18.0.1/16, fake-ip-filter: ["*.lan","*","*.local","geosite:private","geosite:cn"], nameserver: [https://1.1.1.1/dns-query, https://8.8.8.8/dns-query], proxy-server-nameserver: [https://223.5.5.5/dns-query], direct-nameserver: [https://223.5.5.5/dns-query]}

tun: {enable: false, stack: mixed, dns-hijack: ["any:53", "tcp://any:53"], auto-route: true, auto-redirect: true, auto-detect-interface: true, endpoint-independent-nat: true}

#节点相关配置
# 手动设置节点
# proxies:
#     -

##节点正则过滤规则
FilterAll: &FilterAll '^(?=.*(.))(?!.*((?i)群|邀请|返利|循环|官网|客服|网站|网址|获取|订阅|流量|到期|机场|下次|版本|官址|备用|过期|已用|联系|邮箱|所有|工单|贩卖|通知|倒卖|防止|国内|地址|频道|无法|说明|使用|提示|特别|访问|支持|教程|关注|更新|作者|上海|广东|北京|校园|以下|浙江|江苏|加入|(\b(USE|USED|TOTAL|EXPIRE|EMAIL|Panel|Channel|Author)\b|(\d{4}-\d{2}-\d{2}|\d+G)))).*$'
# 锚点 - 节点订阅配置
NodeParam: &NodeParam {type: http, interval: 3600, timeout: 1000, health-check: {enable: true, url: 'https://cp.cloudflare.com/generate_204', interval: 600}, filter: *FilterAll }

proxy-providers:
  kyx: {url: '订阅链接', <<: *NodeParam, path: './proxy_provider/Providers_kyx.yaml', override: {skip-cert-verify: true, additional-prefix: "别名"}}
  pdf: {url: '订阅链接', <<: *NodeParam, path: './proxy_provider/Providers_pdf.yaml', override: {skip-cert-verify: true, additional-prefix: "别名"}}

 #代理组配置
#负载均衡及自动测速配置 hidden: true
UrlTest: &UrlTest {type: url-test, interval: 600, tolerance: 50, lazy: true, url: 'https://cp.cloudflare.com/generate_204', disable-udp: false, timeout: 1000, max-failed-times: 1, include-all: true, hidden: true}
FallBack: &FallBack {type: fallback, interval: 600, tolerance: 50, lazy: true, url: 'https://cp.cloudflare.com/generate_204', disable-udp: false, timeout: 1000, max-failed-times: 1, include-all: true, hidden: true}

# 这里可以根据需要修改策略组名称、添加或删除策略组
proxy-groups:
  # PROXY: 主代理组（可自定义添加其他策略组到proxies列表中）
  - {name: PROXY, type: select, proxies: [AUTO,DIRECT,SELECT,FALLBACK]}
  - {name: VIDEOS, type: select, proxies: [AUTO,FALLBACK], include-all: true, filter: *FilterAll}
  - {name: SELECT, type: select, include-all: true, filter: *FilterAll}
  - {name: AUTO, <<: *UrlTest, filter: *FilterAll}
  - {name: FALLBACK, <<: *FallBack, filter: *FilterAll}

# 订阅规则
# 锚点 - 规则参数 [每天更新一次订阅规则，更新规则时使用Proxy策略]
RuleSet: &RuleSet {type: http, behavior: classical, interval: 86400, format: yaml, proxy: PROXY}
rule-providers:
  秋风广告规则:
    <<: *RuleSet
    url: "https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/Advertising/Advertising_Classical.yaml"
    path: ./rule_providers/AWAvenue-Ads-Rule-Clash.yaml

  anti广告规则:
    <<: *RuleSet
    path: ./rule_providers/anti.yaml
    url: "https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/Privacy/Privacy_Classical.yaml"
    interval: 60480

# 规则优先级从上到下，匹配到即停止
rules:
# 去广告
 - RULE-SET,秋风广告规则,REJECT
 - RULE-SET,anti广告规则,REJECT
# ========== AI服务专用代理规则 ==========
# PROXY策略组：适用于ChatGPT、Claude等AI服务（可根据需要添加或删除）
 - DOMAIN-SUFFIX,ping0.cc,PROXY
 - DOMAIN-SUFFIX,ipdata.co,PROXY
 - DOMAIN-SUFFIX,pingip.cn,PROXY
# PROXY策略组：需要代理访问的域名（根据个人需求自由添加）
 - DOMAIN-SUFFIX,live.com,PROXY
 - DOMAIN-SUFFIX,teracloud.jp,PROXY
# ========== 直连规则 ==========
# DIRECT策略组：不走代理直接连接（根据个人需求自由添加）
 - DOMAIN-KEYWORD,115,DIRECT
 - DOMAIN-KEYWORD,mediahelp,DIRECT
 - DOMAIN-KEYWORD,241100,DIRECT
 - DOMAIN-KEYWORD,247200,DIRECT
 - DOMAIN-SUFFIX,msftconnecttest.com,DIRECT
 - DOMAIN,ping.archlinux.org,DIRECT
 - DOMAIN-SUFFIX,msftncsi.com,DIRECT
 - DOMAIN-SUFFIX,steamserver.net,DIRECT
 - DOMAIN-SUFFIX,steamcontent.com,DIRECT
 - DOMAIN,stun.l.google.com,DIRECT
 - DOMAIN-SUFFIX,edu.cn,DIRECT
 - DOMAIN-SUFFIX,v6.navy,DIRECT
 - DOMAIN-SUFFIX,dynv6.com,DIRECT
 - DOMAIN-SUFFIX,bing.com,DIRECT

# ========== 基于GeoSite的智能分流规则 ==========
# 以下为固定规则，一般无需修改
# 如需调整某个服务的策略，可修改后面的策略组名称
 - GEOSITE,youtube,VIDEOS
 - GEOSITE,cursor,PROXY
 - GEOSITE,telegram,PROXY
 - GEOSITE,google,PROXY
 - GEOSITE,steam@cn,DIRECT
 - GEOSITE,category-games@cn,DIRECT
 - GEOSITE,category-ai-!cn,PROXY
 - GEOSITE,category-ai-cn,DIRECT
 - GEOSITE,onedrive,DIRECT
 - GEOSITE,private,DIRECT
 - GEOSITE,category-scholar-!cn,PROXY
 - GEOSITE,microsoft@cn,DIRECT
 - GEOSITE,apple-cn,DIRECT
 - GEOSITE,geolocation-!cn,PROXY
 - GEOSITE,CN,DIRECT
 - GEOIP,private,DIRECT,no-resolve
 - GEOIP,telegram,PROXY,no-resolve
 - GEOIP,CN,DIRECT
 # 兜底规则：以上规则都不匹配时使用PROXY代理
 - MATCH,PROXY
EOF
        log_warn "已创建示例配置文件 /etc/mihomo/config.yaml，请根据实际情况修改"
    fi
}

# 网络规则管理（调试用）
setup_rules() {
    check_root
    log_info "设置网络规则（调试模式）..."
    if [ -f /etc/mihomo/nftables.conf ]; then
        # 只加载mihomo表，不破坏其他规则
        nft -f /etc/mihomo/nftables.conf
        ip -f inet rule add fwmark $PROXY_FWMARK lookup $PROXY_ROUTE_TABLE 2>/dev/null || true
        ip -f inet route add local default dev lo table $PROXY_ROUTE_TABLE 2>/dev/null || true
        sysctl -w net.ipv4.ip_forward=1 > /dev/null
        sysctl -w net.core.default_qdisc=fq > /dev/null
        log_info "nftables 规则已应用（调试）"
    else
        log_error "nftables 配置文件不存在: /etc/mihomo/nftables.conf"
    fi
}

# 清理网络规则（调试用）
clear_rules() {
    check_root
    log_info "清理网络规则（调试模式）..."
    # 只清理mihomo相关的规则，不破坏其他规则
    IPRULE=$(ip rule show | grep "fwmark $PROXY_FWMARK lookup $PROXY_ROUTE_TABLE")
    if [ -n "$IPRULE" ]; then
        ip -f inet rule del fwmark $PROXY_FWMARK lookup $PROXY_ROUTE_TABLE 2>/dev/null || true
        ip -f inet route flush table $PROXY_ROUTE_TABLE 2>/dev/null || true
    fi
    # 只删除mihomo表，不破坏其他表
    nft delete table inet mihomo 2>/dev/null || true
    log_info "mihomo 网络规则已清理（调试）"
}

# 安装mihomo
install_mihomo() {
    check_root
    log_info "开始安装 mihomo..."

    download_mihomo
    create_config
    create_nftables_config
    create_systemd_service
    install_script_as_command  # 安装脚本为系统命令

    log_info "安装完成！"
    log_info "已将脚本安装为系统命令: mm"
    log_info "现在你可以直接使用 'mm <命令>' 来管理 mihomo 服务"
    log_info ""
    log_info "请编辑 /etc/mihomo/config.yaml 配置你的代理服务器"
    log_info "然后使用以下命令启动服务:"
    log_info "  mm start"
    log_info "  mm enable"
}

# 启动服务
start_service() {
    check_root
    log_info "启动 mihomo 服务..."

    if systemctl is-active mihomo > /dev/null 2>&1; then
        log_info "mihomo 服务已经在运行"
    else
        systemctl start mihomo
        # 等待服务启动
        sleep 2
        if systemctl is-active mihomo > /dev/null 2>&1; then
            log_info "mihomo 服务启动完成"
        else
            log_error "mihomo 服务启动失败"
            journalctl -u mihomo -n 10 --no-pager
            exit 1
        fi
    fi
}

# 停止服务
stop_service() {
    check_root
    log_info "停止 mihomo 服务..."

    if systemctl is-active mihomo > /dev/null 2>&1; then
        systemctl stop mihomo
        # 等待服务停止
        sleep 2
        if systemctl is-active mihomo > /dev/null 2>&1; then
            log_warn "mihomo 服务停止失败，强制停止..."
            systemctl kill mihomo
            sleep 1
        fi
        log_info "mihomo 服务已停止"
    else
        log_info "mihomo 服务未在运行"
    fi
}

# 重启服务
restart_service() {
    check_root
    log_info "重启 mihomo 服务..."

    if systemctl is-active mihomo > /dev/null 2>&1; then
        systemctl restart mihomo
    else
        systemctl start mihomo
    fi

    sleep 2
    if systemctl is-active mihomo > /dev/null 2>&1; then
        log_info "mihomo 服务重启完成"
    else
        log_error "mihomo 服务重启失败"
        journalctl -u mihomo -n 10 --no-pager
        exit 1
    fi
}

# 查看服务状态
status_service() {
    systemctl status mihomo
}

# 启用开机自启
enable_service() {
    check_root
    systemctl enable mihomo
    log_info "mihomo 服务已设置为开机自启"
}

# 禁用开机自启
disable_service() {
    check_root
    systemctl disable mihomo
    log_info "mihomo 服务开机自启已禁用"
}

# 查看日志
view_logs() {
    journalctl -u mihomo -f
}

# 卸载mihomo
uninstall_mihomo() {
    check_root
    log_info "开始卸载 mihomo..."

    stop_service
    disable_service
    uninstall_script_command  # 卸载系统命令

    if [ -f /etc/systemd/system/mihomo.service ]; then
        rm -f /etc/systemd/system/mihomo.service
        systemctl daemon-reload
        log_info "已移除 systemd 服务文件"
    fi

    if [ -f /usr/local/bin/mihomo ]; then
        rm -f /usr/local/bin/mihomo
        log_info "已移除 mihomo 二进制文件"
    fi

    if [ -d /etc/mihomo ]; then
        rm -rf /etc/mihomo
        log_info "已移除配置目录 /etc/mihomo"
    fi

    log_info "卸载完成"
}

# 显示使用说明
show_usage() {
    cat << EOF
使用: $(basename "$0") <命令>

命令:
  install     安装 mihomo 和 systemd 服务（同时安装为系统命令 mm）
  uninstall   卸载 mihomo（同时移除系统命令 mm）
  start       启动 mihomo 服务
  stop        停止 mihomo 服务
  restart     重启 mihomo 服务
  status      查看服务状态
  enable      启用开机自启
  disable     禁用开机自启
  logs        查看服务日志
  setup-rules 仅设置网络规则（调试用）
  clear-rules 仅清理网络规则（调试用）

示例:
  $(basename "$0") install    # 安装 mihomo 并安装为系统命令 mm
  mm start                    # 安装后使用系统命令启动服务
  mm enable                   # 启用开机自启

注意: 安装完成后请编辑 /etc/mihomo/config.yaml 配置你的代理服务器
EOF
}

# 主函数
main() {
    # 如果是从curl下载的，尝试检测GitHub URL
    # 通过检查是否通过管道传递来判断
    if [ -t 0 ] && [ -z "${SCRIPT_GITHUB_URL:-}" ]; then
        # 交互式终端，不是从管道读取
        SCRIPT_GITHUB_URL=""
    fi
    
    if [ $# != 1 ]
    then
        show_usage
        exit 1
    fi

    case "$1" in
        install)
            install_mihomo
            ;;
        uninstall)
            uninstall_mihomo
            ;;
        start)
            start_service
            ;;
        stop)
            stop_service
            ;;
        restart)
            restart_service
            ;;
        status)
            status_service
            ;;
        enable)
            enable_service
            ;;
        disable)
            disable_service
            ;;
        logs)
            view_logs
            ;;
        setup-rules)
            setup_rules
            ;;
        clear-rules)
            clear_rules
            ;;
        *)
            log_error "未知命令: $1"
            show_usage
            exit 1
            ;;
    esac
}

# 如果脚本是通过 curl | bash 方式执行的，尝试从环境变量或参数中获取GitHub URL
# 使用方法: SCRIPT_GITHUB_URL="https://raw.githubusercontent.com/user/repo/branch/mm.sh" bash <(curl -sSL ...)
# 或者: curl -sSL ... | SCRIPT_GITHUB_URL="..." bash

# 运行主函数
main "$@"
