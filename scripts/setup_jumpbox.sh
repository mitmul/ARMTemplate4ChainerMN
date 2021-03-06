#!/bin/sh -xe

# Setup hpcuser
HPC_USER=hpcuser
HPC_UID=7007
HPC_GROUP=hpcuser
HPC_GID=7007
groupadd -g $HPC_GID $HPC_GROUP

# sudo setting
echo "$HPC_USER ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
sed -i 's/^Defaults[ ]*requiretty/# Defaults requiretty/g' /etc/sudoers

# Setup shared home dir
SHARE_HOME=/share/home
DISK_MOUNT=/data1
mkdir -p $SHARE_HOME
mkdir -p $SHARE_HOME/$HPC_USER
mkdir -p $SHARE_HOME/$HPC_USER/.ssh

# Put all environment settings here for VMSS worker nodes
echo 'export LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH' >> ${SHARE_HOME}/${HPC_USER}/.bash_profile
echo 'export CPATH=/usr/local/cuda/include:$CPATH' >> ${SHARE_HOME}/${HPC_USER}/.bash_profile
echo 'export LIBRARY_PATH=/usr/local/cuda/lib64:$LIBRARY_PATH' >> ${SHARE_HOME}/${HPC_USER}/.bash_profile
echo 'export PATH=/usr/local/cuda/bin:$PATH' >> ${SHARE_HOME}/${HPC_USER}/.bash_profile
echo 'source /opt/intel/compilers_and_libraries_2016.3.223/linux/mpi/bin64/mpivars.sh' >> ${SHARE_HOME}/${HPC_USER}/.bash_profile
echo 'source /opt/intel/compilers_and_libraries_2018.2.199/linux/mkl/bin/mklvars.sh intel64' >> $SHARE_HOME/$HPC_USER/.bash_profile
echo 'export I_MPI_FABRICS=shm:dapl' >> ${SHARE_HOME}/${HPC_USER}/.bash_profile
echo 'export I_MPI_DAPL_PROVIDER=ofa-v2-ib0' >> ${SHARE_HOME}/${HPC_USER}/.bash_profile
echo 'export I_MPI_DYNAMIC_CONNECTION=0' >> ${SHARE_HOME}/${HPC_USER}/.bash_profile
echo 'export I_MPI_FALLBACK_DEVICE=0' >> ${SHARE_HOME}/${HPC_USER}/.bash_profile
echo 'export I_MPI_DAPL_DIRECT_COPY_THRESHOLD=16777216' >> ${SHARE_HOME}/${HPC_USER}/.bash_profile
echo 'export I_MPI_SHM_LMT=shm' >> ${SHARE_HOME}/${HPC_USER}/.bash_profile
echo 'export LANG="en_US.UTF-8"' >> ${SHARE_HOME}/${HPC_USER}/.bash_profile
echo 'export LANGUAGE="en_US.UTF-8"' >> ${SHARE_HOME}/${HPC_USER}/.bash_profile
echo 'export LC_ALL="en_US.UTF-8"' >> ${SHARE_HOME}/${HPC_USER}/.bash_profile
echo 'export LC_CTYPE="en_US.UTF-8"' >> ${SHARE_HOME}/${HPC_USER}/.bash_profile
echo 'export PATH=$HOME/.local/bin:$PATH' >> ${SHARE_HOME}/${HPC_USER}/.bash_profile

# Create user
useradd -c "HPC User" -g $HPC_GROUP -m -d $SHARE_HOME/$HPC_USER -s /bin/bash -u $HPC_UID $HPC_USER

# Configure public key auth for the HPC user
ssh-keygen -t rsa -f $SHARE_HOME/$HPC_USER/.ssh/id_rsa -q -P ""
cat $SHARE_HOME/$HPC_USER/.ssh/id_rsa.pub >> $SHARE_HOME/$HPC_USER/.ssh/authorized_keys
echo "Host *" | tee -a $SHARE_HOME/$HPC_USER/.ssh/config
echo "    StrictHostKeyChecking no" | tee -a $SHARE_HOME/$HPC_USER/.ssh/config
echo "    UserKnownHostsFile /dev/null" | tee -a $SHARE_HOME/$HPC_USER/.ssh/config
echo "    PasswordAuthentication no" | tee a $SHARE_HOME/$HPC_USER/.ssh/config
chown -R $HPC_USER:$HPC_GROUP $SHARE_HOME/$HPC_USER
chmod 700 $SHARE_HOME/$HPC_USER/.ssh
chmod 644 $SHARE_HOME/$HPC_USER/.ssh/config
chmod 644 $SHARE_HOME/$HPC_USER/.ssh/authorized_keys
chmod 600 $SHARE_HOME/$HPC_USER/.ssh/id_rsa
chmod 644 $SHARE_HOME/$HPC_USER/.ssh/id_rsa.pub

