#!/bin/bash
echo -e "Checking Docker containers..."

container_ids=$(docker ps | awk {print'$1'} | grep -v "CONTAINER")
for container_id in $container_ids; do
    if [ ! "$(docker ps --filter 'status=running' | grep $container_id)" ]; then
        echo "Restarting container $container_id..."
        name=$(docker ps --filter "id=$container_id" | grep -v "NAMES" | rev | cut -d ' ' -f 1 | rev )
        if [ "$name" -eq "cocalc" ]; then
            docker rm $container_id
            docker run --restart=always -d --name=cocalc -v /data:/data -v /scratch/cocalc:/projects -p 443:443 --mount type=bind,source=/etc/pip.conf,target=/etc/pip.conf --mount type=bind,source=/etc/R/Rprofile.site,target=/etc/R/Rprofile.site sagemathinc/cocalc
        elif [ "$name" -eq "wandb" ]; then
            docker rm $container_id
            docker run --restart=always -d --name=wandb -v /data:/data  -v /scratch/wandb:/vol -p 8080:8080 wandb/local
        else
            echo "Unknown container '$name' with ID '$container_id'"
        fi
    fi
done
