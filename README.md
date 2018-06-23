# hadoop-install-script
hadoop hive install script

hadoop组件：

组件|地址
---|---
Namenode | http://ip:50070/dfshealth.html#tab-overview
History server | http://ip:8188/applicationhistory
Datanode | http://ip:50075
Nodemanager | http://ip:8042/node
Resource manager | http://ip:8088


按顺序执行下面的指令，首先升级系统内核，设置/etc/hosts并复制到其他节点，对主节点这是免密登录，安装主节点，包括hadoop/mysql/hive，再将hadoop复制到其他子节
```

       ./install.sh update-kernel
       升级系统内核

       ./install.sh hosts hadoop01,hadoop02,hadoop03
       复制当前节点/etc/hosts文件到其他节点

       ./install.sh ssh-copy-id hadoop01,hadoop02,hadoop03
       当前节点到其他节点免密码登录

       ./install.sh install --master-hostname hadoop01 --slaves hadoop02,hadoop03 --hadoop-work-dir /root/hadoop --dfs-replication 1
       安装master节点，下面是参数说明：
       --master-hostname:设置主节点主机名。                                                例如：--master-hostname hadoop01
       --hadoop-work-dir：设置hadoop的工作目录，默认值为/root/hadoop。                       例如：--hadoop-work-dir /root/hadoop
       --dfs-replication：设置hdfs副本数，默认值为1。                                       例如：--dfs-replication 1
       --docker-graph：设置docker目录，默认值为/var/lib/docker。                            例如：--docker-graph /var/lib/docker
       --docker-mirrors：docker镜像仓库地址，默认值为https://5md0553g.mirror.aliyuncs.com。  例如：--docker-mirrors https://5md0553g.mirror.aliyuncs.com
       --docker-data-dir：mysql的docker容器的数据持久化目录，默认值为/root/docker。           例如：--docker-data-dir /root/docker

       ./install.sh reset hadoop01,hadoop02,hadoop03 --hadoop-work-dir /root/hadoop --hive-temp-dir=/root/hive/tmp
       删除集群
```
