#!/bin/bash

set -o errexit
set -o nounset
set -o pipefail


# 执行脚本前先设置/etc/hosts
#sudo vi /etc/hosts
#172.16.120.161 hadoop01
#172.16.120.162 hadoop02
#172.16.120.163 hadoop03

#设置主机名
#hostnamectl --static set-hostname  hadoop01

#
#配置 ssh 免登陆
#
ssh_login()
{
    #配置 ssh 免登陆
    #实现自动输入四个回车执行ssh-keygen -t rsa  命令
    (echo -e "\n"
    sleep 1
    echo -e "\n"
    sleep 1
    echo -e "\n"
    sleep 1
    echo -e "\n")|ssh-keygen -t rsa
    #将公钥拷贝到要免登陆的机器上
    cat  ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys
    slave_array=$(echo $SLAVE_HOSTNAMES|tr "," "\n")
    for slave in $slave_array; do
        ssh-copy-id -i ~/.ssh/id_rsa.pub $slave
    done
}

#
#升级最新系统内核
#
update_kernel()
{
    #检查内核
    uname -sr
    #添加升级内核的第三方库 www.elrepo.org 上有方法
    rpm --import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org
    #列出内核相关包
    rpm -Uvh http://www.elrepo.org/elrepo-release-7.0-3.el7.elrepo.noarch.rpm
    #安装最新稳定版
    yum --disablerepo="*" --enablerepo="elrepo-kernel" list available
    #查看内核默认启动顺序
    yum --enablerepo=elrepo-kernel install kernel-ml -y
    #结果显示
    awk -F\' '$1=="menuentry " {print $2}' /etc/grub2.cfg
    #设置默认启动的内核，顺序index 分别是 0,1,2,3，每个人机器不一样，看清楚选择自己的index， 执行以下代码选择内核
    grub2-set-default 0
    #重启
    reboot

}

#
#拷贝hosts文件到slave
#
copy_hosts_file_to_slave()
{
    slave_array=$(echo $SLAVE_HOSTNAMES|tr "," "\n")
    for slave in $slave_array; do
        scp /etc/hosts $slave:/etc/hosts
    done
}

#
#系统判定
#
linux_os_centos()
{
    cnt=$(cat /etc/centos-release|grep "CentOS"|grep "release 7"|wc -l)
    if [ "$cnt" != "1" ];then
       echo "Only support CentOS 7...  exit"
       exit 1
    fi
}


#
#关闭防火墙
#
stop_firewalld()
{
    # 关闭防火墙
    systemctl disable firewalld
    systemctl stop firewalld
    echo "Firewall disabled success!"
}


#
#安装jdk
#
install_jdk()
{
    # 安装openjdk 8
    yum install -y java-1.8.0-openjdk java-1.8.0-openjdk-devel
    # 配置JAVA_HOME
    if [ `grep -c "JAVA_HOME" /etc/profile` -eq '0' ]; then
        echo export JAVA_HOME=$(readlink -f /usr/bin/java | sed "s:bin/java::") >> /etc/profile
        # 生效配置
        source /etc/profile
        echo "jdk8 install success!"
    fi
}

