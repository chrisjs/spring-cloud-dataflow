#!/bin/bash

# appProp/task/grafana diffs in server/server-config.yaml

BASE_DIR=$(cd `dirname $0` && pwd)
CONFIG_DIR=$BASE_DIR
CHART_DIR=$BASE_DIR/spring-cloud-data-flow

RELEASE_NAME=tmpscdfrelease
CHART_NAME=spring-cloud-data-flow
CHART_LOCATION=stable/spring-cloud-data-flow

function setup() {
  #SERVICES=(kafka mysql rabbitmq server skipper)

  #for service in ${SERVICES[@]}; do
  #  DIR=$CONFIG_DIR/$service
  #  if [ ! -d $DIR ]; then
  #    mkdir -p $CONFIG_DIR/$service
  #  fi  
  #done

  pushd $BASE_DIR > /dev/null
  helm repo update
  helm fetch --untar --untardir . $CHART_LOCATION
  popd > /dev/null
}

function generate() {
  scdf_gen
  skipper_gen
}

function do_tmpl() {
  CHART_PATH=$1
  IN_TMPL=$2
  OUT_TMPL=$3
  ARGS=$4

  helm template $ARGS -n $RELEASE_NAME $CHART_PATH -x templates/$IN_TMPL > $OUT_TMPL
}

function mysql_gen() {
  TEMPLATE_DIR=$CONFIG_DIR/mysql
  CHART=$CHART_NAME/charts/mysql
  do_tmpl $CHART deployment.yaml $TEMPLATE_DIR/mysql-deployment.yaml
  do_tmpl $CHART pvc.yaml $TEMPLATE_DIR/mysql-pvc.yaml
  do_tmpl $CHART secrets.yaml $TEMPLATE_DIR/mysql-secrets.yaml
  do_tmpl $CHART svc.yaml $TEMPLATE_DIR/mysql-svc.yaml

  sed -i '/^ *$/d' $TEMPLATE_DIR/mysql-deployment.yaml
  sed -i -e 's/mysql-root-password:.*/mysql-root-password: \"eW91cnBhc3N3b3Jk\"/' -e 's/mysql-password:.*/mysql-password: \"eW91cnBhc3N3b3Jk\"/' -e '/^ *$/d' $TEMPLATE_DIR/mysql-secrets.yaml
  sed -i -e '/\s\sannotations: *$/d' -e '/type: ClusterIP/d' $TEMPLATE_DIR/mysql-svc.yaml
}

function rabbitmq_gen() {
  TEMPLATE_DIR=$CONFIG_DIR/rabbitmq
  CHART=$CHART_NAME/charts/rabbitmq
  do_tmpl $CHART deployment.yaml $TEMPLATE_DIR/rabbitmq-deployment.yaml
  do_tmpl $CHART svc.yaml $TEMPLATE_DIR/rabbitmq-svc.yaml
  do_tmpl $CHART secrets.yaml $TEMPLATE_DIR/rabbitmq-secrets.yaml
  do_tmpl $CHART pvc.yaml $TEMPLATE_DIR/rabbitmq-pvc.yaml

  #sed -i -e '/type: ClusterIP/d' $TEMPLATE_DIR/rabbitmq-svc.yaml
  sed -i -e 's/rabbitmq-password:.*/rabbitmq-password: \"eW91cnBhc3N3b3Jk\"/' -e 's/rabbitmq-erlang-cookie:.*/rabbitmq-erlang-cookie: \"dlVsd2dlUlozaWVnWW45b1pBMHZWQjhtY05RbENQT0c=\"/' $TEMPLATE_DIR/rabbitmq-secrets.yaml
}

function kafka_gen() {
  TEMPLATE_DIR=$CONFIG_DIR/kafka
  CHART=$CHART_NAME/charts/kafka
  do_tmpl $CHART service-brokers.yaml $TEMPLATE_DIR/kafka-svc.yaml
  do_tmpl $CHART statefulset.yaml $TEMPLATE_DIR/kafka-deployment.yaml

  sed -i -e 's/serviceName:.*kafka-headless/serviceName: kafka-zk/' -e 's/zookeeper:2181/kafka-zk:2181/' -e 's/name:.*kafka$/name: kafka-broker/' \
	  -e 's/-.*name:.*kafka-broker$/- name: kafka/' -e '/\s\sannotations: *$/d' $TEMPLATE_DIR/kafka-deployment.yaml

  sed -i -e 's/name:.*broker/name: kafka-port/' -e 's/targetPort:.*kafka/targetPort: 9092/' $TEMPLATE_DIR/kafka-svc.yaml
}

