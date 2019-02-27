#!/bin/bash

function blue(){
    echo -e "\033[34m\033[01m $1 \033[0m"
}
function green(){
    echo -e "\033[32m\033[01m $1 \033[0m"
}
function red(){
    echo -e "\033[31m\033[01m $1 \033[0m"
}
function yellow(){
    echo -e "\033[33m\033[01m $1 \033[0m"
}

systemctl stop ufw
systemctl disable ufw

sudo apt-get install -y software-properties-common
sudo add-apt-repository -y ppa:greaterfire/trojan
sudo apt-get -y update
sudo apt-get -y install unzip wget curl trojan

sudo apt-get -y install nginx
mkdir /etc/nginx/ssl

green "======================"
green " 输入解析到此VPS的域名"
green "======================"
read domain

cat > /etc/nginx/nginx.conf <<-EOF
user  root;
worker_processes  1;
error_log /var/log/nginx/error.log;
pid /run/nginx.pid;
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
    listen       80;
    server_name  $domain;
    location / {
        root /usr/share/nginx/html;
        index index.php index.html index.htm;
    }
    error_page   500 502 503 504  /50x.html;
    location = /50x.html {
        root   /usr/share/nginx/html;
    }
}
EOF

systemctl restart nginx.service

curl https://get.acme.sh | sh
~/.acme.sh/acme.sh  --issue  -d $domain  --webroot /usr/share/nginx/html/

~/.acme.sh/acme.sh  --installcert  -d  $domain   \
        --key-file   /etc/nginx/ssl/$domain.key \
        --fullchain-file /etc/nginx/ssl/fullchain.cer \
        --reloadcmd  "service nginx force-reload"

cd /etc/trojan/
rm -f /etc/trojan/config.json

cat > /etc/trojan/server.conf <<-EOF
{
    "run_type": "server",
    "local_addr": "0.0.0.0",
    "local_port": 443,
    "remote_addr": "127.0.0.1",
    "remote_port": 80,
    "password": [
        "password1"
    ],
    "log_level": 1,
    "ssl": {
        "cert": "/etc/nginx/ssl/fullchain.cer",
        "key": "/etc/nginx/ssl/$domain.key",
        "key_password": "",
        "cipher": "TLS13-AES-256-GCM-SHA384:TLS13-CHACHA20-POLY1305-SHA256:TLS13-AES-128-GCM-SHA256:TLS13-AES-128-CCM-8-SHA256:TLS13-AES-128-CCM-SHA256",
        "prefer_server_cipher": true,
        "alpn": [
            "h2",
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

cat > /etc/nginx/ssl/config.json <<-EOF
{
    "run_type": "client",
    "local_addr": "127.0.0.1",
    "local_port": 1080,
    "remote_addr": "$domain",
    "remote_port": 443,
    "password": [
        "password1"
    ],
    "append_payload": true,
    "log_level": 1,
    "ssl": {
        "verify": true,
        "verify_hostname": true,
        "cert": "fullchain.cer",
        "cipher": "TLS13-AES-256-GCM-SHA384:TLS13-CHACHA20-POLY1305-SHA256:TLS13-AES-128-GCM-SHA256:TLS13-AES-128-CCM-8-SHA256:TLS13-AES-128-CCM-SHA256",
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
mypassword=$(cat /dev/urandom | head -1 | md5sum | head -c 4)
sed -i "s/password1/$mypassword/" /etc/trojan/server.conf
sed -i "s/password1/$mypassword/" /etc/nginx/ssl/config.json

rm -f /usr/share/nginx/html/*
cd /usr/share/nginx/html
wget https://github.com/atrandys/v2ray-ws-tls/raw/master/web.zip
unzip web.zip
systemctl restart nginx.service
systemctl enable nginx.service
sudo cat > /etc/init.d/trojanstart <<-EOF
#! /bin/bash
### BEGIN INIT INFO
# Provides:		trojanstart
# Required-Start:	$remote_fs $syslog
# Required-Stop:    $remote_fs $syslog
# Default-Start:	2 3 4 5
# Default-Stop:		0 1 6
# Short-Description:	trojanstart
### END INIT INFO
nohup trojan -c /etc/trojan/server.conf > /etc/trojan/info.log 2>&1 &
EOF

sudo chmod +x /etc/init.d/trojanstart
sudo update-rc.d trojanstart defaults

nohup trojan -c /etc/trojan/server.conf > /etc/trojan/info.log 2>&1 &

green "===============安装OK==============="
green " 证书文件：/etc/nginx/ssl/fullchain.cer"
green " 客户端配置：/etc/nginx/ssl/config.json"
green " 将以上两个文件传输到客户端trojan文件夹"
