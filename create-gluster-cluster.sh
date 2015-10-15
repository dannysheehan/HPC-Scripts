#!/bin/sh

cd /tmp

REPOS="http://download.gluster.org/pub/gluster/glusterfs/3.6/LATEST/SLES11sp3/"
GLUSTER_VERSION="3.6.3-1"
START_NODE="b10b07"
THIS_NODE=`uname -n`

if [ ! -f "/tmp/glusterfs-$GLUSTER_VERSION.x86_64.rpm" ]
then
  wget $REPOS/glusterfs-$GLUSTER_VERSION.x86_64.rpm
  wget $REPOS/glusterfs-api-$GLUSTER_VERSION.x86_64.rpm
  wget $REPOS/glusterfs-cli-$GLUSTER_VERSION.x86_64.rpm
  wget $REPOS/glusterfs-fuse-$GLUSTER_VERSION.x86_64.rpm
  wget $REPOS/glusterfs-libs-$GLUSTER_VERSION.x86_64.rpm
  wget $REPOS/glusterfs-rdma-$GLUSTER_VERSION.x86_64.rpm
  wget $REPOS/glusterfs-server-$GLUSTER_VERSION.x86_64.rpm
fi

if [ ! -f "/tmp/glusterfs-$GLUSTER_VERSION.x86_64.rpm" ]
then
  echo "ERROR: repository issue"
  exit 1
fi



# the following may not be what you want
#
# if there is an older version
# stop gluster and cleanup the configuration.
#
if [ $(rpm -q glusterfs) != "glusterfs-$GLUSTER_VERSION" ]
then
  /sbin/service glusterd stop 2> /dev/null
  rm -fr /var/lib/glusterd/*

  zypper -n in \
    glusterfs-$GLUSTER_VERSION.x86_64.rpm \
    glusterfs-api-$GLUSTER_VERSION.x86_64.rpm \
    glusterfs-cli-$GLUSTER_VERSION.x86_64.rpm \
    glusterfs-fuse-$GLUSTER_VERSION.x86_64.rpm \
    glusterfs-libs-$GLUSTER_VERSION.x86_64.rpm \
    glusterfs-rdma-$GLUSTER_VERSION.x86_64.rpm \
    glusterfs-server-$GLUSTER_VERSION.x86_64.rpm
fi


# it's a client. If there is no second disk.
if ! parted -s /dev/sdb print > /dev/null 2>&1
then
  mkdir -p /gsw
  echo "${START_NODE}-ib:/gsw /gsw  glusterfs defaults,_netdev 0 3" >> /etc/fstab
  mount /gsw
  exit 0
fi

# use all of the second disk
parted -s  /dev/sdb mklabel msdos
parted -a optimal  /dev/sdb mkpart primary xfs 0% 100%

# xfsprogs 3.1.0 and newer will automatically detect the appropriate sector 
# size for a device
mkfs.xfs -f /dev/sdb1

#
# bake a brick
mkdir -p /glusterfs/brick1
echo "/dev/sdb1    /glusterfs/brick1       xfs     defaults 0 0" >> /etc/fstab
mount /glusterfs/brick1
mkdir /glusterfs/brick1/gsw

/sbin/service glusterd start


#
# the first brick needs to create the volume.
if [ ${THIS_NODE} = ${START_NODE} ] && ! gluster volume info gsw
then
  gluster volume create gsw ${START_NODE}-ib:/glusterfs/brick1/gsw
  gluster volume start gsw
else
  # reverse probe myself from anothe node in the pool
  ssh  $START_NODE "gluster peer probe ${THIS_NODE}-ib"

  BRICKS=$(gluster volume info gsw  | grep "^Brick[0-9]" | wc -l)

  # add myself as a replica.
  REPLICAS=$(($BRICKS + 1))
  gluster volume add-brick gsw replica $REPLICAS \
    ${THIS_NODE}-ib:/glusterfs/brick1/gsw
fi


mkdir -p /gsw
echo 'localhost:/gsw /gsw  glusterfs defaults,_netdev 0 3' >> /etc/fstab
mount /gsw
