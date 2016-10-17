#! /bin/bash

if [ $# -lt 2 ] ; then
  echo "usetag:haproxy_config.sh vip cls_host_list"
  exit 1
fi
. /etc/bashrc

. $APP_BASE/install/funs.sh

VIP="*" #$1 $2
#if [ "$INSTALL_LVS" = "true" ] ; then # ins lvs need Specify IP and VIP used LVS ,
#    VIP="$LOCAL_IP"
#fi
VIP="*" # 减少iptables 设置
haHosts=`getAppHosts haproxy `

# 可能存在应用不是在所有机器上都安装的情况
CLS_HOST_LIST=`cat /bin/cmd.sh |grep "for HOST"|sed -e 's/.*for HOST in//' -e 's/;do.*//'`
FISRTHOST=`echo $CLS_HOST_LIST|awk '{print $1}'`
OLD_IFS=IFS
#IFS=,
mkdir -p /etc/haproxy/errorfiles
echo "haproxy error 403">/etc/haproxy/errorfiles/403.http
echo "haproxy error 500">/etc/haproxy/errorfiles/500.http
echo "haproxy error 502">/etc/haproxy/errorfiles/502.http
echo "haproxy error 503">/etc/haproxy/errorfiles/503.http
echo "haproxy error 504">/etc/haproxy/errorfiles/504.http

isMapp80=false

HTTP_BACK_DEFAULTS="    #http 通用设置
    option    httplog
    option  http-keep-alive
    option    httpclose
    balance    source
    option    redispatch
    retries    3
    timeout http-request    10s
    timeout queue           1m
    timeout connect         10s
    timeout server          30s
    timeout http-keep-alive 2s
    timeout check           5s
    cookie SERVERID insert indirect nocache "
HTTP_FRONT_DEFAULTS="    #http 通用设置
    mode    http
    option    httplog
    option  http-keep-alive
    option    httpclose
    option forwardfor header ORIG_CLIENT_IP
    timeout http-request    10s
    timeout client          30s
    timeout http-keep-alive 2s
    errorfile 403 /etc/haproxy/errorfiles/403.http
    errorfile 500 /etc/haproxy/errorfiles/500.http
    errorfile 502 /etc/haproxy/errorfiles/502.http
    errorfile 503 /etc/haproxy/errorfiles/503.http
    errorfile 504 /etc/haproxy/errorfiles/504.http "
HTTP_ALL_DEFAULTS="    #http 通用设置
    mode    http
    option    httplog
    option  http-keep-alive
    option    httpclose
    balance    source
    option forwardfor header ORIG_CLIENT_IP
    option    redispatch
    retries    3
    timeout http-request    10s
    timeout queue           1m
    timeout connect         10s
    timeout server          30s
    timeout client          30s
    timeout http-keep-alive 2s
    timeout check           5s
    cookie SERVERID insert indirect nocache
    errorfile 403 /etc/haproxy/errorfiles/403.http
    errorfile 500 /etc/haproxy/errorfiles/500.http
    errorfile 502 /etc/haproxy/errorfiles/502.http
    errorfile 503 /etc/haproxy/errorfiles/503.http
    errorfile 504 /etc/haproxy/errorfiles/504.http
    "

HTTP_ACL_CONTROL="    # 性能测试时需要关闭
    acl too_fast fe_sess_rate ge 50 # 速率大于50 延时 50ms
    tcp-request inspect-delay 50ms
    tcp-request content accept if ! too_fast
    tcp-request content accept if WAIT_END
    # 性能测试时需要关闭 end
"
HTTP_ACL_CONTROL="" #压力测试

TCP_DEFAULTS="    #tcp 通用设置
    mode tcp
    timeout connect 20s # default 10 second time out if a backend is not found
    timeout client 3650d #只是解决警告
    timeout server 3650d #只是解决警告
    timeout check 15s
    option tcplog
    #option    tcpka
    #tcp 通用设置 end
"

nbproc=1

echo "#cd /etc/haproxy/"
echo "#touch haproxy.cfg"
echo "#vi /etc/haproxy/haproxy.cfg"

#global配置
echo ""
echo "global"
echo "    stats socket  /tmp/haproxy level admin #echo \"show info\" | sudo socat stdio unix-connect:/tmp/haproxy "
echo "    log 127.0.0.1   local0 notice ##记日志的功能"
echo "    maxconn 64000"  #设定每个haproxy进程所接受的最大并发连接数
echo "    tune.maxaccept 512 " # 设定haproxy进程内核调度运行时一次性可以接受的连接的个数，较大的值可以带来较大的吞吐率
echo "    tune.maxpollevents 512 " #设定一次系统调用可以处理的事件最大数，默认值取决于OS；其值小于200时可节约带宽，但会略微增大网络延迟，而大于200时会降低延迟，但会稍稍增加网络带宽的占用量
echo "    tune.maxrewrite 1024 " #设定为首部重写或追加而预留的缓冲空间，建议使用1024左右的大小；在需要使用更大的空间时，haproxy会自动增加其值
echo "    chroot    /var/lib/haproxy"
echo "    user        haproxy "
echo "    group        haproxy"
echo "    daemon "
echo "    nbproc    $nbproc   "               #进程数量
echo "    pidfile    /var/run/haproxy.pid "
echo "    log-send-hostname
    spread-checks 50
    node `hostname`"

#defaults配置
echo " "
echo "defaults "
echo "    log        global "
echo "    mode http"
echo "    option   httplog "
echo "    option    dontlognull"
echo "    retries    3"
echo "    option    redispatch "#当serverId对应的服务器挂掉后，强制定向到其他健康的服务器
echo "    retries    3"
echo "    balance  source"
echo "    maxconn    64000 "
echo "    timeout connect 10s"    #连接超时，网络状态不好时，可能引起应用连接被中断

echo "#   下面两个超时不要配置到默认参数中，超时过短可能导致mysql的tcp链接断开，不配置则默认无超时 "
echo "#    timeout client 120s    #客户端超时 "
echo "#    timeout server 120s    #服务器超时 "

#admin_status配置
echo " "
echo "listen  Admin_status:48800 ${VIP}:48800 ##VIP "
echo "    stats uri /admin-status        ##统计页面"
echo "    stats auth  admin:admin"
echo "    mode    http "
echo "    option  httplog"
echo "    stats hide-version              #隐藏统计页面上HAProxy的版本信息 "
echo "    option    httpclose"
echo "    stats refresh 30s               #统计页面自动刷新时间"
echo "#      stats    admin if TRUE"
echo "    timeout connect    10s "
echo "    timeout server    10s "
echo "    timeout client    10s  "

for NODE01 in $CLS_HOST_LIST ; do
    echo "    server    ${NODE01} ${NODE01}:22 check   inter 30s rise 3 fall 3 weight 1 "
done


#HAProxy的日志记录内容设置
echo ""
echo "#################HAProxy的日志记录内容设置###################
    capture request header Host len 40
    capture request header Content-Length len 10
    capture request header Referer len 200
    capture response header Server len 40
    capture response header Content-Length len 10
    capture response header Cache-Control len 8 "
echo "
    errorfile 403 /etc/haproxy/errorfiles/403.http
    errorfile 500 /etc/haproxy/errorfiles/500.http
    errorfile 502 /etc/haproxy/errorfiles/502.http
    errorfile 503 /etc/haproxy/errorfiles/503.http
    errorfile 504 /etc/haproxy/errorfiles/504.http"

#zookeeper配置
if [ "`check_app zookeeper`" = "true" ] ; then
    echo " "
    echo "##转发到zookeeper的2181端口，即zookeeper的服务端口"
    echo "listen   ZooKeeper:2182 ${VIP}:2182"
    echo "$TCP_DEFAULTS"
    echo "      option httpchk OPTIONS * HTTP/1.1\r\nHost:\ www"
    echo "      balance roundrobin "

    appHosts=`getAppHosts zookeeper `

	LEN=0
    appHosts=${appHosts:=$CLS_HOST_LIST}
    for NODE01 in $appHosts ; do
	    ((LEN++))
        echo "      server    ZooKeeper_${NODE01} ${NODE01}:2181 check port 49997 inter 30s rise 3 fall 3 weight 1 "
    done
     # 本机不是
    if [ "${appHosts//$LOCAL_HOST/}" = "$appHosts" ] ; then
        echo " "
        echo "listen   ZooKeeper:2181 ${VIP}:2181"
        echo "$TCP_DEFAULTS"
        echo "      option httpchk OPTIONS * HTTP/1.1\r\nHost:\ www"
        echo "      balance roundrobin "
    	LEN=0
    	weight=1
        for NODE01 in $appHosts ; do
    	    echo "      server    ZooKeeper_${NODE01} ${NODE01}:2181 check port 49997 inter 30s rise 3 fall 3 weight 1 "
        done
    fi
fi

#mysql配置
if [ "`check_app mysql`" = "true" ] ; then
    appHosts=`getAppHosts mysql `
    echo " "
    echo "listen    Mysql:3307 ${VIP}:3307 ##转发到mysql的3306端口，即mysql的服务端口 "
    echo "$TCP_DEFAULTS"
    echo "    option httpchk OPTIONS * HTTP/1.1\r\nHost:\ www"
    echo "    balance  roundrobin "
    for NODE01 in $appHosts ; do
	    ((LEN++))
        echo "    server    MySQL_$NODE01 ${NODE01}:3306 check port 49999 inter 30s rise 3 fall 3 weight 1 "
    done

    # 本机是否是mysql
    if [ "${appHosts//$LOCAL_HOST/}" = "$appHosts" ] ; then
        echo " "
        echo "listen    Mysql:3306 ${VIP}:3306 ##转发到mysql的3306端口，即mysql的服务端口 "
        echo "$TCP_DEFAULTS"
        echo "    option httpchk OPTIONS * HTTP/1.1\r\nHost:\ www"
        echo "    balance  source #roundrobin "
    	LEN=0
    	weight=1
        for NODE01 in $appHosts ; do
    	    ((LEN++))
    	    if [ "$LEN" -gt "1" ] ; then
                weight=`expr $weight + $weight \* 10`
            fi
            echo "    server    Mysql_$NODE01 ${NODE01}:3306 check port 49999 inter 30s rise 3 fall 3 weight $weight "
        done
    fi
fi

echo "######################################################257"

#mongo配置
if [ "`check_app mongo`" = "true" ] ; then
    appHosts=`getAppHosts mongo `
    echo " "
    echo "listen    Mongodb:27019 ${VIP}:27019 ##转发到mongodb的27017、27018端口，即mongodb的服务端口 "
    echo "$TCP_DEFAULTS"
    echo "    option httpchk OPTIONS * HTTP/1.1\r\nHost:\ www"
    echo "    balance roundrobin "
	LEN=0
    for NODE01 in $appHosts ; do
	    ((LEN++))
        echo "    server    Mongodb_$NODE01 ${NODE01}:27017 check port 49995 inter 30s rise 3 fall 3 weight 100 "
    done
    # 本机是否是对应应用
    if [ "${appHosts//$LOCAL_HOST/}" = "$appHosts" ] ; then
        echo " "
        echo "listen    Mongodb:27017 ${VIP}:27017 ##转发到mongodb的27017、27018端口，即mongodb的服务端口 "
        echo "$TCP_DEFAULTS"
        echo "    option httpchk OPTIONS * HTTP/1.1\r\nHost:\ www"
        echo "    balance roundrobin "
    	LEN=0
        for NODE01 in $appHosts ; do
    	    ((LEN++))
            echo "    server    Mongodb_$NODE01 ${NODE01}:27017 check port 49995 inter 30s rise 3 fall 3 weight 100 "
        done
    fi
fi

#codis配置
if [ "`check_app codis`" = "true" ] ; then
    echo " "
    echo "#Codis只是为了监控是否启动，没有负载的功能 "
    echo "listen    Codis_Proxy:6307 ${VIP}:6307 "
    echo "$TCP_DEFAULTS"
	appHosts=`getAppHosts codis `
	LEN=0
    for NODE01 in $appHosts ; do
	    ((LEN++))
    	echo "    server    Codis_Proxy_$NODE01 ${NODE01}:6377 check inter 30s rise 3 fall 3 weight 1 "
    done
    # 本机是否是对应应用
    if [ "${appHosts//$LOCAL_HOST/}" = "$appHosts" ] ; then
        echo " "
        echo "#Codis只是为了监控是否启动，没有负载的功能 "
        echo "listen    Codis_Proxy:6377 ${VIP}:6377 "
        echo "$TCP_DEFAULTS"
	    LEN=0
        for NODE01 in $appHosts ; do
	        ((LEN++))
        	echo "    server    Codis_Proxy_$NODE01 ${NODE01}:6377 check inter 30s rise 3 fall 3 weight 1 "
        done
    fi
fi

#eagles配置
if [ "`check_app eagles_docker`" = "true" ] ; then
    echo " "
    echo "#Eagles  check "
    echo "listen   Eagles:9121 ${VIP}:9121"
    echo "$HTTP_ALL_DEFAULTS "
    echo "    option    httpchk GET /_cluster/health "
	appHosts=`getAppHosts eagles_docker `
	LEN=0
    for NODE01 in $appHosts ; do
	    ((LEN++))
        echo "    server    Eagles_$NODE01 ${NODE01}:17100  check inter 15s rise 3 fall 3 "
    done
    # 本机是否是对应应用
    if [ "${appHosts//$LOCAL_HOST/}" = "$appHosts" ] ; then
         echo " "
        echo "#Eagles  check "
        echo "listen   Eagles:17100 ${VIP}:17100"
        echo "$HTTP_ALL_DEFAULTS "
        echo "    option    httpchk GET /_cluster/health "
	    LEN=0
        for NODE01 in $appHosts ; do
    	    ((LEN++))
            echo "    server    Eagles_$NODE01 ${NODE01}:17100  check inter 15s rise 3 fall 3 "
        done
    fi
fi

#nump配置
if [ "`check_app nump`" = "true" ] ; then
    echo " "
    echo "#Nump   check "
    echo "listen   Nump:10056 ${VIP}:10056"
    echo "$HTTP_ALL_DEFAULTS "
    echo "    option    httpchk GET /nump/ "
	appHosts=`getAppHosts nump `

	LEN=0
    for NODE01 in $appHosts ; do
	    ((LEN++))
        echo "    server    Nump_$NODE01 ${NODE01}:10057  check inter 15s rise 2 fall 3 "
    done
    # 本机是否是对应应用
    if [ "${appHosts//$LOCAL_HOST/}" = "$appHosts" ] ; then
    echo " "
    echo "#Nump   check "
    echo "listen   Nump:10057 ${VIP}:10057"
    echo "$HTTP_ALL_DEFAULTS "
    echo "    option    httpchk GET /nump/ "
 	LEN=0
        for NODE01 in $appHosts ; do
    	    ((LEN++))
            echo "    server    Nump_$NODE01 ${NODE01}:10057  check inter 15s rise 2 fall 3 "
        done
    fi
fi

#cayman配置
if [ "`check_app cayman`" = "true" ] ; then
	appHosts=`getAppHosts cayman `
    echo " "
    echo "#Cayman   check "
    echo "listen   Cayman:9131 ${VIP}:9131"
    echo "$HTTP_ALL_DEFAULTS " | sed 's/source/leastconn/'
    echo "    option    httpchk GET  /api/cayman/store/stat/global/get?debug=true "
	LEN=0
    for NODE01 in $appHosts ; do
	    ((LEN++))
        echo "    server    Cayman_$NODE01 ${NODE01}:80 check inter 15s rise 2 fall 3 "
    done
    # 本机是否是对应应用
    if [ "${appHosts//$LOCAL_HOST/}" = "$appHosts" -a "$isMapp80" != "true" ] ; then
        isMapp80=true
        echo " "
        echo "#Cayman   check "
        echo "listen   Cayman:80 ${VIP}:80"
        echo "$HTTP_ALL_DEFAULTS " | sed 's/source/leastconn/'
        echo "    option    httpchk GET  /api/cayman/store/stat/global/get?debug=true "
    	LEN=0
        for NODE01 in $appHosts ; do
    	    ((LEN++))
            echo "    server    Cayman_$NODE01 ${NODE01}:80 check inter 15s rise 2 fall 3 "
        done
    fi
fi

echo " "
echo "frontend Public:88"
echo "    bind  ${VIP}:88 "
echo "    mode  http "
echo "    log        global "
echo "    option        httplog"
echo "    option          dontlognull"
echo "    option    forwardfor except 127.0.0.1"
echo "    option        httpclose"
echo "    monitor-uri    /monitoruri"
echo "$HTTP_FRONT_DEFAULTS"
echo "$HTTP_ACL_CONTROL"
echo " "
echo " "
echo "    # Host: will use a specific keyword soon "
echo "    #use_backend    ^Host:\ img        static "
echo " "
echo "    #    The URI will use a specific keyword soon "
echo "    #    use_backend    ^[^\ ]*\ /(img|css)/    static "
echo "
    acl fp url_dir -i /sobeyhive-fp
    use_backend Hivecore_FP:88 if fp
    acl bp url_dir -i /sobeyhive-bp
    use_backend Hivecore_BP:88 if bp
    acl ftengine url_dir -i /ftengine
    use_backend Ftengine:88 if ftengine
    acl nebula url_dir -i /nebula
    acl api url_dir -i /api
    use_backend Nebula:88 if nebula || api
    "
echo "    default_backend    Nebula:88 "

#hivecore配置
if [ "`check_app hivecore`" = "true" ] ; then
	appHosts=`getAppHosts hivecore `
    echo " "
    echo "backend    Hivecore_FP:88"
    echo "    option    httpchk HEAD /sobeyhive-fp "
    echo "$HTTP_BACK_DEFAULTS"
	LEN=0
    for NODE01 in $appHosts ; do
	    ((LEN++))
        echo "    server    FP_$NODE01 ${NODE01}:8060 cookie FoundationPlatform_$LEN check inter 15s rise 3 fall 3 weight 1 "
    done

    echo " "
    echo "backend    Hivecore_BP:88"
    echo "$HTTP_BACK_DEFAULTS "
    echo "    option    httpchk HEAD /sobeyhive-bp "
	LEN=0
    for NODE01 in $appHosts ; do
	    ((LEN++))
        echo "    server    BP_$NODE01 ${NODE01}:8060 cookie BizCore_$LEN check inter 15s rise 3 fall 3 weight 1 "
    done

    # 本机是否是对应应用
    if [ "${appHosts//$LOCAL_HOST/}" = "$appHosts"   ] ; then
        echo " "
        echo "listen   Hivecore:8060 ${VIP}:8060"
        echo "$HTTP_ALL_DEFAULTS "
        echo "    option    httpchk HEAD /sobeyhive-fp "
    	LEN=0
        for NODE01 in $appHosts ; do
    	    ((LEN++))
            echo "    server    Hivecore_$NODE01 ${NODE01}:8060 check inter 15s rise 2 fall 3 "
        done
    fi
fi

#ftengine2配置
if [ "`check_app ftengine2`" = "true" ] ; then
	appHosts=`getAppHosts ftengine2 `
    echo " "
    echo "backend    Ftengine:88 "
    echo "$HTTP_BACK_DEFAULTS "
    echo "    option    httpchk HEAD /ftengine "
	LEN=0
    for NODE01 in $appHosts ; do
	    ((LEN++))
        echo "    server    Ftengine_$NODE01 ${NODE01}:8090 cookie FTengine_$LEN check inter 15s rise 3 fall 3 weight 1 "
    done
    # 本机是否是对应应用
    if [ "${appHosts//$LOCAL_HOST/}" = "$appHosts"   ] ; then
        echo " "
        echo "listen   Ftengine:8090 ${VIP}:8090"
        echo "$HTTP_ALL_DEFAULTS "
        echo "    option    httpchk HEAD /ftengine "
    	LEN=0
        for NODE01 in $appHosts ; do
    	    ((LEN++))
            echo "    server    Ftengine_$NODE01 ${NODE01}:8090 cookie FTengine_$LEN check inter 15s rise 3 fall 3 weight 1 "
        done
    fi
fi

#nebula配置
if [ "`check_app nebula`" = "true" ] ; then
	appHosts=`getAppHosts nebula `
    echo " "
    echo "backend    Nebula:88 "
    echo "    option http-server-close "
    echo "$HTTP_BACK_DEFAULTS "
    echo "    option    httpchk GET /api/version  HTTP/1.1\r\nHost:\ www "
	LEN=0
    for NODE01 in $appHosts ; do
	    ((LEN++))
        echo "    server    Nebula_$NODE01 ${NODE01}:9090 cookie Nebula_$LEN check inter 15s rise 3 fall 3 weight 1 "
    done
    # 本机是否是对应应用
    if [ "${appHosts//$LOCAL_HOST/}" = "$appHosts"   ] ; then
        echo " "
        echo "listen   Nebula:9090 ${VIP}:9090"
        echo "$HTTP_ALL_DEFAULTS "
        echo "    option    httpchk GET /api/version  HTTP/1.1\r\nHost:\ www "
    	LEN=0
        for NODE01 in $appHosts ; do
    	    ((LEN++))
            echo "    server    Nebula_$NODE01 ${NODE01}:9090 cookie Nebula_$LEN check inter 15s rise 3 fall 3 weight 1 "
        done
    fi
fi

#cmserver配置
if [ "`check_app cmserver`" = "true" -o "`check_app cmweb`" = "true" ] ; then
	appHosts=`getAppHosts cmserver `
    echo " "
    echo "#CMserver "
    echo "listen    CMserver:9023 ${VIP}:9023"
    echo "$HTTP_ALL_DEFAULTS " | sed 's/source/leastconn/'
    echo "    option    httpchk GET /CMApi/api/basic/account/testconnect"
	LEN=0
    for NODE01 in $appHosts ; do
	    ((LEN++))
        echo "    server    CMserver_$NODE01 ${NODE01}:9022  check  inter 15s rise 3 fall 3 "
    done
    # 本机是否是对应应用
    if [ "${appHosts//$LOCAL_HOST/}" = "$appHosts"   ] ; then
        echo " "
        echo "#CMserver "
        echo "listen    CMserver:9022 ${VIP}:9022"
        echo "$HTTP_ALL_DEFAULTS " | sed 's/source/leastconn/'
        echo "    option    httpchk GET /CMApi/api/basic/account/testconnect"
    	LEN=0
        for NODE01 in $appHosts ; do
    	    ((LEN++))
            echo "    server    CMserver_$NODE01 ${NODE01}:9022  check  inter 15s rise 3 fall 3 "
        done
    fi
#cmserver windows配置
    # echo " "
    # echo "#CMserver Windows"
    # echo "listen    CMserver_windows:9037 ${VIP}:9037"
    # echo "$HTTP_ALL_DEFAULTS " | sed 's/source/leastconn/'
    # echo "    option    httpchk GET /CMApi/api/basic/account/testconnect"
	# LEN=0
    # for NODE01 in $appHosts ; do
	    # ((LEN++))
        # echo "    server    CMserver_windows_$NODE01 ${NODE01}:9036  check  inter 15s rise 3 fall 3 "
    # done
fi

#cmweb配置
if [ "`check_app cmserver`" = "true" -o "`check_app cmweb`" = "true" ] ; then
	appHosts=`getAppHosts cmweb `
    
    if [ -z "$appHosts" -a "`check_app cmweb`" = "false" ];then
        appHosts=$CLS_HOST_LIST
    fi    
    
    echo " "
    echo "#CM-Web "
    echo "listen    CMweb:9021 ${VIP}:9021"
    echo "$HTTP_ALL_DEFAULTS "
    echo "    option    httpchk GET /index.aspx "
	LEN=0
    for NODE01 in $appHosts ; do
	    ((LEN++))
        echo "    server    CMweb_$NODE01 ${NODE01}:9020  check  inter 15s rise 3 fall 3 "
    done
     # 本机是否是对应应用
    if [ "${appHosts//$LOCAL_HOST/}" = "$appHosts"   ] ; then
        echo " "
        echo "#CM-Web "
        echo "listen    CMweb:9020 ${VIP}:9020"
        echo "$HTTP_ALL_DEFAULTS "
        echo "    option    httpchk GET /index.aspx "
    	LEN=0
        for NODE01 in $appHosts ; do
    	    ((LEN++))
            echo "    server    CMweb_$NODE01 ${NODE01}:9020  check  inter 15s rise 3 fall 3 "
        done
    fi
fi

echo " "
echo "frontend Streams:86"
echo "    bind  ${VIP}:86 "
echo "    mode  http "
echo "    log        global "
echo "    option        httplog"
echo "    option          dontlognull"
echo "    option    forwardfor except 127.0.0.1"
echo "    option        httpclose"
echo "    monitor-uri    /monitoruri"
echo "$HTTP_FRONT_DEFAULTS"
echo "$HTTP_ACL_CONTROL"
if [ "`check_app nebula`" = "true" ] ; then
    echo "    acl streams url_dir -m reg -i /bucket.*
    use_backend Streams_Bucket:86 if streams "
fi

if [ "`check_app ntag`" = "true" ] ; then
    echo "    acl ntag url_dir -i /.*
    use_backend Ntag:86 if ntag
    default_backend Ntag:86"
else
    echo "    default_backend Streams_Bucket:86"
fi

#Streams配置
if [ "`check_app nebula`" = "true" ] ; then
	appHosts=`getAppHosts nebula `
    echo " "
    echo "backend Streams_Bucket:86 "
    echo "    option http-server-close "
    echo "$HTTP_BACK_DEFAULTS "
    echo "  option  httpchk GET /hacheck/index.html"
	LEN=0
    for NODE01 in $appHosts ; do
	    ((LEN++))
        echo "  server  Streams_Bucket_$NODE01 ${NODE01}:9010 cookie Streams_$LEN check inter 15s rise 3 fall 3 weight 1 "
    done
    # 本机是否是对应应用
    if [ "${appHosts//$LOCAL_HOST/}" = "$appHosts"   ] ; then
        echo " "
        echo "#CM-Web "
        echo "listen    Streams_Bucket:9010 ${VIP}:9010"
        echo "$HTTP_ALL_DEFAULTS "
        echo "  option  httpchk GET /hacheck/index.html"
    	LEN=0
        for NODE01 in $appHosts ; do
    	    ((LEN++))
            echo "  server  Streams_Bucket_$NODE01 ${NODE01}:9010 cookie Streams_$LEN check inter 15s rise 3 fall 3 weight 1 "
        done
    fi
fi

#Ntag配置
if [ "`check_app ntag`" = "true" ] ; then
	appHosts=`getAppHosts ntag `
    echo " "
    echo "backend Ntag:86 "
    echo "  option http-server-close "
    echo "$HTTP_BACK_DEFAULTS "
    echo "  option  httpchk GET /user/#/login"
    LEN=0
    for NODE01 in $appHosts ; do
        ((LEN++))
        echo "  server  Ntag_$NODE01 ${NODE01}:9060 cookie Ntag_$LEN check inter 10s rise 3 fall 3 weight 1 "
    done
    # 本机是否是对应应用
    if [ "${appHosts//$LOCAL_HOST/}" = "$appHosts"   ] ; then
        echo " "
        echo "backend Ntag:9060 "
        echo "  option http-server-close "
        echo "$HTTP_BACK_DEFAULTS "
        echo "  option  httpchk GET /user/#/login"
        LEN=0
        for NODE01 in $appHosts ; do
            ((LEN++))
            echo "  server  Ntag_$NODE01 ${NODE01}:9060 cookie Ntag_$LEN check inter 10s rise 3 fall 3 weight 1 "
        done
    fi
fi

#Infoshare配置
if [ "`check_app infoshare`" = "true" ] ; then
	appHosts=`getAppHosts infoshare `
    echo " "
    echo "#Infoshare   check "
    echo "listen   Infoshare:82 ${VIP}:82"
    echo "$HTTP_ALL_DEFAULTS "
    echo "    option    httpchk GET /news/login.jsp "
    LEN=0
    for NODE01 in $appHosts ; do
        ((LEN++))
        echo "    server    Infoshare_$NODE01 ${NODE01}:9080  check inter 10s rise 2 fall 3 "
    done
    # 本机是否是对应应用
    if [ "${appHosts//$LOCAL_HOST/}" = "$appHosts"   ] ; then
        echo " "
        echo "#Infoshare   check "
        echo "listen   Infoshare:9080 ${VIP}:9080"
        echo "$HTTP_ALL_DEFAULTS "
        echo "    option    httpchk GET /news/login.jsp "
        LEN=0
        for NODE01 in $appHosts ; do
            ((LEN++))
            echo "    server    Infoshare_$NODE01 ${NODE01}:9080  check inter 10s rise 2 fall 3 "
        done
    fi
fi


#新增配置
#后期排序

#ingestdbsvr配置
if [ "`check_app ingestdbsvr`" = "true" ] ; then
	appHosts=`getAppHosts ingestdbsvr `
    echo " "
    echo "#IngestDBSvr   check "
    echo "listen   IngestDBSvr:9025 ${VIP}:9025"
    echo "$HTTP_ALL_DEFAULTS "
    echo "    option    httpchk GET /api/device/GetAllCaptureChannels "
	LEN=0
    for NODE01 in $appHosts ; do
	    ((LEN++))
        echo "    server    IngestDBSvr_$NODE01 ${NODE01}:9024  check inter 15s rise 3 fall 3 weight 1"
    done
    # 本机是否是对应应用
    if [ "${appHosts//$LOCAL_HOST/}" = "$appHosts"   ] ; then
        echo " "
        echo "#IngestDBSvr   check "
        echo "listen   IngestDBSvr:9024 ${VIP}:9024"
        echo "$HTTP_ALL_DEFAULTS "
        echo "    option    httpchk GET /api/device/GetAllCaptureChannels "
    	LEN=0
        for NODE01 in $appHosts ; do
    	    ((LEN++))
            echo "    server    IngestDBSvr_$NODE01 ${NODE01}:9024  check inter 15s rise 3 fall 3 weight 1"
        done
    fi
#ingestDEVCTL配置
    # echo " "
    # echo "#IngestDEVCTL   check "
    # echo "listen   IngestDEVCTL:9039 ${VIP}:9039"
    # echo "$HTTP_ALL_DEFAULTS "
    # echo "    option    httpchk GET  /api/G2MatrixWebCtrl/getall "

	# LEN=0
    # for NODE01 in $appHosts ; do
	    # ((LEN++))
        # echo "    server    IngestDEVCTL_$NODE01 ${NODE01}:9038  check inter 15s rise 3 fall 3 weight 1"
    # done
    # 本机是否是对应应用
    # if [ "${appHosts//$LOCAL_HOST/}" = "$appHosts"   ] ; then
        # echo " "
        # echo "#IngestDEVCTL   check "
        # echo "listen   IngestDEVCTL:9038 ${VIP}:9038"
        # echo "$HTTP_ALL_DEFAULTS "
        # echo "    option    httpchk GET  /api/G2MatrixWebCtrl/getall "
    	# LEN=0
        # for NODE01 in $appHosts ; do
    	    # ((LEN++))
             # echo "    server    IngestDEVCTL_$NODE01 ${NODE01}:9038  check inter 15s rise 3 fall 3 weight 1"
        # done
    # fi
fi

#ingesttasksvr配置
if [ "`check_app ingesttasksvr`" = "true" ] ; then
	appHosts=`getAppHosts ingesttasksvr `
    echo " "
    echo "#IngestTaskSvr   check "
    echo "listen   IngestTaskSvr:9041 ${VIP}:9041"
    echo "$HTTP_ALL_DEFAULTS "
    echo "    option    httpchk GET #need modify "
	LEN=0
    for NODE01 in $appHosts ; do
	    ((LEN++))
        echo "    server    IngestTaskSvr_$NODE01 ${NODE01}:9040  check inter 15s rise 3 fall 3 weight 1"
    done
    # 本机是否是对应应用
    if [ "${appHosts//$LOCAL_HOST/}" = "$appHosts"   ] ; then
        echo " "
        echo "#IngestTaskSvr   check "
        echo "listen   IngestTaskSvr:9040 ${VIP}:9040"
        echo "$HTTP_ALL_DEFAULTS "
        echo "    option    httpchk GET #need modify "
    	LEN=0
        for NODE01 in $appHosts ; do
    	    ((LEN++))
            echo "    server    IngestTaskSvr_$NODE01 ${NODE01}:9040  check inter 15s rise 3 fall 3 weight 1"
        done
    fi
fi

#ingestmsgsvr配置
if [ "`check_app ingestmsgsvr`" = "true" ] ; then
	appHosts=`getAppHosts ingestmsgsvr `
    echo " "
    echo "#IngestMsgSvr   check "
    echo "listen   IngestMsgSvr:9043 ${VIP}:9043"
    echo "$HTTP_ALL_DEFAULTS "
    echo "    option    httpchk GET #need modify "
	LEN=0
    for NODE01 in $appHosts ; do
	    ((LEN++))
        echo "    server    IngestMsgSvr_$NODE01 ${NODE01}:9042  check inter 15s rise 3 fall 3 weight 1"
    done
    # 本机是否是对应应用
    if [ "${appHosts//$LOCAL_HOST/}" = "$appHosts"   ] ; then
        echo " "
        echo "#IngestMsgSvr   check "
        echo "listen   IngestMsgSvr:9042 ${VIP}:9042"
        echo "$HTTP_ALL_DEFAULTS "
        echo "    option    httpchk GET #need modify "
    	LEN=0
        for NODE01 in $appHosts ; do
    	    ((LEN++))
            echo "    server    IngestMsgSvr_$NODE01 ${NODE01}:9042  check inter 15s rise 3 fall 3 weight 1"
        done
    fi
fi

#mosgateway配置
if [ "`check_app mosgateway`" = "true" ] ; then
	appHosts=`getAppHosts mosgateway `
    echo " "
    echo "#MosGateway   check "
    echo "listen   MosGateway:10540 ${VIP}:10540"
    echo "$TCP_DEFAULTS"
	LEN=0
    for NODE01 in $appHosts ; do
	    ((LEN++))
        echo "    server    MosGateway_$NODE01 ${NODE01}:10550  check inter 30s rise 3 fall 3 weight 1"
    done
# 本机是否是对应应用
    if [ "${appHosts//$LOCAL_HOST/}" = "$appHosts"   ] ; then
        echo " "
        echo "#MosGateway   check "
        echo "listen   MosGateway:10550 ${VIP}:10550"
        echo "$TCP_DEFAULTS"
    	LEN=0
        for NODE01 in $appHosts ; do
    	    ((LEN++))
            echo "    server    MosGateway_$NODE01 ${NODE01}:10550  check inter 30s rise 3 fall 3 weight 1"
        done
    fi
	echo " "
	echo "listen   MosGateway:10541 ${VIP}:10541"
    echo "$TCP_DEFAULTS"
	LEN=0
    for NODE01 in $appHosts ; do
	    ((LEN++))
        echo "    server    MosGateway_$NODE01 ${NODE01}:10551  check inter 30s rise 3 fall 3 weight 1"
    done
# 本机是否是对应应用
    if [ "${appHosts//$LOCAL_HOST/}" = "$appHosts"   ] ; then
        echo " "
    	echo "listen   MosGateway:10551 ${VIP}:10551"
        echo "$TCP_DEFAULTS"
    	LEN=0
        for NODE01 in $appHosts ; do
    	    ((LEN++))
            echo "    server    MosGateway_$NODE01 ${NODE01}:10551  check inter 30s rise 3 fall 3 weight 1"
        done
    fi
	echo " "
	echo "listen   MosGateway:10542 ${VIP}:10542"
    echo "$TCP_DEFAULTS"

	LEN=0
    for NODE01 in $appHosts ; do
	    ((LEN++))
        echo "    server    MosGateway_$NODE01 ${NODE01}:10552  check inter 30s rise 3 fall 3 weight 1"
    done
# 本机是否是对应应用
    if [ "${appHosts//$LOCAL_HOST/}" = "$appHosts"   ] ; then
        echo " "
    	echo "listen   MosGateway:10552 ${VIP}:10552"
        echo "$TCP_DEFAULTS"

    	LEN=0
        for NODE01 in $appHosts ; do
    	    ((LEN++))
            echo "    server    MosGateway_$NODE01 ${NODE01}:10552  check inter 30s rise 3 fall 3 weight 1"
        done
    fi
	echo " "
    echo "listen   MosGateway:10555 ${VIP}:10555"
    echo "    option http-server-close "
    echo "$HTTP_BACK_DEFAULTS "
    echo "    option httpchk GET /index.htm "

	LEN=0
    for NODE01 in $appHosts ; do
	    ((LEN++))
        echo "    server    MosGateway_$NODE01 ${NODE01}:10556  check inter 15s rise 3 fall 3 weight 1"
    done
    # 本机是否是对应应用
    if [ "${appHosts//$LOCAL_HOST/}" = "$appHosts"   ] ; then
        echo " "
        echo "listen   MosGateway:10556 ${VIP}:10556"
        echo "    option http-server-close "
        echo "$HTTP_BACK_DEFAULTS "
        echo "    option httpchk GET /index.htm "

    	LEN=0
        for NODE01 in $appHosts ; do
    	    ((LEN++))
            echo "    server    MosGateway_$NODE01 ${NODE01}:10556  check inter 15s rise 3 fall 3 weight 1"
        done
    fi
fi

#jove配置
if [ "`check_app jove`" = "true" ] ; then
	appHosts=`getAppHosts jove `
    echo " "
    echo "#Jove   check "
    echo "listen   Jove:9027 ${VIP}:9027"
    echo "$HTTP_ALL_DEFAULTS "
    echo "    option    httpchk GET /Cm/Login?usertoken= "
	LEN=0
    for NODE01 in $appHosts ; do
	    ((LEN++))
        echo "    server    Jove_$NODE01 ${NODE01}:9026  check inter 15s rise 3 fall 3 weight 1"
    done
    # 本机是否是对应应用
    if [ "${appHosts//$LOCAL_HOST/}" = "$appHosts"   ] ; then
        echo " "
        echo "#Jove   check "
        echo "listen   Jove:9026 ${VIP}:9026"
        echo "$HTTP_ALL_DEFAULTS "
        echo "    option    httpchk GET /Cm/Login?usertoken= "
    	LEN=0
        for NODE01 in $appHosts ; do
    	    ((LEN++))
            echo "    server    Jove_$NODE01 ${NODE01}:9026  check inter 15s rise 3 fall 3 weight 1"
        done
    fi
fi


#otcserver配置
if [ "`check_app otcserver`" = "true" ] ; then
	appHosts=`getAppHosts otcserver `
    echo " "
    echo "#OTCSvr   check "
    echo "listen   OTCSvr:9045 ${VIP}:9045"
    echo "$HTTP_ALL_DEFAULTS "
    echo "    option    httpchk GET /getotc HTTP/1.1\r\nHost:\ www"
	LEN=0
    for NODE01 in $appHosts ; do
	    ((LEN++))
        echo "    server    OTCSvr_$NODE01 ${NODE01}:9044  check inter 15s rise 3 fall 3 weight 1"
    done
    # 本机是否是对应应用
    if [ "${appHosts//$LOCAL_HOST/}" = "$appHosts"   ] ; then
       echo " "
        echo "#OTCSvr   check "
        echo "listen   OTCSvr:9044 ${VIP}:9044"
        echo "$HTTP_ALL_DEFAULTS "
        echo "    option    httpchk GET /getotc HTTP/1.1\r\nHost:\ www"
    	LEN=0
        for NODE01 in $appHosts ; do
    	    ((LEN++))
            echo "    server    OTCSvr_$NODE01 ${NODE01}:9044  check inter 15s rise 3 fall 3 weight 1"
        done
    fi
fi

#Floating license Server配置
if [ "`check_app floatinglicenseserver`" = "true" ] ; then
	appHosts=`getAppHosts floatinglicenseserver `
    echo " "
    echo "#Floatinglicensesvr   check "
    echo "listen   FLSvr:9033 ${VIP}:9033"
    echo "$HTTP_ALL_DEFAULTS "
    echo "    option    httpchk GET /testalive "
	LEN=0
    appHosts=${appHosts:=$CLS_HOST_LIST}
    for NODE01 in $appHosts ; do
	    ((LEN++))
        echo "    server    FLSvr_$NODE01 ${NODE01}:9032  check inter 15s rise 3 fall 3 weight 1"
    done
	# 本机是否是对应应用
    if [ "${appHosts//$LOCAL_HOST/}" = "$appHosts"   ] ; then
        echo " "
        echo "#Floatinglicensesvr   check "
        echo "listen   FLSvr:9032 ${VIP}:9032"
        echo "$HTTP_ALL_DEFAULTS "
        echo "    option    httpchk GET /testalive "
    	LEN=0
        appHosts=${appHosts:=$CLS_HOST_LIST}
        for NODE01 in $appHosts ; do
    	    ((LEN++))
            echo "    server    FLSvr_$NODE01 ${NODE01}:9032  check inter 15s rise 3 fall 3 weight 1"
        done
    fi


    echo " "
	echo "listen   FLSvr:9031 ${VIP}:9031"
    echo "$TCP_DEFAULTS"
	LEN=0
    for NODE01 in $appHosts ; do
	    ((LEN++))
        echo "    server    FLSvr_$NODE01 ${NODE01}:9030  check inter 30s rise 3 fall 3 weight 1"
    done
    # 本机是否是对应应用
    if [ "${appHosts//$LOCAL_HOST/}" = "$appHosts"   ] ; then
        echo " "
    	echo "listen   FLSvr:9030 ${VIP}:9030"
        echo "$TCP_DEFAULTS"
    	LEN=0
        for NODE01 in $appHosts ; do
    	    ((LEN++))
            echo "    server    FLSvr_$NODE01 ${NODE01}:9030  check inter 30s rise 3 fall 3 weight 1"
        done
    fi

    # echo " "
    # echo "#PLS_Windows   check "
    # echo "listen   PLS_Windows:9035 ${VIP}:9035"
    # echo "$HTTP_ALL_DEFAULTS "
    # echo "    option    httpchk GET /api/Studio/heartbeat "
	# LEN=0
    # for NODE01 in $appHosts ; do
	    # ((LEN++))
        # echo "    server    PLS_Windows_$NODE01 ${NODE01}:9034  check inter 15s rise 3 fall 3 weight 1"
    # done
fi

#sangha tcp配置
if [ "`check_app sangha`" = "true" ] ; then
	appHosts=`getAppHosts sangha `
    echo " "
    echo "#Sangha   check "
	echo "listen   Sangha:4505 ${VIP}:4505"
    echo "$TCP_DEFAULTS"
	LEN=0
    for NODE01 in $appHosts ; do
	    ((LEN++))
        echo "    server    Sangha_$NODE01 ${NODE01}:4504  check inter 30s rise 3 fall 3 weight 1"
    done
# 本机是否是对应应用
    if [ "${appHosts//$LOCAL_HOST/}" = "$appHosts"   ] ; then
        echo " "
        echo "#Sangha   check "
    	echo "listen   Sangha:4504 ${VIP}:4504"
        echo "$TCP_DEFAULTS"
    	LEN=0
        for NODE01 in $appHosts ; do
    	    ((LEN++))
            echo "    server    Sangha_$NODE01 ${NODE01}:4504  check inter 30s rise 3 fall 3 weight 1"
        done
    fi

#sanghaserver配置
    echo " "
    echo "#SanghaServer   check "
    echo "listen   SanghaServer:9047 ${VIP}:9047"
    echo "$HTTP_ALL_DEFAULTS "
    echo "    option    httpchk GET /sobey/plat/cmd "

	LEN=0
    for NODE01 in $appHosts ; do
	    ((LEN++))
        echo "    server    SanghaServer_$NODE01 ${NODE01}:9046  check inter 15s rise 3 fall 3 weight 1"
    done
    # 本机是否是对应应用
    if [ "${appHosts//$LOCAL_HOST/}" = "$appHosts"   ] ; then
        echo " "
        echo "#SanghaServer   check "
        echo "listen   SanghaServer:9046 ${VIP}:9046"
        echo "$HTTP_ALL_DEFAULTS "
        echo "    option    httpchk GET /sobey/plat/cmd "

    	LEN=0
        for NODE01 in $appHosts ; do
    	    ((LEN++))
            echo "    server    SanghaServer_$NODE01 ${NODE01}:9046  check inter 15s rise 3 fall 3 weight 1"
        done
    fi

#sanghaweb配置
    echo " "
    echo "#SanghaWeb   check "
    echo "listen   SanghaWeb:9049 ${VIP}:9049"
    echo "$HTTP_ALL_DEFAULTS "
    echo "    option    httpchk GET /Plat.Web/NormalServicePage.html "
	LEN=0
    for NODE01 in $appHosts ; do
	    ((LEN++))
        echo "    server    SanghaWeb_$NODE01 ${NODE01}:9048  check inter 15s rise 3 fall 3 weight 1"
    done
    # 本机是否是对应应用
    if [ "${appHosts//$LOCAL_HOST/}" = "$appHosts"   ] ; then
        echo " "
        echo "#SanghaWeb   check "
        echo "listen   SanghaWeb:9048 ${VIP}:9048"
        echo "$HTTP_ALL_DEFAULTS "
        echo "    option    httpchk GET /Plat.Web/NormalServicePage.html "
    	LEN=0
        for NODE01 in $appHosts ; do
    	    ((LEN++))
            echo "    server    SanghaWeb_$NODE01 ${NODE01}:9048  check inter 15s rise 3 fall 3 weight 1"
        done
    fi
fi

echo " "
IFS=OLD_IFS
