Title: Configure AWS VPC peering | Aerospike Documentation

Description: A step-by-step guide for creating a secure and private VPC Peering connection between an AWS VPC and an Aerospike Cloud Database's VPC   

Skip to content

Aerospike Cloud/Manage/Configure VPC peering

Aerospike Cloud is currently offered as a Preview (see Aerospike product stage definitions).

On this page

On this page

*   Prerequisites
*   Configure VPC peering
*   VPC peering status definitions
*   Troubleshooting
*   Conclusion

Configure AWS VPC peering
=========================

With VPC peering, your app running in an AWS VPC (consumer) can communicate privately with an Aerospike Cloud Database running in our AWS VPC (producer) without traversing the public internet. VPC peering reduces latency and exposure, ensuring a more secure connection for your applications.

Prerequisites
-------------

*   The **AWS CLI** is installed and configured.

*   An existing AWS VPC with an IPv4 CIDR block that does **not** overlap with Aerospike Cloud CIDR blocks:

*   The CIDR block you selected when provisioning your cluster: `10.128.0.0/19` by default

*   The CIDR block used for internal services in Aerospike Cloud: `10.129.0.0/24`

*   Basic familiarity with AWS VPC peering.

*   **DNS hostnames** and **DNS resolution** are enabled in your VPC attributes.

Tip

Be ready to provide your **VPC ID**, **VPC CIDR**, **AWS Account ID**, and **Region**. Aerospike Cloud provides the details needed for the Aerospike side of the connection.

Configure VPC peering
---------------------

1.  **Create or identify your AWS VPC**

*   Create a new VPC in AWS or verify your existing VPC, ensuring that the CIDR block does not overlap with the Aerospike Cloud CIDR blocks listed above.
*   Take note of your VPC:
*   **VPC ID** (for example, `vpc-0abcd1234efgh5678`)
*   **CIDR Block** (for example, `10.0.0.0/16`)
*   **AWS Account ID** (for example, `123456789012`)
*   **AWS Region** (for example, `us-east-1`)
2.  **Initiate VPC peering**

*   Console
*   API

In the Aerospike Cloud Console:

1.  Navigate to your project and find the **Networking** or **VPC Peering** section for your database.
2.  Click **Create VPC Peering**.
3.  Fill in the details of your AWS VPC:
*   **AWS Account ID**: The 12-digit ID of your AWS account where your VPC resides.
*   **AWS Region**: The AWS region of the consumer VPC.
*   **VPC ID**: The identifier of your VPC (for example, `vpc-0abcd1234efgh5678`).
*   **VPC CIDR**: Your VPC’s IPv4 CIDR block (for example, `10.0.0.0/16`).
4.  Submit the peering request.

1.  Create a VPC peering request:

Terminal window

```
curl -X POST "https://api.aerospike.cloud/v2/databases/{databaseId}/vpc-peering" \  -H "Authorization: Bearer <YOUR_TOKEN>" \  -H "Content-Type: application/json" \  -d '{    "vpcId": <YOUR_VPC_ID>,    "cidrBlock": <YOUR_CIDR_BLOCK>,    "accountId": <YOUR_AWS_ACCOUNT_ID>,    "region": <YOUR_AWS_REGION>  }'
```

2.  Check the peering status:

Terminal window

```
curl -X GET "https://api.aerospike.cloud/v2/databases/{databaseId}/vpc-peering" \  -H "Authorization: Bearer <YOUR_TOKEN>"
```

The response will be similar to this output. Note the status of “initiating-request”.

```
{  "accountId": "123456789012",  "vpcId": "vpc-0abcd1234efgh5678",  "region": "us-east-1",  "status": "initiating-request",  "peeringId": "pcx-1410263943e464f4a",  "cidrBlock": "10.0.0.0/16",  "zoneId": "Z04089311NGVVH0FO3QGG"}
```

What Happens Next?

Aerospike Cloud creates a peering connection request. The connection status reads **Pending Acceptance** until you accept it in your AWS account.

3.  **Accept the peering request**

Since Aerospike Cloud initiated the peering request, you must accept it from the consumer VPC.

*   AWS Console
*   AWS CLI

In the AWS console:

