# Grafana Alerting resources: Contact Point, Notification Policy, and Rule Groups

resource "grafana_folder" "alerts" {
  count = var.ntfy_url != "" ? 1 : 0
  title = "Alerts"
}

resource "grafana_contact_point" "ntfy" {
  count = var.ntfy_url != "" ? 1 : 0
  name  = "ntfy"

  webhook {
    url                     = var.ntfy_url
    http_method             = "POST"
    disable_resolve_message = false
  }
}

resource "grafana_notification_policy" "default" {
  count           = var.ntfy_url != "" ? 1 : 0
  contact_point   = grafana_contact_point.ntfy[0].name
  group_by        = ["alertname", "cluster"]
  group_wait      = "10s"
  group_interval  = "1m"
  repeat_interval = var.notification_repeat_interval
}

locals {
  # Group 1: Kubernetes Workloads
  kube_workload_rules = [
    {
      name        = "KubePodCrashLooping"
      expr        = "max_over_time(kube_pod_container_status_waiting_reason{reason=\"CrashLoopBackOff\"}[5m]) >= 1"
      threshold   = 0
      operator    = "gt"
      for         = "2m"
      severity    = "critical"
      category    = "pod"
      summary     = "Pod is crash looping"
      description = "Pod {{ $labels.namespace }}/{{ $labels.pod }} (container {{ $labels.container }}) is in CrashLoopBackOff."
    },
    {
      name        = "KubePodNotHealthy"
      expr        = "sum by (namespace, pod) (kube_pod_status_phase{phase=~\"Pending|Unknown|Failed\"}) > 0"
      threshold   = 0
      operator    = "gt"
      for         = "15m"
      severity    = "critical"
      category    = "pod"
      summary     = "Pod not healthy"
      description = "Pod {{ $labels.namespace }}/{{ $labels.pod }} has been in a non-running state for longer than 15 minutes."
    },
    {
      name        = "KubePodNotReady"
      expr        = "sum by (namespace, pod, cluster) (kube_pod_status_ready{condition=\"true\"} == 0 and on (namespace, pod, cluster) kube_pod_status_phase{phase=\"Running\"} == 1)"
      threshold   = 0
      operator    = "gt"
      for         = "10m"
      severity    = "warning"
      category    = "pod"
      summary     = "Pod not ready"
      description = "Pod {{ $labels.namespace }}/{{ $labels.pod }} on cluster {{ $labels.cluster }} is running but not ready for more than 10 minutes."
    },
    {
      name        = "KubeContainerWaiting"
      expr        = "kube_pod_container_status_waiting_reason{reason!=\"CrashLoopBackOff\"} > 0"
      threshold   = 0
      operator    = "gt"
      for         = "1h"
      severity    = "warning"
      category    = "pod"
      summary     = "Container in waiting state"
      description = "Container {{ $labels.container }} in pod {{ $labels.namespace }}/{{ $labels.pod }} waiting > 1h (reason: {{ $labels.reason }})."
    },
    {
      name        = "KubeContainerOOMKilled"
      expr        = "(kube_pod_container_status_restarts_total - kube_pod_container_status_restarts_total offset 10m >= 1) and ignoring (reason) min_over_time(kube_pod_container_status_last_terminated_reason{reason=\"OOMKilled\"}[10m]) == 1"
      threshold   = 0
      operator    = "gt"
      for         = "0m"
      severity    = "warning"
      category    = "pod"
      summary     = "Container OOMKilled"
      description = "Container {{ $labels.container }} in pod {{ $labels.namespace }}/{{ $labels.pod }} was killed by OOM in last 10m."
    },
    {
      name        = "KubeDeploymentReplicasMismatch"
      expr        = "kube_deployment_spec_replicas != kube_deployment_status_replicas_available"
      threshold   = 0
      operator    = "gt"
      for         = "10m"
      severity    = "warning"
      category    = "deployment"
      summary     = "Deployment replicas mismatch"
      description = "Deployment {{ $labels.namespace }}/{{ $labels.deployment }} has replicas mismatch for more than 10 minutes."
    },
    {
      name        = "KubeDeploymentGenerationMismatch"
      expr        = "kube_deployment_status_observed_generation != kube_deployment_metadata_generation"
      threshold   = 0
      operator    = "gt"
      for         = "10m"
      severity    = "critical"
      category    = "deployment"
      summary     = "Deployment generation mismatch"
      description = "Deployment {{ $labels.namespace }}/{{ $labels.deployment }} has failed and not rolled back."
    },
    {
      name        = "KubeDeploymentRolloutStuck"
      expr        = "kube_deployment_status_condition{condition=\"Progressing\",status=\"false\"} != 0"
      threshold   = 0
      operator    = "gt"
      for         = "10m"
      severity    = "warning"
      category    = "deployment"
      summary     = "Deployment rollout stuck"
      description = "Deployment {{ $labels.namespace }}/{{ $labels.deployment }} rollout is not progressing."
    },
    {
      name        = "KubeStatefulSetReplicasMismatch"
      expr        = "kube_statefulset_status_replicas_ready != kube_statefulset_status_replicas"
      threshold   = 0
      operator    = "gt"
      for         = "10m"
      severity    = "warning"
      category    = "statefulset"
      summary     = "StatefulSet replicas mismatch"
      description = "StatefulSet {{ $labels.namespace }}/{{ $labels.statefulset }} does not match expected replicas."
    },
    {
      name        = "KubeStatefulSetGenerationMismatch"
      expr        = "kube_statefulset_status_observed_generation != kube_statefulset_metadata_generation"
      threshold   = 0
      operator    = "gt"
      for         = "10m"
      severity    = "critical"
      category    = "statefulset"
      summary     = "StatefulSet generation mismatch"
      description = "StatefulSet {{ $labels.namespace }}/{{ $labels.statefulset }} update failed and not rolled back."
    },
    {
      name        = "KubeStatefulSetDown"
      expr        = "kube_statefulset_replicas > 0 and kube_statefulset_replicas != kube_statefulset_status_replicas_ready and changes(kube_statefulset_status_replicas_updated[10m]) == 0"
      threshold   = 0
      operator    = "gt"
      for         = "3m"
      severity    = "critical"
      category    = "statefulset"
      summary     = "StatefulSet down"
      description = "StatefulSet {{ $labels.namespace }}/{{ $labels.statefulset }} went down and is not recovering."
    },
    {
      name        = "KubeDaemonSetRolloutStuck"
      expr        = "((kube_daemonset_status_number_ready / kube_daemonset_status_desired_number_scheduled * 100 < 100 and kube_daemonset_status_desired_number_scheduled > 0) or kube_daemonset_status_desired_number_scheduled - kube_daemonset_status_current_number_scheduled > 0) and changes(kube_daemonset_status_updated_number_scheduled[5m]) == 0"
      threshold   = 0
      operator    = "gt"
      for         = "10m"
      severity    = "warning"
      category    = "daemonset"
      summary     = "DaemonSet rollout stuck"
      description = "DaemonSet {{ $labels.namespace }}/{{ $labels.daemonset }} pods are not ready or scheduled."
    },
    {
      name        = "KubeDaemonSetMisscheduled"
      expr        = "kube_daemonset_status_number_misscheduled > 0"
      threshold   = 0
      operator    = "gt"
      for         = "1m"
      severity    = "warning"
      category    = "daemonset"
      summary     = "DaemonSet misscheduled"
      description = "Pods of DaemonSet {{ $labels.namespace }}/{{ $labels.daemonset }} are running where they should not."
    },
    {
      name        = "KubeJobFailed"
      expr        = "kube_job_status_failed > 0"
      threshold   = 0
      operator    = "gt"
      for         = "1m"
      severity    = "warning"
      category    = "job"
      summary     = "Job failed"
      description = "Job {{ $labels.namespace }}/{{ $labels.job_name }} failed to complete."
    },
    {
      name        = "KubeJobSlowCompletion"
      expr        = "kube_job_status_active > 0 and (time() - kube_job_status_start_time) > 43200"
      threshold   = 0
      operator    = "gt"
      for         = "12h"
      severity    = "critical"
      category    = "job"
      summary     = "Job slow completion"
      description = "Job {{ $labels.namespace }}/{{ $labels.job_name }} did not complete within 12 hours."
    },
    {
      name        = "KubeCronJobFailing"
      expr        = "(kube_cronjob_status_last_schedule_time > kube_cronjob_status_last_successful_time) AND (kube_cronjob_status_active == 0) AND (kube_cronjob_spec_suspend == 0)"
      threshold   = 0
      operator    = "gt"
      for         = "0m"
      severity    = "critical"
      category    = "cronjob"
      summary     = "CronJob failing"
      description = "CronJob {{ $labels.namespace }}/{{ $labels.cronjob }} is failing."
    },
    {
      name        = "KubeHpaScaleInability"
      expr        = "(kube_horizontalpodautoscaler_spec_max_replicas - kube_horizontalpodautoscaler_status_desired_replicas) * on (horizontalpodautoscaler,namespace) (kube_horizontalpodautoscaler_status_condition{condition=\"ScalingLimited\", status=\"true\"} == 1) == 0"
      threshold   = 0
      operator    = "gt"
      for         = "2m"
      severity    = "warning"
      category    = "hpa"
      summary     = "HPA unable to scale"
      description = "HPA {{ $labels.namespace }}/{{ $labels.horizontalpodautoscaler }} is unable to scale."
    }
  ]

  # Group 2: Kubernetes Cluster & Nodes
  kube_cluster_rules = [
    {
      name        = "KubeNodeNotReady"
      expr        = "kube_node_status_condition{condition=\"Ready\",status=\"true\"} < 1"
      threshold   = 0
      operator    = "gt"
      for         = "3m"
      severity    = "critical"
      category    = "node"
      summary     = "Node is NotReady"
      description = "Node {{ $labels.node }} has been unready for more than 3 minutes."
    },
    {
      name        = "KubeNodeMemoryPressure"
      expr        = "kube_node_status_condition{condition=\"MemoryPressure\",status=\"true\"} == 1"
      threshold   = 0
      operator    = "gt"
      for         = "2m"
      severity    = "critical"
      category    = "node"
      summary     = "Node memory pressure"
      description = "Node {{ $labels.node }} has MemoryPressure condition."
    },
    {
      name        = "KubeNodeDiskPressure"
      expr        = "kube_node_status_condition{condition=\"DiskPressure\",status=\"true\"} == 1"
      threshold   = 0
      operator    = "gt"
      for         = "2m"
      severity    = "critical"
      category    = "node"
      summary     = "Node disk pressure"
      description = "Node {{ $labels.node }} has DiskPressure condition."
    },
    {
      name        = "KubeNodeNetworkUnavailable"
      expr        = "kube_node_status_condition{condition=\"NetworkUnavailable\",status=\"true\"} == 1"
      threshold   = 0
      operator    = "gt"
      for         = "2m"
      severity    = "critical"
      category    = "node"
      summary     = "Node network unavailable"
      description = "Node {{ $labels.node }} has NetworkUnavailable condition."
    },
    {
      name        = "KubeNodeSchedulingDisabled"
      expr        = "kube_node_spec_taint{key=\"node.kubernetes.io/unschedulable\"} == 1"
      threshold   = 0
      operator    = "gt"
      for         = "30m"
      severity    = "warning"
      category    = "node"
      summary     = "Node scheduling disabled"
      description = "Node {{ $labels.node }} has been unschedulable for more than 30 minutes."
    },
    {
      name        = "KubeNodeOutOfPodCapacity"
      expr        = "sum by (node) ((kube_pod_status_phase{phase=\"Running\"} == 1) + on(uid, instance) group_left(node) (0 * kube_pod_info{pod_template_hash=\"\"})) / sum by (node) (kube_node_status_allocatable{resource=\"pods\"}) * 100"
      threshold   = 90
      operator    = "gt"
      for         = "2m"
      severity    = "warning"
      category    = "node"
      summary     = "Node out of pod capacity"
      description = "Node {{ $labels.node }} has reached > 90% of pod capacity."
    },
    {
      name        = "KubeKsmListWatchErrors"
      expr        = "(rate(kube_state_metrics_list_total{result=\"error\"}[5m]) / rate(kube_state_metrics_list_total[5m]) > 0.01 and rate(kube_state_metrics_list_total[5m]) > 0) or (rate(kube_state_metrics_watch_total{result=\"error\"}[5m]) / rate(kube_state_metrics_watch_total[5m]) > 0.01 and rate(kube_state_metrics_watch_total[5m]) > 0)"
      threshold   = 0
      operator    = "gt"
      for         = "5m"
      severity    = "critical"
      category    = "monitoring"
      summary     = "kube-state-metrics list/watch errors"
      description = "kube-state-metrics is failing to list or watch objects from the Kubernetes API server."
    },
    {
      name        = "KubeVersionMismatch"
      expr        = "count by (cluster) (count by (git_version, cluster) (kubernetes_build_info))"
      threshold   = 1
      operator    = "gt"
      for         = "10m"
      severity    = "warning"
      category    = "cluster"
      summary     = "Kubernetes version mismatch"
      description = "Multiple semantic versions of Kubernetes are running simultaneously in cluster {{ $labels.cluster }}."
    }
  ]

  # Group 3: Kubernetes Storage & PVCs
  kube_storage_rules = [
    {
      name        = "KubePersistentVolumeError"
      expr        = "kube_persistentvolume_status_phase{phase=~\"Failed|Pending\"} > 0"
      threshold   = 0
      operator    = "gt"
      for         = "1m"
      severity    = "critical"
      category    = "storage"
      summary     = "PersistentVolume error"
      description = "PersistentVolume {{ $labels.persistentvolume }} is in phase Failed or Pending."
    },
    {
      name        = "KubePersistentVolumeClaimPending"
      expr        = "kube_persistentvolumeclaim_status_phase{phase=\"Pending\"} == 1"
      threshold   = 0
      operator    = "gt"
      for         = "2m"
      severity    = "warning"
      category    = "storage"
      summary     = "PVC pending"
      description = "PersistentVolumeClaim {{ $labels.namespace }}/{{ $labels.persistentvolumeclaim }} is pending."
    },
    {
      name        = "KubeVolumeOutOfDiskSpace"
      expr        = "kubelet_volume_stats_available_bytes / kubelet_volume_stats_capacity_bytes * 100"
      threshold   = 10
      operator    = "lt"
      for         = "2m"
      severity    = "critical"
      category    = "storage"
      summary     = "PVC out of disk space"
      description = "PVC {{ $labels.namespace }}/{{ $labels.persistentvolumeclaim }} has less than 10% space remaining."
    },
    {
      name        = "KubeVolumeFullInFourDays"
      expr        = "predict_linear(kubelet_volume_stats_available_bytes[6h:5m], 4 * 24 * 3600)"
      threshold   = 0
      operator    = "lt"
      for         = "5m"
      severity    = "warning"
      category    = "storage"
      summary     = "PVC full in 4 days"
      description = "PVC {{ $labels.namespace }}/{{ $labels.persistentvolumeclaim }} is predicted to fill up within 4 days."
    },
    {
      name        = "KubeVolumeOutOfInodes"
      expr        = "kubelet_volume_stats_inodes_free / kubelet_volume_stats_inodes * 100"
      threshold   = 3
      operator    = "lt"
      for         = "2m"
      severity    = "warning"
      category    = "storage"
      summary     = "PVC out of inodes"
      description = "PVC {{ $labels.namespace }}/{{ $labels.persistentvolumeclaim }} has less than 3% inodes free."
    }
  ]

  # Group 4: Host & Hardware (node-exporter)
  host_hardware_rules = [
    {
      name        = "HostDiskSpaceCritical"
      expr        = "(node_filesystem_avail_bytes{fstype!~\"rootfs|tmpfs\",mountpoint!~\"/var/lib/kubelet/.*\"} / node_filesystem_size_bytes{fstype!~\"rootfs|tmpfs\",mountpoint!~\"/var/lib/kubelet/.*\"}) * 100"
      threshold   = 10
      operator    = "lt"
      for         = "5m"
      severity    = "critical"
      category    = "disk"
      summary     = "Filesystem almost out of space"
      description = "Filesystem {{ $labels.mountpoint }} on {{ $labels.instance }} has less than 10% space remaining."
    },
    {
      name        = "HostDiskSpaceWarning"
      expr        = "(node_filesystem_avail_bytes{fstype!~\"rootfs|tmpfs\",mountpoint!~\"/var/lib/kubelet/.*\"} / node_filesystem_size_bytes{fstype!~\"rootfs|tmpfs\",mountpoint!~\"/var/lib/kubelet/.*\"}) * 100"
      threshold   = 20
      operator    = "lt"
      for         = "10m"
      severity    = "warning"
      category    = "disk"
      summary     = "Filesystem low disk space"
      description = "Filesystem {{ $labels.mountpoint }} on {{ $labels.instance }} has less than 20% space remaining."
    },
    {
      name        = "HostDiskWillFillIn24Hours"
      expr        = "predict_linear(node_filesystem_free_bytes{fstype!~\"rootfs|tmpfs\",mountpoint!~\"/var/lib/kubelet/.*\"}[1h], 24 * 3600)"
      threshold   = 0
      operator    = "lt"
      for         = "5m"
      severity    = "warning"
      category    = "disk"
      summary     = "Filesystem will fill in 24h"
      description = "Filesystem {{ $labels.mountpoint }} on {{ $labels.instance }} is predicted to fill up within 24 hours."
    },
    {
      name        = "HostOutOfInodes"
      expr        = "node_filesystem_files_free{fstype!~\"rootfs|tmpfs\",mountpoint!~\"/var/lib/kubelet/.*\"} / node_filesystem_files{fstype!~\"rootfs|tmpfs\",mountpoint!~\"/var/lib/kubelet/.*\"} * 100"
      threshold   = 10
      operator    = "lt"
      for         = "5m"
      severity    = "warning"
      category    = "disk"
      summary     = "Filesystem low inodes"
      description = "Filesystem {{ $labels.mountpoint }} on {{ $labels.instance }} has less than 10% inodes remaining."
    },
    {
      name        = "HostOutOfMemory"
      expr        = "node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes * 100"
      threshold   = 10
      operator    = "lt"
      for         = "5m"
      severity    = "critical"
      category    = "memory"
      summary     = "Host low memory"
      description = "Host {{ $labels.instance }} has less than 10% memory available."
    },
    {
      name        = "HostHighCpuLoad"
      expr        = "100 - (avg by(instance) (rate(node_cpu_seconds_total{mode=\"idle\"}[5m])) * 100)"
      threshold   = 90
      operator    = "gt"
      for         = "10m"
      severity    = "warning"
      category    = "cpu"
      summary     = "Host high CPU load"
      description = "CPU usage on {{ $labels.instance }} is above 90% for more than 10 minutes."
    },
    {
      name        = "HostOomKillDetected"
      expr        = "increase(node_vmstat_oom_kill[1m])"
      threshold   = 0
      operator    = "gt"
      for         = "0m"
      severity    = "warning"
      category    = "memory"
      summary     = "Host OOM kill detected"
      description = "An OOM kill was detected on host {{ $labels.instance }}."
    },
    {
      name        = "HostSystemdServiceCrashed"
      expr        = "node_systemd_unit_state{state=\"failed\"}"
      threshold   = 0
      operator    = "gt"
      for         = "5m"
      severity    = "warning"
      category    = "systemd"
      summary     = "Systemd service crashed"
      description = "Systemd unit {{ $labels.name }} on {{ $labels.instance }} is in failed state."
    },
    {
      name        = "HostNetworkReceiveErrors"
      expr        = "rate(node_network_receive_errs_total[2m])"
      threshold   = 0
      operator    = "gt"
      for         = "5m"
      severity    = "warning"
      category    = "network"
      summary     = "Network receive errors"
      description = "Network interface {{ $labels.device }} on {{ $labels.instance }} has receive errors."
    }
  ]

  # Group 5: Core Services & Mesh (DNS, Cert-Manager, Postgres, Blackbox, Istio, NGINX, Alloy)
  core_services_rules = [
    {
      name        = "CoreDnsDown"
      expr        = "kube_deployment_status_replicas_available{deployment=~\"coredns\"} < 1"
      threshold   = 0
      operator    = "gt"
      for         = "2m"
      severity    = "critical"
      category    = "dns"
      summary     = "CoreDNS down"
      description = "CoreDNS deployment has no available replicas in cluster {{ $labels.cluster }}."
    },
    {
      name        = "CoreDnsErrorsHigh"
      expr        = "sum(rate(coredns_dns_responses_total{rcode=~\"SERVFAIL|NXDOMAIN\"}[5m])) / sum(rate(coredns_dns_responses_total[5m])) * 100"
      threshold   = 5
      operator    = "gt"
      for         = "5m"
      severity    = "warning"
      category    = "dns"
      summary     = "CoreDNS errors high"
      description = "CoreDNS is returning > 5% SERVFAIL/NXDOMAIN responses."
    },
    {
      name        = "CertManagerCertExpiringSoon"
      expr        = "(certmanager_certificate_expiration_timestamp_seconds - time()) / 86400"
      threshold   = 14
      operator    = "lt"
      for         = "1h"
      severity    = "warning"
      category    = "tls"
      summary     = "Certificate expiring soon"
      description = "Certificate {{ $labels.name }} in {{ $labels.namespace }} expires in less than 14 days."
    },
    {
      name        = "CertManagerCertNotReady"
      expr        = "certmanager_certificate_ready_status{condition=\"False\"} == 1"
      threshold   = 0
      operator    = "gt"
      for         = "10m"
      severity    = "critical"
      category    = "tls"
      summary     = "Certificate not ready"
      description = "Certificate {{ $labels.name }} in {{ $labels.namespace }} is in NotReady condition."
    },
    {
      name        = "PostgresqlDown"
      expr        = "pg_up < 1"
      threshold   = 0
      operator    = "gt"
      for         = "2m"
      severity    = "critical"
      category    = "database"
      summary     = "PostgreSQL is down"
      description = "PostgreSQL instance {{ $labels.instance }} is down."
    },
    {
      name        = "PostgresqlTooManyConnections"
      expr        = "sum(pg_stat_activity_count) by (instance) / on (instance) pg_settings_max_connections * 100"
      threshold   = 80
      operator    = "gt"
      for         = "5m"
      severity    = "warning"
      category    = "database"
      summary     = "PostgreSQL connections high"
      description = "PostgreSQL instance {{ $labels.instance }} is using > 80% connections."
    },
    {
      name        = "PostgresqlDeadLocks"
      expr        = "rate(pg_stat_database_deadlocks[5m])"
      threshold   = 0
      operator    = "gt"
      for         = "5m"
      severity    = "warning"
      category    = "database"
      summary     = "PostgreSQL deadlocks detected"
      description = "PostgreSQL database {{ $labels.datname }} is experiencing deadlocks."
    },
    {
      name        = "MonitoringStorageDown"
      expr        = "probe_success{instance=\"greptimedb-internal\"} < 1"
      threshold   = 0
      operator    = "gt"
      for         = "1m"
      severity    = "critical"
      category    = "monitoring"
      summary     = "Monitoring Storage Down (GreptimeDB)"
      description = "GreptimeDB metric store is unreachable or unresponsive on port 4000."
    },
    {
      name        = "MonitoringAgentDown"
      expr        = "absent(up{instance=\"delva-home-node-1\",job=\"integrations/unix\"}) == 1"
      threshold   = 0
      operator    = "gt"
      for         = "3m"
      severity    = "critical"
      category    = "monitoring"
      summary     = "Monitoring Agent Down (On-Prem)"
      description = "Alloy agent on delva-home-node-1 is unresponsive or has stopped pushing metrics for > 3 minutes."
    },
    {
      name        = "IpsecTunnelDown"
      expr        = "probe_success{instance=~\"ipsec-.*\"} < 1"
      threshold   = 0
      operator    = "gt"
      for         = "2m"
      severity    = "critical"
      category    = "network"
      summary     = "IPsec Tunnel / Cross-Cluster connection down"
      description = "Cross-cluster probe {{ $labels.instance }} has failed to connect across the IPsec VPN tunnel."
    },
    {
      name        = "BlackboxProbeFailed"
      expr        = "probe_success{instance!~\"ipsec-.*|greptimedb-internal\"} < 1"
      threshold   = 0
      operator    = "gt"
      for         = "3m"
      severity    = "critical"
      category    = "probe"
      summary     = "HTTP Probe failed"
      description = "Blackbox probe for {{ $labels.instance }} has failed for > 3 minutes."
    },
    {
      name        = "BlackboxSslCertificateExpiringSoon"
      expr        = "(probe_ssl_earliest_cert_expiry - time()) / 86400"
      threshold   = 14
      operator    = "lt"
      for         = "1h"
      severity    = "warning"
      category    = "tls"
      summary     = "SSL certificate expiring soon"
      description = "SSL certificate for {{ $labels.instance }} expires in less than 14 days."
    },
    {
      name        = "BlackboxProbeSlow"
      expr        = "probe_http_duration_seconds"
      threshold   = 5
      operator    = "gt"
      for         = "5m"
      severity    = "warning"
      category    = "probe"
      summary     = "HTTP Probe slow"
      description = "HTTP probe for {{ $labels.instance }} is taking longer than 5s."
    },
    {
      name        = "IstiodDown"
      expr        = "up{namespace=\"istio-system\",pod=~\"istiod-.*\"} < 1"
      threshold   = 0
      operator    = "gt"
      for         = "2m"
      severity    = "critical"
      category    = "mesh"
      summary     = "Istiod is down"
      description = "Istiod pod in {{ $labels.namespace }} is down."
    },
    {
      name        = "IstioHigh5xxRate"
      expr        = "sum(rate(istio_requests_total{response_code=~\"5.*\"}[5m])) / sum(rate(istio_requests_total[5m])) * 100"
      threshold   = 5
      operator    = "gt"
      for         = "5m"
      severity    = "warning"
      category    = "mesh"
      summary     = "Istio high 5xx error rate"
      description = "More than 5% of requests in Istio mesh are returning 5xx errors."
    },
    {
      name        = "NginxGatewayDown"
      expr        = "kube_deployment_status_replicas_available{deployment=~\"main-gateway-nginx|public-gateway-nginx|internal-gateway-nginx|vpn-gateway-nginx\"} < 1"
      threshold   = 0
      operator    = "gt"
      for         = "2m"
      severity    = "critical"
      category    = "ingress"
      summary     = "NGINX Gateway is down"
      description = "NGINX Gateway deployment {{ $labels.deployment }} in {{ $labels.namespace }} has no available replicas."
    },
    {
      name        = "AlloyScrapeIssues"
      expr        = "rate(prometheus_target_scrapes_sample_out_of_order_total[5m]) + rate(prometheus_target_scrapes_exceeded_sample_limit_total[5m])"
      threshold   = 0
      operator    = "gt"
      for         = "5m"
      severity    = "warning"
      category    = "monitoring"
      summary     = "Alloy scrape issues"
      description = "Grafana Alloy is encountering scraping or ingestion errors."
    }
  ]
}

