# ## Coding Session. Terraform + Flux
Знайомство з концепцією тераформ модулів, розгорнемо набір інструментів що реалізують повний повний автоматичний цикл на базі GitOps та Kubernetes.
- Terraform створить  Kubernetes cluster та розгорне Flux 
- Flux почне узгоджувати стан ІС та застосунків базуючись на джерелі у GitHub
- GitHub в свою чергу також буде створено за допомогою Terraform

1. Виконаємо ініціалізацію terraform:
```sh
✗ terraform init
Terraform has been successfully initialized!
```
2. Виконаємо початкові команду `terraform apply` та перевіримо результат у tfstate-файлі, де ми побачимо згенеровану пару ключів та аргументи в яких можна посилатись наприклад в output блоці.

3. Ми можемо створити окремий репозиторій для новоствореного модуля, та змінити `source` аргумент на посилання до віддаленого репозиторію: "github.com/vit-um/tf-google-gke-cluster".   Опишемо основні компонентні модулі в головному файлі кореневого модуля:
```hcl
module "github_repository" {
  source                   = "github.com/den-vasyliev/tf-github-repository"
  github_owner             = var.GITHUB_OWNER
  github_token             = var.GITHUB_TOKEN
  repository_name          = var.FLUX_GITHUB_REPO
  public_key_openssh       = module.tls_private_key.public_key_openssh
  public_key_openssh_title = "flux0"
}

module "gke_cluster" {
  source         = "github.com/den-vasyliev/tf-google-gke-cluster"
  GOOGLE_REGION  = var.GOOGLE_REGION
  GOOGLE_PROJECT = var.GOOGLE_PROJECT
  GKE_NUM_NODES  = 1
}

module "flux_bootstrap" {
  source            = "github.com/den-vasyliev/tf-fluxcd-flux-bootstrap"
  github_repository = "${var.GITHUB_OWNER}/${var.FLUX_GITHUB_REPO}"
  private_key       = module.tls_private_key.private_key_pem
  config_path       = module.gke_cluster.kubeconfig
}

module "tls_private_key" {
  source = "github.com/den-vasyliev/tf-hashicorp-tls-keys"
  algorithm = "RSA"
}
```
- Зверніть увагу, що модулі на локальній файловій системі використовуватись не будуть.  
- В модулі `flux_bootstrap` бачимо посилання посилання для значень `private_key` на модуль `tls_private_key`,
- В цьому ж модулі аргумент `config_path` вказує на значення `gke_cluster.kubeconfig`,
- Тоб-то значення файлу `kubeconfig`, що створюється після розгортання кластеру буде використано наступним залежним від нього модулем `flux_bootstrap`.

