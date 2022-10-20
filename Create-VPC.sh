#!/bin/sh
#file: Create-VPC.sh
#author: TWolfis
#Function: deploy vpc to aws cloud 

#Create VPC and store the value of the VPCID
echo "Creating VPC"
VPCID=$(aws ec2 create-vpc --cidr-block 10.0.0.0/16 --region us-east-1 --query Vpc.VpcId --output text)

#couple tags to created VPC
aws ec2 create-tags --resources $VPCID --tags 'Key=Name,Value="Lab VPC"'

#create internet gateway and store value of the internet gateway ID
echo "Creating Internet gateway"
IGWID=$(aws ec2 create-internet-gateway --query InternetGateway.InternetGatewayId --output text)

#attach tags to internet gateway
aws ec2 create-tags --resources $IGWID --tags 'Key=Name,Value="Lab IGW"'

#attach VPC to igw
echo "Attaching VPC to internet gateway"
aws ec2 attach-internet-gateway --internet-gateway-id $IGWID --vpc-id $VPCID

#find zoneID value of the first Availability Zone, this is where we will put our public subnet
echo "Finding availability Zone ID"
ZONEID=$(aws ec2 describe-availability-zones --filters "Name=zone-name,Values='us-east-1a'" --query 'AvailabilityZones[0].ZoneId'|  sed 's/\"//g')

#create public subnet
echo "Creating Public subnet"
PUBSUBID=$(aws ec2 create-subnet --availability-zone-id $ZONEID --cidr-block 10.0.0.0/24 --vpc-id $VPCID --query Subnet.SubnetId --output text)

#tag public subnet
aws ec2 create-tags --resources $PUBSUBID --tags 'Key=Name,Value="Lab Public Subnet"'

#get elastic IP
ELASTICIP=$(aws ec2 allocate-address --query AllocationId --output text)

#Create Nat gateway
echo "Create NAT gateway"
NATID=$(aws ec2 create-nat-gateway --subnet-id  $PUBSUBID --allocation-id $ELASTICIP --query NatGateway.NatGatewayId --output text)

#Create Route Table for public subnet
echo "Create Route Table in public subnet"
PUBROUTETBID=$(aws ec2 create-route-table --vpc-id $VPCID --query RouteTable.RouteTableId --output text)

#tag Route Table 
aws ec2 create-tags --resources $PUBROUTETBID --tags 'Key=Name,Value="Public Subnet Route Table"'

#add default route to route table
echo "Add default route to route table in public subnet"
aws ec2 create-route --destination-cidr-block 0.0.0.0/0 --gateway-id $IGWID --route-table-id $PUBROUTETBID

#associate route table with public subnet and store association ID
echo "Associating created route table with public subnet"
ASOCID=$(aws ec2 associate-route-table --route-table-id $PUBROUTETBID --subnet-id $PUBSUBID --query AssociationId --output text)

#create private subnet
echo "Create private subnet"
PRIVSUBID=$(aws ec2 create-subnet --availability-zone-id $ZONEID --cidr-block 10.0.1.0/24 --vpc-id $VPCID --query Subnet.SubnetId --output text)

#tag private subnet
aws ec2 create-tags --resources $PRIVSUBID --tags 'Key=Name,Value="Lab Private Subnet"'

#Create route table for private subnet
echo "Create route for private subnet"
PRIVROUTETBID=$(aws ec2 create-route-table --vpc-id $VPCID --query RouteTable.RouteTableId --output text)

#tag Route Table 
aws ec2 create-tags --resources $PRIVROUTETBID --tags 'Key=Name,Value="Public Subnet Route Table"'

#add route to route table for private subnet, set default route to be send to nat gateway
echo "Adding default route to private subnet"
aws ec2 create-route --destination-cidr-block 0.0.0.0/0 --nat-gateway-id $NATID --route-table-id $PRIVROUTETBID

#associate private subnet route table with lab private subnet
echo "Associating created route table with private subnet"
ASOCID=$(aws ec2 associate-route-table --route-table-id $PRIVROUTETBID --subnet-id $PRIVSUBID --query AssociationId --output text)

#create VPC security group 
echo "Create VPC security group for HTTP access"
SECGROUPID=$(aws ec2 create-security-group --description "Enable HTTP access" --group-name "Web Security Group" --vpc-id $VPCID --query GroupId --output text)

#add ingress rule to security group
echo "Adding rules to security group" 
aws ec2 authorize-security-group-ingress --group-id $SECGROUPID --protocol tcp --port 80 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id $SECGROUPID --protocol tcp --port 22 --cidr 0.0.0.0/0

#get latest ami
AMI=$(./Get-Latest-AMI.sh)

#create instance
echo "Create instance"
INSTANCEID=$(aws ec2 run-instances --image-id $AMI --count 1 --instance-type t2.micro --key-name vockey --security-group-ids $SECGROUPID --subnet-id $PUBSUBID --associate-public-ip-address --user-data user_data.txt --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value="Web Server 1"}]' --query 'Instances[0].InstanceId' --output text)

#describe instance
aws ec2 describe-instances --filter Name=instance-id,Values=$INSTANCEID
exit