# 1. Kubernetes Workloads Rule Group
resource "grafana_rule_group" "kubernetes_workloads" {
  count            = var.ntfy_url != "" ? 1 : 0
  name             = "Kubernetes Workloads"
  folder_uid       = grafana_folder.alerts[0].uid
  interval_seconds = 120

  dynamic "rule" {
    for_each = local.kube_workload_rules
    content {
      name           = rule.value.name
      condition      = "C"
      for            = rule.value.for
      no_data_state  = "OK"
      exec_err_state = "OK"

      labels = {
        severity = rule.value.severity
        category = rule.value.category
      }

      annotations = {
        summary     = rule.value.summary
        description = rule.value.description
      }

      data {
        ref_id         = "A"
        datasource_uid = grafana_data_source.greptimedb.uid
        relative_time_range {
          from = 300
          to   = 0
        }
        model = jsonencode({
          expr  = rule.value.expr
          refId = "A"
        })
      }

      data {
        ref_id         = "B"
        datasource_uid = "__expr__"
        relative_time_range {
          from = 0
          to   = 0
        }
        model = jsonencode({
          expression = "A"
          reducer    = "last"
          refId      = "B"
          type       = "reduce"
          settings = {
            mode = "dropNN"
          }
        })
      }

      data {
        ref_id         = "C"
        datasource_uid = "__expr__"
        relative_time_range {
          from = 0
          to   = 0
        }
        model = jsonencode({
          expression = "B"
          type       = "threshold"
          refId      = "C"
          conditions = [
            {
              evaluator = {
                type   = rule.value.operator
                params = [rule.value.threshold]
              }
            }
          ]
        })
      }
    }
  }
}

