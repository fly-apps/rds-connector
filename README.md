# A trivial Terraform example for WireGuard peering

This is potato-Terraform sufficient to create an RDS database, and connect 
it to a Fly.io 6PN network. It needs:

* An AWS account (strong recommend: [aws-vault](https://github.com/99designs/aws-vault))

* A password for a newly created RDS database

* A WireGuard configuration generated from `flyctl wireguard create`, in
  `wg0.conf`.

* An SSH key pair (you'll need to edit the Terraform, replacing `YOUR_KEY_HERE`).

It will create:

* A new VPC, numbered 172.16.0.0/16

* An EC2 instance, to which SSH is allowed from the world (see below).

* An RDS database called "appdb" with the specified password, and a security
  group rule allowing the EC2 instance to talk to it.

It uses Terraform's `remote-exec` to provision the EC2 instance:

* Installing WireGuard

* Setting up the WireGuard configuration

* Installing PgBouncer

* Configuring PgBouncer to talk to our RDS instance.

After running, you should have a WireGuard peer in your 6PN DNS, by
whichever name you gave the peer, to which you can connect Postgres
on 5432/tcp.

## Important Note

Part of the point of deploying like this is *not* having management dependencies
like SSH lying around, but an even bigger point of why I work at Fly.io is not 
having to be good at Terraform, so I don't have a standalone Terraform that 
"temporarily" allows SSH. If it were me, I'd just go in afterwards and kill the
SSH rule with the AWS CLI. Maybe you'd create an AMI instead; there's lots of
ways to do this.