#
#安装hadoop
#
install_hadoop()
{
    mkdir -p ${HADOOP_WORK_DIR}
    # hadoop下载地址
    HADOOP_URL=https://mirrors.tuna.tsinghua.edu.cn/apache/hadoop/common/hadoop-${HADOOP_VERSION}/hadoop-${HADOOP_VERSION}.tar.gz
    # 下载并解压hadoop
    if [ ! -f "$(pwd)/hadoop.tar.gz" ]; then
        # 下载hadoop
        curl -fSL "$HADOOP_URL" -o $(pwd)/hadoop.tar.gz
        # hadoop验证文件
        curl -fSL "$HADOOP_URL.asc" -o $(pwd)/hadoop.tar.gz.asc
        # 验证hadoop
        gpg --verify $(pwd)/hadoop.tar.gz.asc
    fi
    # 将hadoop解压到创建的目录
    if [ ! -d "/usr/local/hadoop" ]; then
        mkdir /usr/local/hadoop
        tar -zxvf $(pwd)/hadoop.tar.gz -C /usr/local/hadoop
    fi

    export HADOOP_HOME=/usr/local/hadoop/hadoop-${HADOOP_VERSION}
    # 配置HADOOP_HOME环境变量
    if [ `grep -c "HADOOP_HOME" /etc/profile` -eq '0' ]; then
        echo export HADOOP_HOME=${HADOOP_HOME} >> /etc/profile
        # 配置JAVA和HADOOP的PATH变量
        echo export PATH=$PATH:\${HADOOP_HOME}/bin:\${HADOOP_HOME}/sbin:\$JAVA_HOME/bin >> /etc/profile
        # 生效配置
        source /etc/profile
    fi
    #配置 hadoop-env.sh
    sed -i 's/\export JAVA_HOME=\${JAVA_HOME}/#export JAVA_HOME=${JAVA_HOME}/g' ${HADOOP_HOME}/etc/hadoop/hadoop-env.sh
    echo export JAVA_HOME=$(readlink -f /usr/bin/java | sed "s:bin/java::") >> ${HADOOP_HOME}/etc/hadoop/hadoop-env.sh

    #配置 core-site.xml
    if [  -f "${HADOOP_HOME}/etc/hadoop/core-site.xml" ]; then
        rm -rf ${HADOOP_HOME}/etc/hadoop/core-site.xml
    fi
    cat > ${HADOOP_HOME}/etc/hadoop/core-site.xml <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>
<configuration>
    <!-- 制定HDFS的老大(NameNode)的地址 -->
    <property>
        <name>fs.defaultFS</name>
        <value>hdfs://${MASTER_HOSTNAME}:9000</value>
    </property>
    <!-- 指定hadoop运行时产生文件的存储目录 -->
    <property>
        <name>hadoop.tmp.dir</name>
        <value>${HADOOP_WORK_DIR}</value>
    </property>
</configuration>
EOF

    #配置 hdfs-site.xml
    if [  -f "${HADOOP_HOME}/etc/hadoop/hdfs-site.xml" ]; then
        rm -rf ${HADOOP_HOME}/etc/hadoop/hdfs-site.xml
    fi
    cat > ${HADOOP_HOME}/etc/hadoop/hdfs-site.xml <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>
<configuration>
    <property>
        <name>dfs.datanode.ipc.address</name>
        <value>0.0.0.0:50020</value>
    </property>
    <property>
        <name>dfs.datanode.http.address</name>
        <value>0.0.0.0:50075</value>
    </property>
    <property>
        <name>dfs.replication</name>
        <value>${DFS_REPLICATION}</value>
    </property>
    <property>
        <name>dfs.namenode.name.dir</name>
        <value>${HADOOP_WORK_DIR}/namenode</value>
    </property>
    <property>
        <name>dfs.datanode.data.dir</name>
        <value>${HADOOP_WORK_DIR}/data</value>
    </property>
</configuration>
EOF
    #配置 mapred-site.xml
    if [  -f "${HADOOP_HOME}/etc/hadoop/mapred-site.xml" ]; then
        rm -rf ${HADOOP_HOME}/etc/hadoop/mapred-site.xml
    fi
    cat > ${HADOOP_HOME}/etc/hadoop/mapred-site.xml <<EOF
<?xml version="1.0"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>
<configuration>
    <!-- mapreduce运行在yarn框架上 -->
    <property>
        <name>mapreduce.framework.name</name>
        <value>yarn</value>
    </property>
    <property>
        <name>mapreduce.cluster.temp.dir</name>
        <value>${HADOOP_WORK_DIR}/mr_temp</value>
    </property>
</configuration>
EOF
    #配置 yarn-site.xml
    if [  -f "${HADOOP_HOME}/etc/hadoop/yarn-site.xml" ]; then
        rm -rf ${HADOOP_HOME}/etc/hadoop/yarn-site.xml
    fi
    cat > ${HADOOP_HOME}/etc/hadoop/yarn-site.xml <<EOF
<?xml version="1.0"?>
<configuration>
    <!-- 指定YARN的老大(ResourceManager)的地址 -->
    <property>
        <name>yarn.resourcemanager.hostname</name>
        <value>${MASTER_HOSTNAME}</value>
    </property>
    <!-- reducer获取数据的方式 -->
    <property>
        <name>yarn.nodemanager.aux-services</name>
        <value>mapreduce_shuffle</value>
    </property>
    <property>
        <name>yarn.log.dir</name>
        <value>${HADOOP_WORK_DIR}/yarn_log</value>
    </property>
</configuration>
EOF
}

