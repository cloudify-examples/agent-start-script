## agent-start-script
A script that can be used to start an agent for nodes running in "provided" agent mode

### Overview

Blueprints can designate compute nodes agent configuration in a few ways, one being setting the install-method property to `provided`.  When the install workflow sees that an agent is a `provided` agent, rather than install the agent, it waits for the agent to connect, assuming it will be started by some other process.  This script provides the means to download and start the agent.

### Parameters

* `--manager-ip` The IP address of the cloudify manager.  This is used to connect to RabbitMQ

* `--node-instance-id` This is the id assigned by Cloudify when the corresponding blueprint's "install" workflow is run.

* `--deployment-id` This is the deployment id that the node is part of.  This is assigned by whoever (or whatever) creates a deployment (e.g. cfy deployments create -d <deployment_id>).  This will also be passed by the plugin.

* `--daemon-user` This is the user you want the agent installed as and run as.  Defaults to 'root'.

* `--fileserver-url`  I added this one because I anticipated you'd want to store agent packages somewhere other than the manager. If you set this, it will be used to get the agent packages.  It defaults to using the manager.


Note that the script also has many environment variables for finer grained tuning.  Of particular note is `PACKAGE_URL`, which will override the standard manager path for agent packages.

Example run from the command line:  sudo ./start-agent.sh --manager-ip=172.16.0.3 --node-instance-id=host_6ddf4 --deployment-id=my_deployment --daemon-user=centos