# 2. Kubernetes Cluster & Nodes Rule Group
resource "grafana_rule_group" "kubernetes_cluster" {
  count            = var.ntfy_url != "" ? 1 : 0
  name             = "Kubernetes Cluster & Nodes"
  folder_uid       = grafana_folder.alerts[0].uid
  interval_seconds = 120

  dynamic "rule" {
    for_each = local.kube_cluster_rules
    content {
      name           = rule.value.name
      condition      = "C"
      for            = rule.value.for
      no_data_state  = "OK"
      exec_err_state = "OK"

      labels = {
        severity = rule.value.severity
        category = rule.value.category
      }

      annotations = {
        summary     = rule.value.summary
        description = rule.value.description
      }

      data {
        ref_id         = "A"
        datasource_uid = grafana_data_source.greptimedb.uid
        relative_time_range {
          from = 300
          to   = 0
        }
        model = jsonencode({
          expr  = rule.value.expr
          refId = "A"
        })
      }

      data {
        ref_id         = "B"
        datasource_uid = "__expr__"
        relative_time_range {
          from = 0
          to   = 0
        }
        model = jsonencode({
          expression = "A"
          reducer    = "last"
          refId      = "B"
          type       = "reduce"
          settings = {
            mode = "dropNN"
          }
        })
      }

      data {
        ref_id         = "C"
        datasource_uid = "__expr__"
        relative_time_range {
          from = 0
          to   = 0
        }
        model = jsonencode({
          expression = "B"
          type       = "threshold"
          refId      = "C"
          conditions = [
            {
              evaluator = {
                type   = rule.value.operator
                params = [rule.value.threshold]
              }
            }
          ]
        })
      }
    }
  }
}

