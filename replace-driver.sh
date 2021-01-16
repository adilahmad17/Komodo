#!/bin/bash -e

if [ $# != 3 ];
then
  echo "Usage: sudo ./replace-driver.sh <offset> <image> <dst>"
  exit
fi

umount $3 || true
mount -t auto -o loop,offset=$(($1*512)) $2 $3
make -C driver
cp driver/komodo.ko $3/lib/modules/