#
#将hadoop发送到slave
#
copy_hadoop_to_slave()
{
    export HADOOP_HOME=/usr/local/hadoop/hadoop-${HADOOP_VERSION}
    if [  -f "${HADOOP_HOME}/etc/hadoop/slaves" ]; then
        rm -rf ${HADOOP_HOME}/etc/hadoop/slaves
    fi

    slave_array=$(echo $SLAVE_HOSTNAMES|tr "," "\n")
    for slave in $slave_array; do
        echo $slave >> ${HADOOP_HOME}/etc/hadoop/slaves
    done

    for slave in $slave_array; do
        ssh root@${slave} > /dev/null 2>&1 << eeooff
    mkdir -p ${HADOOP_WORK_DIR} ${HADOOP_HOME}
    yum install -y java-1.8.0-openjdk java-1.8.0-openjdk-devel
eeooff
        scp -r ${HADOOP_HOME} root@${slave}:/usr/local/hadoop/
    done
}


#
#启动hadoop
#
start_hadoop()
{
    start-dfs.sh
    start-yarn.sh
}

#
#安装docker
#
install_docker()
{
    if [ -f "/etc/yum.repos.d/docker.repo" ]; then
        rm -rf /etc/yum.repos.d/docker.repo
    fi
    # dockerproject docker源
    cat > /etc/yum.repos.d/docker.repo <<EOF
[docker-repo]
name=Docker Repository
baseurl=https://yum.dockerproject.org/repo/main/centos/7
enabled=1
gpgcheck=0
EOF

    #查看docker版本
    #yum list docker-engine showduplicates
    #安装docker
    yum install -y docker-engine-17.03.0.ce-1.el7.centos.x86_64
    echo "Docker installed successfully!"
    # 如果/etc/docker目录不存在，就创建目录
    if [ ! -d "/etc/docker" ]; then
     mkdir -p /etc/docker
    fi
    # 删除daemon.json
    if [ -f "/etc/docker/daemon.json" ]; then
        rm -rf /etc/docker/daemon.json
    fi
    # 配置加速器
    cat > /etc/docker/daemon.json <<EOF
{
  "registry-mirrors": ["${DOCKER_MIRRORS}"],
  "graph":"${DOCKER_GRAPH}",
  "storage-driver": "overlay2"
}
EOF
    echo "Config docker success!"
    systemctl daemon-reload
    systemctl enable docker
    systemctl start docker
    echo "Docker start successfully!"
    # 下载docker compose
    #curl -L https://github.com/docker/compose/releases/download/1.7.1/docker-compose-`uname -s`-`uname -m` > /usr/local/bin/docker-compose
    # 修改执行权限
    #chmod a+x /usr/local/bin/docker-compose
    yum -y install epel-release
    yum -y install python-pip
    pip install docker-compose
    echo "Docker compose install successfully!"
}


#
# 运行mysql容器
#
run_mysql_container()
{
    # 删除docker-compose-mysql.yaml
    if [ -f "$(pwd)/docker-compose-mysql.yaml" ]; then
        rm -rf $(pwd)/docker-compose-mysql.yaml
    fi
    # 运行mysql
    cat > $(pwd)/docker-compose-mysql.yaml <<EOF
version: "2"
services:
    mysql:
      restart: always
      image: mysql:5.6
      volumes:
        - ${DOCKER_DATA_DIR}/mysql/data:/var/lib/mysql
        - ${DOCKER_DATA_DIR}/mysql/conf:/etc/mysql/conf.d
      ports:
        - "3306:3306"
      environment:
        - MYSQL_DATABASE=hive
        - MYSQL_ROOT_PASSWORD=hive
EOF
    docker-compose -f $(pwd)/docker-compose-mysql.yaml stop

    docker-compose -f $(pwd)/docker-compose-mysql.yaml rm
    # 启动mysql
    docker-compose -f $(pwd)/docker-compose-mysql.yaml up -d
}