# 3. Kubernetes Storage & Volumes Rule Group
resource "grafana_rule_group" "kubernetes_storage" {
  count            = var.ntfy_url != "" ? 1 : 0
  name             = "Kubernetes Storage & Volumes"
  folder_uid       = grafana_folder.alerts[0].uid
  interval_seconds = 120

  dynamic "rule" {
    for_each = local.kube_storage_rules
    content {
      name           = rule.value.name
      condition      = "C"
      for            = rule.value.for
      no_data_state  = "OK"
      exec_err_state = "OK"

      labels = {
        severity = rule.value.severity
        category = rule.value.category
      }

      annotations = {
        summary     = rule.value.summary
        description = rule.value.description
      }

      data {
        ref_id         = "A"
        datasource_uid = grafana_data_source.greptimedb.uid
        relative_time_range {
          from = 300
          to   = 0
        }
        model = jsonencode({
          expr  = rule.value.expr
          refId = "A"
        })
      }

      data {
        ref_id         = "B"
        datasource_uid = "__expr__"
        relative_time_range {
          from = 0
          to   = 0
        }
        model = jsonencode({
          expression = "A"
          reducer    = "last"
          refId      = "B"
          type       = "reduce"
          settings = {
            mode = "dropNN"
          }
        })
      }

      data {
        ref_id         = "C"
        datasource_uid = "__expr__"
        relative_time_range {
          from = 0
          to   = 0
        }
        model = jsonencode({
          expression = "B"
          type       = "threshold"
          refId      = "C"
          conditions = [
            {
              evaluator = {
                type   = rule.value.operator
                params = [rule.value.threshold]
              }
            }
          ]
        })
      }
    }
  }
}