function zookeeper_gen() {
  TEMPLATE_DIR=$CONFIG_DIR/kafka
  CHART=$CHART_NAME/charts/kafka/charts/zookeeper
  do_tmpl $CHART service-headless.yaml $TEMPLATE_DIR/kafka-zk-svc.yaml
  do_tmpl $CHART statefulset.yaml $TEMPLATE_DIR/kafka-zk-deployment.yaml

  sed -i -e 's/name:.*zookeeper/name: kafka-zk/' \
  	  -e 's/app:.*zookeeper/app: kafka-zk/' \
  	  -e 's/app:.*kafka-zk/app: kafka/' \
	  -e '0,/app:.*kafka/s/app:.*kafka\-zk/app: kafka/' \
  	  -e 's/serviceName:.*zookeeper-headless/serviceName: kafka/' \
	  -e '/\s\sannotations: *$/d' $TEMPLATE_DIR/kafka-zk-deployment.yaml

  sed -i -e 's/name:.*zookeeper-headless/name: kafka-zk/' \
	  -e '0,/app:*zookeeper/s/app:.*zookeeper/app: kafka/' \
	  -e '/targetPort.*/d' -e 's/server/follower/' -e 's/election/leader/' \
	  -e '0,/app:.*kafka/s/app:.*kafka/app: kafka-zk-tmp/' -e '/clusterIP: None/d' \
	  -e 's/app:.*kafka$/app: kafka-zk/' -e 's/app:.*kafka-zk-tmp/app: kafka/' $TEMPLATE_DIR/kafka-zk-svc.yaml
}

function scdf_gen() {
  TEMPLATE_DIR=$CONFIG_DIR/server
  CHART=$CHART_NAME
  do_tmpl $CHART server-config.yaml $TEMPLATE_DIR/server-config.yaml
  do_tmpl $CHART server-deployment.yaml $TEMPLATE_DIR/server-deployment.yaml
  do_tmpl $CHART server-rbac.yaml $TEMPLATE_DIR/server-rbac.yaml
  do_tmpl $CHART server-service.yaml $TEMPLATE_DIR/server-svc.yaml

  pushd $TEMPLATE_DIR > /dev/null
  awk '{print $0 > "tmprb" NR}' RS='---' server-rbac.yaml
  sed '1d' tmprb2 > server-roles.yaml
  sed '1d' tmprb3 > server-rolebinding.yaml
  rm tmprb*
  rm server-rbac.yaml
  popd > /dev/null

  sed -i -e 's/name:.*data-flow-server/name: scdf-server/g' -e 's/app:.*spring-cloud-data-flow/app: scdf-server/g' \
      -e '/component:/d' -e '/cpu:.*500m/d' -e 's/\/dataflow/\/mysql/' $TEMPLATE_DIR/server-config.yaml

  sed -i -e 's/name:.*data-flow-server/name: scdf-server/g' -e 's/app:.*spring-cloud-data-flow/app: scdf-server/g' \
      -e '/component:/d' -e 's/IfNotPresent/Always/' -e 's/8080/80/' -e 's/\/dataflow/\/mysql/' \
	  -e 's/image:.*springcloud\/spring-cloud-dataflow-server:.*/image: springcloud\/spring-cloud-dataflow-server:latest/' \
	  -e 's/value:.*data-flow-server/value: scdf-server/' -e 's/DATA_FLOW_SERVER_/SCDF_SERVER_/g' \
      -e 's/\${DATA_FLOW_SKIPPER_SERVICE_HOST}/\${SKIPPER_SERVICE_HOST}:\${SKIPPER_SERVICE_PORT}/'  $TEMPLATE_DIR/server-deployment.yaml
}

function skipper_gen() {
  TEMPLATE_DIR=$CONFIG_DIR/skipper
  CHART=$CHART_NAME
  do_tmpl $CHART skipper-config.yaml $TEMPLATE_DIR/skipper-config-rabbit.yaml
  do_tmpl $CHART skipper-deployment.yaml $TEMPLATE_DIR/skipper-deployment.yaml
  do_tmpl $CHART skipper-service.yaml $TEMPLATE_DIR/skipper-svc.yaml
  do_tmpl $CHART skipper-config.yaml $TEMPLATE_DIR/skipper-config-kafka.yaml "--set rabbitmq.enabled=false,kafka.enabled=true"
}

function cleanup() {
  for filename in $(find $CONFIG_DIR -name *.yaml); do
      sed -i -e '/chart:/d' -e '/release:/d' -e '/heritage:/d' -e '/# Source:/d' -e s/tmpscdfrelease-//g \
		  -e s/^---$// -e '/./,/^$/!d' -e s/TMPSCDFRELEASE_//g $filename
  done

  rm -rf $CHART_DIR
}

setup
generate
cleanup

