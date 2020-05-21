#!/bin/bash

blue(){
    echo -e "\033[34m\033[01m$1\033[0m"
}
green(){
    echo -e "\033[32m\033[01m$1\033[0m"
}
red(){
    echo -e "\033[31m\033[01m$1\033[0m"
}
version_lt(){
    test "$(echo "$@" | tr " " "\n" | sort -rV | head -n 1)" != "$1"; 
}

install_php7(){

    $systemPackage -y install  unzip vim tcl expect curl
    echo
    echo
    green "=========="
    green " 安装PHP7"
    green "=========="
    sleep 1
    rpm -Uvh https://mirror.webtatic.com/yum/el7/webtatic-release.rpm
    $systemPackage -y install php70w php70w-mysql php70w-gd php70w-xml php70w-fpm
    systemctl enable php-fpm
    systemctl start  php-fpm
}

install_mysql(){

    green "==============="
    green "   安装MySQL"
    green "==============="
    sleep 1
    wget http://repo.mysql.com/mysql-community-release-el7-5.noarch.rpm
    rpm -ivh mysql-community-release-el7-5.noarch.rpm
    $systemPackage -y install mysql-server
    systemctl enable mysqld.service
    systemctl start  mysqld.service

    echo
    green "==============="
    green "   配置MySQL"
    green "==============="
    sleep 2
    mysqlpasswd=$(cat /dev/urandom | head -1 | md5sum | head -c 8)
    
/usr/bin/expect << EOF
spawn mysql_secure_installation
expect "password for root" {send "\r"}
expect "root password" {send "Y\r"}
expect "New password" {send "$mysqlpasswd\r"}
expect "Re-enter new password" {send "$mysqlpasswd\r"}
expect "Remove anonymous users" {send "Y\r"}
expect "Disallow root login remotely" {send "Y\r"}
expect "database and access" {send "Y\r"}
expect "Reload privilege tables" {send "Y\r"}
spawn mysql -u root -p
expect "Enter password" {send "$mysqlpasswd\r"}
expect "mysql" {send "create database wordpress_db;\r"}
expect "mysql" {send "exit\r"}
EOF


}

