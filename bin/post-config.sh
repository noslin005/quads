#!/bin/bash 
if [ ! -e $(dirname $0)/load-config.sh ]; then
    echo "$(basename $0): could not find load-config.sh"
    exit 1
fi
source $(dirname $0)/load-config.sh
quads=${quads["install_dir"]}/bin/quads.py
openstack_installer=${quads["install_dir"]}/bin/openstack.py
install_dir=${quads["install_dir"]}
bin_dir=${quads["install_dir"]}/bin
data_dir=${quads["data_dir"]}
infrared_dir=${quads["infrared_directory"]}
ssh_priv_key=${quads["private_key_location"]}
json_web_path=${quads["json_web_path"]}
openstack_templates_dir=${quads["openstack_templates"]}
openstack_templates_git=https://github.com/smalleni/automated-openstack-templates.git
function finish {
  rm $data_dir/postconfig/${env}-${owner}-${ticket}-${1}-start
}
trap finish EXIT

apply_post_config() {
   setup_infrared
   pushd $infrared_dir/infrared
   source .venv/bin/activate
   delete_workspace $1
   create_workspace $1
   undercloud=$($quads --cloud-only $1 | head -1)
   setup_inventory $1 $undercloud
   version=$($openstack_installer -c $1 -q | head -1)
   build=$($openstack_installer -c $1 -q | tail -1)
   # TODO(sai): add clean_nodes option
   IR_WORKSPACE=$1 ir tripleo-undercloud --version 11 --build GA --config-options DEFAULT.local_interface=em2
   $openstack_installer -c $1 -i $2 -t $3 -uc $undercloud
   # wait for the openstack install script to write out appropriate
   # instakcenv.json and for it to be available 
   sleep 300
   IR_WORKSPACE=$1 ir tripleo-undercloud --images-task rpm
   # introspect
   IR_WORKSPACE=$1 ir tripleo-overcloud --introspect yes --tag yes --version $version --instackenv-file $2 --deployment-files $3
   # deploy
   IR_WORKSPACE=$1 ir tripleo-overcloud --introspect yes --tag yes --deploy yes --version $version --instackenv-file $2 --deployment-files $3
}





delete_workspace() {
    workspace=$(ir wokspace list | grep -q $1)
    if [  "$workspace" != "" ]
    then
        if [ ! -d $infrared_dir/backup ]; then
           mkdir $infrared_dir/backup
        fi
    infrared workspace export $1 --dest $infrared_dir/backup/$1-$(date +"%s")
    infrared workspace cleanup $1
    fi
}


create_workspace() {
    infrared workspace create $1
}


setup_inventory() {
    cat <<EOF > $infrared_dir/infrared/.workspaces/$1/hosts
$2 ansible_ssh_host=$2 ansible_ssh_user=root ansible_ssh_private_key_file=$ssh_priv_key
localhost ansible_connection=local ansible_python_interpreter=python

[undercloud]
$2

[local]
localhost


# Pass "openstack" as first argument to this script

setup_infrared() {
    if [ ! -d $infrared_dir/infrared ]; then
        git clone https://github.com/redhat-openstack/infrared.git $infrared_dir
        pushd $infrared_dir/infrared
        virtualenv .venv && source .venv/bin/activate
        pip install --upgrade pip
        pip install --upgrade setuptools
        pip install .
        popd
    fi

}

if [ ! -d ${data_dir}/postconfig ]; then
    mkdir ${data_dir}/postconfig
fi


for env in $($quads --summary --post-config $1 ; do
    owner=$($quads --ls-owner --cloud-only $env)
    ticket=$($quads --ls-ticket --cloud-only $env)
    if [ "$owner" != "nobody" -a "$owner" -a "$ticket" ]; then
        if [ -f $data_dir/release/${env}-${owner}-${ticket} ]; then
            if [ -f $data_dir/postconfig/${env}-${owner}-${ticket}-${1}-start ] && [ ! -f {env}-${owner}-${ticket}-${1}-success ]; then
                touch $data_dir/postconfig/${env}-${owner}-${ticket}-${1}-start
                # Clone OpenStack Templates
                cloud_specific_templates=${openstack_templates_dir}/${env}-${owner}-${ticket}
                if [ ! -d $cloud_specific_templates ]; then
                    mkdir $cloud_specific_templates
                fi
                git clone  https://github.com/smalleni/automated-openstack-templates  $cloud_specific_templates
                apply_post_config $env $json_web_path/${env}_instackenv.json $cloud_specific_templates/automated-openstack-templates
            fi
        fi
    fi
done