# 4. Host & Hardware Rule Group
resource "grafana_rule_group" "host_hardware" {
  count            = var.ntfy_url != "" ? 1 : 0
  name             = "Host & Hardware"
  folder_uid       = grafana_folder.alerts[0].uid
  interval_seconds = 120

  dynamic "rule" {
    for_each = local.host_hardware_rules
    content {
      name           = rule.value.name
      condition      = "C"
      for            = rule.value.for
      no_data_state  = "OK"
      exec_err_state = "OK"

      labels = {
        severity = rule.value.severity
        category = rule.value.category
      }

      annotations = {
        summary     = rule.value.summary
        description = rule.value.description
      }

      data {
        ref_id         = "A"
        datasource_uid = grafana_data_source.greptimedb.uid
        relative_time_range {
          from = 300
          to   = 0
        }
        model = jsonencode({
          expr  = rule.value.expr
          refId = "A"
        })
      }

      data {
        ref_id         = "B"
        datasource_uid = "__expr__"
        relative_time_range {
          from = 0
          to   = 0
        }
        model = jsonencode({
          expression = "A"
          reducer    = "last"
          refId      = "B"
          type       = "reduce"
          settings = {
            mode = "dropNN"
          }
        })
      }

      data {
        ref_id         = "C"
        datasource_uid = "__expr__"
        relative_time_range {
          from = 0
          to   = 0
        }
        model = jsonencode({
          expression = "B"
          type       = "threshold"
          refId      = "C"
          conditions = [
            {
              evaluator = {
                type   = rule.value.operator
                params = [rule.value.threshold]
              }
            }
          ]
        })
      }
    }
  }
}