*   Navigate to **VPC → Peering Connections**
*   Select the pending peering connection containing your peering connection ID
*   Select **Actions → Accept Request**.

Accept the peering connection:

Terminal window

```
aws ec2 accept-vpc-peering-connection \  --vpc-peering-connection-id <YOUR_VPC_PEERING_CONNECTION_ID> \  --region <YOUR_AWS_REGION>
```

4.  **Update route tables**

To route traffic from your app (consumer) VPC to the Aerospike Cloud Database VPC, you must add route table entries in the consumer VPC route tables.

You need to locate the route tables for each subnet that requires Aerospike access and add a route table entry to each one.

Each route table entry should include the following:

*   Destination: The Aerospike Cloud Database’s CIDR block, `10.128.0.0/19` by default
*   Target: The VPC peering connection, for example `pcx-1410263943e464f4a`

*   AWS Console
*   AWS CLI

*   In **VPC → Route Tables**, locate the route tables for subnets that require Aerospike access.
*   **Add a route** to each required route table with:
*   Destination: The Aerospike Cloud Database’s CIDR block, `10.128.0.0/19` by default
*   Target: The VPC peering connection, for example `pcx-1410263943e464f4a`

Create the route table entry:

Terminal window

```
aws ec2 create-route \  --region <YOUR_AWS_REGION> \  --route-table-id <YOUR_ROUTE_TABLE_ID> \  --destination-cidr-block <AEROSPIKE_DATABASE_CIDR_BLOCK> \  --vpc-peering-connection-id <YOUR_VPC_PEERING_CONNECTION_ID>
```

5.  **Associate Private Hosted Zone (DNS)**

Mandatory Step

DNS association is required to resolve Aerospike database endpoints. Ensure `enableDnsSupport` and `enableDnsHostnames` are set to `true` in your VPC settings. These settings appear as `DNS hostnames` and `DNS resolution` in the AWS VPC Console.

1.  After the peering connection is accepted, get the Hosted Zone ID associated with your Aerospike Cloud Database.

*   Console
*   API

The Zone ID, for example `Z04089311NGVVH0FO3QGG`, is available in the Networking tab of your Aerospike Cloud Database, within the VPC Peering details.

Get the Hosted Zone ID using the VPC peering information endpoint:

Terminal window

```
curl -X GET "https://api.aerospike.cloud/v2/databases/{databaseId}/vpc-peering" \  -H "Authorization: Bearer <YOUR_TOKEN>"
```

The response includes the `zoneId` field, for example:

```
{  "zoneId": "Z04089311NGVVH0FO3QGG",  ...}
```

2.  Associate your VPC with Aerospike’s private hosted zone.

Note

You can only perform this action with the AWS CLI, as the hosted zone is owned by an Aerospike Cloud AWS Account.

Terminal window

```
aws route53 associate-vpc-with-hosted-zone \  --hosted-zone-id <HOSTED_ZONE_ID> \  --vpc VPCRegion=<YOUR_AWS_REGION>,VPCId=<YOUR_VPC_ID>
```

3.  After a few minutes, DNS queries in your VPC, for example `fcd8461a-49ee-42ea-ae08-7366a94e7654.aerospike.internal`, will resolve to Aerospike’s private IP addresses.

6.  **Configure security groups**

Follow these guidelines for configuring security groups in your VPC:

*   **Outbound Rules**
*   Allow outbound traffic on the following ports to Aerospike Cloud Database’s CIDR block, `10.128.0.0/19` by default
*   TCP port 4000 to the Aerospike port
*   (Optional) TCP port 9145 to the Aerospike Prometheus Exporter metrics port.
*   (Optional) TCP Port 3000 For insecure (non-tls) connections. Insecure connections must be enabled on your Aerospike Cloud database first.
*   **Inbound Rules**
*   Do not add an inbound rule that explicitly allows traffic from the Aerospike VPC block. Since security groups are stateful, if an instance in your VPC initiates a connection to the Aerospike VPC, the return traffic is automatically allowed back in.

Note

The Aerospike Cloud VPC is automatically configured to allow inbound traffic from peered VPCs and has outbound rules configured to ensure proper return traffic to your VPC.

7.  **Test connectivity**

The Database hostname or TLS name can be found in the Aerospike Cloud Console. It should include the database ID, for example `fcd8461a-49ee-42ea-ae08-7366a94e7654.aerospike.internal`.

