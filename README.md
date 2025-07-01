# 🐎 Pegasus
Pegasus is an orchestration and automation tool designed to simplify large-scale testing of Aerospike. While it can be used independently to deploy Aerospike clusters of any size on AWS, Pegasus also integrates seamlessly with [Aerospike-Perseus](https://github.com/aerospike-community/aerospike-perseus)—a powerful and flexible benchmarking engine. Together, they provide everything needed to launch, monitor, and manage complete test environments with ease. From provisioning clusters and configuring Grafana dashboards to running complex workloads, Pegasus takes care of the heavy lifting so you can focus on insights and results.

Pegasus is named after the winged horse of Greek mythology, born from the blood of Medusa and later ridden by the hero Perseus. In the same spirit, Aerospike-Pegasus gives Perseus the wings to operate at scale. Together, they form a complete testing framework—Perseus provides the benchmark power, while Pegasus enables agility, automation, and cloud-scale orchestration.

# 🚀 Introduction
Pegasus is a command-line tool designed for running Proof of Technology (PoT) workloads with [Aerospike](https://aerospike.com/). It simplifies the process of deploying, configuring, and benchmarking Aerospike clusters at scale. Pegasus leverages [AeroLab](https://github.com/aerospike/aerolab) under its hood.

With Pegasus, you can easily:
- ✅ Launch an Aerospike cluster of any size on AWS
- 📊 Set up Aerospike's monitoring stack
- 💥 Run complex workloads via multiple Perseus clients
- 📈 Scale clusters up or down
- 🛠 Simulate failures by killing nodes

# Pegasus and Perseus
Pegasus and Perseus are legendary figures from Greek mythology. Pegasus, the winged horse born from the blood of Medusa, symbolises speed, freedom, and divine inspiration. Perseus, a heroic demigod and the slayer of Medusa, is renowned for his bravery, precision, and strategy. Their stories are intertwined—Perseus rode Pegasus after defeating Medusa, using the winged steed to complete his heroic quests. Together, they represent a powerful union of bold action and agile movement.

In the Aerospike ecosystem, Perseus is a high-performance benchmarking tool designed to test and validate Aerospike clusters under various workloads. Pegasus, on the other hand, is a wrapper and orchestration layer that automates the deployment of test environments and runs Perseus at scale. Pegasus makes it easy to spin up full test clusters, configure monitoring, run realistic workloads, and tear down the environment when finished. Much like their mythical counterparts, Aerospike-Perseus and Aerospike-Pegasus work in tandem—Perseus delivers the precision and intensity of benchmarking, while Pegasus provides the speed and flexibility to take flight across environments.

## 📦 Prerequisites
Before using Pegasus, make sure the following tools and configurations are set up:

### 1. Install AeroLab
Pegasus relies on AeroLab to manage Aerospike clusters.
➡️ [Download and install AeroLab](https://aerospike.com/download/oandm/aerolab/)

### 2. Configure AWS CLI
To launch clusters on AWS, you’ll need the AWS CLI installed and configured.
➡️ [Follow these instructions](https://github.com/aerospike/aerolab/blob/master/docs/aws-setup.md#using-aws-cli)

### 3. Aerospike Enterprise License
Pegasus assumes access to an Aerospike Enterprise Edition license.

- If you don’t have one, you can request a free 60-day trial here:

    👉 [Try Now](https://aerospike.com/try-now/)

- Once you have your license file, point AeroLab to it:

    👉 [License setup instructions](https://github.com/aerospike/aerolab/blob/master/docs/GETTING_STARTED.md#getting-started-configuration-basics)

## 🛠️ How To Use

The root of the project includes the following folders:

📁 aws        → High-level scripts for setup, teardown, and orchestration  
📁 client     → Generic AeroLab scripts for managing client nodes  
📁 cluster    → Generic AeroLab scripts for managing Aerospike clusters  
📁 grafana    → Generic AeroLab scripts for managing Grafana dashboard  

The client, cluster, and grafana folders contain generic Aerolab scripts. Unless you’re planning to customise something specific, there’s no need to modify these.

The main focus is the aws/ folder, which contains the high-level orchestration scripts. Each file performs a specific action:

- Files starting with `cluster_` perform actions on the Aerospike cluster
- Files starting with `client_` manage the client nodes
- Files starting with `grafana_` handle Grafana monitoring setup
- Additional utility scripts are included and explained in the sections below

## Running a Test at a High-Level
### 1. Configure the environment
Open `aws/configure.sh` and set the specs for your cluster, clients, and workload. This defines the behaviour of your test environment. The contents of this file are explained in the following sections.

### 2. Set up the environment
Run `aws/setup.sh` to:
- Provision the Aerospike cluster
- Deploy client nodes capable of running complex workloads
- Launch a Grafana dashboard for real-time performance monitoring

### 3. Monitor the environment and adjust the workload
Once all components are up and running, you can:

- Monitor the cluster using the Grafana dashboard, which launches automatically. (Username/Password: admin/admin)
- Adjust the workload by editing `thread.yaml` and running `aws/copyThread.sh` to apply the changes.
- Scale the cluster by adding or removing nodes as needed.

### 4. Tear down the environment
Run `aws/destroy.sh` to clean up all resources created for the test.

### 5. Additional Control
If you need finer control, the aws/ folder also includes scripts for individual components. For example:

- Rebuild only the clients
- Tear down just the Grafana dashboard or the clients
- Restart a specific part of the setup without resetting everything

In the following sections, you'll find a detailed breakdown of each script and its purpose.

# How to Configure the Test Environment
As discussed earlier, the overall behaviour of the test environment is controlled through a single file: `aws/configure.sh`. You only need to modify this file to define the cluster size, workload parameters, and other high-level settings.

All other scripts in the aws directory read their configuration from this file. For example, if the environment is already running and you want to update the client configuration, you can simply modify the relevant sections in configure.sh and rerun the client setup—there’s no need to rebuild the entire environment.

Below is an explanation of each configuration field in the file:

## `aws/configure.sh`
### AWS Config
- `AWS_REGION`: Specifies the AWS region where the test environment will be deployed.
- `AWS_EXPIRE`: After the duration specified here has passed, all resources provisioned for the test will be automatically released. You can define the time using seconds, minutes, or hours—for example: 20h 30m. Use 0 to disable auto-expiry.

    ⚠️ Note: Avoid setting this value too short, as your demo could abruptly end mid-presentation. Also, remember to manually tear down the environment once you're finished to avoid unnecessary AWS charges!
### Aerospike Config
- `VER`: Aerospike server version.
- `CLUSTER_NAME`: Name of the Aerospike cluster.
- `CLUSTER_NUMBER_OF_NODES`: Number of Aerospike cluster nodes.
- `CLUSTER_INSTANCE_TYPE`: Instance type of the Aerospike cluster nodes.
### Namespace Config
- `NAMESPACE_NAME`: The name of the namespace that will be configured to use during the test. (Cannot be changed after the cluster is created.)
- `NAMESPACE_DEFAULT_TTL`: Default TTL (time-to-live) for all records inserted into the database. Set to 0 to disable TTL. (Cannot be changed after the cluster is created.)
- `NAMESPACE_COMPRESSION`: Enables selection of the compression algorithm to be used during the test. Available options are: none, lz4, snappy, and zstd.
While this won't provide a representative compression ratio, it allows you to evaluate the overhead introduced by enabling compression.
- `NAMESPACE_PRIMARY_INDEX_STORAGE_TYPE`: Where to store the Primary Index. Choose between MEMORY and DISK. (Cannot be changed after the cluster is created.)
- `NAMESPACE_SECONDARY_INDEX_STORAGE_TYPE`: Where to store the Secondary Index. Choose between MEMORY and DISK. (Cannot be changed after the cluster is created.)
- `NAMESPACE_DATA_STORAGE_TYPE`: Where to store the Data. Choose between MEMORY and DISK. (Cannot be changed after the cluster is created.)

    ⚠️ Note: Data can only be stored in memory if the Primary and the Secondary Index are stored on memory as well.
- `NAMESPACE_REPLICATION_FACTOR`: The replication factor of the namespace.
### NVMe Config 
- `NUMBER_OF_PARTITION_ON_EACH_NVME`: Specifies the number of partitions to create per NVMe device.

    For example, if a machine has 2 NVMe drives and this value is set to 10, each node will have a total of 20 partitions (10 per NVMe).
- `OVERPROVISIONING_PERCENTAGE`: Percentage of overprovisioning required.   

    AWS recommends overprovisioning for some instance types. Overprovisioning might not be necessary for light workloads.
- `PRIMARY_INDEX_STORAGE_PARTITIONS`: This parameter is only relevant if the Primary Index is configured to be stored on disk—otherwise, it can be ignored.

    Use this setting to specify which partitions on each NVMe device should be allocated for Primary Index storage. Be sure that no partition is assigned to more than one purpose to avoid conflicts.

    You can specify partitions using comma-separated values (e.g. 1,2,3,7,8,9) or ranges (e.g. 1-3,7-9).

    Note: Partition numbering starts at 1.
- `PARTITION_TREE_SPRIGS`:This parameter is only relevant if the Primary Index is configured to be stored on disk—otherwise, it can be ignored.

    Use it to specify the number of sprigs. The appropriate value should be calculated based on the guidance provided in the official documentation:

    👉 [Primary index on flash](https://aerospike.com/docs/server/operations/plan/capacity#primary-index-on-flash)
- `SECONDARY_INDEX_STORAGE_PARTITIONS`: This parameter is only relevant if the Secondary Index is configured to be stored on disk—otherwise, it can be ignored.

    Use this setting to specify which partitions on each NVMe device should be allocated for Secondary Index storage. Be sure that no partition is assigned to more than one purpose to avoid conflicts.

    You can specify partitions using comma-separated values (e.g. 1,2,3,7,8,9) or ranges (e.g. 1-3,7-9).

    Note: Partition numbering starts at 1.
- `DATA_STORAGE_PARTITIONS`: This parameter is only relevant if the Data is configured to be stored on disk—otherwise, it can be ignored.

    Use this setting to specify which partitions on each NVMe device should be allocated for Data storage. Be sure that no partition is assigned to more than one purpose to avoid conflicts.

    You can specify partitions using comma-separated values (e.g. 1,2,3,7,8,9) or ranges (e.g. 1-3,7-9).

    Note: Partition numbering starts at 1.
### Grafana Config
- `GRAFANA_NAME`: Name of the Grafana instance.
- `GRAFANA_INSTANCE_TYPE`: Instance type of the Grafana node. (t3.xlarge is good enough)
### Client Instance Config
- `CLIENT_NAME`: Name of the instance running Perseus.
- `CLIENT_INSTANCE_TYPE`: Specifies the instance type for the node running Perseus.

    Perseus requires a good number of vCPUs, high network bandwidth, and a small amount of RAM.

    The C6a and C6i instance families are ideal—they meet all these requirements and are among the most cost-effective options on AWS.
- `CLIENT_NUMBER_OF_NODES`: Number of Perseus nodes. 

    For heavy workloads, running multiple Perseus instances can provide additional resources and network bandwidth.


### Client Generic Workload Config
- `TRUNCATE_SET`: Determines whether existing data in the cluster should be truncated before the test begins.

    This only takes effect if the test environment has been used before and contains records. In a fresh setup, truncation has no effect.

    ⚠️ Note: Truncating large datasets can take time.

- `RECORD_SIZE`: Specifies the average size (in bytes) for each record inserted during the test.

- `BATCH_READ_SIZE`: Number of records per batch in the batch read workload.

⚠️ Note: This must be a non-zero, positive number.

- `BATCH_WRITE_SIZE`: Number of records per batch in the batch write workload.

⚠️ Note: This must also be a non-zero, positive number.

- `READ_HIT_RATIO`: Controls the percentage of read queries expected to return a result.
    
    Perseus caches a portion of inserted keys to simulate realistic read hit rates. This value (between 0.0 and 1.0) defines the ratio of reads that should hit existing records vs. those that return nothing.

    ⚠️ Note: If the delete workload is enabled, actual hit ratios may be lower than configured due to deleted records.

### Client Caching Config
Perseus generates random records and inserts them into the database. This randomness is crucial—it allows the dataset to grow practically without bounds. However, since records are randomly generated, Perseus must cache inserted keys so that subsequent read, update, delete, and search operations target records that actually exist.

⚠️ Note: Perseus instances do not share cache data. Each instance only queries records it has inserted and cached itself. If Perseus is restarted, its cache is lost and must be repopulated before accurate read/delete/update workloads can resume.

To manage memory usage efficiently, Perseus offers two parameters to control caching behaviour:

### Client Query Workload Config
⚠️ Note: If you're not planning to test a specific query workload, it's best to keep it disabled. Secondary Index maintenance adds overhead on every write, update, or delete operation, which may affect overall performance and skew benchmark results.

- `STRING_INDEX`: Enables a workload that runs Secondary Index queries on a bin containing string values. A secondary index of type STRING is created.

    Each query targets a previously inserted item and is expected to return a single record—unless it has been deleted by the delete workload.

- `NUMERIC_INDEX`: Enables a workload that runs Secondary Index queries on a bin containing numeric values. A secondary index of type NUMERIC is created.

    Like STRING_INDEX, queries target known inserted items and typically return a single record—unless deleted.

- `GEO_SPATIAL_INDEX`: Enables a workload that runs Secondary Index queries on a bin containing geospatial values. A GeoSpatial index is created.

    Queries are completely random and may return zero, one, or many results.

- `UDF_AGGREGATION`: Enables a workload that runs range queries using a UDF on numeric data. A secondary index of type NUMERIC is created.

    Query range behaviour is controlled by parameters detailed in the section below.

- `RANGE_QUERY`: Enables a workload that runs range-based Secondary Index queries on numeric values. A secondary index of type NUMERIC is created.

    As with UDF aggregation, the range of values queried is configurable and described in detail below.

### Client Range Query Workload Config
- `NORMAL_RANGE`: This setting can be ignored if neither the Range Query nor UDF Aggregation workloads are enabled.

    Perseus inserts a monotonically increasing number into one of the bins of every record. Querying any value between 0 and the current maximum (let’s call it X) should return exactly one record (assuming the delete workload hasn't removed it). The range query selects a range between X and X + NORMAL_RANGE (this parameter).

- `MAX_RANGE`: Also only relevant if Range Query or UDF Aggregation workloads are enabled.

    Defines the size of a large range, which may occasionally be queried to simulate edge cases or heavier loads.

- `CHANCE_OF_MAX`: Again, only applicable if Range Query or UDF Aggregation workloads are in use.

    Specifies the probability (e.g. as a percentage) that a query will use the MAX_RANGE instead of NORMAL_RANGE.

# Actions
This section outlines the actions you can perform by running each of the scripts in the aws directory.

## 'aws/setup.sh`
Running this single file performs the following tasks, based on the configuration specified in `aws/configure.sh`:
- Allocates instances in the specified AWS region.
- Prepares the instances and deploys an Aerospike cluster on them.
- Creates nodes designated for running Perseus.
- Deploys Perseus on those nodes and configures it to connect to the Aerospike cluster created above.
- Runs Perseus with a minimal workload.
- Open new terminals that tail the result of the perseus instances. (You must have iTerm installed, and run the script there.)
- Creates a node to host Grafana and Prometheus.
- Deploys Grafana and configures it to display Aerospike cluster metrics.
- Opens a browser window pointing to the Grafana dashboard. (Note: The username and password are both ‘admin’.)

This streamlined process sets up the entire environment for testing and monitoring with minimal effort.

## `aws/threads.yaml`
The number of threads each Perseus instance allocates to each workload can be dynamically adjusted while the test is running. To increase throughput, simply increase the number of threads assigned to a workload. To disable a workload, set its thread count to 0.

Modifying this file on your local machine does not automatically update the running environment. You must run aws/copyThreads.sh to upload the updated file to all Perseus nodes.

⚠️ Note: Query workloads must be enabled during cluster creation. If they weren’t enabled at that time, any thread settings for those workloads in this file will be ignored. 

## `aws/copyThreads.sh`
Running this file copies the contents of threads.yaml to all nodes running Perseus. Details about threads.yaml can be found in the documentation of Perseus.
To modify the workload dynamically, simply update threads.yaml and rerun copyThreads.sh.

## `aws/destroy.sh`
Tears down the entire setup, including the Aerospike cluster, Perseus instances, and monitoring instances.

⚠️ Note: Remember to run ```./destroy.sh```  when you don’t need the cluster. Running a large scale test is not cheap. If you don’t need the result, don’t waste money.

## `aws/cluster_setup.sh`
Sets up an Aerospike cluster based on the specifications in `aws/configure.sh`.

## `aws/cluster_destroy.sh`
Destroys the Aerospike cluster named in the `aws/configure.sh` without affecting other components.

## `aws/clusterconnect.sh`
Allows you to connect to a specific Aerospike node by providing an index, useful for diagnostics. The index starts at 1. 

## `aws/cluster_add_node.sh`
Adds a new node to the Aerospike cluster. Once added, Aerospike will automatically start rebalancing the cluster.

## `aws/cluster_stop_node.sh`
Stops the Aerospike process on a specified node, reducing the number of active nodes in the cluster. You need to specify the index number of the node to stop. The index starts at 1. 

## `aws/cluster_restart_node.sh`
Restarts a previously stopped Aerospike node to simulate recovery. Provide the same index number used when stopping the node.

## `aws/client_setup.sh`
Sets up Perseus instances based on the specifications in `aws/configure.sh`.

## `aws/client_destroy.sh`
Destroys the Perseus nodes without affecting other components.

## `aws/client_connect.sh`
Allows you to connect to a specific Perseus node by providing an index, useful for diagnostics. The index starts at 1. 

## `aws/client_rebuild.sh`
Rebuilds the Perseus code across all nodes after changes are made. Before running this file, ensure your changes are pushed to the repository, as Perseus clones the repository before building. After running this file, the updated code is pulled, rebuilt, and restarted on all Perseus machines.

## `aws/client_build_perseus.sh`
Similar to client_rebuild.sh, but it just pull and build Perseus. It does not automatically run Perseus after the build.

## `aws/client_rerun.sh`
Stops the Perseus process and reruns it.

## `aws/grafana_setup.sh`
Configures the Grafana instance. Use this file if the Grafana setup in setup.sh fails for any reason.

## `aws/grafana_destroy.sh`
Tears down the Grafana instance.
