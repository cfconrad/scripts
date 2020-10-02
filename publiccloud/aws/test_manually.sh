#!/bin/bash

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

ltp_bin=ltp-20200930.da2f34028-qa.457.1.x86_64.rpm
ssh_key=cfconrad.pem
IP=${IP:-35.163.116.14}
VERSION=SLE-15-SP2
ARCH=x86_64
log_dir=$SCRIPT_DIR/$IP
img_proof_tests=test_sles test_sles_ec2

function run_ssh()
{
  ssh -i $SCRIPT_DIR/$ssh_key ec2-user@$IP -- $@
}

mkdir -p $log_dir

test -e runltp-ng || git clone git@github.com:metan-ucw/runltp-ng.git
#http://download.suse.de/ibs/QA:/Head/SLE-15-SP2/x86_64/

scp -i $SCRIPT_DIR/$ssh_key $SCRIPT_DIR/$ltp_bin ec2-user@$IP:~/

run_ssh sudo zypper  --no-gpg-checks --gpg-auto-import-keys -q  in -y $ltp_bin

run_ssh sudo ec2metadata --api latest --document > $log_dir/instance_metadata.json
run_ssh sudo dmesg > $log_dir/dmesg.txt
run_ssh sudo cat /proc/cpuinfo > $log_dir/cpuinfo.txt
run_ssh sudo uname -a > $log_dir/uname.txt
run_ssh sudo systemd-analyze > $log_dir/systemd_analyze.txt
run_ssh sudo systemd-analyze blame > $log_dir/systemd_analyze_blame.txt
run_ssh sudo cat /etc/os-release > $log_dir/os-release.txt
run_ssh sudo zypper lr -u > $log_dir/zypper_lr_u.txt

### Change name of logdirectory
instanceType="$(cat $log_dir/instance_metadata.json | jq -r '.instanceType')"
. $log_dir/os-release.txt
new_log_dir="$SCRIPT_DIR/${IP}_${instanceType}_${NAME}_${VERSION}"
mv "$log_dir" "$new_log_dir"
log_dir="$new_log_dir"

#### RUN img-proof
docker run --mount type=bind,source=/home/clemix,target=/home/clemix \
    --env AWS_ACCESS_KEY_ID \
    --env AWS_SECRET_ACCESS_KEY \
    --env AWS_SESSION_TOKEN \
    img-proof \
    img-proof --no-color test ec2 --distro sles  \
    --region us-west-2 --no-cleanup --collect-vm-info \
    --results-dir "$log_dir/img-proof/" --ssh-private-key-file "$SCRIPT_DIR/$ssh_key" \
    --running-instance-id "$(cat $log_dir/instance_metadata.json | jq -r '.instanceId')" \
    $img_proof_tests
Testing soft reboot



### RUN LTP
run_ssh sudo dmesg -w > $log_dir/dmesg_ltp.txt &
dmesg_pid=$!

run_ssh sudo CREATE_ENTRIES=1 /opt/ltp/IDcheck.sh

perl -I runltp-ng/ ./runltp-ng/runltp-ng "--logname=$log_dir/syscalls" --run syscalls --exclude 'ltp_16$|^(move_pages|msg(ctl|get|rcv|snd|stress)|sem(ctl|get|op|snd)|shm(at|ctl|dt|get)|syslog|inotify07|inotify08|epoll_wait02|sendto03)' \
    "--backend=ssh:user=ec2-user:key_file=$SCRIPT_DIR/$ssh_key:host=$IP"

perl -I runltp-ng/ ./runltp-ng/runltp-ng "--logname=$log_dir/cve" --run cve \
    --exclude '^(cve-2015-3290|cve-2017-17805|cve-2020-14386)' \
    "--backend=ssh:user=ec2-user:key_file=$SCRIPT_DIR/$ssh_key:host=$IP"
kill $dmesg_pid

