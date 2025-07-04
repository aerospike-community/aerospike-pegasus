echo "Uploading Perseus Configuration"
aerolab files upload -c -n ${CLIENT_NAME} $PREFIX"/../client/templates/perseus.sh" /root/perseus.sh || exit 1

nip=$(aerolab cluster list -i |grep -A7 ${CLUSTER_NAME} | head -1 | grep -E -o 'int_ip=.{0,15}' | egrep -o '([0-9]{1,3}\.){3}[0-9]{1,3}' )

for (( i=1; i  <= ${CLIENT_NUMBER_OF_NODES}; i++ ))
  do
    Perseus_Conf=$PREFIX"/../client/templates/perseus_configuration_template.yaml"
    sed "s/_NAMESPACE_NAME_/${NAMESPACE_NAME}/g" ${Perseus_Conf} | \
    sed "s/_IP_/${nip}/g" | \
    sed "s/_STRING_INDEX_/${STRING_INDEX}/g" | \
    sed "s/_NUMERIC_INDEX_/${NUMERIC_INDEX}/g"| \
    sed "s/_GEO_SPATIAL_INDEX_/${GEO_SPATIAL_INDEX}/g" | \
    sed "s/_UDF_AFFREGATION_/${UDF_AFFREGATION}/g" | \
    sed "s/_RANGE_QUERY_/${RANGE_QUERY}/g" | \
    sed "s/_NORMAL_RANGE_/${NORMAL_RANGE}/g" | \
    sed "s/_MAX_RANGE_/${MAX_RANGE}/g" | \
    sed "s/_CHANCE_OF_MAX_/${CHANCE_OF_MAX}/g" | \
    sed "s/_RECORD_SIZE_/${RECORD_SIZE}/g" |  \
    sed "s/_BATCH_READ_SIZE_/${BATCH_READ_SIZE}/g" | \
    sed "s/_BATCH_WRITE_SIZE_/${BATCH_WRITE_SIZE}/g" | \
    sed "s/_TRUNCATE_SET_/${TRUNCATE_SET}/g" | \
    sed "s/_PERSEUS_ID_/$(expr $i - 1)/g" | \
    sed "s/_READ_HIT_RATIO_/${READ_HIT_RATIO}/g" > configuration.yaml

    aerolab files upload -c -n ${CLIENT_NAME} --nodes=${i} configuration.yaml /root/configuration.yaml || exit 1
    rm -rf configuration.yaml
  done

echo "Running Perseus"
aerolab client attach -n ${CLIENT_NAME} -l all --detach --parallel -- bash /root/perseus.sh

sleep 5

for (( i=1; i  <= ${CLIENT_NUMBER_OF_NODES}; i++ ))
  do
    echo ". "$PREFIX"/configure.sh\naerolab client attach -n "${CLIENT_NAME}" -l "${i}" -- tail -f out.log" > "term"${i}".sh"
    chmod 744 "term"${i}".sh"
    open -a iTerm "term"${i}".sh"
    sleep 3
    rm -f "term"${i}".sh"
  done