install_nginx(){
    echo
    echo
    green "==============="
    green "  安装nginx"
    green "==============="
    sleep 1
    $systemPackage -y install nginx
    systemctl enable nginx.service
    systemctl stop nginx.service
    rm -f /etc/nginx/conf.d/default.conf
    rm -f /etc/nginx/nginx.conf


cat > /etc/nginx/nginx.conf <<-EOF
user  nginx;
worker_processes  1;
error_log  /var/log/nginx/error.log warn;
pid        /var/run/nginx.pid;
events {
    worker_connections  1024;
}
http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;
    log_format  main  '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                      '\$status \$body_bytes_sent "\$http_referer" '
                      '"\$http_user_agent" "\$http_x_forwarded_for"';
    access_log  /var/log/nginx/access.log  main;
    sendfile        on;
    #tcp_nopush     on;
    keepalive_timeout  120;
    client_max_body_size 20m;
    #gzip  on;
    include /etc/nginx/conf.d/*.conf;
}
EOF
	
cat > /etc/nginx/conf.d/default.conf<<-EOF
server {
    listen 80 default_server;
    server_name _;
    return 404;  
}
server {
    listen  80;
    server_name $your_domain;
    root /usr/share/nginx/html;
    index index.php index.html;
    location ~ \.php$ {
    	fastcgi_pass 127.0.0.1:9000;
    	fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    	include fastcgi_params;
    }
    location / {
       try_files \$uri \$uri/ /index.php?\$args;
    }
}
server {
    listen  4443;
    server_name $your_domain;
    allow 127.0.0.1;
    root /usr/share/nginx/html;
    index index.php index.html;
    ssl_certificate /usr/src/trojan-cert/fullchain.cer; 
    ssl_certificate_key /usr/src/trojan-cert/private.key;
    location ~ \.php$ {
    	fastcgi_pass 127.0.0.1:9000;
    	fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    	include fastcgi_params;
    }
    location / {
       try_files \$uri \$uri/ /index.php?\$args;
    }
}
EOF

}

config_php(){

    echo
    green "===================="
    green "  配置php和php-fpm"
    green "===================="
    echo
    echo
    sleep 1
    sed -i "s/upload_max_filesize = 2M/upload_max_filesize = 20M/;" /etc/php.ini
    sed -i "s/pm.start_servers = 5/pm.start_servers = 3/;s/pm.min_spare_servers = 5/pm.min_spare_servers = 3/;s/pm.max_spare_servers = 35/pm.max_spare_servers = 8/;" /etc/php-fpm.d/www.conf
    systemctl restart php-fpm.service
    systemctl restart nginx.service

}


download_wp(){

    mkdir /usr/share/wordpresstemp
    cd /usr/share/wordpresstemp/
    wget https://cn.wordpress.org/latest-zh_CN.zip
    if [ ! -f "/usr/share/wordpresstemp/latest-zh_CN.zip" ]; then
    	red "从cn官网下载wordpress失败，尝试从github下载……"
	    wget https://github.com/atrandys/wordpress/raw/master/latest-zh_CN.zip    
    fi
    if [ ! -f "/usr/share/wordpresstemp/latest-zh_CN.zip" ]; then
	    red "我它喵的从github下载wordpress也失败了，请尝试手动安装……"
	    green "从wordpress官网下载包然后命名为latest-zh_CN.zip，新建目录/usr/share/wordpresstemp/，上传到此目录下即可"
	    exit 1
    fi
}

install_wp(){

    green "===================="
    green "  安装wordpress"
    green "===================="
    echo
    echo
    sleep 1
    cd /usr/share/nginx/html
    mv /usr/share/wordpresstemp/latest-zh_CN.zip ./
    unzip latest-zh_CN.zip
    mv wordpress/* ./
    cp wp-config-sample.php wp-config.php
    green "===================="
    green "  配置wordpress"
    green "===================="
    echo
    echo
    sleep 1
    sed -i "s/database_name_here/wordpress_db/;s/username_here/root/;s/password_here/$mysqlpasswd/;" /usr/share/nginx/html/wp-config.php
    echo "define('FS_METHOD', "direct");" >> /usr/share/nginx/html/wp-config.php
    chown -R nginx:root /usr/share/nginx/html/
    chmod -R 777 /usr/share/nginx/html/wp-content
}

check_os(){

#copy from 秋水逸冰 ss scripts
if [[ -f /etc/redhat-release ]]; then
    release="centos"
    systemPackage="yum"
    systempwd="/usr/lib/systemd/system/"
elif cat /etc/issue | grep -Eqi "debian"; then
    release="debian"
    systemPackage="apt-get"
    systempwd="/lib/systemd/system/"
elif cat /etc/issue | grep -Eqi "ubuntu"; then
    release="ubuntu"
    systemPackage="apt-get"
    systempwd="/lib/systemd/system/"
elif cat /etc/issue | grep -Eqi "centos|red hat|redhat"; then
    release="centos"
    systemPackage="yum"
    systempwd="/usr/lib/systemd/system/"
elif cat /proc/version | grep -Eqi "debian"; then
    release="debian"
    systemPackage="apt-get"
    systempwd="/lib/systemd/system/"
elif cat /proc/version | grep -Eqi "ubuntu"; then
    release="ubuntu"
    systemPackage="apt-get"
    systempwd="/lib/systemd/system/"
elif cat /proc/version | grep -Eqi "centos|red hat|redhat"; then
    release="centos"
    systemPackage="yum"
    systempwd="/usr/lib/systemd/system/"
fi
nginx_status=`ps -aux | grep "nginx: worker" |grep -v "grep"`
if [ -n "$nginx_status" ]; then
    systemctl stop nginx
fi
$systemPackage -y install net-tools >/dev/null 2>&1
Port80=`netstat -tlpn | awk -F '[: ]+' '$1=="tcp"{print $5}' | grep -w 80`
Port443=`netstat -tlpn | awk -F '[: ]+' '$1=="tcp"{print $5}' | grep -w 443`
if [ -n "$Port80" ]; then
    process80=`netstat -tlpn | awk -F '[: ]+' '$5=="80"{print $9}'`
    red "==========================================================="
    red "检测到80端口被占用，占用进程为：${process80}，本次安装结束"
    red "==========================================================="
    exit 1
fi
if [ -n "$Port443" ]; then
    process443=`netstat -tlpn | awk -F '[: ]+' '$5=="443"{print $9}'`
    red "============================================================="
    red "检测到443端口被占用，占用进程为：${process443}，本次安装结束"
    red "============================================================="
    exit 1
fi
if [ "$release" == "centos" ]; then
    if  [ -n "$(grep ' 6\.' /etc/redhat-release)" ] ;then
        red "==============="
        red "当前系统不受支持"
        red "==============="
        exit
    fi
    if  [ -n "$(grep ' 5\.' /etc/redhat-release)" ] ;then
        red "==============="
        red "当前系统不受支持"
        red "==============="
        exit
    fi
    CHECK=$(grep SELINUX= /etc/selinux/config | grep -v "#")
    if [ "$CHECK" != "SELINUX=disabled" ]; then
        green "检测到SELinux开启状态，添加放行80/443端口规则"
        yum install -y policycoreutils-python >/dev/null 2>&1
        semanage port -m -t http_port_t -p tcp 80
        semanage port -m -t http_port_t -p tcp 443
	semanage port -a -t http_port_t -p tcp 4443
    fi
    firewall_status=`firewall-cmd --state`
    if [ "$firewall_status" == "running" ]; then
        green "检测到firewalld开启状态，添加放行80/443端口规则"
        yum install -y policycoreutils-python >/dev/null 2>&1
        firewall-cmd --zone=public --add-port=80/tcp --permanent
	      firewall-cmd --zone=public --add-port=443/tcp --permanent
	      firewall-cmd --reload
    fi
    yum -y install epel-release
    rpm -Uvh http://nginx.org/packages/centos/7/noarch/RPMS/nginx-release-centos-7-0.el7.ngx.noarch.rpm
elif [ "$release" == "ubuntu" ]; then
    if  [ -n "$(grep ' 14\.' /etc/os-release)" ] ;then
        red "==============="
        red "当前系统不受支持"
        red "==============="
        exit
    fi
    if  [ -n "$(grep ' 12\.' /etc/os-release)" ] ;then
        red "==============="
        red "当前系统不受支持"
        red "==============="
        exit
    fi
    ufw_status=`systemctl status ufw | grep "Active: active"`
    if [ -n "$ufw_status" ]; then
        ufw allow 80/tcp
        ufw allow 443/tcp
    fi
    apt-get update
elif [ "$release" == "debian" ]; then
    ufw_status=`systemctl status ufw | grep "Active: active"`
    if [ -n "$ufw_status" ]; then
        ufw allow 80/tcp
        ufw allow 443/tcp
    fi
    apt-get update
fi
}

function install_trojanwp(){

	#设置伪装站
	systemctl stop nginx
	sleep 5
	#申请https证书
	if [ ! -d "/usr/src" ]; then
	    mkdir /usr/src
	fi
	mkdir /usr/src/trojan-cert /usr/src/trojan-temp
	curl https://get.acme.sh | sh
	~/.acme.sh/acme.sh  --issue  -d $your_domain  --standalone
  ~/.acme.sh/acme.sh  --installcert  -d  $your_domain   \
        --key-file   /usr/src/trojan-cert/private.key \
        --fullchain-file /usr/src/trojan-cert/fullchain.cer
	if test -s /usr/src/trojan-cert/fullchain.cer; then
	    systemctl start nginx
      cd /usr/src
    	#wget https://github.com/trojan-gfw/trojan/releases/download/v1.13.0/trojan-1.13.0-linux-amd64.tar.xz
	    wget https://api.github.com/repos/trojan-gfw/trojan/releases/latest >/dev/null 2>&1
	    latest_version=`grep tag_name latest| awk -F '[:,"v]' '{print $6}'`
	    rm -f latest
	    wget https://github.com/trojan-gfw/trojan/releases/download/v${latest_version}/trojan-${latest_version}-linux-amd64.tar.xz >/dev/null 2>&1
	    tar xf trojan-${latest_version}-linux-amd64.tar.xz >/dev/null 2>&1
	    #下载trojan客户端
	    wget https://github.com/atrandys/trojan/raw/master/trojan-cli.zip >/dev/null 2>&1
	    wget -P /usr/src/trojan-temp https://github.com/trojan-gfw/trojan/releases/download/v${latest_version}/trojan-${latest_version}-win.zip >/dev/null 2>&1
	    unzip trojan-cli.zip >/dev/null 2>&1
	    unzip /usr/src/trojan-temp/trojan-${latest_version}-win.zip -d /usr/src/trojan-temp/ >/dev/null 2>&1
	    cp /usr/src/trojan-cert/fullchain.cer /usr/src/trojan-cli/fullchain.cer
	    mv -f /usr/src/trojan-temp/trojan/trojan.exe /usr/src/trojan-cli/ 
	    trojan_passwd=$(cat /dev/urandom | head -1 | md5sum | head -c 8)
cat > /usr/src/trojan-cli/config.json <<-EOF
{
    "run_type": "client",
    "local_addr": "127.0.0.1",
    "local_port": 1080,
    "remote_addr": "$your_domain",
    "remote_port": 443,
    "password": [
        "$trojan_passwd"
    ],
    "log_level": 1,
    "ssl": {
        "verify": true,
        "verify_hostname": true,
        "cert": "fullchain.cer",
        "cipher_tls13":"TLS_AES_128_GCM_SHA256:TLS_CHACHA20_POLY1305_SHA256:TLS_AES_256_GCM_SHA384",
	"sni": "",
        "alpn": [
            "h2",
            "http/1.1"
        ],
        "reuse_session": true,
        "session_ticket": false,
        "curves": ""
    },
    "tcp": {
        "no_delay": true,
        "keep_alive": true,
        "fast_open": false,
        "fast_open_qlen": 20
    }
}
EOF
	rm -rf /usr/src/trojan/server.conf
	cat > /usr/src/trojan/server.conf <<-EOF
{
    "run_type": "server",
    "local_addr": "0.0.0.0",
    "local_port": 443,
    "remote_addr": "127.0.0.1",
    "remote_port": 4443,
    "password": [
        "$trojan_passwd"
    ],
    "log_level": 1,
    "ssl": {
        "cert": "/usr/src/trojan-cert/fullchain.cer",
        "key": "/usr/src/trojan-cert/private.key",
        "key_password": "",
        "cipher_tls13":"TLS_AES_128_GCM_SHA256:TLS_CHACHA20_POLY1305_SHA256:TLS_AES_256_GCM_SHA384",
	"prefer_server_cipher": true,
        "alpn": [
            "http/1.1"
        ],
        "reuse_session": true,
        "session_ticket": false,
        "session_timeout": 600,
        "plain_http_response": "",
        "curves": "",
        "dhparam": ""
    },
    "tcp": {
        "no_delay": true,
        "keep_alive": true,
        "fast_open": false,
        "fast_open_qlen": 20
    },
    "mysql": {
        "enabled": false,
        "server_addr": "127.0.0.1",
        "server_port": 3306,
        "database": "trojan",
        "username": "trojan",
        "password": ""
    }
}
EOF
	#增加启动脚本
	
cat > ${systempwd}trojan.service <<-EOF
[Unit]  
Description=trojan  
After=network.target  
   
[Service]  
Type=simple  
PIDFile=/usr/src/trojan/trojan/trojan.pid
ExecStart=/usr/src/trojan/trojan -c "/usr/src/trojan/server.conf"  
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure
RestartSec=1s
   
[Install]  
WantedBy=multi-user.target
EOF

	    chmod +x ${systempwd}trojan.service
	    systemctl start trojan.service
	    systemctl enable trojan.service
            install_php7
            install_mysql
            install_nginx
            config_php
            download_wp
            install_wp
            cd /usr/src/trojan-cli/
            zip -q -r trojan-cli.zip /usr/src/trojan-cli/
            trojan_path=$(cat /dev/urandom | head -1 | md5sum | head -c 16)
            mkdir /usr/share/nginx/html/${trojan_path}
            mv /usr/src/trojan-cli/trojan-cli.zip /usr/share/nginx/html/${trojan_path}/
	    green "======================================================================"
	    green "Trojan已安装完成，请使用以下链接下载trojan客户端，此客户端已配置好所有参数"
	    green "1、复制下面的链接，在浏览器打开，下载客户端，注意此下载链接将在1个小时后失效"
	    blue "http://${your_domain}/$trojan_path/trojan-cli.zip"
	    green "2、将下载的压缩包解压，打开文件夹，打开start.bat即打开并运行Trojan客户端"
	    green "3、打开stop.bat即关闭Trojan客户端"
	    green "4、Trojan客户端需要搭配浏览器插件使用，例如switchyomega等"
      green "==========================================================="
      green " WordPress服务端配置已完成，请打开浏览器访问您的域名进行前台配置"
      green " 数据库密码等信息参考文件：/usr/share/nginx/html/wp-config.php"
      green "==========================================================="
	else
      red "==================================="
	    red "https证书没有申请成果，自动安装失败"
	    green "不要担心，你可以手动修复证书申请"
	    red "==================================="
	fi
}
function install_main(){

check_os
$systemPackage -y install  socat wget unzip zip curl tar >/dev/null 2>&1
green "======================="
blue "请输入绑定到本VPS的域名"
green "======================="
read your_domain
real_addr=`ping ${your_domain} -c 1 | sed '1{s/[^(]*(//;s/).*//;q}'`
local_addr=`curl ipv4.icanhazip.com`
if [ $real_addr == $local_addr ] ; then
	green "=========================================="
	green "       域名解析正常，开始安装trojan"
	green "=========================================="
	sleep 1s
  install_trojanwp
