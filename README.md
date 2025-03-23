- [Prerequisites](#prerequisites)
- [Deploying](#deploying)
  - [Deploying a Rama Cluster and Modules](#deploying-a-rama-cluster-and-modules)
- [Cluster Configuration and Debugging](#cluster-configuration-and-debugging)
  - [systemd and journalctl](#systemd-and-journalctl)
  - [file system layout](#file-system-layout)
- [Azure Configuration](#azure-configuration)
  - [Virtual Machine Image](#virtual-machine-image)
  - [Networking](#networking)
    - [Security Group](#security-group)
    - [Subnet](#subnet)
- [Terraform Configuration](#terraform-configuration)
  - [username](#username)
  - [security\_group\_ids](#vpc_security_group_ids)
  - [rama\_source\_path](#rama_source_path)
  - [license\_source\_path](#license_source_path)
  - [zookeeper\_url](#zookeeper_url)
  - [conductor\_vm\_image](#conductor_vm_image)
  - [supervisor\_vm\_image](#supervisor_vm_image)
  - [zookeeper\_vm\_image](#zookeeper_vm_image)
  - [conductor\_size](#conductor_size)
  - [supervisor\_size](#supervisor_size)
  - [zookeeper\_size](#zookeeper_size)
  - [supervisor\_num\_nodes](#supervisor_num_nodes)
  - [zookeeper\_num\_nodes](#zookeeper_num_nodes)
  - [supervisor\_volume\_size\_gb](#supervisor_volume_size_gb)
  - [private\_ssh\_key](#private_ssh_key)

## Prerequisites

Terraform and the Azure CLI must be installed, and you must be signed in to the
Azure CLI. (you can do this via `az login`)

`~/.rama/` must be added to your PATH.

In addition to authenticating with the Azure CLI, you must setup a keypair to
connect to the deployed instances with. Make sure to add the private key to
your SSH identities with `ssh-add path/to/private/key`

For the public key, create a file `~/.rama/auth.tfvars` with the following
content:

```
azure_public_key = "/path/to/corresponding/public/key"
```

You can download a Rama release [from our website](https://redplanetlabs.com/download).

## Deploying

### Deploying a Rama Cluster and Modules

To deploy a rama cluster:

1. Make sure you have your zip file of Rama.
2. Create `rama.tfvars` at the root of your project to set Terraform variables.
   These govern e.g. the number of supervisors to deploy.
   See `rama.tfvars.example`. There are several variables that are
   required to set.
3. Run `bin/rama-cluster.sh deploy <cluster-name> [opt-args]`.
   `opt-args` are passed to `terraform apply`.
   For example, if you wanted to just deploy zookeeper servers, you would run
   `bin/rama-cluster.sh deploy my-cluster -target=aws_instance.zookeeper`.

To run modules, use `rama-<cluster-name> deploy ...`. `rama-<cluster-name>` is a
symlink to a `rama` script that is configured to point to the launched cluster.

To destroy a cluster run `bin/rama-cluster.sh destroy <cluster-name>`.

## Cluster Information and Debugging

### systemd and journalctl

All deployed processes (zookeeper, conductor rama, supervisor rama) are managed
using systemd. systemd is used to start the processes and restart them if they
exit. Some useful snippets include (substitute `conductor` or `supervisor` for
`zookeeper`):

``` sh
sudo systemctl status zookeeper.service # check if service is running
sudo systemctl start zookeeper.service
sudo systemctl stop zookeeper.service
```

systemd uses journald for logging. Our processes configure their own logging,
but logs related to starting and stopping will be captured by journald. To read
logs:

``` sh
journalctl -u zookeeper.service    # view all logs
journalctl -u zookeeper.service -f # follow logs
```

An application's systemd config file is located at

``` sh
/etc/systemd/system/zookeeper.service
```

### file system layout

Each cluster node has one main application process; zookeeper nodes run
zookeeper, conductor nodes run a rama conductor, supervisor nodes run a rama
supervisor.

The relevant directories to look at are the `$HOME` directory, as well as
`/data/rama`.

## Azure Configuration

### Virtual Machine Image

Zookeeper and Rama nodes all require Java to be present on the system to run.
Rama supports LTS versions of Java - 8, 11, 17 and 21. One of these needs to
be installed on the image.

In addition, while setting up the nodes, `unzip` and `curl` are used and must
also be present on the image.

### Networking

Two networking inputs are required for this terraform config: a network
security group ID, and a subnet ID. As such, both of these will be required to
configure in the Azure portal.

All nodes created will get assigned to the provided network security group and
subnet.

#### Subnet

When configuring your subnet, make sure that the address space is large enough
to support all of the nodes you want to deploy.

#### Security group

When configuring the network security group, it is recommended for simplicity
that all traffic to any port is permitted within the network. However, the
minimum requirements are:
- Port 8888 is available on the conductor node to serve the API and UI dashboard
- Port 1972 is available on the conductor for Thrift
- Port 2181 is available for Zookeeper nodes
- Supervisors have a configured port range in rama.yaml.
  This full range needs to be available for supervisors.

In addition to those all being required internally for Rama to be operational,
it's also required that port 22 is available on all nodes during the terraform
configuration. This is required for provisioning the nodes. If you have a VPN
or Azure Bastion set up, this can be disabled after deployment of the cluster.

#### Public IPs

Terraform will provision a public IP address for each node in the cluster. In
addition to the above, make sure that your Azure subscription permits enough
public IPs for your cluster.

NOTE: while this configuration doesn't support it, you can potentially remove
this requirement by having a VPN configured or using Azure Bastion.

## Terraform configuration

### location
- type: `string`
- required: `true`

The Azure region to deploy the cluster to. (ex. eastus, eastasia)

### username
- type: `string`
- required: `true`

The login username to use for the nodes. Needed to know how to SSH into them and
know where the home directory should be located.

### rama_source_path
- type: `string`
- required: `true`

An absolute path pointing to the location on the local disk of your `rama.zip`.

### license_source_path
- type: `string`
- required: `false`

An absolute path pointing to the location on the local disk of your Rama license file.

### zookeeper_url
- type: `string`
- required: `true`

The URL to download a zookeeper tar ball from to install on the zookeeper node(s).

NOTE: the url in the example tfvars is likely to break whenever zookeeper has a
version upgrade. If the URL there isn't working for you, check what's available
from the Zookeeper CDN at https://dlcdn.apache.org/zookeeper/

### security_group_id
- type: `string`
- required: `true`

The network security group that the nodes are a member of.

### subnet_id
- type: `string`
- required: `true`

The subnet that nodes in this cluster will belong to.

NOTE: This information isn't available in the Azure portal. To access, you
can run the command:
```bash
az network vnet subnet list \
   --resource-group <resource-group> \
   --vnet-name <virtual-network-name>
```
The subnet ID will be available in the output.

### conductor_vm_image
- type: `string`
- required: `true`

The ID for the VM image that the conductor node should use.

### supervisor_vm_image
- type: `string`
- required: `true`

The ID for the VM image that the supervisor node(s) should use.

### zookeeper_vm_image
- type: `string`
- required: `true`

The ID for the VM image that the zookeeper node(s) should use.

### conductor_size
- type: `string`
- required: `true`

The size of the VM that the conductor should use.

Ex. Standard_B1s

### supervisor_size
- type: `string`
- required: `true`

The size of the VM that the supervisor node(s) should use.

Ex. Standard_B1s

### zookeeper_size
- type: `string`
- required: `true`

The size of the VM that the zookeeper node(s) should use.

Ex. Standard_B1s

### supervisor_num_nodes
- type: `number`
- required: `true`

The number of supervisor nodes you want to run.

### zookeeper_num_nodes
- type: `number`
- required: `false`
- default: `1`

The number of zookeeper nodes you want to run.

Note: Zookpeeer recommends setting this to an odd number

### supervisor_volume_size_gb
- type: `number`
- required: `false`
- default: `100`

The size of the supervisors' disks on the nodes.

### private_ssh_key
- type: `string`
- required: `false`
- default: `null`