#
#安装hive
#
install_hive()
{
    mkdir -p ${HIVE_TEMP_DIR}
    # hive下载地址
    HIVE_URL=https://mirrors.tuna.tsinghua.edu.cn/apache/hive/hive-${HIVE_VERSION}/apache-hive-${HIVE_VERSION}-bin.tar.gz
    # 下载并解压hive
    if [ ! -f "$(pwd)/hive.tar.gz" ]; then
        # 下载hive
        curl -fSL "$HIVE_URL" -o $(pwd)/hive.tar.gz
    fi
    # 将hive解压到创建的目录
    if [ ! -d "/usr/local/hive" ]; then
        mkdir /usr/local/hive
        tar -zxvf $(pwd)/hive.tar.gz -C /usr/local/hive
    fi
    # 配置HIVE_HOME环境变量
    export HIVE_HOME=/usr/local/hive/apache-hive-${HIVE_VERSION}-bin
    if [ `grep -c "HIVE_HOME" /etc/profile` -eq '0' ]; then
        echo export HIVE_HOME=${HIVE_HOME} >> /etc/profile
        # 配置JAVA和HADOOP的PATH变量
        echo export PATH=$PATH:\${HIVE_HOME}/bin:\${HIVE_HOME}/sbin:\$JAVA_HOME/bin >> /etc/profile
        # 生效配置
        source /etc/profile
    fi

    # 删除hive-site.xml
    if [  -f "${HIVE_HOME}/conf/hive-site.xml" ]; then
        rm -rf ${HIVE_HOME}/conf/hive-site.xml
    fi
    # 复制配置文件
    cp ${HIVE_HOME}/conf/hive-default.xml.template ${HIVE_HOME}/conf/hive-site.xml
    cp ${HIVE_HOME}/conf/hive-log4j2.properties.template ${HIVE_HOME}/conf/hive-log4j2.properties
    cp ${HIVE_HOME}/conf/hive-exec-log4j2.properties.template ${HIVE_HOME}/conf/hive-exec-log4j2.properties
    cp ${HIVE_HOME}/conf/hive-env.sh.template ${HIVE_HOME}/conf/hive-env.sh

    # 配置hive-site.xml
    # 设置hive.metastore.warehouse.dir
    sed -i "s#/user/hive/warehouse#${HIVE_WAREHOUSE_DIR}#g" ${HIVE_HOME}/conf/hive-site.xml
    # 设置hive.exec.scratchdir
    sed -i "s#/tmp/hive#${HIVE_EXEC_SCRATCHDIR}#g" ${HIVE_HOME}/conf/hive-site.xml
    # 设置hive.querylog.location
    sed -i "s#\${system:java.io.tmpdir}/\${system:user.name}#${HIVE_QUERYLOG_DIR}#g" ${HIVE_HOME}/conf/hive-site.xml
    # 设置javax.jdo.option.ConnectionURL
    MYSQL_JDBC_URL="jdbc:mysql://${MASTER_HOSTNAME}:3306/hive?createDatabaseIfNotExist=true"
    sed -i "s#jdbc:derby:;databaseName=metastore_db;create=true#${MYSQL_JDBC_URL}#g" ${HIVE_HOME}/conf/hive-site.xml
    # 配置javax.jdo.option.ConnectionDriverName
    sed -i "s/org.apache.derby.jdbc.EmbeddedDriver/com.mysql.jdbc.Driver/g" ${HIVE_HOME}/conf/hive-site.xml
    # 配置javax.jdo.option.ConnectionUserName
    sed -i "s/<value>APP<\/value>/<value>root<\/value>/g" ${HIVE_HOME}/conf/hive-site.xml
    # 配置javax.jdo.option.ConnectionPassword
    sed -i "s/<value>mine<\/value>/<value>hive<\/value>/g" ${HIVE_HOME}/conf/hive-site.xml
    # 替换${system:java.io.tmpdir}
    sed -i "s#\${system:java.io.tmpdir}#${HIVE_TEMP_DIR}#g" ${HIVE_HOME}/conf/hive-site.xml
    # 替换${system:user.name}
    sed -i "s/{system:user.name}/{user.name}/g" ${HIVE_HOME}/conf/hive-site.xml

    # 配置hive-env.sh
    echo export HADOOP_HOME=/usr/local/hadoop/hadoop-${HADOOP_VERSION} >> ${HIVE_HOME}/conf/hive-env.sh
    echo export HIVE_CONF_DIR=${HIVE_HOME}/conf >> ${HIVE_HOME}/conf/hive-env.sh
    echo export HIVE_AUX_JARS_PATH=${HIVE_HOME}/lib >> ${HIVE_HOME}/conf/hive-env.sh

    # 启动hdfs
    start-dfs.sh

    # hdfs中创建目录
    hadoop fs -mkdir -p ${HIVE_WAREHOUSE_DIR}
    hadoop fs -mkdir -p ${HIVE_EXEC_SCRATCHDIR}
    hadoop fs -mkdir -p ${HIVE_QUERYLOG_DIR}
    hadoop fs -chmod -R 777 ${HIVE_WAREHOUSE_DIR}
    hadoop fs -chmod -R 777 ${HIVE_EXEC_SCRATCHDIR}
    hadoop fs -chmod -R 777 ${HIVE_QUERYLOG_DIR}

    # 下载mysql驱动
    MYSQL_JDBC_URL=http://central.maven.org/maven2/mysql/mysql-connector-java/6.0.6/mysql-connector-java-6.0.6.jar
    # 下载并解压hive
    if [ ! -f "${HIVE_HOME}/lib/mysql-connector-java-6.0.6.jar" ]; then
        # 下载hive
        curl -fSL "$MYSQL_JDBC_URL" -o ${HIVE_HOME}/lib/mysql-connector-java-6.0.6.jar
    fi

    schematool -initSchema -dbType mysql
}

