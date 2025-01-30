#!/bin/bash
while true; do
    oci compute instance launch \
        --availability-domain "AD-1" \
        --compartment-id "ocid1.tenancy.oc1..aaaaaaaas3eczgc6mvdonhbbyny7dbzxehbzrpe4ejyzdvbo7vjl467kkgpa" \
        --display-name "sanjose-arm" \
        --shape "VM.Standard.A1.Flex" \
        --shape-config '{"ocpus": 4, "memoryInGBs": 24}' \
        --subnet-id "ocid1.subnet.oc1.us-sanjose-1.aaaaaaaaachecb32q7nxiyl4y3jhhez7noasfrlr7ozhdoj4a3kmtehesokq" \
        --image-id "ocid1.image.oc1.us-sanjose-1.aaaaaaaa5tnuiqevhoyfnaa5pqeiwjv6w5vf6w4q2hpj3atyvu3yd6rhlhyq" \
        --assign-public-ip true \
        && break
    echo "资源不足，等待 5 分钟后重试..."
    sleep 300
done