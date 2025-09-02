# Proyek Aplikasi Node.js di Azure Kubernetes Service (AKS)

Repositori ini berisi contoh lengkap untuk men-deploy, mengelola, dan memonitor aplikasi Node.js di Azure Kubernetes Service (AKS) dengan praktik DevOps modern.

## Prasyarat

Sebelum memulai, pastikan Anda telah menginstal dan mengkonfigurasi tool berikut:

- **Azure CLI**: `v2.50.0` atau lebih baru
- **Terraform**: `v1.9.0` atau lebih baru
- **kubectl**: `v1.28.0` atau lebih baru
- **Helm**: `v3.13.0` atau lebih baru
- **Docker**: `v24.0.0` atau lebih baru
- Akun Azure dengan subscription aktif.
- Akun GitHub.

## Panduan Langkah Demi Langkah

### 1. Setup Awal

1.  **Clone repositori ini:**

    ```bash
    git clone <URL_REPO_ANDA>
    cd <NAMA_REPO>
    ```

2.  **Login ke Azure:**
    ```bash
    az login
    # Pastikan Anda menggunakan subscription yang benar
    az account set --subscription "NAMA_ATAU_ID_SUBSCRIPTION_ANDA"
    ```

### 2. Provisioning Infrastruktur dengan Terraform

Infrastruktur inti (Resource Group, ACR, AKS, Log Analytics) akan dibuat menggunakan Terraform.

1.  **Siapkan file variabel Terraform:**
    Salin file contoh dan sesuaikan nilainya. `prefix_name` harus unik.

    ```bash
    cp terraform/terraform.tfvars.sample terraform/terraform.tfvars
    # Edit terraform/terraform.tfvars sesuai kebutuhan Anda
    # Contoh: prefix_name = "devopsapp"
    ```

2.  **Inisialisasi dan Terapkan Terraform:**
    ```bash
    cd terraform
    terraform init
    terraform plan -out=tfplan
    terraform apply "tfplan"
    ```
    Proses ini akan memakan waktu 10-15 menit. Setelah selesai, Terraform akan menampilkan output yang berisi nama resource yang dibuat. Simpan output ini.

### 3. Konfigurasi GitHub Secrets

Pipeline CI/CD memerlukan akses ke Azure. Kita akan membuat Service Principal dan menyimpannya sebagai secret di GitHub.

1.  **Buat Service Principal (SP) untuk GitHub Actions:**
    Ganti `<SUBSCRIPTION_ID>` dan `<RESOURCE_GROUP_NAME>` dengan nilai dari output Terraform.

    ```bash
    # Dapatkan Subscription ID
    SUB_ID=$(az account show --query id --output tsv)

    # Dapatkan Resource Group dari output Terraform (mis: 'devopsapp-rg')
    RG_NAME="devopsapp-rg" # Ganti dengan nama resource group Anda

    # Buat SP dengan scope ke Resource Group
    az ad sp create-for-rbac --name "github-actions-sp" --role "Contributor" --scopes "/subscriptions/${SUB_ID}/resourceGroups/${RG_NAME}" --sdk-auth
    ```

2.  **Salin output JSON** yang dihasilkan oleh perintah di atas.

3.  **Tambahkan secrets ke repositori GitHub Anda:**
    Buka `Settings` > `Secrets and variables` > `Actions` di repositori GitHub Anda dan tambahkan secrets berikut:

| Secret Name            | Value                                                     |
| ---------------------- | --------------------------------------------------------- |
| `AZURE_CREDENTIALS`    | JSON lengkap yang Anda salin dari langkah sebelumnya.     |
| `AZURE_RESOURCE_GROUP` | Nama Resource Group Anda (mis. `devopsapp-rg`).           |
| `ACR_NAME`             | Nama Azure Container Registry Anda (mis. `devopsappacr`). |
| `AZURE_AKS_NAME`       | Nama cluster AKS Anda (mis. `devopsapp-aks`).             |
| `AZURE_CONTAINER_REGISTRY_LOGIN_SERVER`       | Dari Tahap tfplan (mis. `devopsappacr.azurecr.io`).             |
| `AZURE_CLIENT_ID`       | Dari output JSON AZURE_CREDENTIALS (mis. `7056f1c4-ee88-494axxx`).             |
| `AZURE_CLIENT_SECRET`       | Dari output JSON AZURE_CREDENTIALS (mis. `YqU8Q~fZBvufiV_Fzxxx`).             |

### 4. Setup Cluster Kubernetes

Setelah cluster AKS siap, kita perlu mengkonfigurasi beberapa komponen di dalamnya.

1.  **Dapatkan Kredensial `kubectl`:**

    ```bash
    # Gunakan nama dari output Terraform atau secret GitHub
    az aks get-credentials --resource-group <NAMA_RESOURCE_GROUP> --name <NAMA_CLUSTER_AKS>
    ```