#
#启动hive
#
start_hive()
{
    nohup hive --service hiveserver2 &
}

#
#格式化 namenode
#
namenode_format()
{
    hadoop namenode -format
}

#
#安装主节点
#
master_hadoop_install()
{
    stop_firewalld
    install_jdk
    install_hadoop
    namenode_format
}

# 主节点安装hive
master_hive_install()
{
    install_docker
    run_mysql_container
    install_hive
}

#
#安装从节点
#
slave_hadoop_install()
{
    copy_hadoop_to_slave
}

#
#卸载hadoop
#
reset_hadoop()
{
    #stop-dfs.sh
    #stop-yarn.sh
    rm -rf ${HADOOP_WORK_DIR} /usr/local/hadoop

    slave_array=$(echo $SLAVE_HOSTNAMES|tr "," "\n")
    for slave in $slave_array; do
        ssh root@${slave} rm -rf ${HADOOP_WORK_DIR} /usr/local/hadoop
    done
}

#
#卸载hive
#
reset_hive()
{
    #stop-dfs.sh
    #stop-yarn.sh
    rm -rf /usr/local/hive ${DOCKER_DATA_DIR} ${HIVE_TEMP_DIR}
}

help()
{
    echo "按顺序执行下面的指令，首先升级系统内核，设置/etc/hosts并复制到其他节点，对主节点这是免密登录，安装主节点，包括hadoop/mysql/hive，再将hadoop复制到其他子节点。"
    echo "usage:"
    echo "       $0 update-kernel"
    echo "       升级系统内核"
    echo ""
    echo "       $0 hosts hadoop01,hadoop02,hadoop03"
    echo "       复制当前节点/etc/hosts文件到其他节点"
    echo ""
    echo "       $0 ssh-copy-id hadoop01,hadoop02,hadoop03"
    echo "       当前节点到其他节点免密码登录"
    echo ""
    echo "       $0 install --master-hostname hadoop01 --slaves hadoop02,hadoop03 --hadoop-work-dir /root/hadoop --dfs-replication 1"
    echo "       安装master节点，下面是参数说明："
    echo "       --master-hostname:设置主节点主机名。                                                例如：--master-hostname hadoop01"
    echo "       --hadoop-work-dir：设置hadoop的工作目录，默认值为/root/hadoop。                       例如：--hadoop-work-dir /root/hadoop"
    echo "       --dfs-replication：设置hdfs副本数，默认值为1。                                       例如：--dfs-replication 1"
    echo "       --docker-graph：设置docker目录，默认值为/var/lib/docker。                            例如：--docker-graph /var/lib/docker"
    echo "       --docker-mirrors：docker镜像仓库地址，默认值为https://5md0553g.mirror.aliyuncs.com。  例如：--docker-mirrors https://5md0553g.mirror.aliyuncs.com"
    echo "       --docker-data-dir：mysql的docker容器的数据持久化目录，默认值为/root/docker。           例如：--docker-data-dir /root/docker"
    echo ""
    echo "       $0 reset hadoop01,hadoop02,hadoop03 --hadoop-work-dir /root/hadoop --hive-temp-dir=/root/hive/tmp"
    echo "       删除集群"
}