else
  red "===================================="
	red "域名解析地址与本VPS IP地址不一致"
	red "若你确认解析成功你可强制脚本继续运行"
	red "===================================="
	read -p "是否强制运行 ?请输入 [Y/n] :" yn
	[ -z "${yn}" ] && yn="y"
	if [[ $yn == [Yy] ]]; then
      green "强制继续运行脚本"
	    sleep 1s
	    install_trojanwp
      
	else
	    exit 1
	fi
fi
}

function repair_cert(){
systemctl stop nginx
iptables -I INPUT -p tcp --dport 80 -j ACCEPT
iptables -I INPUT -p tcp --dport 443 -j ACCEPT
Port80=`netstat -tlpn | awk -F '[: ]+' '$1=="tcp"{print $5}' | grep -w 80`
if [ -n "$Port80" ]; then
    process80=`netstat -tlpn | awk -F '[: ]+' '$5=="80"{print $9}'`
    red "==========================================================="
    red "检测到80端口被占用，占用进程为：${process80}，本次安装结束"
    red "==========================================================="
    exit 1
fi
green "======================="
blue "请输入绑定到本VPS的域名"
blue "务必与之前失败使用的域名一致"
green "======================="
read your_domain
real_addr=`ping ${your_domain} -c 1 | sed '1{s/[^(]*(//;s/).*//;q}'`
local_addr=`curl ipv4.icanhazip.com`
if [ $real_addr == $local_addr ] ; then
    ~/.acme.sh/acme.sh  --issue  -d $your_domain  --standalone
    ~/.acme.sh/acme.sh  --installcert  -d  $your_domain   \
        --key-file   /usr/src/trojan-cert/private.key \
        --fullchain-file /usr/src/trojan-cert/fullchain.cer
    if test -s /usr/src/trojan-cert/fullchain.cer; then
        green "证书申请成功"
	green "请将/usr/src/trojan-cert/下的fullchain.cer下载放到客户端trojan-cli文件夹"
	systemctl restart trojan
	systemctl start nginx
    else
    	red "申请证书失败"
    fi
else
    red "================================"
    red "域名解析地址与本VPS IP地址不一致"
    red "本次安装失败，请确保域名解析正常"
    red "================================"
fi	
}