2.  **Install NGINX Ingress Controller:**

    ```bash
    helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
    helm repo update
    helm install ingress-nginx ingress-nginx/ingress-nginx \
      --create-namespace \
      --namespace ingress-nginx \
      --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-load-balancer-health-probe-request-path"=/healthz
    ```

3.  **Install kube-prometheus-stack (Monitoring):**

    ```bash
    helm repo add prometheus-community [https://prometheus-community.github.io/helm-charts](https://prometheus-community.github.io/helm-charts)
    helm repo update
    helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
      --create-namespace \
      --namespace monitoring \
      -f monitoring/values-kube-prom.yaml
    ```

4.  **Konfigurasi Alerting Email untuk Prometheus:**

    - Buat file `secret-alertmanager.yaml` dari contoh: `cp monitoring/secret-alertmanager.example.yaml monitoring/secret-alertmanager.yaml`
    - Edit `monitoring/secret-alertmanager.yaml` dan isi detail SMTP Anda (enkripsi base64).
    - Apply secret tersebut: `kubectl apply -f monitoring/secret-alertmanager.yaml -n monitoring`
    - Update Helm release untuk menggunakan config baru: 

    ```bash
    helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
        --namespace monitoring \
        -f monitoring/values-kube-prom.yaml \
        --set alertmanager.config.global.smtp_from='sender_email'
    ```
    (lihat `values-kube-prom.yaml` untuk detail).

5.  **Install Trivy Operator (Security):**

    ```bash
    helm repo add aqua https://aquasecurity.github.io/helm-charts/
    helm repo update
    helm install trivy-operator aqua/trivy-operator \
      --create-namespace \
      --namespace security \
      --set="trivy.ignoreUnfixed=true" \
      --set="operator.vulnerabilityScanner.enabled=true" \
      --set="operator.serviceMonitor.enabled=true" # Untuk integrasi Prometheus

    # Terapkan aturan alert untuk kerentanan
    kubectl apply -f monitoring/prometheus-rules/trivy-vuln-rules.yaml -n monitoring
    ```

6.  **Buat Secret untuk Aplikasi:**
    - Buat file `k8s/base/secret.yaml` dari `secret.example.yaml`.
    - Isi dengan nilai rahasia (sebagai string base64).
    - Buat secret di cluster:
      ```bash
      kubectl create namespace staging

      kubectl create secret generic app-secret \
        --from-literal=APP_SECRET='super-secret-string-for-app' \
        -n staging
      ```

### 5. Deploy Aplikasi

Setelah semua setup selesai, lakukan `push` ke branch `main` untuk memicu pipeline CI/CD pertama kali.

```bash
git add .
git commit -m "feat: initial setup and deployment trigger"
git push origin main
```

Anda dapat memantau jalannya workflow di tab "Actions" pada repositori GitHub Anda.

### 6. Verifikasi

1.  **Akses Aplikasi:**\
    Tunggu beberapa menit hingga IP publik untuk Ingress Controller tersedia.

    ```bash
    kubectl get svc -n ingress-nginx
    # Dapatkan EXTERNAL-IP dari service ingress-nginx-controller
    ```

    Edit file `/etc/hosts` Anda (atau konfigurasikan DNS) untuk mengarahkan `staging.devops.com` ke IP eksternal tersebut. Lalu akses di browser: `http://staging.devops.com`

2.  **Akses Grafana:**\
    Akses `http://grafana.devops.com`. Login dengan user `admin` dan password `prom-operator` (atau yang dikonfigurasi di `values-kube-prom.yaml`). Anda akan melihat dashboard untuk memonitor cluster dan aplikasi Anda.

3.  **Verifikasi HPA:**\
    Gunakan tool seperti `hey` atau `ab` untuk mengirim beban ke aplikasi dan lihat HPA men-skala jumlah pod.

    ```bash
        # Pantau HPA
        kubectl get hpa -n staging -w

        # Kirim beban dari pod lain
        kubectl run -it --rm load-generator --image=busybox -- sh
        # Di dalam pod:
        # while true; do wget -q -O- [http://hello-app-service.staging.svc.cluster.local/](http://hello-app-service.staging.svc.cluster.local/); done
    ```

### 7. Cleanup

Untuk menghapus semua resource yang telah dibuat:

```bash
cd terraform
terraform destroy
```

Ini akan menghapus semua resource Azure yang dibuat oleh Terraform.

## Troubleshooting

1. ImagePullBackOff: Pastikan Service Principal memiliki peran `AcrPull` pada ACR. Terraform seharusnya sudah mengaturnya, tetapi verifikasi di Azure Portal jika terjadi masalah.

2. Ingress tidak mendapatkan IP: Cek log dari pod NGINX Ingress Controller di namespace `ingress-nginx`. Pastikan tidak ada batasan jaringan di Azure.

3. Alert tidak terkirim: Verifikasi konfigurasi SMTP di Alertmanager dan pastikan port SMTP tidak diblokir oleh provider cloud Anda.
