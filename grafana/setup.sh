echo "Adding Grafana"
aerolab client create ams -n ${GRAFANA_NAME} -s ${CLUSTER_NAME} --instance-type ${GRAFANA_INSTANCE_TYPE} --ebs=40 --aws-expire=${AWS_EXPIRE} || exit 1

grafana=$(aerolab client  list -j | jq -c '.[] | select(.ClientName == '\"${GRAFANA_NAME}\"') | .AccessUrl')

open ${grafana}