function remove_trojan(){
    red "================================"
    red "即将卸载trojan"
    red "同时卸载安装的nginx"
    red "================================"
    systemctl stop trojan
    systemctl disable trojan
    rm -f ${systempwd}trojan.service
    if [ "$release" == "centos" ]; then
        yum remove -y nginx
    else
        apt autoremove -y nginx
    fi
    rm -rf /usr/src/trojan*
    rm -rf /usr/share/nginx/html/*
    green "=============="
    green "trojan删除完毕"
    green "=============="
}

function update_trojan(){
    /usr/src/trojan/trojan -v 2>trojan.tmp
    curr_version=`cat trojan.tmp | grep "trojan" | awk '{print $4}'`
    wget https://api.github.com/repos/trojan-gfw/trojan/releases/latest >/dev/null 2>&1
    latest_version=`grep tag_name latest| awk -F '[:,"v]' '{print $6}'`
    rm -f latest
    rm -f trojan.tmp
    if version_lt "$curr_version" "$latest_version"; then
        green "当前版本$curr_version,最新版本$latest_version,开始升级……"
        mkdir trojan_update_temp && cd trojan_update_temp
        wget https://github.com/trojan-gfw/trojan/releases/download/v${latest_version}/trojan-${latest_version}-linux-amd64.tar.xz >/dev/null 2>&1
        tar xf trojan-${latest_version}-linux-amd64.tar.xz >/dev/null 2>&1
        mv ./trojan/trojan /usr/src/trojan/
        cd .. && rm -rf trojan_update_temp
        systemctl restart trojan
	      /usr/src/trojan/trojan -v 2>trojan.tmp
	      green "trojan升级完成，当前版本：`cat trojan.tmp | grep "trojan" | awk '{print $4}'`"
	      rm -f trojan.tmp
    else
        green "当前版本$curr_version,最新版本$latest_version,无需升级"
    fi
   
   
}

start_menu(){
    clear
    green " ======================================="
    green " 介绍：一键安装trojan+wordpress      "
    green " 系统：centos7/debian9+/ubuntu16.04+"
    green " 作者：A              "
    blue " 声明："
    red " *请不要在任何生产环境使用此脚本"
    red " *请不要有其他程序占用80和443端口"
    green " ======================================="
    echo
    green " 1. 安装trojan+wordpress"
    green " 2. 升级trojan"
    blue " 0. 退出脚本"
    echo
    read -p "请输入数字 :" num
    case "$num" in
    1)
    install_main
    ;;
    2)
    update_trojan 
    ;;
    0)
    exit 1
    ;;
    *)
    clear
    red "请输入正确数字"
    sleep 1s
    start_menu
    ;;
    esac
}

start_menu