4. Додамо в консолі дві змінних, а саме [логин та кокен](https://github.com/settings/tokens) с правами створення репозиторіїв на github:
```sh
$ tf init
Terraform has been successfully initialized!
$ export TF_VAR_GITHUB_OWNER=vit-um
$ export TF_VAR_GITHUB_TOKEN=ghp_HLD0c53mk0psx...

$ tf apply

```
- По перше змінюємо output створення кластеру так щоб замість `kubeconfig` отримати параметри для авторизації в робочий репозиторій `flux-gitops` що створюється та видаляється автоматично конфігурацією Terraform
```hcl
# output "kubeconfig" {
#  value       = "${path.module}/kubeconfig"
#  description = "The path to the kubeconfig file"
#}

output "config_host" {
  value = "https://${data.google_container_cluster.main.endpoint}"
}

output "config_token" {
  value = data.google_client_config.current.access_token
}

output "config_ca" {
  value = base64decode(
    data.google_container_cluster.main.master_auth[0].cluster_ca_certificate,
  )
}

output "name" {
  value = google_container_cluster.this.name
}
```
- При створені модуля `flux_bootstrap` в `main.tf` посилаємось на вихідні змінні створені на попередньому кроці модулем `gke_cluster`

- Відповідно `flux` має їх отримати, тому в основному файлі цього модулю зазначаємо:
```hcl
provider "flux" {
  kubernetes = {
    host                   = var.config_host
    token                  = var.config_token
    cluster_ca_certificate = var.config_ca
  }
```
- Також зміниться файл зі зіміними модулю `tf-fluxcd-flux-bootstrap`
- На виході знов помилка:

![Bootstrap run error](.img/Bootstrap_run_error.png)  

- Щоб вивести на екран створені модулем змінні додамо їх у файл:
```hcl
output "FLUX_GITHUB_TARGET_PATH" {
  value = var.FLUX_GITHUB_TARGET_PATH
}
``` 
- Дозволимо в файлі `tf/modules/gke_cluster/main.tf` створення "kubeconfig", як результат помилка зникне:

- Створені ресурси:
```sh
$ tf state list
module.github_repository.github_repository.this
module.github_repository.github_repository_deploy_key.this
module.gke_cluster.data.google_client_config.current
module.gke_cluster.data.google_container_cluster.main
module.gke_cluster.google_container_cluster.this
module.gke_cluster.google_container_node_pool.this
module.tls_private_key.tls_private_key.this
module.gke_cluster.module.gke_auth.data.google_client_config.provider
module.gke_cluster.module.gke_auth.data.google_container_cluster.gke_cluster
module.gke_cluster.local_file.kubeconfig
```

- Розміщення файлу в [bucket](https://console.cloud.google.com/storage/browser)  
Щоб розмістити файл state в бакеті, ви можете використовувати команду terraform init з опцією --backend-config. Наприклад, щоб розмістити файл state в бакеті Google Cloud Storage, ви можете виконати наступну команду:
```sh
# Створимо bucket:
$ gsutil mb gs://vit-secret
Creating gs://vit-secret/...

# Перевірити вміст диску:
$ gsutil ls gs://vit-secret
gs://vit-secret/terraform/

```
- Отримаємо помилку. Як створити bucket [читаємо документацію](https://developer.hashicorp.com/terraform/language/settings/backends/gcs#example-configuration) та додаємо до основного файлу конфігурації наступний код:

```hcl
terraform {
  backend "gcs" {
    bucket  = "tf-state-prod"
    prefix  = "vit-secret"
  }
}

```
- Після повторної ініціалізації файл terraform.tfstate стане пустим, а його вміст буде зберігатись в бакеті
```sh
$ terraform init
$ tf show | more

```

5. Конвеєр управління ІС - Flux  

[Flux](https://fluxcd.io/flux/get-started/) передбачає що вся система описується декларативно, контролюється версіями та має автоматизований процес, що гарантує, архівує, зберігає та інше.  

Flux складається з [GitOps Toolkit components](https://fluxcd.io/flux/components/) які фактично є спеціалізованими Kubernetes контролери. 

![GitOps Toolkit components](.img/GitOpsToolkit.png)  

[Source Controller](https://fluxcd.io/flux/components/source/) реалізує ресурс або джерело з якого буде відбуватись реконселяція або узгодження між актуальним та бажаним станом ІС. Це відбувається за допомогою [Git](https://fluxcd.io/flux/components/source/gitrepositories/), [Helm](https://fluxcd.io/flux/components/source/helmrepositories/) та інших контролерів через Kubernetes API та CRD (Custom Resource Definitions), тоб-то ресурсами розширення Kubernetes.

Зворотній зв'язок про стан ІС у вигляді events, alerts, notifications можна отримувати в стандартні месенджери, web-hucks та системи типу Slack

Створений репозиторій `flux-gitops` містить інфраструктурну директорію `clusters/flux-system/`, що відповідає за компоненти flux на кластері у namespace `flux-system`. Тут можна знайти маніфести для наступних компонентів:
- gotk-components.yaml
- gotk-sync.yaml (містить 2 CRD для GitRepository та Kustomization для синхронізації саме компонентів flux)
- kustomization.yaml - файл конфігурації, що описує які ресурси контролювати

6. Отримаємо доступ до [нового кластеру](https://console.cloud.google.com/kubernetes/list/overview) за допомогою команди:
```sh

$ gcloud container clusters get-credentials main --zone us-central1-c --project vit-um
Fetching cluster endpoint and auth data.
kubeconfig entry generated for main.

# Якщо робота з локальної машини, то попередньо потрібно встановити плагін
$ gcloud components install gke-gcloud-auth-plugin
```

7. Перевіримо список ns по стан поду системи flux:
```sh
➜  k get ns
NAME              STATUS   AGE
default           Active   6h23m
flux-system       Active   155m
gmp-public        Active   6h23m
gmp-system        Active   6h23m
kube-node-lease   Active   6h23m
kube-public       Active   6h23m
kube-system       Active   6h23m
➜  k get po -n flux-system  
NAME                                       READY   STATUS    RESTARTS   AGE
helm-controller-69dbf9f968-cf9kg           1/1     Running   0          156m
kustomize-controller-796b4fbf5d-wzt5g      1/1     Running   0          156m
notification-controller-78f97c759b-9wrb5   0/1     Pending   0          156m
source-controller-7bc7c48d8d-495nb         1/1     Running   0          156m
``` 
- Перевірка подів показала, що всі контролери на місці. По суті контролери це звичайні процеси, що запущені в контейнері та слухають event-loop через Kubernetes-API  

- Для зручності встановимо [CLI клієнт Flux](https://fluxcd.io/flux/installation/)
```sh
curl -s https://fluxcd.io/install.sh | bash
```
- Вивчимо деякі команди CLI Flux
```sh
$ flux get all
NAME                            REVISION                SUSPENDED       READY   MESSAGE                                           
gitrepository/flux-system       main@sha1:7a3534f9      False           True    stored artifact for revision 'main@sha1:7a3534f9'

NAME                            REVISION                SUSPENDED       READY   MESSAGE                              
kustomization/flux-system       main@sha1:7a3534f9      False           True    Applied revision: main@sha1:7a3534f9

$ flux logs -f
2023-12-16T17:48:01.390Z info Kustomization/flux-system.flux-system - Source is not ready, artifact not found 
2023-12-16T17:50:14.799Z info Kustomization/flux-system.flux-system - server-side apply for cluster definitions completed 
```
8. Розбираємо приклад роботи Flux
- Додамо в репозиторій каталог `demo` та файл `ns.yaml` що містить маніфест довільного `namespace`  
```sh
$ k ai "маніфест ns demo"
✨ Attempting to apply the following manifest:

apiVersion: v1
kind: Namespace
metadata:
  name: demo
```
- Після зміни стану репозиторію контролер Flux їх виявить:
    - зробить git clone  
    - підготує артефакт   
    - виконає узгодження поточного стану IC   

У даному випадку буде створено `ns demo`:
```sh
k get ns 
NAME              STATUS   AGE
default           Active   6h57m
demo              Active   4m36s
flux-system       Active   3h8m
```
Це був приклад як Flux може керувати конфігурацією ІС Kubernetes

9. Роздивимось взаємодію Flux з репозиторієм на якому код застосунку.
- застосуємо CLI для генерації маніфестів необхідних ресурсів:
```sh
$ flux create source git kbot \
    --url=https://github.com/vit-um/kbot \
    --branch=main \
    --namespace=demo \
    --export
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: kbot
  namespace: demo
spec:
  interval: 1m0s
  ref:
    branch: main
  url: https://github.com/vit-um/kbot
```
- отриманим маніфестом ми визначимо об'єкт за який відповідає source контролер.
- наступною командою згенеруємо helm release, тоб-то об'єкт для HELM-контролера 
```sh
$ flux create helmrelease kbot \
    --namespace=demo \
    --source=GitRepository/kbot \
    --chart="./helm" \
    --interval=1m \
    --export
---
apiVersion: helm.toolkit.fluxcd.io/v2beta2
kind: HelmRelease
metadata:
  name: kbot
  namespace: demo
spec:
  chart:
    spec:
      chart: ./helm
      reconcileStrategy: ChartVersion
      sourceRef:
        kind: GitRepository
        name: kbot
  interval: 1m0s
```
- Зверніть увагу на специфікацію, ми вказуємо:
    - посилання на `sourceRef`
    - шлях до `chart: ./helm`
    - стратегію для узгодження `reconcileStrategy: ChartVersion`   

Або простими словами: "Встанови хелм чарт з репозиторію з ім'ям kbot шлях ./helm` якщо змінилася чарт версія, перевіряти зміни щохвилини.

- Ми можемо імперативно створити ці ресурси в Kubernetes cluster за допомогою `flux cli` або `kubectl`, але то буде не декларативний підхід якого ми прагнемо. 

- Отже додамо маніфести в репозиторій, створивши в каталозі `demo` файли `kbot-gr.yaml` та `kbot-hr.yaml` з отриманими нами маніфестами та перевіримо логи:

- Проаналізуємо журнал kubectl:
```sh
$ kubectl logs -n flux-system deployment/helm-controller | jq -r 'select(.source != null) | .source'
kind source: *v2beta1.HelmRelease
kind source: *v1beta2.HelmChart

$  flux check --pre
► checking prerequisites
✔ Kubernetes 1.27.3-gke.100 >=1.26.0-0
✔ prerequisites checks passed

➜ flux get all
NAME                            REVISION                SUSPENDED       READY   MESSAGE                                           
gitrepository/flux-system       main@sha1:fdf255bc      False           True    stored artifact for revision 'main@sha1:fdf255bc'

NAME                            REVISION                SUSPENDED       READY   MESSAGE                              
kustomization/flux-system       main@sha1:fdf255bc      False           True    Applied revision: main@sha1:fdf255bc

➜ flux get all -A
NAMESPACE       NAME                            REVISION                SUSPENDED       READY   MESSAGE                                           
demo            gitrepository/kbot              main@sha1:12f309fe      False           True    stored artifact for revision 'main@sha1:12f309fe'
flux-system     gitrepository/flux-system       main@sha1:fdf255bc      False           True    stored artifact for revision 'main@sha1:fdf255bc'

NAMESPACE       NAME                    REVISION        SUSPENDED       READY   MESSAGE                                    
demo            helmchart/demo-kbot     0.1.0           False           True    packaged 'helm' chart with version '0.1.0'

NAMESPACE       NAME                            REVISION                SUSPENDED       READY   MESSAGE                              
flux-system     kustomization/flux-system       main@sha1:fdf255bc      False           True    Applied revision: main@sha1:fdf255bc
```


- Далі перевіримо под, його теж немає, хоча він мав існувати в стані `CreateContainerConfigError` через те що ми не створили secret з токеном. 
```sh
$ k get po -n demo
No resources found in demo namespace.
$ k describe po -n demo
No resources found in demo namespace.
```
- Але після того як усунули проблему версії та відбулась реконселяція под знайшовся:
```sh
$ k get po -n demo
NAME                         READY   STATUS   RESTARTS       AGE
kbot-helm-6796599d7c-72k8b   0/1     Error    5 (107s ago)   3m26s

$ k describe po -n demo | grep Warning
  Warning  BackOff  4m59s (x4737 over 17h)  kubelet  Back-off restarting failed container kbot in pod kbot-helm-6796599d7c-72k8b_demo(796091a0-a42c-4840-a7fd-c70c478ded93)
```

