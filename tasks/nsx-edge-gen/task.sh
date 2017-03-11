#!/bin/bash
set -ex


### Setup Python Reqs for nsx edge gen.  Will add this to dockerfile once basic func is set.
pushd nsx-edge-gen

# get Python reqs
apt-get -y update
apt-get -y install python-pip python-dev libffi-dev libssl-dev libxml2-dev libxslt1-dev libjpeg8-dev zlib1g-dev
pip install --upgrade pip
pip install six pynsxv pyquery xmltodict ipcalc click Jinja2 shyaml

# Init config file template
if [[ -e nsx_cloud_config.yml ]]; then rm -rf nsx_cloud_config.yml;fi
./nsx-gen/bin/nsxgen init
yml_file=nsx_cloud_config.yml
yml_template=nsx_cloud_config.template
mv $yml_file $yml_template

# This var holds the new values from concuorse to place in nsx-gen yml
nsx_edge_gen_json=$(echo "{
    \"name\":{},
    \"vcenter\":{
      \"address\": \"$VCENTER_HOST\",
      \"admin_user\": \"$VCENTER_USR\",
      \"admin_passwd\": \"$VCENTER_PWD\",
      \"datacenter\": \"$VCENTER_DATA_CENTER\"
    },
    \"nsx_manager\":{
      \"address\": \"$NSX_EDGE_GEN_NSX_MANAGER_ADDRESS\",
      \"admin_user\": \"$NSX_EDGE_GEN_NSX_MANAGER_ADMIN_USER\",
      \"admin_passwd\": \"$NSX_EDGE_GEN_NSX_MANAGER_ADMIN_PASSWD\",
      \"transport_zone\": \"$NSX_EDGE_GEN_NSX_MANAGER_TRANSPORT_ZONE\"
    },
    \"uplink\":{},
    \"logical_switches\":{},
    \"edge_service_gateways\":{},
    \"properties\":{}
}")

# Gen new yml config file template
function fn_get_json_val {
    my_val=$(echo $nsx_edge_gen_json | jq .$1 2>/dev/null)
    echo $my_val
}

function fn_get_yml_val {
    my_val=$(cat $yml_template | shyaml get-value $1 2>/dev/null)
    echo $my_val
}

function fn_get_yml_type {
    my_val=$(cat $yml_template | shyaml get-type $1)
    echo $my_val
}

function fn_get_yml_sequence_len {
    my_val=$(cat $yml_template | shyaml get-value $1 | grep "^- name:" | wc -l)
    echo $my_val
}

function fn_get_my_val {
  my_new_yml_val=$(fn_get_json_val $1)
  if [[ -z $my_new_yml_val ]] || [[ $my_new_yml_val = "{}" ]] || [[ $my_new_yml_val =~ "null" ]]; then
    my_new_yml_val=$(fn_get_yml_val $1)
  fi
  echo $my_new_yml_val
}

echo "---" > $yml_file
for i in $(echo $nsx_edge_gen_json |  jq -r 'to_entries[] | "\(.key)"'); do
  echo "Pipeline is Generating the $i section of the nsx-edge-gen YML..."
  #json_val_count=$(echo $nsx_edge_gen_json | jq --raw-output .$i[] | wc -l)
  yml_val_count=$(cat $yml_template | shyaml get-value $i | wc -l)

  #get section header set
  new_yml_val=$(fn_get_my_val $i)

  #iterate thru yaml struct children
  if [[ $yml_val_count -eq 0 ]]; then
      echo "$i: $new_yml_val" >> $yml_file
  else
      echo "$i:" >> $yml_file
      if [[ ! $(fn_get_yml_type $i) = "sequence" ]]; then
        for x in $(cat $yml_template | shyaml keys $i); do
          new_yml_val=$(fn_get_my_val $i.$x)
          if [[ ! $(fn_get_yml_type $i.$x) = "sequence" ]]; then
            echo "  $x: $new_yml_val" >> $yml_file
          else
            seq_depth_1=$(fn_get_yml_sequence_len $i.$x)
            echo "  $x:" >> $yml_file
            for (( depth_b=0; depth_b<=${seq_depth_1}-1; depth_b++ )); do
              for y in $(cat $yml_template | shyaml keys $i.$x.$depth_b); do
                new_yml_val_b=$(fn_get_my_val $i.$x.$depth_b.$y)
                if [[ $y = "name" ]]; then
                  echo "  - $y: $new_yml_val_b" >> $yml_file
                else
                  echo "    $y: $new_yml_val_b" >> $yml_file
                fi
              done
            done
          fi
        done
     else
        echo "Is Sequence so will skip till Merlin scripts it"
     fi
  fi
  echo "" >> $yml_file
done

cat $yml_file
### Just a debug exit to keep the container hanging around till we r done testing
exit 1
