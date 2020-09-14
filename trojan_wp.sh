#!/bin/bash
function blue(){
    echo -e "\033[34m\033[01m$1\033[0m"
}
function green(){
    echo -e "\033[32m\033[01m$1\033[0m"
}
function red(){
    echo -e "\033[31m\033[01m$1\033[0m"
}
function version_lt(){
    test "$(echo "$@" | tr " " "\n" | sort -rV | head -n 1)" != "$1"; 
}

source /etc/os-release
RELEASE=$ID
VERSION=$VERSION_ID


function install_wordpress(){
    yum install -y iptables-services
    systemctl start iptables
    systemctl enable iptables
    iptables -F
    SSH_PORT=$(awk '$1=="Port" {print $2}' /etc/ssh/sshd_config)
    if [ ! -n "$SSH_PORT" ]; then
        iptables -A INPUT -p tcp -m tcp --dport 22 -j ACCEPT
    else
        iptables -A INPUT -p tcp -m tcp --dport ${SSH_PORT} -j ACCEPT
    fi
    iptables -A INPUT -p tcp -m tcp --dport 80 -j ACCEPT
    iptables -A INPUT -p tcp -m tcp --dport 443 -j ACCEPT
    iptables -A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT
    iptables -A INPUT -i lo -j ACCEPT
    iptables -P INPUT DROP
    iptables -P FORWARD DROP
    iptables -P OUTPUT ACCEPT
    service iptables save
    green "====================================================================="
    green "安全起见，iptables仅开启ssh,http,https端口，如需开放其他端口请自行放行"
    green "====================================================================="
    sleep 1
    yum -y install  wget
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
    green "==============="
    green " 1.安装必要软件"
    green "==============="
    sleep 1
    wget https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
    wget https://rpms.remirepo.net/enterprise/remi-release-7.rpm
    rpm -Uvh remi-release-7.rpm epel-release-latest-7.noarch.rpm
    #sed -i "0,/enabled=0/s//enabled=1/" /etc/yum.repos.d/epel.repo
    yum -y install  unzip vim tcl expect curl socat
    echo
    echo
    green "============"
    green "2.安装PHP7.4"
    green "============"
    sleep 1
    yum -y install php74 php74-php-gd  php74-php-pdo php74-php-mbstring php74-php-cli php74-php-fpm php74-php-mysqlnd php74-php-xml
    service php74-php-fpm start
    chkconfig php74-php-fpm on
    if [ `yum list installed | grep php74 | wc -l` -ne 0 ]; then
        echo
        green "【checked】 PHP7安装成功"
        echo
        echo
        sleep 2
        php_status=1
    fi
    green "==============="
    green "  3.安装MySQL"
    green "==============="
    sleep 1
    #wget http://repo.mysql.com/mysql-community-release-el7-5.noarch.rpm
    wget https://repo.mysql.com/mysql80-community-release-el7-3.noarch.rpm
    rpm -ivh mysql80-community-release-el7-3.noarch.rpm
    yum -y install mysql-server
    systemctl enable mysqld.service
    systemctl start  mysqld.service
    if [ `yum list installed | grep mysql-community | wc -l` -ne 0 ]; then
        green "【checked】 MySQL安装成功"
        echo
        echo
        sleep 2
        mysql_status=1
    fi
    echo
    echo
    green "==============="
    green "  4.配置MySQL"
    green "==============="
    sleep 2
    originpasswd=`cat /var/log/mysqld.log | grep password | head -1 | rev  | cut -d ' ' -f 1 | rev`
    mysqlpasswd=`mkpasswd -l 18 -d 2 -c 3 -C 4 -s 5 | sed $'s/[\'\/\;\"\:\.\?]//g'`
cat > ~/.my.cnf <<EOT
[mysql]
user=root
password="$originpasswd"
EOT
    mysql  --connect-expired-password  -e "alter user 'root'@'localhost' identified by '$mysqlpasswd';"
    systemctl restart mysqld
    sleep 5s
cat > ~/.my.cnf <<EOT
[mysql]
user=root
password="$mysqlpasswd"
EOT
    mysql  --connect-expired-password  -e "create database wordpress_db;"
    echo
    green "===================="
    green " 5.配置php和php-fpm"
    green "===================="
    echo
    echo
    sleep 1
    sed -i "s/upload_max_filesize = 2M/upload_max_filesize = 20M/;" /etc/opt/remi/php74/php.ini
    sed -i "s/pm.start_servers = 5/pm.start_servers = 3/;s/pm.min_spare_servers = 5/pm.min_spare_servers = 3/;s/pm.max_spare_servers = 35/pm.max_spare_servers = 8/;" /etc/opt/remi/php74/php-fpm.d/www.conf
    systemctl restart php74-php-fpm.service
    systemctl restart nginx.service
    green "===================="
    green "  6.安装wordpress"
    green "===================="
    echo
    echo
    sleep 1
    cd /usr/share/nginx/html
    mv /usr/share/wordpresstemp/latest-zh_CN.zip ./
    unzip latest-zh_CN.zip >/dev/null 2>&1
    mv wordpress/* ./
    #cp wp-config-sample.php wp-config.php
    wget https://raw.githubusercontent.com/atrandys/trojan/master/wp-config.php
    green "===================="
    green "  7.配置wordpress"
    green "===================="
    echo
    echo
    sleep 1
    sed -i "s/database_name_here/wordpress_db/;s/username_here/root/;s?password_here?$mysqlpasswd?;" /usr/share/nginx/html/wp-config.php
    #echo "define('FS_METHOD', "direct");" >> /usr/share/nginx/html/wp-config.php
    chown -R apache:apache /usr/share/nginx/html/
    #chmod 775 apache:apache /usr/share/nginx/html/ -Rf
    chmod -R 775 /usr/share/nginx/html/wp-content
    green "=========================================================================="
    green " WordPress服务端配置已完成，请打开浏览器访问您的域名进行前台配置"
    green " 数据库密码等信息参考文件：/usr/share/nginx/html/wp-config.php"
    green "=========================================================================="
    echo
    green "=========================================================================="
    green "Trojan已安装完成，请使用以下链接下载trojan客户端，此客户端已配置好所有参数"
    blue "http://${your_domain}/$trojan_path/trojan-cli.zip"
    green "=========================================================================="
    green "                          客户端配置文件"
    green "=========================================================================="
    cat /usr/src/trojan-cli/config.json
    green "=========================================================================="
}

function install_trojan(){
    yum install -y nginx
    if [ ! -d "/etc/nginx/" ]; then
        red "nginx安装有问题，请使用卸载trojan后重新安装"
        exit 1
    fi
    cat > /etc/nginx/nginx.conf <<-EOF
user  root;
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
    server {
        listen       80;
        server_name  $your_domain;
        root /usr/share/nginx/html;
        index index.php index.html index.htm;
    }
}
EOF
    systemctl restart nginx
    sleep 3
    rm -rf /usr/share/nginx/html/*
    cd /usr/share/nginx/html/
    wget https://github.com/atrandys/trojan/raw/master/fakesite.zip >/dev/null 2>&1
    unzip fakesite.zip >/dev/null 2>&1
    sleep 5
    if [ ! -d "/usr/src" ]; then
        mkdir /usr/src
    fi
    if [ ! -d "/usr/src/trojan-cert" ]; then
        mkdir /usr/src/trojan-cert /usr/src/trojan-temp
        mkdir /usr/src/trojan-cert/$your_domain
        curl https://get.acme.sh | sh
        ~/.acme.sh/acme.sh  --issue  -d $your_domain  --nginx
        if test -s /root/.acme.sh/$your_domain/fullchain.cer; then
            cert_success="1"
        fi
    elif [ -f "/usr/src/trojan-cert/$your_domain/fullchain.cer" ]; then
        cd /usr/src/trojan-cert/$your_domain
        create_time=`stat -c %Y fullchain.cer`
        now_time=`date +%s`
        minus=$(($now_time - $create_time ))
        if [  $minus -gt 5184000 ]; then
            curl https://get.acme.sh | sh
            ~/.acme.sh/acme.sh  --issue  -d $your_domain  --nginx
            if test -s /root/.acme.sh/$your_domain/fullchain.cer; then
                cert_success="1"
            fi
        else 
            green "检测到域名$your_domain证书存在且未超过60天，无需重新申请"
            cert_success="1"
        fi        
    else 
        curl https://get.acme.sh | sh
        ~/.acme.sh/acme.sh  --issue  -d $your_domain  --webroot /usr/share/nginx/html/
        if test -s /root/.acme.sh/$your_domain/fullchain.cer; then
            cert_success="1"
        fi
    fi
    
    if [ "$cert_success" == "1" ]; then
        cat > /etc/nginx/nginx.conf <<-EOF
user  root;
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
    server {
        listen       127.0.0.1:80;
        server_name  $your_domain;
        root /usr/share/nginx/html;
        index index.php index.html index.htm;
        add_header Strict-Transport-Security "max-age=31536000";
        #access_log /var/log/nginx/hostscube.log combined;
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
        listen       0.0.0.0:80;
        server_name  $your_domain;
        return 301 https://$your_domain\$request_uri;
    }
    
}
EOF
        systemctl restart nginx
        systemctl enable nginx
        cd /usr/src
        wget https://api.github.com/repos/trojan-gfw/trojan/releases/latest >/dev/null 2>&1
        latest_version=`grep tag_name latest| awk -F '[:,"v]' '{print $6}'`
        rm -f latest
        green "开始下载最新版trojan amd64"
        wget https://github.com/trojan-gfw/trojan/releases/download/v${latest_version}/trojan-${latest_version}-linux-amd64.tar.xz
        tar xf trojan-${latest_version}-linux-amd64.tar.xz >/dev/null 2>&1
        rm -f trojan-${latest_version}-linux-amd64.tar.xz
        #下载trojan客户端
        green "开始下载并处理trojan windows客户端"
        wget https://github.com/atrandys/trojan/raw/master/trojan-cli.zip
        wget -P /usr/src/trojan-temp https://github.com/trojan-gfw/trojan/releases/download/v${latest_version}/trojan-${latest_version}-win.zip
        unzip trojan-cli.zip >/dev/null 2>&1
        unzip /usr/src/trojan-temp/trojan-${latest_version}-win.zip -d /usr/src/trojan-temp/ >/dev/null 2>&1
        mv -f /usr/src/trojan-temp/trojan/trojan.exe /usr/src/trojan-cli/
        green "请设置trojan密码，建议不要出现特殊字符"
        read -p "请输入密码 :" trojan_passwd
        #trojan_passwd=$(cat /dev/urandom | head -1 | md5sum | head -c 8)
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
        "cert": "",
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
    "remote_port": 80,
    "password": [
        "$trojan_passwd"
    ],
    "log_level": 1,
    "ssl": {
        "cert": "/usr/src/trojan-cert/$your_domain/fullchain.cer",
        "key": "/usr/src/trojan-cert/$your_domain/private.key",
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
        cd /usr/src/trojan-cli/
        zip -q -r trojan-cli.zip /usr/src/trojan-cli/
        rm -rf /usr/src/trojan-temp/
        rm -f /usr/src/trojan-cli.zip
        trojan_path=$(cat /dev/urandom | head -1 | md5sum | head -c 16)
        mkdir /usr/share/nginx/html/${trojan_path}
        mv /usr/src/trojan-cli/trojan-cli.zip /usr/share/nginx/html/${trojan_path}/	
        cat > /etc/systemd/system/trojan.service <<-EOF
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

        chmod +x /etc/systemd/system/trojan.service
        systemctl enable trojan.service
        cd /root
        ~/.acme.sh/acme.sh  --installcert  -d  $your_domain   \
            --key-file   /usr/src/trojan-cert/$your_domain/private.key \
            --fullchain-file  /usr/src/trojan-cert/$your_domain/fullchain.cer \
            --reloadcmd  "systemctl restart trojan"	
    else
        red "==================================="
        red "https证书没有申请成功，本次安装失败"
        red "==================================="
    fi
}
function preinstall_check(){
    yum -y install net-tools socat >/dev/null 2>&1
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
    if [ -f "/etc/selinux/config" ]; then
        CHECK=$(grep SELINUX= /etc/selinux/config | grep -v "#")
        if [ "$CHECK" != "SELINUX=disabled" ]; then
            green "检测到SELinux开启状态，添加放行80/443端口规则"
            yum install -y policycoreutils-python >/dev/null 2>&1
            semanage port -a -t http_port_t -p tcp 80
            semanage port -a -t http_port_t -p tcp 443
        fi
    fi
    if [[ "$RELEASE" == "centos" ]] && [[ "$VERSION" == "7" ]]; then
        firewall_status=`systemctl status firewalld | grep "Active: active"`
        if [ -n "$firewall_status" ]; then
            green "检测到firewalld开启状态，添加放行80/443端口规则"
            firewall-cmd --zone=public --add-port=80/tcp --permanent
            firewall-cmd --zone=public --add-port=443/tcp --permanent
            firewall-cmd --reload
        fi
        rpm -Uvh http://nginx.org/packages/centos/7/noarch/RPMS/nginx-release-centos-7-0.el7.ngx.noarch.rpm
    else
            red "==============="
            red "当前系统不受支持"
            red "==============="
            exit
    fi
    yum -y install  wget unzip zip curl tar >/dev/null 2>&1
    green "======================="
    blue "请输入绑定到本VPS的域名"
    green "======================="
    read your_domain
    real_addr=`ping ${your_domain} -c 1 | sed '1{s/[^(]*(//;s/).*//;q}'`
    local_addr=`curl ipv4.icanhazip.com`
    if [ $real_addr == $local_addr ] ; then
        green "=========================================="
        green "    域名解析正常，开始安装trojan+wp"
        green "=========================================="
        sleep 1s
        install_trojan
        install_wordpress
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
            install_trojan
            install_wordpress
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
    green "============================"
    blue "请输入绑定到本VPS的域名"
    blue "务必与之前失败使用的域名一致"
    green "============================"
    read your_domain
    real_addr=`ping ${your_domain} -c 1 | sed '1{s/[^(]*(//;s/).*//;q}'`
    local_addr=`curl ipv4.icanhazip.com`
    if [ $real_addr == $local_addr ] ; then
        ~/.acme.sh/acme.sh  --issue  -d $your_domain  --standalone
        ~/.acme.sh/acme.sh  --installcert  -d  $your_domain   \
            --key-file   /usr/src/trojan-cert/$your_domain/private.key \
            --fullchain-file /usr/src/trojan-cert/$your_domain/fullchain.cer \
            --reloadcmd  "systemctl restart trojan"
        if test -s /usr/src/trojan-cert/$your_domain/fullchain.cer; then
            green "证书申请成功"
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
    systemctl stop nginx
    systemctl disable nginx
    rm -f /etc/systemd/system/trojan.service
    if [ "$RELEASE" == "centos" ]; then
        yum remove -y nginx
    else
        apt-get -y autoremove nginx
        apt-get -y --purge remove nginx
        apt-get -y autoremove && apt-get -y autoclean
        find / | grep nginx | sudo xargs rm -rf
    fi
    rm -rf /usr/src/trojan/
    rm -rf /usr/src/trojan-cli/
    rm -rf /usr/share/nginx/html/*
    rm -rf /etc/nginx/
    rm -rf /root/.acme.sh/
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
    green "服务端trojan升级完成，当前版本：`cat trojan.tmp | grep "trojan" | awk '{print $4}'`，客户端请在trojan github下载最新版"
    rm -f trojan.tmp
    else
        green "当前版本$curr_version,最新版本$latest_version,无需升级"
    fi
   
   
}

start_menu(){
    clear
    green " ======================================="
    green " 介绍: 一键安装trojan + wordpress      "
    green " 系统: centos7+/debian9+/ubuntu16.04+"
    green " 作者: A             "
    blue " 注意:"
    red " *1. 不要在任何生产环境使用此脚本"
    red " *2. 不要占用80和443端口"
    red " *3. 若第二次使用脚本，请先执行卸载trojan"
    green " ======================================="
    echo
    green " 1. 安装trojan + wp"
    red " 2. 卸载trojan + wp"
    green " 3. 升级trojan"
    green " 4. 修复证书"
    blue " 0. 退出脚本"
    echo
    read -p "请输入数字 :" num
    case "$num" in
    1)
    preinstall_check
    ;;
    2)
    remove_trojan 
    ;;
    3)
    update_trojan 
    ;;
    4)
    repair_cert 
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