main()
{
    # hadoop版本号
    export HADOOP_VERSION=2.8.4
    # hdfs的副本数量
    export DFS_REPLICATION=1
    # hive版本号
    export HIVE_VERSION=2.3.3
    # hadoop工作目录
    export HADOOP_WORK_DIR=/root/hadoop
    # mysql的docker容器的数据持久化目录
    export DOCKER_DATA_DIR=/root/docker
    # docker存储目录
    export DOCKER_GRAPH=/var/lib/docker
    # docker加速器
    export DOCKER_MIRRORS=https://5md0553g.mirror.aliyuncs.com
    # hive数据仓库目录
    export HIVE_WAREHOUSE_DIR=/root/hive/warehouse
    # hive临时目录
    export HIVE_TEMP_DIR=/root/hive/tmp
    # hive作业目录
    export HIVE_EXEC_SCRATCHDIR=/root/hive/job/tmp
    # hive查询日志
    export HIVE_QUERYLOG_DIR=/root/hive/log/hadoop

    # 系统检测
    linux_os_centos
    #$# 查看这个程式的参数个数
    while [[ $# -gt 0 ]]
    do
        #获取第一个参数
        key="$1"

        case $key in
            update-kernel)
                export COMMAND="update-kernel"
            ;;
            ssh-copy-id)
                export COMMAND="ssh-copy-id"
                export SLAVE_HOSTNAMES=$2
                #向左移动位置一个参数位置
                shift
            ;;
            hosts)
                export COMMAND="hosts"
                export SLAVE_HOSTNAMES=$2
                #向左移动位置一个参数位置
                shift
            ;;
            reset)
                export COMMAND="reset"
                export SLAVE_HOSTNAMES=$2
                #向左移动位置一个参数位置
                shift
            ;;
            #获取节点类型
            install)
                export COMMAND="install"
            ;;
            #主节点名称
            -m|--master-hostname)
                export MASTER_HOSTNAME=$2
                #向左移动位置一个参数位置
                shift
            ;;
            #设置工作目录
            -w|--hadoop-work-dir)
                export HADOOP_WORK_DIR=$2
                #向左移动位置一个参数位置
                shift
            ;;
                      #设置docker的数据目录
            --docker-data-dir)
                export DOCKER_DATA_DIR=$2
                #向左移动位置一个参数位置
                shift
            ;;
            #slave节点，多个用逗号分隔
            -s|--slaves)
                export SLAVE_HOSTNAMES=$2
                #向左移动位置一个参数位置
                shift
            ;;
            #hdfs副本数目
            -d|--dfs-replication)
                export DFS_REPLICATION=$2
                #向左移动位置一个参数位置
                shift
            ;;
            #获取docker存储路径
            --docker-graph)
                export DOCKER_GRAPH=$2
                #向左移动位置一个参数位置
                shift
            ;;
            #获取docker加速器地址
            --docker-mirrors)
                export DOCKER_MIRRORS=$2
                #向左移动位置一个参数位置
                shift
            ;;
            #获取hive数据仓库地址
            --hive-warehouse-dir)
                export HIVE_WAREHOUSE_DIR=$2
                #向左移动位置一个参数位置
                shift
            ;;
            #获取hive临时目录
            --hive-temp-dir)
                export HIVE_TEMP_DIR=$2
                #向左移动位置一个参数位置
                shift
            ;;
            #获取hive作业目录
            --hive-exec-scratchdir)
                export HIVE_EXEC_SCRATCHDIR=$2
                #向左移动位置一个参数位置
                shift
            ;;
            #获取hive查询日志目录
            --hive-querylog-dir)
                export HIVE_QUERYLOG_DIR=$2
                #向左移动位置一个参数位置
                shift
            ;;
            #获取帮助
            -h|--help)
                help
                exit 1
            ;;
            *)
                # unknown option
                echo "unkonw option [$key]"
            ;;
        esac
        shift
    done

 case $COMMAND in
    "update-kernel" )
        update_kernel
        ;;
    "ssh-copy-id" )
        ssh_login
        ;;
    "hosts" )
        copy_hosts_file_to_slave
        ;;
    "reset" )
        reset_hadoop
        reset_hive
        ;;
    "install" )
        master_hadoop_install
        slave_hadoop_install
        start_hadoop
        master_hive_install
        start_hive
        ;;
    *)
        help
        ;;
 esac
}

main $@