*   Test DNS resolution. The following commands should return a list of private IPs, one for each Aerospike node:

Terminal window

```
# with dig:dig +short <AEROSPIKE_TLS_NAME>
# with getent:getent hosts <AEROSPIKE_TLS_NAME>
```

*   From the **consumer** VPC, test connectivity to the Aerospike port:

Terminal window

```
nc -zv <ip address> 4000 # Check Aerospike on port 4000
```

*   If the connection fails, double-check route tables, peering acceptance, and security group rules.

*   Connect to Aerospike using AQL and TLS:

Find the connection details for your database, found in the Aerospike Cloud Console. Details include the hostname and a TLS CA file. The CA certificate verifies the authenticity of the Aerospike server you are connecting to and establishes an encrypted connection, ensuring your data is secure.

Terminal window

```
aql --tls-enable --tls-name {database-id} --tls-cafile {TLS-certificate-file-path} -h {hostname}:{port} -U {username} -P {password}
```

VPC peering status definitions
------------------------------

Throughout the VPC peering process, Aerospike Cloud and AWS indicate the status of the peering connection. Following are common statuses and their meaning:

*   **Pending Acceptance**: The peering connection request has been created by Aerospike and is awaiting your acceptance in AWS. In this state, you need to take action to accept the request. (If not accepted within 7 days, the request will expire.)
*   **Active**: The peering connection is fully established. An active status on both sides means the link is ready for use (though routing/DNS may still need to be configured as described above).
*   **Provisioning**: (Transient state) The request was accepted and AWS is in the process of making it active. This status usually changes to Active within a short time without further action.
*   **Failed**: The peering request failed to establish. This can happen due to invalid parameters or network overlaps. A failed connection cannot be accepted or used. You may need to delete it and create a new request.
*   **Rejected**: The peering request was explicitly declined by the accepter (your side). No connection is made. You would need to create a new request if you rejected by mistake.
*   **Expired**: The request wasn’t accepted within the allowed time (7 days). The connection is not made and the request must be recreated if still needed.

In the Aerospike Cloud Console, these statuses might be labeled slightly differently (for example, _Pending_ instead of _Pending Acceptance_) but the status is unchanged. _Active_ is the desired end state. If your connection shows _Active_ but you cannot connect to the database, double-check that routes and DNS are configured correctly as those steps are outside the raw peering status.

Troubleshooting
---------------

If any failures occur, make sure to check the following:

*   The account ID for your VPC (Accepter) is entered correctly.
*   The correct VPC ID for your VPC (Accepter) is selected.
*   None of the primary or secondary CIDR blocks in your VPC overlap those in the Aerospike Cloud VPC.
*   VPC Peering status is _Active_.
*   Your subnet uses the correct route table, with the Aerospike CIDR route.
*   Your VPC CIDR was entered correctly in the Aerospike Cloud Console.
*   DNS resolution returns Aerospike private IPs.
*   You are testing the correct port (4000 if TLS is enabled, 3000 if it is not).
*   Your security groups allow outbound traffic to the Aerospike VPC range on the correct port (4000 if TLS is enabled, 3000 if it is not).
*   No NACLs are blocking the traffic.
*   You waited 10 minutes after applying route changes.

The AWS Network Reachability Analyzer tool is helpful for debugging network connectivity.

Conclusion
----------

After peering is active and routes are properly configured, your AWS resources (EC2, EKS, etc.) communicate **privately** with Aerospike Cloud. This approach eliminates internet exposure and generally yields lower latency. If there is a problem connecting, check that the following are configured correctly:

*   **Security group rules**: Ensure inbound/outbound rules allow Aerospike port 4000, or 3000 for insecure connections (AWS Security Group Rules documentation)
*   **Route table entries**: Confirm that these entries target the correct CIDR and peering connection ID. Confirm that these entries exist on route tables attached to your application subnets.
*   **DNS settings**: Confirm successful DNS resolution. Ensure `enableDnsSupport` and `enableDnsHostnames` are set to `true` in your VPC settings. These settings appear as `DNS hostnames` and `DNS resolution` in the VPC Console UI.

**Next steps:**

*   Create your first database user

F