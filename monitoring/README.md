# QuakeWatch Monitoring Setup Guide

This directory contains all monitoring resources for QuakeWatch application.

## 📁 Files

- `servicemonitor-quakewatch.yaml` - Tells Prometheus to scrape metrics from QuakeWatch
- `grafana-quakewatch-dashboard.yaml` - Pre-configured Grafana dashboard
- `prometheus-quakewatch-alerts.yaml` - Alert rules (7 alerts)
- `alertmanager-config.yaml` - Email notification configuration (reference only)

---

## 🚀 Quick Start

### 1. Apply ServiceMonitor (Already Applied)

```bash
kubectl apply -f monitoring/servicemonitor-quakewatch.yaml
```

**What it does:** Configures Prometheus to scrape `/metrics` from QuakeWatch pods every 30s.

---

### 2. Apply Grafana Dashboard (Already Applied)

```bash
kubectl apply -f monitoring/grafana-quakewatch-dashboard.yaml
```

**What it does:** Creates a dashboard in Grafana showing request rate, response time, error rate, and total requests.

**Access:**
```bash
kubectl port-forward svc/kube-prometheus-stack-grafana -n monitoring 3000:80
# Navigate to: http://localhost:3000
# Find: Dashboards → QuakeWatch Application Metrics
```

---

### 3. Apply Prometheus Alert Rules

```bash
kubectl apply -f monitoring/prometheus-quakewatch-alerts.yaml
```

**What it does:** Creates 7 alert rules that Prometheus evaluates every 30 seconds.

**Verify:**
```bash
# Check if PrometheusRule was created
kubectl get prometheusrules -n monitoring | grep quakewatch

# View alerts in Prometheus UI
kubectl port-forward -n monitoring prometheus-kube-prometheus-stack-prometheus-0 9090:9090
# Navigate to: http://localhost:9090/alerts
```

---

### 4. Configure Alertmanager for Email Notifications

**Option A: Update via Helm (Recommended)**

Create a values file:

```yaml
# alertmanager-values.yaml
alertmanager:
  config:
    global:
      resolve_timeout: 5m
      smtp_from: 'alertmanager@quakewatch.com'
      smtp_smarthost: 'smtp.gmail.com:587'
      smtp_auth_username: 'your-email@gmail.com'
      smtp_auth_password: 'your-app-password'
      smtp_require_tls: true

    route:
      receiver: 'email-default'
      group_by: ['alertname', 'severity']
      group_wait: 10s
      group_interval: 5m
      repeat_interval: 12h

      routes:
      - match:
          severity: critical
        receiver: 'email-critical'
      - match:
          severity: warning
        receiver: 'email-warnings'

    receivers:
    - name: 'email-default'
      email_configs:
      - to: 'devops-team@example.com'
        headers:
          Subject: '[QuakeWatch] {{ .GroupLabels.alertname }}'
        html: '<h3>Alert: {{ .GroupLabels.alertname }}</h3>'

    - name: 'email-critical'
      email_configs:
      - to: 'oncall-team@example.com'
        headers:
          Subject: '[CRITICAL] QuakeWatch: {{ .GroupLabels.alertname }}'
        html: '<h2 style="color:red;">🚨 CRITICAL</h2><p>{{ .CommonAnnotations.description }}</p>'

    - name: 'email-warnings'
      email_configs:
      - to: 'devops-team@example.com'
        headers:
          Subject: '[WARNING] QuakeWatch: {{ .GroupLabels.alertname }}'
        html: '<h3>⚠️ Warning: {{ .GroupLabels.alertname }}</h3>'
```

Apply the configuration:

```bash
helm upgrade kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values alertmanager-values.yaml \
  --reuse-values
```

---

**Option B: Patch Existing Secret (Quick Test)**

For testing only - changes will be lost on Helm upgrade:

```bash
# Get current config
kubectl get secret alertmanager-kube-prometheus-stack-alertmanager -n monitoring -o jsonpath='{.data.alertmanager\.yaml}' | base64 -d > current-config.yaml

# Edit the file with your SMTP settings
nano current-config.yaml

# Update the secret
kubectl create secret generic alertmanager-kube-prometheus-stack-alertmanager \
  --from-file=alertmanager.yaml=current-config.yaml \
  --namespace monitoring \
  --dry-run=client -o yaml | kubectl apply -f -

# Restart Alertmanager to load new config
kubectl rollout restart statefulset/alertmanager-kube-prometheus-stack-alertmanager -n monitoring
```

---

## 📧 Gmail Setup for Email Alerts

### 1. Enable 2-Factor Authentication
- Go to: https://myaccount.google.com/security
- Enable 2-Step Verification

### 2. Create App Password
- Go to: https://myaccount.google.com/apppasswords
- Select "Mail" and your device
- Copy the 16-character password

### 3. Use in Configuration
```yaml
smtp_auth_username: 'your-email@gmail.com'
smtp_auth_password: 'abcd efgh ijkl mnop'  # 16-char app password
```

---

## 🔍 Alert Rules Reference

| Alert Name | Severity | Threshold | Description |
|------------|----------|-----------|-------------|
| QuakeWatchHighErrorRate | Critical | 5% error rate for 2m | High HTTP 5xx errors |
| QuakeWatchDown | Critical | Up = 0 for 1m | Application unreachable |
| QuakeWatchSlowResponse | Warning | p95 > 2s for 5m | Slow response times |
| QuakeWatchPodRestarting | Warning | Restarts > 0 for 5m | Pod restart loop |
| QuakeWatchNoTraffic | Warning | 0 req/s for 10m | No incoming traffic |
| QuakeWatchHighMemory | Warning | Memory > 90% for 5m | High memory usage |
| QuakeWatchHighCPU | Warning | CPU > 0.8 cores for 5m | High CPU usage |

---

## 🧪 Testing Alerts

### Test High Error Rate:
```bash
# Generate 500 errors
for i in {1..500}; do
  curl http://localhost:8080/nonexistent-page
done
```

### Test Application Down:
```bash
# Scale to 0 replicas
kubectl scale deployment earthquake-app-quackwatch-helm -n default --replicas=0

# Wait 2 minutes, alert should fire

# Scale back up
kubectl scale deployment earthquake-app-quackwatch-helm -n default --replicas=3
```

### Check Alert Status:
```bash
# Prometheus UI
kubectl port-forward -n monitoring prometheus-kube-prometheus-stack-prometheus-0 9090:9090
# http://localhost:9090/alerts

# Alertmanager UI
kubectl port-forward -n monitoring alertmanager-kube-prometheus-stack-alertmanager-0 9093:9093
# http://localhost:9093
```

---

## 🔧 Troubleshooting

### Alerts not firing?
1. Check if PrometheusRule exists: `kubectl get prometheusrules -n monitoring`
2. Check Prometheus is scraping: http://localhost:9090/targets
3. Check alert evaluation: http://localhost:9090/alerts
4. Check Prometheus logs: `kubectl logs -n monitoring prometheus-kube-prometheus-stack-prometheus-0 -c prometheus`

### Emails not sending?
1. Check Alertmanager config: `kubectl get secret alertmanager-kube-prometheus-stack-alertmanager -n monitoring -o yaml`
2. Test SMTP connection manually
3. Check Alertmanager logs: `kubectl logs -n monitoring alertmanager-kube-prometheus-stack-alertmanager-0`
4. Verify Gmail app password is correct

### Dashboard shows no data?
1. Check ServiceMonitor: `kubectl get servicemonitor -n default`
2. Check Prometheus targets: http://localhost:9090/targets (should show quakewatch-app)
3. Verify `/metrics` endpoint works: `curl http://pod-ip:5000/metrics`
4. Check if Docker image has prometheus-flask-exporter installed

---

## 📚 Additional Resources

- [Prometheus Alerting Rules](https://prometheus.io/docs/prometheus/latest/configuration/alerting_rules/)
- [Alertmanager Configuration](https://prometheus.io/docs/alerting/latest/configuration/)
- [PromQL Query Examples](https://prometheus.io/docs/prometheus/latest/querying/examples/)
- [Grafana Dashboard Guide](https://grafana.com/docs/grafana/latest/dashboards/)