# 5. Core Services & Mesh Rule Group
resource "grafana_rule_group" "core_services" {
  count            = var.ntfy_url != "" ? 1 : 0
  name             = "Core Services & Mesh"
  folder_uid       = grafana_folder.alerts[0].uid
  interval_seconds = 120

  dynamic "rule" {
    for_each = local.core_services_rules
    content {
      name           = rule.value.name
      condition      = "C"
      for            = rule.value.for
      no_data_state  = "OK"
      exec_err_state = "OK"

      labels = {
        severity = rule.value.severity
        category = rule.value.category
      }

      annotations = {
        summary     = rule.value.summary
        description = rule.value.description
      }

      data {
        ref_id         = "A"
        datasource_uid = grafana_data_source.greptimedb.uid
        relative_time_range {
          from = 300
          to   = 0
        }
        model = jsonencode({
          expr  = rule.value.expr
          refId = "A"
        })
      }

      data {
        ref_id         = "B"
        datasource_uid = "__expr__"
        relative_time_range {
          from = 0
          to   = 0
        }
        model = jsonencode({
          expression = "A"
          reducer    = "last"
          refId      = "B"
          type       = "reduce"
          settings = {
            mode = "dropNN"
          }
        })
      }

      data {
        ref_id         = "C"
        datasource_uid = "__expr__"
        relative_time_range {
          from = 0
          to   = 0
        }
        model = jsonencode({
          expression = "B"
          type       = "threshold"
          refId      = "C"
          conditions = [
            {
              evaluator = {
                type   = rule.value.operator
                params = [rule.value.threshold]
              }
            }
          ]
        })
      }
    }
  }
}
