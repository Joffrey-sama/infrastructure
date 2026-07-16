# OCI Free Tier Kubernetes Infrastructure (Terraform)

Deploys an OKE cluster on Oracle Cloud Always Free tier.

## ⚠️ Load Balancer - Don't Forget!

When deploying services with LoadBalancer type, add these annotations:

```yaml
annotations:
  oci.oraclecloud.com/oci-load-balancer-type: "nlb"
  oci.oraclecloud.com/load-balancer-initial-flex-bandwidth-in-mbps: "10"
```

See `LOADBALANCER_FREETIER.md` for details.

## 📋 Quick Start

### 1. Configure OCI Locally

Ensure your OCI API credentials are in `~/.oci/config` with your API key in `~/.oci/` directory.

### 2. Configure Terraform

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your compartment_id
```

Required: Just your `compartment_id` (from OCI Console > Identity > Compartments)

### 3. Deploy

```bash
terraform init
terraform plan
terraform apply
```

### 4. Get Kubeconfig

```bash
terraform output -raw kubeconfig > ~/.kube/config-oci
export KUBECONFIG=~/.kube/config-oci
kubectl get nodes
```

## 📦 Infrastructure

- OKE cluster (managed control plane)
- 2-3 × Ampere A1 nodes (1 vCPU, 6 GB RAM) - Always Free
- VCN + public subnet
- Reserved Public IP for Load Balancer

## 💰 Free Tier Checklist

- ✅ Ampere A1 compute (Always Free)
- ✅ OKE control plane (Always Free)  
- ✅ VCN & networking (Always Free)
- ⚠️ **Load Balancer requires annotations** (see above)
- ⚠️ Egress traffic limited to 10 GB/month

## 🗑️ Destroy

```bash
terraform destroy
```

## 📚 More Info

- `LOADBALANCER_FREETIER.md` - Load balancer configuration details
- `POSTDEPLOY_CHECKLIST.md` - Post-deployment validation
- [OCI Always Free](https://www.oracle.com/cloud/free/)
- [OKE Documentation](https://docs.oracle.com/en-us/iaas/Container-Kubernetes-Engine/home.htm)
