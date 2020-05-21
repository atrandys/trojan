#!/bin/bash

#仅仅搞centos7
if [ ! -e '/etc/redhat-release' ]; then
echo "仅支持centos7"
exit
fi
if  [ -n "$(grep ' 6\.' /etc/redhat-release)" ] ;then
echo "仅支持centos7"
exit
fi

install_docker(){

	yum remove -y docker docker-client docker-client-latest docker-common docker-latest  docker-latest-logrotate docker-logrotate docker-selinux docker-engine-selinux docker-engine		
	yum install -y yum-utils device-mapper-persistent-data lvm2
	yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
	yum makecache fast
	yum -y install docker-ce
	systemctl start docker
	systemctl enable docker

}

config_website(){

	cd /usr/src/trojan/web
	wget https://github.com/atrandys/trojan/raw/master/index.zip
	unzip index.zip

}

uninstall_trojan(){
	docker update --restart=no trojan
	docker stop trojan
	docker rm trojan
	rm -rf /usr/src/trojan/
	echo "================="
	echo "    卸载完成"
	echo "================="
}

config_trojan(){

yum -y install  wget unzip vim tcl expect expect-devel
mkdir /usr/src/trojan
mkdir /usr/src/trojan/web
cd /usr/src/trojan
read -p "输入你的VPS绑定的域名：" domain
SUBJECT="/C=US/ST=Mars/L=iTranswarp/O=iTranswarp/OU=iTranswarp/CN=$domain"
echo "============================"
echo " 接下来需要设定密码，输入两次（随意设置，5-10位）"
echo "============================"
openssl genrsa -des3 -out private.key 1024
echo "============================"
echo " 接下来需要输入刚设定的密码"
echo "============================"
openssl req -new -subj $SUBJECT -key private.key -out private.csr
echo "============================"
echo " 再次输入刚设定的密码"
echo "============================"
mv private.key private.or.key
openssl rsa -in private.or.key -out private.key
openssl x509 -req -days 3650 -in private.csr -signkey private.key -out private.crt

cat > /usr/src/trojan/server.conf <<-EOF
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
        "cert": "/usr/src/trojan/private.crt",
        "key": "/usr/src/trojan/private.key",
        "key_password": "",
        "cipher": "ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-SHA384:ECDHE-RSA-AES256-SHA384:ECDHE-ECDSA-AES128-SHA256:ECDHE-RSA-AES128-SHA256",
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

echo "============================"
echo " 设置验证密码，服务端和客户端使用相同密码"
echo "============================"
read -p "设置密码：" mypassword
sed -i "s/password1/$mypassword/" /usr/src/trojan/server.conf

}

start_docker(){

        sudo firewall-cmd --zone=public --add-port=80/tcp --permanent
	sudo firewall-cmd --zone=public --add-port=443/tcp --permanent
	sudo firewall-cmd --reload
	docker run --name trojan --restart=always -d -p 80:80 -p 443:443 -v /usr/src/trojan:/usr/src/trojan  atrandys/trojan sh -c "/etc/init.d/nginx start && trojan -c /usr/src/trojan/server.conf"
	echo "============================"
	echo "       trojan启动完成"
	echo "============================"
}

start_menu(){
    clear
    echo "========================="
    echo " 介绍：适用于CentOS7"
    echo " 作者：A"
    echo "========================="
    echo "1. 安装Trojan"
    echo "2. 卸载Trojan"
    echo "3. 退出"
    echo
    read -p "请输入数字:" num
    case "$num" in
    	1)
	install_docker
	config_trojan
	config_website
	start_docker
	;;
	2)
	uninstall_trojan
	;;
	3)
	exit 1
	;;
	*)
	clear
	echo "请输入正确数字"
	sleep 5s
	start_menu
	;;
    esac
}

start_menu