# Mount NFS
fdisk /dev/sdc <<EOF
n
p

1


w
EOF
sleep 10
mkdir ${DISK_MOUNT}
mkfs.ext4 /dev/sdc1
mount -t ext4 /dev/sdc1 ${DISK_MOUNT}
sleep 10
echo "/dev/sdc1    ${DISK_MOUNT}    ext4 defaults    0    1" | tee -a /etc/fstab

# Install NFS
apt-get update
apt-get -y install nfs-kernel-server		
echo "$SHARE_HOME    *(rw,async,no_subtree_check)" | tee -a /etc/exports
echo "$DISK_MOUNT    *(rw,async,no_subtree_check)" | tee -a /etc/exports
exportfs -a		
systemctl enable nfs-kernel-server.service
systemctl start nfs-kernel-server.service

# Install Python3
apt-get install -y ccache python3 python3-dev python3-dbg python3-wheel python3-pip parallel htop
update-alternatives --install /usr/bin/python python /usr/bin/python3 100
update-alternatives --install /usr/bin/pip pip /usr/bin/pip3 100

export LANG="en_US.UTF-8"
export LANGUAGE="en_US.UTF-8"
export LC_CTYPE="en_US.UTF-8"
export LC_ALL="en_US.UTF-8"
locale-gen en_US.UTF-8

# Install packages
apt-get update -y && apt-get install -y \
curl git build-essential gfortran nasm tmux sudo openssh-client libgoogle-glog-dev rsync curl wget cmake automake libgmp3-dev cpio libtool libyaml-dev realpath valgrind software-properties-common unzip libz-dev vim emacs libssl-dev libffi-dev parallel htop

# Install Intel MKL
cd /opt
wget http://registrationcenter-download.intel.com/akdlm/irc_nas/tec/12725/l_mkl_2018.2.199.tgz && \
tar zxvf l_mkl_2018.2.199.tgz && rm -rf l_mkl_2018.2.199.tgz && \
cd l_mkl_2018.2.199 && \
sed -i -E "s/ACCEPT_EULA=decline/ACCEPT_EULA=accept/g" silent.cfg && \
./install.sh -s silent.cfg
source /opt/intel/compilers_and_libraries_2018.2.199/linux/mkl/bin/mklvars.sh intel64

# Install numpy & scipy with mkl backend
echo "[mkl]" >> $HOME/.numpy-site.cfg
echo "library_dirs = /opt/intel/compilers_and_libraries_2018.2.199/linux/mkl/lib/intel64" >> $HOME/.numpy-site.cfg
echo "include_dirs = /opt/intel/compilers_and_libraries_2018.2.199/linux/mkl/include" >> $HOME/.numpy-site.cfg
echo "mkl_libs = mkl_rt" >> $HOME/.numpy-site.cfg
echo "lapack_libs =" >> $HOME/.numpy-site.cfg
pip install --no-binary :all: numpy
pip install --no-binary :all: scipy

# Set environment variables
echo 'export LANG="en_US.UTF-8"' | tee -a /home/ubuntu/.bashrc
echo 'export LC_CTYPE="en_US.UTF-8"' | tee -a /home/ubuntu/.bashrc
echo 'export LC_ALL="en_US.UTF-8"' | tee -a /home/ubuntu/.bashrc

# Install IntelMPI
apt-get install -y cpio libffi-dev libssl-dev
cd /opt
curl -L -O http://registrationcenter-download.intel.com/akdlm/irc_nas/tec/9278/l_mpi_p_5.1.3.223.tgz
tar zxvf l_mpi_p_5.1.3.223.tgz
rm -rf l_mpi_p_5.1.3.223.tgz
cd l_mpi_p_5.1.3.223
sed -i -e "s/decline/accept/g" silent.cfg
sed -i -e "s/exist_lic/trial_lic/g" silent.cfg
./install.sh --silent silent.cfg
echo 'source /opt/intel/compilers_and_libraries_2016.3.223/linux/mpi/bin64/mpivars.sh' | tee -a /home/ubuntu/.bashrc
exec $SHEEL

pip install -U cryptography
pip install -U azure-cli
